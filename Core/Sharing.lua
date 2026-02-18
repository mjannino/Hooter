local _, Hooter = ...

local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")

function Hooter:ExportTrigger(word)
    word = word:lower()
    local triggerData = self.db.triggers[word]
    if not triggerData then
        return nil, "Trigger !" .. word .. " not found."
    end
    local exportData = {
        v = 1,
        trigger = { word = word, data = triggerData },
    }
    local serialized = LibSerialize:Serialize(exportData)
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return self.EXPORT_PREFIX .. encoded
end

function Hooter:ImportConfig(str)
    -- Validate prefix
    if not str or not str:match("^!HT%d+:") then
        return false, "Not a valid Hooter config string."
    end

    local encoded = str:match("^!HT%d+:(.+)$")

    -- Decode → Decompress → Deserialize (each step validated)
    local decoded = LibDeflate:DecodeForPrint(encoded)
    if not decoded then return false, "Failed to decode string." end

    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then return false, "Failed to decompress data." end

    local ok, data = LibSerialize:Deserialize(decompressed)
    if not ok then return false, "Failed to deserialize data." end

    -- Validate structure (per-trigger format)
    if type(data) ~= "table" or type(data.trigger) ~= "table" then
        return false, "Invalid data structure."
    end

    local word = data.trigger.word
    local triggerData = data.trigger.data
    if type(word) ~= "string" or type(triggerData) ~= "table" or type(triggerData.responses) ~= "table" then
        return false, "Malformed trigger data."
    end

    for _, resp in ipairs(triggerData.responses) do
        if type(resp) ~= "string" then
            return false, "Non-string response in trigger: !" .. word
        end
    end

    -- Ensure enabled field exists
    if triggerData.enabled == nil then
        triggerData.enabled = true
    end

    -- Install trigger (overwrites existing with same name)
    self.db.triggers[word:lower()] = triggerData

    return true, word
end
