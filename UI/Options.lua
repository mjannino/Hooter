local _, Hooter = ...

-- Module-level selection state
local selectedTrigger       -- string: currently selected trigger word (nil = none)
local selectedResponseIdx   -- number: currently selected response index (nil = none)

function Hooter:InitOptions()
    local panel = CreateFrame("Frame")
    panel.name = "Hooter"
    panel:Hide()

    panel:SetScript("OnShow", function()
        Hooter:BuildOptionsPanel(panel)
        panel:SetScript("OnShow", nil) -- Only build once
    end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    self.settingsCategory = category
end

---------------------------------------------------------------------------
-- Panel Builder
---------------------------------------------------------------------------
function Hooter:BuildOptionsPanel(panel)
    local yOffset = -16

    -- Title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, yOffset)
    title:SetText("Hooter v" .. self.VERSION)
    yOffset = yOffset - 30

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", 16, yOffset)
    subtitle:SetText("Chat trigger auto-response addon with shareable configurations")
    yOffset = yOffset - 30

    ---------------------------------------------------------------------------
    -- Enable/Disable Checkbox
    ---------------------------------------------------------------------------
    local enableCB = CreateFrame("CheckButton", "HooterEnableCheck", panel, "UICheckButtonTemplate")
    enableCB:SetPoint("TOPLEFT", 16, yOffset)
    enableCB.text = enableCB.text or enableCB:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    enableCB.text:SetPoint("LEFT", enableCB, "RIGHT", 4, 0)
    enableCB.text:SetText("Enable scanning on this character")
    enableCB:SetChecked(self:IsEnabled())
    enableCB:SetScript("OnClick", function(cb)
        Hooter:SetEnabled(cb:GetChecked())
    end)
    yOffset = yOffset - 30

    ---------------------------------------------------------------------------
    -- Settings Sliders
    ---------------------------------------------------------------------------
    yOffset = yOffset - 10
    local settingsHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    settingsHeader:SetPoint("TOPLEFT", 16, yOffset)
    settingsHeader:SetText("Settings")
    yOffset = yOffset - 25

    -- Forward-declare so cross-referencing callbacks can capture the locals
    local minDelaySlider, maxDelaySlider

    -- Cooldown Slider
    _, _, yOffset = self:CreateSlider(panel, "Cooldown (seconds)", 1, 30, 1, self.db.settings.cooldown, yOffset, function(value)
        Hooter.db.settings.cooldown = value
    end)

    -- Min Delay Slider
    minDelaySlider, _, yOffset = self:CreateSlider(panel, "Min Delay (seconds)", 0.0, 5.0, 0.1, self.db.settings.minDelay, yOffset, function(value)
        Hooter.db.settings.minDelay = value
        -- Clamp max delay if min exceeds it
        if value > Hooter.db.settings.maxDelay then
            Hooter.db.settings.maxDelay = value
            maxDelaySlider:SetValue(value)
        end
    end)

    -- Max Delay Slider
    maxDelaySlider, _, yOffset = self:CreateSlider(panel, "Max Delay (seconds)", 0.0, 10.0, 0.1, self.db.settings.maxDelay, yOffset, function(value)
        Hooter.db.settings.maxDelay = value
        -- Clamp min delay if max is below it
        if value < Hooter.db.settings.minDelay then
            Hooter.db.settings.minDelay = value
            minDelaySlider:SetValue(value)
        end
    end)

    ---------------------------------------------------------------------------
    -- Trigger Management
    ---------------------------------------------------------------------------
    yOffset = yOffset - 20
    local trigHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    trigHeader:SetPoint("TOPLEFT", 16, yOffset)
    trigHeader:SetText("Triggers")
    yOffset = yOffset - 25

    -- Trigger dropdown + buttons row
    local triggerDropdown = CreateFrame("Frame", "HooterTriggerDropdown", panel, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(triggerDropdown, 200)
    triggerDropdown:SetPoint("TOPLEFT", 0, yOffset)
    UIDropDownMenu_Initialize(triggerDropdown, function(dd, level)
        Hooter:InitTriggerDropdown(dd, level)
    end)
    UIDropDownMenu_SetText(triggerDropdown, "Select a trigger")
    self.triggerDropdown = triggerDropdown

    local addBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 22)
    addBtn:SetPoint("LEFT", triggerDropdown, "RIGHT", -10, 2)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        StaticPopup_Show("HOOTER_ADD_TRIGGER")
    end)

    local importBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    importBtn:SetSize(80, 22)
    importBtn:SetPoint("LEFT", addBtn, "RIGHT", 4, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        Hooter:Cmd_import("")
    end)

    local exportBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    exportBtn:SetSize(80, 22)
    exportBtn:SetPoint("LEFT", importBtn, "RIGHT", 4, 0)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        if not selectedTrigger then
            Hooter:PrintError("Select a trigger to export.")
            return
        end
        Hooter:Cmd_export("!" .. selectedTrigger)
    end)

    yOffset = yOffset - 30

    ---------------------------------------------------------------------------
    -- Trigger Edit Row (hidden when no trigger selected)
    ---------------------------------------------------------------------------
    local triggerEditRow = CreateFrame("Frame", nil, panel)
    triggerEditRow:SetSize(500, 26)
    triggerEditRow:SetPoint("TOPLEFT", 16, yOffset)
    triggerEditRow:Hide()
    self.triggerEditRow = triggerEditRow

    local triggerEditBox = CreateFrame("EditBox", "HooterTriggerEditBox", triggerEditRow, "InputBoxTemplate")
    triggerEditBox:SetSize(160, 20)
    triggerEditBox:SetPoint("LEFT", 4, 0)
    triggerEditBox:SetAutoFocus(false)
    self.triggerEditBox = triggerEditBox

    local renameBtn = CreateFrame("Button", nil, triggerEditRow, "UIPanelButtonTemplate")
    renameBtn:SetSize(70, 22)
    renameBtn:SetPoint("LEFT", triggerEditBox, "RIGHT", 8, 0)
    renameBtn:SetText("Rename")
    self.triggerRenameBtn = renameBtn
    renameBtn:SetScript("OnClick", function()
        if not selectedTrigger then return end
        local newWord = triggerEditBox:GetText():lower():gsub("[^%w]", "")
        if newWord == "" then
            Hooter:PrintError("Invalid trigger name.")
            return
        end
        local ok, err = Hooter:RenameTrigger(selectedTrigger, newWord)
        if ok then
            selectedTrigger = newWord
            Hooter:RefreshTriggerList()
        else
            Hooter:PrintError(err or "Rename failed.")
        end
    end)
    triggerEditBox:SetScript("OnEnterPressed", function()
        renameBtn:Click()
    end)

    local trigDeleteBtn = CreateFrame("Button", nil, triggerEditRow, "UIPanelButtonTemplate")
    trigDeleteBtn:SetSize(70, 22)
    trigDeleteBtn:SetPoint("LEFT", renameBtn, "RIGHT", 4, 0)
    trigDeleteBtn:SetText("Delete")
    self.triggerDeleteBtn = trigDeleteBtn
    trigDeleteBtn:SetScript("OnClick", function()
        if not selectedTrigger then return end
        Hooter:RemoveTrigger(selectedTrigger)
        selectedTrigger = nil
        selectedResponseIdx = nil
        Hooter:RefreshTriggerList()
    end)

    local trigEnableCB = CreateFrame("CheckButton", "HooterTriggerEnableCB", triggerEditRow, "UICheckButtonTemplate")
    trigEnableCB:SetPoint("LEFT", trigDeleteBtn, "RIGHT", 8, 0)
    trigEnableCB.text = trigEnableCB.text or trigEnableCB:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    trigEnableCB.text:SetPoint("LEFT", trigEnableCB, "RIGHT", 2, 0)
    trigEnableCB.text:SetText("Enabled")
    self.triggerEnableCB = trigEnableCB
    trigEnableCB:SetScript("OnClick", function(cb)
        if selectedTrigger then
            Hooter:SetTriggerEnabled(selectedTrigger, cb:GetChecked())
            Hooter:RefreshTriggerList()
        end
    end)

    yOffset = yOffset - 30

    ---------------------------------------------------------------------------
    -- Force Unique Row (hidden when no trigger selected)
    ---------------------------------------------------------------------------
    local uniqueRow = CreateFrame("Frame", nil, panel)
    uniqueRow:SetSize(500, 26)
    uniqueRow:SetPoint("TOPLEFT", 16, yOffset)
    uniqueRow:Hide()
    self.uniqueRow = uniqueRow

    local uniqueCB = CreateFrame("CheckButton", "HooterForceUniqueCB", uniqueRow, "UICheckButtonTemplate")
    uniqueCB:SetPoint("LEFT", 4, 0)
    uniqueCB.text = uniqueCB.text or uniqueCB:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    uniqueCB.text:SetPoint("LEFT", uniqueCB, "RIGHT", 2, 0)
    uniqueCB.text:SetText("Force Unique Responses")
    self.uniqueCB = uniqueCB
    uniqueCB:SetScript("OnClick", function(cb)
        if selectedTrigger then
            local trigger = Hooter:GetTrigger(selectedTrigger)
            if trigger then
                trigger.forceUnique = cb:GetChecked()
                Hooter:UpdateUniqueArea()
            end
        end
    end)

    local overflowDropdown = CreateFrame("Frame", "HooterOverflowDropdown", uniqueRow, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(overflowDropdown, 100)
    overflowDropdown:SetPoint("LEFT", uniqueCB.text, "RIGHT", 10, 0)
    UIDropDownMenu_Initialize(overflowDropdown, function(dd, level)
        if not selectedTrigger then return end
        local trigger = Hooter:GetTrigger(selectedTrigger)
        if not trigger then return end

        local options = { { value = "silent", text = "Silent" }, { value = "wrap", text = "Wrap" } }
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.text
            info.value = opt.value
            info.checked = (trigger.uniqueOverflow or "silent") == opt.value
            info.func = function(btn)
                trigger.uniqueOverflow = btn.value
                UIDropDownMenu_SetSelectedValue(dd, btn.value)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    self.overflowDropdown = overflowDropdown

    yOffset = yOffset - 30

    ---------------------------------------------------------------------------
    -- Response Section
    ---------------------------------------------------------------------------
    local respHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    respHeader:SetPoint("TOPLEFT", 16, yOffset)
    respHeader:SetText("Responses (select a trigger)")
    self.respHeaderLabel = respHeader
    yOffset = yOffset - 25

    -- Response dropdown
    local responseDropdown = CreateFrame("Frame", "HooterResponseDropdown", panel, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(responseDropdown, 350)
    responseDropdown:SetPoint("TOPLEFT", 0, yOffset)
    UIDropDownMenu_Initialize(responseDropdown, function(dd, level)
        Hooter:InitResponseDropdown(dd, level)
    end)
    UIDropDownMenu_SetText(responseDropdown, "Select a response")
    self.responseDropdown = responseDropdown

    yOffset = yOffset - 30

    ---------------------------------------------------------------------------
    -- Response Edit Row (hidden when no response selected)
    ---------------------------------------------------------------------------
    local respEditRow = CreateFrame("Frame", nil, panel)
    respEditRow:SetSize(500, 26)
    respEditRow:SetPoint("TOPLEFT", 16, yOffset)
    respEditRow:Hide()
    self.respEditRow = respEditRow

    local respEditBox = CreateFrame("EditBox", "HooterRespEditBox", respEditRow, "InputBoxTemplate")
    respEditBox:SetSize(300, 20)
    respEditBox:SetPoint("LEFT", 4, 0)
    respEditBox:SetAutoFocus(false)
    self.respEditBox = respEditBox

    local respSaveBtn = CreateFrame("Button", nil, respEditRow, "UIPanelButtonTemplate")
    respSaveBtn:SetSize(60, 22)
    respSaveBtn:SetPoint("LEFT", respEditBox, "RIGHT", 8, 0)
    respSaveBtn:SetText("Save")
    self.respSaveBtn = respSaveBtn
    respSaveBtn:SetScript("OnClick", function()
        if not selectedTrigger or not selectedResponseIdx then return end
        local trigger = Hooter:GetTrigger(selectedTrigger)
        if not trigger then return end
        local text = respEditBox:GetText()
        if text and text ~= "" then
            trigger.responses[selectedResponseIdx] = text
            Hooter:RefreshResponseList()
        end
    end)
    respEditBox:SetScript("OnEnterPressed", function()
        respSaveBtn:Click()
    end)

    local respDeleteBtn = CreateFrame("Button", nil, respEditRow, "UIPanelButtonTemplate")
    respDeleteBtn:SetSize(70, 22)
    respDeleteBtn:SetPoint("LEFT", respSaveBtn, "RIGHT", 4, 0)
    respDeleteBtn:SetText("Delete")
    self.respDeleteBtn = respDeleteBtn
    respDeleteBtn:SetScript("OnClick", function()
        if not selectedTrigger or not selectedResponseIdx then return end
        Hooter:RemoveResponse(selectedTrigger, selectedResponseIdx)
        selectedResponseIdx = nil
        if not Hooter:GetTrigger(selectedTrigger) then
            selectedTrigger = nil
            Hooter:RefreshTriggerList()
        else
            Hooter:RefreshResponseList()
        end
    end)

    yOffset = yOffset - 30

    ---------------------------------------------------------------------------
    -- Add Response Row
    ---------------------------------------------------------------------------
    local addRespBox = CreateFrame("EditBox", "HooterAddRespBox", panel, "InputBoxTemplate")
    addRespBox:SetSize(300, 20)
    addRespBox:SetPoint("TOPLEFT", 20, yOffset)
    addRespBox:SetAutoFocus(false)

    local addRespBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    addRespBtn:SetSize(100, 22)
    addRespBtn:SetPoint("LEFT", addRespBox, "RIGHT", 8, 0)
    addRespBtn:SetText("Add Response")
    addRespBtn:SetScript("OnClick", function()
        if not selectedTrigger then
            Hooter:PrintError("Select a trigger first.")
            return
        end
        local text = addRespBox:GetText()
        if text and text ~= "" then
            Hooter:AddTrigger(selectedTrigger, text)
            addRespBox:SetText("")
            Hooter:RefreshTriggerList()
            Hooter:RefreshResponseList()
        end
    end)
    addRespBox:SetScript("OnEnterPressed", function()
        addRespBtn:Click()
    end)

    -- Static Popups
    self:RegisterPopups()
end

---------------------------------------------------------------------------
-- Slider Factory
---------------------------------------------------------------------------
function Hooter:CreateSlider(parent, label, minVal, maxVal, step, currentVal, yOffset, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(300, 40)
    container:SetPoint("TOPLEFT", 16, yOffset)

    local text = container:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetText(label)

    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 0, -16)
    slider:SetSize(200, 17)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(currentVal)

    slider.Low:SetText(tostring(minVal))
    slider.High:SetText(tostring(maxVal))

    local valText = container:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    valText:SetPoint("LEFT", slider, "RIGHT", 10, 0)
    valText:SetText(string.format("%.1f", currentVal))

    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        valText:SetText(string.format("%.1f", value))
        onChange(value)
    end)

    return slider, valText, yOffset - 50
end

---------------------------------------------------------------------------
-- Trigger Dropdown Initializer
---------------------------------------------------------------------------
function Hooter:InitTriggerDropdown(dropdown, level)
    local triggers = self:GetAllTriggers()
    local sortedKeys = {}
    for word in pairs(triggers) do
        table.insert(sortedKeys, word)
    end
    table.sort(sortedKeys)

    for _, word in ipairs(sortedKeys) do
        local info = UIDropDownMenu_CreateInfo()
        local data = triggers[word]
        local status = data.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        info.text = "!" .. word .. " (" .. #data.responses .. ") " .. status
        info.value = word
        info.func = function(btn)
            selectedTrigger = btn.value
            selectedResponseIdx = nil
            UIDropDownMenu_SetSelectedValue(dropdown, btn.value)
            Hooter:UpdateTriggerEditArea()
            Hooter:RefreshResponseList()
        end
        UIDropDownMenu_AddButton(info, level)
    end
end

---------------------------------------------------------------------------
-- Response Dropdown Initializer
---------------------------------------------------------------------------
function Hooter:InitResponseDropdown(dropdown, level)
    if not selectedTrigger then return end
    local trigger = self:GetTrigger(selectedTrigger)
    if not trigger then return end

    for i, resp in ipairs(trigger.responses) do
        local info = UIDropDownMenu_CreateInfo()
        local display = resp
        if #display > 60 then
            display = display:sub(1, 57) .. "..."
        end
        info.text = i .. ". " .. display
        info.value = i
        info.func = function(btn)
            selectedResponseIdx = btn.value
            UIDropDownMenu_SetSelectedValue(dropdown, btn.value)
            Hooter:UpdateResponseEditArea()
        end
        UIDropDownMenu_AddButton(info, level)
    end
end

---------------------------------------------------------------------------
-- Refresh Functions (names kept for Commands.lua compatibility)
---------------------------------------------------------------------------
function Hooter:RefreshTriggerList()
    if not self.triggerDropdown then return end
    UIDropDownMenu_Initialize(self.triggerDropdown, function(dd, level)
        Hooter:InitTriggerDropdown(dd, level)
    end)
    -- Validate selection still exists
    if selectedTrigger and not self:GetTrigger(selectedTrigger) then
        selectedTrigger = nil
        selectedResponseIdx = nil
    end
    if selectedTrigger then
        UIDropDownMenu_SetSelectedValue(self.triggerDropdown, selectedTrigger)
    else
        UIDropDownMenu_SetText(self.triggerDropdown, "Select a trigger")
    end
    self:UpdateTriggerEditArea()
    self:RefreshResponseList()
end

function Hooter:RefreshResponseList()
    if not self.responseDropdown then return end
    UIDropDownMenu_Initialize(self.responseDropdown, function(dd, level)
        Hooter:InitResponseDropdown(dd, level)
    end)
    -- Validate selection
    if selectedResponseIdx then
        local trigger = selectedTrigger and self:GetTrigger(selectedTrigger)
        if not trigger or selectedResponseIdx > #trigger.responses then
            selectedResponseIdx = nil
        end
    end
    if selectedResponseIdx then
        UIDropDownMenu_SetSelectedValue(self.responseDropdown, selectedResponseIdx)
    else
        UIDropDownMenu_SetText(self.responseDropdown, "Select a response")
    end
    self:UpdateResponseEditArea()
end

---------------------------------------------------------------------------
-- Edit Area Visibility
---------------------------------------------------------------------------
function Hooter:UpdateTriggerEditArea()
    if not self.triggerEditRow then return end
    if selectedTrigger and self:GetTrigger(selectedTrigger) then
        self.triggerEditRow:Show()
        self.triggerEditBox:SetText(selectedTrigger)
        self.triggerEnableCB:SetChecked(self:GetTrigger(selectedTrigger).enabled)
        self.respHeaderLabel:SetText("Responses for |cff00ccff!" .. selectedTrigger .. "|r")
        self:UpdateUniqueArea()
    else
        self.triggerEditRow:Hide()
        if self.uniqueRow then self.uniqueRow:Hide() end
        self.respHeaderLabel:SetText("Responses (select a trigger)")
    end
end

function Hooter:UpdateUniqueArea()
    if not self.uniqueRow then return end
    local trigger = selectedTrigger and self:GetTrigger(selectedTrigger)
    if not trigger then
        self.uniqueRow:Hide()
        return
    end
    self.uniqueRow:Show()
    self.uniqueCB:SetChecked(trigger.forceUnique or false)
    if trigger.forceUnique then
        UIDropDownMenu_SetSelectedValue(self.overflowDropdown, trigger.uniqueOverflow or "silent")
        UIDropDownMenu_SetText(self.overflowDropdown, (trigger.uniqueOverflow or "silent") == "wrap" and "Wrap" or "Silent")
        self.overflowDropdown:Show()
    else
        self.overflowDropdown:Hide()
    end
end

function Hooter:UpdateResponseEditArea()
    if not self.respEditRow then return end
    if selectedResponseIdx and selectedTrigger then
        local trigger = self:GetTrigger(selectedTrigger)
        if trigger and trigger.responses[selectedResponseIdx] then
            self.respEditRow:Show()
            self.respEditBox:SetText(trigger.responses[selectedResponseIdx])
            return
        end
    end
    self.respEditRow:Hide()
end

---------------------------------------------------------------------------
-- Static Popups
---------------------------------------------------------------------------
function Hooter:RegisterPopups()
    StaticPopupDialogs["HOOTER_ADD_TRIGGER"] = {
        text = "Enter trigger word (without !):",
        button1 = "OK",
        button2 = "Cancel",
        hasEditBox = true,
        editBoxWidth = 200,
        OnAccept = function(dialog)
            local word = dialog.EditBox:GetText()
            if word and word ~= "" then
                word = word:lower():gsub("[^%w]", "")
                if word ~= "" then
                    if not Hooter.db.triggers[word] then
                        Hooter.db.triggers[word] = { enabled = true, responses = {} }
                    end
                    selectedTrigger = word
                    selectedResponseIdx = nil
                    Hooter:RefreshTriggerList()
                end
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end
