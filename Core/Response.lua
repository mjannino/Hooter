local _, Hooter = ...

-- Cooldown tracking: trigger_word → GetTime() of last response
Hooter.cooldowns = {}

-- Burst detection state
Hooter.recentFires = {}
Hooter.burstSuppressUntil = 0

-- Sanitize response text by inserting a space into any !word that matches an
-- enabled trigger, breaking the pattern so other Hooter clients won't match it.
-- Why: the scanner uses !(%w+) to detect triggers, so inserting a space between
-- ! and the word breaks that pattern, preventing infinite response loops between
-- Hooter clients.
function Hooter:SanitizeResponse(text)
    return text:gsub("!(%w+)", function(word)
        local trigger = self.db.triggers[word:lower()]
        if trigger and trigger.enabled then
            return "! " .. word
        end
        return "!" .. word
    end)
end

-- Check if burst breaker is active, prune old fires, and trip breaker if threshold exceeded
local function IsBurstSuppressed(self, now)
    if now < self.burstSuppressUntil then
        return true
    end

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
        return true
    end

    return false
end

-- Check if the per-trigger cooldown is still active
local function IsOnCooldown(self, triggerWord, now)
    local lastFired = self.cooldowns[triggerWord]
    return lastFired and (now - lastFired) < self.db.settings.cooldown
end

function Hooter:QueueResponse(triggerWord, triggerData, event, sender)
    local now = GetTime()

    if IsBurstSuppressed(self, now) then return end
    if IsOnCooldown(self, triggerWord, now) then return end

    self.cooldowns[triggerWord] = now
    self.recentFires[#self.recentFires + 1] = now

    -- If forceUnique is enabled and channel supports coordination, use coordination path
    if triggerData.forceUnique and self:CanCoordinate(event) then
        self:StartCoordination(triggerWord, triggerData, event, sender, sender)
        return
    end

    -- Pick random response and send after delay
    local response = triggerData.responses[math.random(#triggerData.responses)]
    local chatType = self.EVENT_TO_CHAT[event]
    local target = (chatType == "WHISPER") and sender or nil
    local sanitized = self:SanitizeResponse(response)

    C_Timer.After(self:CalculateDelay(), function()
        C_ChatInfo.SendChatMessage(sanitized, chatType, nil, target)
    end)
end
