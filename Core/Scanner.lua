local _, Hooter = ...

-- Chat events to scan (CraftScan conditional registration pattern)
local CHAT_EVENTS = {
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_GUILD",
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_INSTANCE_CHAT",
}

function Hooter:InitScanner()
    if self:IsEnabled() then
        self:EnableScanning()
    end
end

function Hooter:EnableScanning()
    for _, event in ipairs(CHAT_EVENTS) do
        self.frame:RegisterEvent(event)
    end
end

function Hooter:DisableScanning()
    for _, event in ipairs(CHAT_EVENTS) do
        self.frame:UnregisterEvent(event)
    end
end

-- Shared message handler (CraftScan pipeline with early-out pattern)
function Hooter:OnChatMessage(event, message, sender, ...)
    local lineID = select(9, ...)

    -- Early-out: no ! means no trigger
    if not message:find("!", 1, true) then return end

    -- Skip share marker messages (metadata, not trigger invocations)
    if message:find("%[Hooter: !%w+") then return end

    -- Skip own messages (Ambiguate handles realm-qualified names and connected realms)
    if Ambiguate(sender, "short") == UnitName("player") then
        return
    end

    -- Extract first trigger match (case-insensitive)
    local lowerMsg = message:lower()
    for word in lowerMsg:gmatch("!(%w+)") do
        local triggerData = self.db.triggers[word]
        if triggerData and triggerData.enabled and #triggerData.responses > 0 then
            self:QueueResponse(word, triggerData, event, sender, lineID)
            return  -- One response per message
        end
    end
end

-- Thin wrappers for each chat event, routing to shared handler
function Hooter:CHAT_MSG_PARTY(message, sender, ...)
    self:OnChatMessage("CHAT_MSG_PARTY", message, sender, ...)
end

function Hooter:CHAT_MSG_PARTY_LEADER(message, sender, ...)
    self:OnChatMessage("CHAT_MSG_PARTY_LEADER", message, sender, ...)
end

function Hooter:CHAT_MSG_RAID(message, sender, ...)
    self:OnChatMessage("CHAT_MSG_RAID", message, sender, ...)
end

function Hooter:CHAT_MSG_RAID_LEADER(message, sender, ...)
    self:OnChatMessage("CHAT_MSG_RAID_LEADER", message, sender, ...)
end

function Hooter:CHAT_MSG_GUILD(message, sender, ...)
    self:OnChatMessage("CHAT_MSG_GUILD", message, sender, ...)
end

function Hooter:CHAT_MSG_WHISPER(message, sender, ...)
    self:OnChatMessage("CHAT_MSG_WHISPER", message, sender, ...)
end

function Hooter:CHAT_MSG_INSTANCE_CHAT(message, sender, ...)
    self:OnChatMessage("CHAT_MSG_INSTANCE_CHAT", message, sender, ...)
end
