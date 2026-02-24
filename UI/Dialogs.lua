local _, Hooter = ...

-- Shared factory for text dialogs (export/import share a common frame layout)
local function CreateTextDialog(config)
    local f = CreateFrame("Frame", config.name, UIParent, "BackdropTemplate")
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
    title:SetText(config.title)

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

    f.editBox = editBox

    -- Create buttons from config
    for _, btn in ipairs(config.buttons) do
        local button = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        button:SetSize(80, 22)
        button:SetPoint(btn.anchor, btn.anchorX, 12)
        button:SetText(btn.text)
        button:SetScript("OnClick", btn.onClick(f, editBox))
    end

    return f
end

function Hooter:InitDialogs()
    self.exportDialog = CreateTextDialog({
        name = "HooterExportDialog",
        title = "Hooter - Export",
        buttons = {
            {
                text = "Close",
                anchor = "BOTTOM",
                anchorX = 0,
                onClick = function(f)
                    return function() f:Hide() end
                end,
            },
        },
    })

    self.importDialog = CreateTextDialog({
        name = "HooterImportDialog",
        title = "Hooter - Import",
        buttons = {
            {
                text = "Import",
                anchor = "BOTTOMRIGHT",
                anchorX = -100,
                onClick = function(f, editBox)
                    return function()
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
                    end
                end,
            },
            {
                text = "Cancel",
                anchor = "BOTTOMLEFT",
                anchorX = 100,
                onClick = function(f)
                    return function() f:Hide() end
                end,
            },
        },
    })
end
