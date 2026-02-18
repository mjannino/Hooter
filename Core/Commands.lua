local _, Hooter = ...

local ADDON_COLOR = "|cff00ccff"
local ERROR_COLOR = "|cffff4444"

function Hooter:Print(msg)
    print(ADDON_COLOR .. "[Hooter]|r " .. msg)
end

function Hooter:PrintError(msg)
    print(ADDON_COLOR .. "[Hooter]|r " .. ERROR_COLOR .. msg .. "|r")
end

function Hooter:InitCommands()
    SLASH_HOOTER1 = "/hooter"
    SLASH_HOOTER2 = "/hoot"
    SlashCmdList["HOOTER"] = function(input)
        self:HandleCommand(input)
    end
end

function Hooter:HandleCommand(input)
    local cmd, rest = input:match("^(%S+)%s*(.*)$")
    if not cmd then
        self:PrintHelp()
        return
    end
    cmd = cmd:lower()

    if cmd == "enable" then
        self:Cmd_enable()
    elseif cmd == "disable" then
        self:Cmd_disable()
    elseif cmd == "add" then
        self:Cmd_add(rest)
    elseif cmd == "remove" then
        self:Cmd_remove(rest)
    elseif cmd == "list" then
        self:Cmd_list()
    elseif cmd == "export" then
        self:Cmd_export(rest)
    elseif cmd == "import" then
        self:Cmd_import(rest)
    elseif cmd == "cooldown" then
        self:Cmd_cooldown(rest)
    elseif cmd == "delay" then
        self:Cmd_delay(rest)
    else
        self:PrintError("Unknown command: " .. cmd)
        self:PrintHelp()
    end
end

function Hooter:PrintHelp()
    self:Print("v" .. self.VERSION .. " - Chat trigger auto-response")
    self:Print("Status: " .. (self:IsEnabled() and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
    print("  /hooter enable          - Enable scanning")
    print("  /hooter disable         - Disable scanning")
    print("  /hooter add !word text  - Add a response to a trigger")
    print("  /hooter remove !word    - Remove entire trigger")
    print("  /hooter remove !word #  - Remove response # from a trigger")
    print("  /hooter list            - List all triggers")
    print("  /hooter export !word    - Export a trigger's config string")
    print("  /hooter import <str>    - Import a trigger from a config string")
    print("  /hooter cooldown <sec>  - Set trigger cooldown")
    print("  /hooter delay <min> <max> - Set response delay range")
end

function Hooter:Cmd_enable()
    self:SetEnabled(true)
    self:Print("Scanning |cff00ff00enabled|r for this character.")
end

function Hooter:Cmd_disable()
    self:SetEnabled(false)
    self:Print("Scanning |cffff0000disabled|r for this character.")
end

function Hooter:Cmd_add(rest)
    local word, response = rest:match("^!(%w+)%s+(.+)$")
    if not word or not response then
        self:PrintError("Usage: /hooter add !word Response text here")
        return
    end
    word = word:lower()
    local trigger = self:AddTrigger(word, response)
    self:Print("Added response to |cff00ccff!" .. word .. "|r (" .. #trigger.responses .. " total)")
end

function Hooter:Cmd_remove(rest)
    -- Check if removing a specific response: /hooter remove !word 2
    local word, indexStr = rest:match("^!(%w+)%s+(%d+)$")
    if word and indexStr then
        word = word:lower()
        local index = tonumber(indexStr)
        if self:RemoveResponse(word, index) then
            local trigger = self:GetTrigger(word)
            if trigger then
                self:Print("Removed response #" .. index .. " from |cff00ccff!" .. word .. "|r (" .. #trigger.responses .. " remaining)")
            else
                self:Print("Removed response #" .. index .. ". No responses left, trigger |cff00ccff!" .. word .. "|r deleted.")
            end
        else
            self:PrintError("Invalid trigger or response index.")
        end
        return
    end

    -- Remove entire trigger: /hooter remove !word
    word = rest:match("^!(%w+)$")
    if not word then
        self:PrintError("Usage: /hooter remove !word [index]")
        return
    end
    word = word:lower()
    if self:RemoveTrigger(word) then
        self:Print("Removed trigger |cff00ccff!" .. word .. "|r")
    else
        self:PrintError("Trigger !" .. word .. " not found.")
    end
end

function Hooter:Cmd_list()
    local triggers = self:GetAllTriggers()
    local count = 0
    for word, data in pairs(triggers) do
        count = count + 1
        local status = data.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        self:Print(status .. " |cff00ccff!" .. word .. "|r (" .. #data.responses .. " responses)")
        for i, resp in ipairs(data.responses) do
            print("    " .. i .. ". " .. resp)
        end
    end
    if count == 0 then
        self:Print("No triggers configured. Use /hooter add !word Response text")
    end
end

function Hooter:Cmd_export(rest)
    local word = rest:match("^!(%w+)$")
    if not word then
        self:PrintError("Usage: /hooter export !word")
        return
    end
    local str, err = self:ExportTrigger(word)
    if not str then
        self:PrintError(err)
        return
    end
    -- Copy to clipboard via editbox
    if not self.exportDialog then
        self:CreateExportDialog()
    end
    self.exportDialog.editBox:SetText(str)
    self.exportDialog:Show()
    self.exportDialog.editBox:HighlightText()
    self.exportDialog.editBox:SetFocus()
    self:Print("Export string for |cff00ccff!" .. word:lower() .. "|r generated. Press Ctrl+C to copy.")
end

function Hooter:Cmd_import(rest)
    if not rest or rest == "" then
        -- Open import dialog
        if not self.importDialog then
            self:CreateImportDialog()
        end
        self.importDialog.editBox:SetText("")
        self.importDialog:Show()
        self.importDialog.editBox:SetFocus()
        return
    end
    local ok, result = self:ImportConfig(rest)
    if ok then
        self:Print("Imported trigger |cff00ccff!" .. result .. "|r successfully.")
    else
        self:PrintError("Import failed: " .. result)
    end
end

function Hooter:Cmd_cooldown(rest)
    local sec = tonumber(rest)
    if not sec or sec < 1 then
        self:PrintError("Usage: /hooter cooldown <seconds> (current: " .. self.db.settings.cooldown .. "s)")
        return
    end
    self.db.settings.cooldown = sec
    self:Print("Cooldown set to " .. sec .. "s")
end

function Hooter:Cmd_delay(rest)
    local minVal, maxVal = rest:match("^([%d%.]+)%s+([%d%.]+)$")
    minVal, maxVal = tonumber(minVal), tonumber(maxVal)
    if not minVal or not maxVal or minVal < 0 or maxVal < minVal then
        self:PrintError("Usage: /hooter delay <min> <max> (current: " .. self.db.settings.minDelay .. "-" .. self.db.settings.maxDelay .. "s)")
        return
    end
    self.db.settings.minDelay = minVal
    self.db.settings.maxDelay = maxVal
    self:Print("Delay range set to " .. minVal .. "-" .. maxVal .. "s")
end

-- Export/Import dialog frames (reusable popups)
function Hooter:CreateExportDialog()
    local f = CreateFrame("Frame", "HooterExportDialog", UIParent, "BackdropTemplate")
    f:SetSize(450, 200)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Hooter - Export")

    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 16, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 40)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    local sw = scrollFrame:GetWidth()
    editBox:SetWidth((sw and sw > 0) and sw or 390)
    editBox:SetScript("OnEscapePressed", function() f:Hide() end)
    scrollFrame:SetScrollChild(editBox)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("BOTTOM", 0, 12)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    f.editBox = editBox
    self.exportDialog = f
end

function Hooter:CreateImportDialog()
    local f = CreateFrame("Frame", "HooterImportDialog", UIParent, "BackdropTemplate")
    f:SetSize(450, 200)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Hooter - Import")

    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 16, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 40)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    local sw = scrollFrame:GetWidth()
    editBox:SetWidth((sw and sw > 0) and sw or 390)
    editBox:SetScript("OnEscapePressed", function() f:Hide() end)
    scrollFrame:SetScrollChild(editBox)

    local importBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    importBtn:SetSize(80, 22)
    importBtn:SetPoint("BOTTOMRIGHT", -100, 12)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        local text = editBox:GetText()
        if text and text ~= "" then
            local ok, result = Hooter:ImportConfig(text)
            if ok then
                Hooter:Print("Imported trigger |cff00ccff!" .. result .. "|r successfully.")
                Hooter:RefreshTriggerList()
                Hooter:RefreshResponseList()
                f:Hide()
            else
                Hooter:PrintError("Import failed: " .. result)
            end
        end
    end)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("BOTTOMLEFT", 100, 12)
    closeBtn:SetText("Cancel")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    f.editBox = editBox
    self.importDialog = f
end
