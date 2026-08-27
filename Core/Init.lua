local ADDON_NAME, Hooter = ...

-- Expose namespace globally for slash commands and settings panel
_G.Hooter = Hooter

-- Constants
-- Replaced by the BigWigs packager at release time. In a plain source
-- checkout the keyword is left untouched, so fall back to "dev".
Hooter.VERSION = "@project-version@"
if Hooter.VERSION:find("@project", 1, true) then
    Hooter.VERSION = "dev"
end
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
    self:InitDialogs()
    self:InitCommands()
    self:InitOptions()
    self:Print("v" .. self.VERSION .. " loaded. Type /hooter for help.")
    self.frame:UnregisterEvent("ADDON_LOADED")
end
