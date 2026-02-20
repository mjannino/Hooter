local _, Hooter = ...

local ACCOUNT_DEFAULTS = {
    settings = {
        minDelay = 0.5,
        maxDelay = 3.0,
        cooldown = 5,
    },
    triggers = {},
}

local CHAR_DEFAULTS = {
    enabled = true,
}

function Hooter:InitConfig()
    -- Account-wide DB (triggers, responses, settings)
    if not HooterDB then
        HooterDB = CopyTable(ACCOUNT_DEFAULTS)
    else
        self:MergeDefaults(HooterDB, ACCOUNT_DEFAULTS)
    end
    self.db = HooterDB

    -- Per-character DB (just the enabled toggle)
    if not HooterCharDB then
        HooterCharDB = CopyTable(CHAR_DEFAULTS)
    else
        self:MergeDefaults(HooterCharDB, CHAR_DEFAULTS)
    end
    self.charDB = HooterCharDB
end

function Hooter:MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = (type(v) == "table") and CopyTable(v) or v
        elseif type(v) == "table" and type(target[k]) == "table" then
            self:MergeDefaults(target[k], v)
        end
    end
end

-- Per-character scanning toggle
function Hooter:IsEnabled()
    return self.charDB.enabled
end

function Hooter:SetEnabled(enabled)
    self.charDB.enabled = enabled
    if enabled then
        self:EnableScanning()
    else
        self:DisableScanning()
    end
end

-- Trigger management API
function Hooter:AddTrigger(word, response)
    word = word:lower()
    if not self.db.triggers[word] then
        self.db.triggers[word] = {
            enabled = true,
            responses = {},
            forceUnique = false,
            uniqueOverflow = "silent",
        }
    end
    table.insert(self.db.triggers[word].responses, response)
    return self.db.triggers[word]
end

function Hooter:RemoveTrigger(word)
    word = word:lower()
    if self.db.triggers[word] then
        self.db.triggers[word] = nil
        return true
    end
    return false
end

function Hooter:RemoveResponse(word, index)
    word = word:lower()
    local trigger = self.db.triggers[word]
    if not trigger then return false end
    if index < 1 or index > #trigger.responses then return false end
    table.remove(trigger.responses, index)
    -- Remove trigger entirely if no responses left
    if #trigger.responses == 0 then
        self.db.triggers[word] = nil
    end
    return true
end

function Hooter:SetTriggerEnabled(word, enabled)
    word = word:lower()
    local trigger = self.db.triggers[word]
    if not trigger then return false end
    trigger.enabled = enabled
    return true
end

function Hooter:RenameTrigger(oldWord, newWord)
    oldWord = oldWord:lower()
    newWord = newWord:lower()
    if oldWord == newWord then return true end
    if not self.db.triggers[oldWord] then return false, "Source not found" end
    if self.db.triggers[newWord] then return false, "Target already exists" end
    self.db.triggers[newWord] = self.db.triggers[oldWord]
    self.db.triggers[oldWord] = nil
    return true
end

function Hooter:GetTrigger(word)
    return self.db.triggers[word:lower()]
end

function Hooter:GetAllTriggers()
    return self.db.triggers
end
