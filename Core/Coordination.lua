local _, Hooter = ...

-- Coordination Protocol
--
-- Problem: When a "forceUnique" trigger fires in group chat, every Hooter client
-- sees the same message. Without coordination, all of them would respond —
-- duplicating lines or colliding on the same response index.
--
-- Solution — leader-less 2-phase protocol:
--   1. BROADCAST: Each client sends a JOIN:<eventID> addon message on the same
--      channel.  The eventID is deterministic (sender:triggerWord) so every
--      client generates the same key for the same chat event.
--   2. RESOLVE: After a short collection window (COORD.JOIN_WINDOW), each client
--      independently sorts the collected participant names alphabetically and
--      assigns response indices by position.  Because every client sees the same
--      set of JOINs and uses the same sort, they all agree on the assignment
--      without electing a leader.
--
-- Overflow policies (when more participants than responses):
--   "silent" — extra participants stay quiet (default)
--   "wrap"   — extra participants wrap around to earlier responses

local ADDON_PREFIX = "Hooter"

-- Active coordination sessions: eventID → { participants = {}, timer = nil, resolved = false }
Hooter.coordSessions = {}

function Hooter:InitCoordination()
    C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)
    self.frame:RegisterEvent("CHAT_MSG_ADDON")
end

-- Event handler for addon messages
function Hooter:CHAT_MSG_ADDON(prefix, message, distribution, sender)
    -- Secret payloads cannot be compared or parsed (see IsChatRestricted)
    if self:IsChatRestricted(prefix, message, sender) then return end

    if prefix ~= ADDON_PREFIX then return end

    local msgType, eventID = message:match("^(%u+):(.+)$")
    if msgType == "JOIN" then
        self:OnJoinReceived(eventID, sender)
    elseif msgType == "SH" then
        local word, chunkNum, totalChunks, data = eventID:match("^(%w+):(%d+):(%d+):(.+)$")
        if word and chunkNum and totalChunks and data then
            self:OnShareChunkReceived(sender, word, tonumber(chunkNum), tonumber(totalChunks), data)
        end
    end
end

-- Determine the channel to broadcast addon messages on based on the chat event.
-- Derives from the shared EVENT_TO_CHAT mapping, excluding WHISPER (no addon
-- channel for whispers).
local function GetAddonChannel(event)
    local chatType = Hooter.EVENT_TO_CHAT[event]
    if chatType == "WHISPER" then return nil end
    return chatType
end

-- Check if the event type supports coordination (not WHISPER)
function Hooter:CanCoordinate(event)
    return GetAddonChannel(event) ~= nil
end

-- Build a deterministic event ID from the trigger context
-- Uses only data from the chat message itself (sender + trigger word) so all
-- clients receiving the same message produce the same key.  No timestamps —
-- the cooldown in QueueResponse already prevents rapid re-triggers.
local function MakeEventID(sender, triggerWord)
    return sender .. ":" .. triggerWord
end

-- Start the coordination protocol for a forceUnique trigger
function Hooter:StartCoordination(triggerWord, triggerData, event, sender, chatSender)
    local eventID = MakeEventID(chatSender, triggerWord)

    -- If the previous session for this key already resolved, discard it so a
    -- new round can begin (the cooldown in QueueResponse gates re-entry).
    if self.coordSessions[eventID] and self.coordSessions[eventID].resolved then
        self.coordSessions[eventID] = nil
    end

    local addonChannel = GetAddonChannel(event)
    if not addonChannel then return end

    -- Create session if it doesn't exist yet
    if not self.coordSessions[eventID] then
        self.coordSessions[eventID] = {
            participants = {},
            resolved = false,
            triggerWord = triggerWord,
            triggerData = triggerData,
            event = event,
            sender = sender,
        }
    end

    local session = self.coordSessions[eventID]

    -- Add ourselves
    local myName = UnitName("player")
    session.participants[myName] = true

    -- Broadcast JOIN
    C_ChatInfo.SendAddonMessage(ADDON_PREFIX, "JOIN:" .. eventID, addonChannel)

    -- Start collection timer
    if not session.timer then
        session.timer = true
        C_Timer.After(Hooter.COORD.JOIN_WINDOW, function()
            self:ResolveCoordination(eventID)
        end)
    end

    -- Schedule cleanup — only remove THIS session; a later round may have
    -- replaced it with a new table under the same key.
    C_Timer.After(Hooter.COORD.CLEANUP_DELAY, function()
        if self.coordSessions[eventID] == session then
            self.coordSessions[eventID] = nil
        end
    end)
end

-- Handle an incoming JOIN message
function Hooter:OnJoinReceived(eventID, sender)
    local session = self.coordSessions[eventID]
    if not session or session.resolved then return end

    -- Normalize sender name (strip realm)
    local shortName = Ambiguate(sender, "short")
    session.participants[shortName] = true
end

-- After the collection window, compute assignment and schedule response
function Hooter:ResolveCoordination(eventID)
    local session = self.coordSessions[eventID]
    if not session or session.resolved then return end
    session.resolved = true

    local triggerData = session.triggerData
    local responses = triggerData.responses
    local numResponses = #responses

    -- Build sorted participant list
    local sorted = {}
    for name in pairs(session.participants) do
        table.insert(sorted, name)
    end
    table.sort(sorted)

    -- Find our position
    local myName = UnitName("player")
    local myIndex = nil
    for i, name in ipairs(sorted) do
        if name == myName then
            myIndex = i
            break
        end
    end

    if not myIndex then return end -- We're not in the list somehow

    -- Determine which response we get
    local responseIndex
    local overflow = triggerData.uniqueOverflow or "silent"

    if myIndex <= numResponses then
        responseIndex = myIndex
    elseif overflow == "wrap" then
        responseIndex = ((myIndex - 1) % numResponses) + 1
    else
        -- "silent" - we don't respond
        return
    end

    local response = responses[responseIndex]

    -- Apply normal random delay and send
    local chatType = self.EVENT_TO_CHAT[session.event]
    if not chatType then return end

    local sanitized = self:SanitizeResponse(response)
    C_Timer.After(self:CalculateDelay(), function()
        C_ChatInfo.SendChatMessage(sanitized, chatType, nil, nil)
    end)
end
