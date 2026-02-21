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

-- Burst detection state
Hooter.recentFires = {}
Hooter.burstSuppressUntil = 0

-- Sanitize response text by inserting a space into any !word that matches an
-- enabled trigger, breaking the pattern so other Hooter clients won't match it.
function Hooter:SanitizeResponse(text)
    return text:gsub("!(%w+)", function(word)
        local trigger = self.db.triggers[word:lower()]
        if trigger and trigger.enabled then
            return "! " .. word
        end
        return "!" .. word
    end)
end

function Hooter:QueueResponse(triggerWord, triggerData, event, sender)
    local now = GetTime()

    -- Burst suppression: if we tripped the breaker, suppress all triggers
    if now < self.burstSuppressUntil then
        return
    end

    -- Burst tracking: prune old entries and check count
    local window = self.db.settings.burstWindow
    local pruned = {}
    for _, t in ipairs(self.recentFires) do
        if (now - t) < window then
            pruned[#pruned + 1] = t
        end
    end
    self.recentFires = pruned

    if #self.recentFires >= self.db.settings.burstThreshold then
        self.burstSuppressUntil = now + self.db.settings.burstCooldown
        self:Print("|cffff6600Burst detected — suppressing all triggers for "
            .. self.db.settings.burstCooldown .. "s.|r")
        return
    end

    -- Per-trigger cooldown
    local lastFired = self.cooldowns[triggerWord]
    if lastFired and (now - lastFired) < self.db.settings.cooldown then
        return
    end
    self.cooldowns[triggerWord] = now

    -- Record this fire for burst tracking
    self.recentFires[#self.recentFires + 1] = now

    -- If forceUnique is enabled and channel supports coordination, use coordination path
    if triggerData.forceUnique and self:CanCoordinate(event) then
        self:StartCoordination(triggerWord, triggerData, event, sender, sender)
        return
    end

    -- Pick random response
    local response = triggerData.responses[math.random(#triggerData.responses)]

    -- Calculate random delay within configured range
    local min = self.db.settings.minDelay
    local max = self.db.settings.maxDelay
    local delay = min + (math.random() * (max - min))

    -- Determine chat type and target
    local chatType = EVENT_TO_CHAT[event]
    local target = (chatType == "WHISPER") and sender or nil

    -- Schedule delayed response (sanitize before sending)
    local sanitized = self:SanitizeResponse(response)
    C_Timer.After(delay, function()
        C_ChatInfo.SendChatMessage(sanitized, chatType, nil, target)
    end)
end
