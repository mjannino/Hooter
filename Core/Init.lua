local ADDON_NAME, Hooter = ...

-- Expose namespace globally for slash commands and settings panel
_G.Hooter = Hooter

-- Constants
Hooter.VERSION = "1.0.0"
Hooter.EXPORT_PREFIX = "!HT1:"

-- Event frame with method-name-based dispatch (CraftScan pattern)
Hooter.frame = CreateFrame("Frame")
Hooter.frame:SetScript("OnEvent", function(self, event, ...)
    if Hooter[event] then
        Hooter[event](Hooter, ...)
    end
end)
Hooter.frame:RegisterEvent("ADDON_LOADED")

function Hooter:ADDON_LOADED(addonName)
    if addonName ~= ADDON_NAME then return end
    self:InitConfig()
    self:InitCoordination()
    self:InitChatLinks()
    self:InitScanner()
    self:InitCommands()
    self:InitOptions()
    self:Print("v" .. self.VERSION .. " loaded. Type /hooter for help.")
    self.frame:UnregisterEvent("ADDON_LOADED")
end
