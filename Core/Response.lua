local _, Hooter = ...

-- Event name → SendChatMessage chatType
local EVENT_TO_CHAT = {
    CHAT_MSG_PARTY         = "PARTY",
    CHAT_MSG_PARTY_LEADER  = "PARTY",
    CHAT_MSG_RAID          = "RAID",
    CHAT_MSG_RAID_LEADER   = "RAID",
    CHAT_MSG_GUILD         = "GUILD",
    CHAT_MSG_WHISPER       = "WHISPER",
    CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT",
}

-- Cooldown tracking: trigger_word → GetTime() of last response
Hooter.cooldowns = {}

function Hooter:QueueResponse(triggerWord, triggerData, event, sender)
    -- Check cooldown
    local now = GetTime()
    local lastFired = self.cooldowns[triggerWord]
    if lastFired and (now - lastFired) < self.db.settings.cooldown then
        return
    end
    self.cooldowns[triggerWord] = now

    -- Pick random response
    local response = triggerData.responses[math.random(#triggerData.responses)]

    -- Calculate random delay within configured range
    local min = self.db.settings.minDelay
    local max = self.db.settings.maxDelay
    local delay = min + (math.random() * (max - min))

    -- Determine chat type and target
    local chatType = EVENT_TO_CHAT[event]
    local target = (chatType == "WHISPER") and sender or nil

    -- Schedule delayed response
    C_Timer.After(delay, function()
        C_ChatInfo.SendChatMessage(response, chatType, nil, target)
    end)
end
