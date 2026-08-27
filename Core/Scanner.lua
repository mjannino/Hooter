local _, Hooter = ...

function Hooter:InitScanner()
    if self:IsEnabled() then
        self:EnableScanning()
    end
end

function Hooter:EnableScanning()
    for _, event in ipairs(Hooter.CHAT_EVENTS) do
        self.frame:RegisterEvent(event)
    end
end

function Hooter:DisableScanning()
    for _, event in ipairs(Hooter.CHAT_EVENTS) do
        self.frame:UnregisterEvent(event)
    end
end

-- Shared message handler (CraftScan pipeline with early-out pattern)
function Hooter:OnChatMessage(event, message, sender, ...)
    -- Early-out: secret payloads cannot be inspected (see IsChatRestricted)
    if self:IsChatRestricted(message, sender) then return end

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
            self:QueueResponse(word, triggerData, event, sender)
            return  -- One response per message
        end
    end
end

-- Generate event handlers for each chat event, routing to shared handler
for _, event in ipairs(Hooter.CHAT_EVENTS) do
    Hooter[event] = function(self, message, sender, ...)
        self:OnChatMessage(event, message, sender, ...)
    end
end
