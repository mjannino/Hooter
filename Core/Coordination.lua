local _, Hooter = ...

local ADDON_PREFIX = "Hooter"
local JOIN_WINDOW = 0.4  -- seconds to collect JOIN messages
local CLEANUP_DELAY = 10 -- seconds after which stale coordination state is purged

-- Active coordination sessions: eventID → { participants = {}, timer = nil, resolved = false }
Hooter.coordSessions = {}

function Hooter:InitCoordination()
    C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)
    self.frame:RegisterEvent("CHAT_MSG_ADDON")
end

-- Event handler for addon messages
function Hooter:CHAT_MSG_ADDON(prefix, message, distribution, sender)
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

-- Determine the channel to broadcast addon messages on based on the chat event
local function GetAddonChannel(event)
    if event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" then
        return "PARTY"
    elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
        return "RAID"
    elseif event == "CHAT_MSG_GUILD" then
        return "GUILD"
    elseif event == "CHAT_MSG_INSTANCE_CHAT" then
        return "INSTANCE_CHAT"
    end
    return nil
end

-- Check if the event type supports coordination (not WHISPER)
function Hooter:CanCoordinate(event)
    return GetAddonChannel(event) ~= nil
end

-- Build a deterministic event ID from the trigger context
local function MakeEventID(sender, triggerWord)
    return sender .. ":" .. triggerWord .. ":" .. math.floor(GetTime())
end

-- Start the coordination protocol for a forceUnique trigger
function Hooter:StartCoordination(triggerWord, triggerData, event, sender, chatSender)
    local eventID = MakeEventID(chatSender, triggerWord)

    -- If we already have a session for this event, just make sure we're in it
    if self.coordSessions[eventID] and self.coordSessions[eventID].resolved then
        return
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
        C_Timer.After(JOIN_WINDOW, function()
            self:ResolveCoordination(eventID)
        end)
    end

    -- Schedule cleanup
    C_Timer.After(CLEANUP_DELAY, function()
        self.coordSessions[eventID] = nil
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
    local EVENT_TO_CHAT = {
        CHAT_MSG_PARTY         = "PARTY",
        CHAT_MSG_PARTY_LEADER  = "PARTY",
        CHAT_MSG_RAID          = "RAID",
        CHAT_MSG_RAID_LEADER   = "RAID",
        CHAT_MSG_GUILD         = "GUILD",
        CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT",
    }

    local chatType = EVENT_TO_CHAT[session.event]
    if not chatType then return end

    local min = self.db.settings.minDelay
    local max = self.db.settings.maxDelay
    local delay = min + (math.random() * (max - min))

    C_Timer.After(delay, function()
        C_ChatInfo.SendChatMessage(response, chatType, nil, nil)
    end)
end
