local _, Hooter = ...

local ADDON_PREFIX = "Hooter"

-- Chat marker pattern: [Hooter: !word (N responses)]
local MARKER_PATTERN = "%[Hooter: !(%w+) %((%d+) responses?%)%]"

-- State
local shareCache = {}     -- "sender:word" → { data = string, time = number }
local pendingChunks = {}  -- "sender:word" → { chunks = {}, total = number, time = number }

function Hooter:InitChatLinks()
    -- Register chat filter on all relevant event types (WHISPER excluded — no share links in whispers)
    for _, event in ipairs(Hooter.CHAT_EVENTS) do
        if event ~= "CHAT_MSG_WHISPER" then
            ChatFrame_AddMessageEventFilter(event, function(frame, evt, msg, sender, ...)
                return Hooter:FilterChatMessage(frame, evt, msg, sender, ...)
            end)
        end
    end

    -- Hook hyperlink clicks
    hooksecurefunc("SetItemRef", function(link, text, button, chatFrame)
        Hooter:OnHyperlinkClick(link, text, button, chatFrame)
    end)

    -- Register import confirmation popup
    StaticPopupDialogs["HOOTER_SHARE_IMPORT"] = {
        text = "Import trigger !%s shared by %s?",
        button1 = "Import",
        button2 = "Cancel",
        OnAccept = function(dialog, data)
            local cached = shareCache[data.cacheKey]
            if not cached then
                Hooter:PrintError("Share data no longer available.")
                return
            end
            local ok, result = Hooter:ImportConfig(cached.data)
            if ok then
                Hooter:Print("Imported trigger |cff00ccff!" .. result .. "|r from " .. data.sender)
                Hooter:RefreshTriggerList()
                Hooter:RefreshResponseList()
            else
                Hooter:PrintError("Import failed: " .. result)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

-- Chat filter: replace marker text with clickable hyperlink
function Hooter:FilterChatMessage(frame, event, msg, sender, ...)
    -- Secret payloads cannot be inspected; pass them through untouched
    if self:IsChatRestricted(msg, sender) then
        return false, msg, sender, ...
    end

    local word, count = msg:match(MARKER_PATTERN)
    if not word then
        return false, msg, sender, ...
    end

    local shortSender = Ambiguate(sender, "short")
    local link = "|cff00ccff|Haddon:Hooter:" .. word .. ":" .. shortSender
        .. "|h[Hooter: !" .. word .. " (" .. count .. " responses)]|h|r"

    local newMsg = msg:gsub(MARKER_PATTERN, function() return link end, 1)
    return false, newMsg, sender, ...
end

-- Handle clicks on Hooter hyperlinks
function Hooter:OnHyperlinkClick(link, text, button, chatFrame)
    local word, sender = link:match("^addon:Hooter:(%w+):(.+)$")
    if not word or not sender then return end

    local cacheKey = sender .. ":" .. word

    local cached = shareCache[cacheKey]
    if not cached then
        self:PrintError("No share data received for !" .. word .. " from " .. sender .. ".")
        return
    end

    if GetTime() - cached.time > Hooter.SHARE.TTL then
        shareCache[cacheKey] = nil
        self:PrintError("Share data for !" .. word .. " from " .. sender .. " has expired.")
        return
    end

    local dialog = StaticPopup_Show("HOOTER_SHARE_IMPORT", word, sender)
    if dialog then
        dialog.data = { cacheKey = cacheKey, sender = sender, word = word }
    end
end

-- Send a trigger as a clickable share link in chat
function Hooter:SendShareData(word, chatType)
    word = word:lower()
    local exportStr, err = self:ExportTrigger(word)
    if not exportStr then
        self:PrintError(err)
        return
    end

    local trigger = self:GetTrigger(word)
    local responseCount = trigger and #trigger.responses or 0

    -- Send addon data first (gives receivers a head start on caching)
    self:SendChunkedAddonMessage(exportStr, word, chatType)

    -- Then send the visible chat marker
    local marker = "[Hooter: !" .. word .. " (" .. responseCount .. " response" .. (responseCount == 1 and "" or "s") .. ")]"
    C_ChatInfo.SendChatMessage(marker, chatType)

    self:Print("Shared |cff00ccff!" .. word .. "|r in " .. chatType .. " chat.")
end

-- Chunk and send export data via addon messages.
-- WoW addon messages are limited to 255 bytes each.  The header
-- ("SH:<word>:<chunkNum>:<totalChunks>:") consumes a variable number of bytes
-- depending on the trigger word length and the digit count of totalChunks, so
-- the available data space per chunk is computed dynamically.  On the receiving
-- side, Coordination.lua routes SH messages to OnShareChunkReceived, which
-- reassembles chunks in order once all have arrived.
function Hooter:SendChunkedAddonMessage(payload, word, chatType)
    -- Compute available space per chunk dynamically based on header length
    -- Header format: "SH:word:N:M:" where N/M are chunk/total digits
    local totalLen = #payload
    -- Estimate total chunks with conservative header overhead to compute digit count
    local estChunks = math.ceil(totalLen / Hooter.SHARE.CHUNK_DATA_SIZE)
    local digitLen = #tostring(estChunks)
    -- Header: "SH:" + word + ":" + chunkNum + ":" + totalChunks + ":"
    local headerLen = 3 + #word + 1 + digitLen + 1 + digitLen + 1
    local dataPerChunk = 255 - headerLen

    local totalChunks = math.ceil(totalLen / dataPerChunk)

    for i = 1, totalChunks do
        local startPos = (i - 1) * dataPerChunk + 1
        local endPos = math.min(i * dataPerChunk, totalLen)
        local chunk = payload:sub(startPos, endPos)

        local message = "SH:" .. word .. ":" .. i .. ":" .. totalChunks .. ":" .. chunk
        C_ChatInfo.SendAddonMessage(ADDON_PREFIX, message, chatType)
    end
end

-- Receive a share chunk from addon messages (called from Coordination.lua)
function Hooter:OnShareChunkReceived(sender, word, chunkNum, totalChunks, data)
    if chunkNum < 1 or chunkNum > totalChunks or totalChunks > Hooter.SHARE.MAX_CHUNKS then return end

    local shortSender = Ambiguate(sender, "short")
    local key = shortSender .. ":" .. word

    if not pendingChunks[key] then
        pendingChunks[key] = { chunks = {}, total = totalChunks, time = GetTime() }
        -- Schedule cleanup for stale pending entries
        C_Timer.After(Hooter.SHARE.PENDING_TIMEOUT, function()
            pendingChunks[key] = nil
        end)
    end

    local pending = pendingChunks[key]
    pending.chunks[chunkNum] = data

    -- Check if all chunks have arrived
    local received = 0
    for _ in pairs(pending.chunks) do
        received = received + 1
    end

    if received >= pending.total then
        -- Reassemble in order
        local parts = {}
        for i = 1, pending.total do
            parts[i] = pending.chunks[i]
        end
        local fullPayload = table.concat(parts)
        pendingChunks[key] = nil
        self:CacheShareData(shortSender, word, fullPayload)
    end
end

-- Store assembled share data in cache
function Hooter:CacheShareData(sender, word, data)
    -- Single pass: expire stale entries, count live ones, track oldest for eviction
    local now = GetTime()
    local count = 0
    local oldestKey, oldestTime = nil, math.huge

    for k, v in pairs(shareCache) do
        if now - v.time > Hooter.SHARE.TTL then
            shareCache[k] = nil
        else
            count = count + 1
            if v.time < oldestTime then
                oldestKey = k
                oldestTime = v.time
            end
        end
    end

    if count >= Hooter.SHARE.MAX_CACHE and oldestKey then
        shareCache[oldestKey] = nil
    end

    shareCache[sender .. ":" .. word] = { data = data, time = now }
end

-- Determine chat channel for sharing
function Hooter:ResolveShareChannel(explicit)
    if explicit and explicit ~= "" then
        local upper = explicit:upper()
        local valid = { PARTY = true, RAID = true, GUILD = true, INSTANCE_CHAT = true }
        if valid[upper] then
            return upper
        end
        -- Allow shorthand
        local aliases = { INSTANCE = "INSTANCE_CHAT" }
        if aliases[upper] then
            return aliases[upper]
        end
        return nil, "Invalid channel: " .. explicit .. ". Use party, raid, guild, or instance."
    end

    -- Auto-detect
    if IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    elseif IsInGuild() then
        return "GUILD"
    end

    return nil, "Not in a group or guild. Specify a channel: /hooter share !word party"
end
