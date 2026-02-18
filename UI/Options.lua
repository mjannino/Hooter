local _, Hooter = ...

-- Cached references for the trigger list refresh
local triggerListContent
local selectedTrigger
local responseListContent

-- Frame pools to avoid leaking frames on refresh
local triggerFramePool = {}
local responseFramePool = {}
local activeTriggerFrames = {}
local activeResponseFrames = {}

local function AcquireFrame(pool, parent)
    local f = table.remove(pool)
    if f then
        f:ClearAllPoints()
        f:Show()
        return f
    end
    return CreateFrame("Frame", nil, parent)
end

local function ReleaseFrames(pool, activeList)
    for i = #activeList, 1, -1 do
        activeList[i]:Hide()
        activeList[i]:ClearAllPoints()
        table.insert(pool, activeList[i])
        activeList[i] = nil
    end
end

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

function Hooter:OpenOptions()
    Settings.OpenToCategory(self.settingsCategory:GetID())
end

---------------------------------------------------------------------------
-- Panel Builder
---------------------------------------------------------------------------
function Hooter:BuildOptionsPanel(panel)
    -- Outer scroll fills the canvas so content can exceed the ~569px window
    local outerScroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    outerScroll:SetPoint("TOPLEFT", 0, 0)
    outerScroll:SetPoint("BOTTOMRIGHT", -22, 0)

    local outerContent = CreateFrame("Frame", nil, outerScroll)
    outerContent:SetSize(1, 1)
    outerScroll:SetScrollChild(outerContent)

    outerScroll:SetScript("OnSizeChanged", function(frame)
        local width = frame:GetWidth()
        if width > 0 then
            outerContent:SetWidth(width)
        end
    end)

    local yOffset = -16

    -- Title
    local title = outerContent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, yOffset)
    title:SetText("Hooter v" .. self.VERSION)
    yOffset = yOffset - 30

    local subtitle = outerContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", 16, yOffset)
    subtitle:SetText("Chat trigger auto-response addon with shareable configurations")
    yOffset = yOffset - 30

    ---------------------------------------------------------------------------
    -- Enable/Disable Checkbox
    ---------------------------------------------------------------------------
    local enableCB = CreateFrame("CheckButton", "HooterEnableCheck", outerContent, "UICheckButtonTemplate")
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
    local settingsHeader = outerContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    settingsHeader:SetPoint("TOPLEFT", 16, yOffset)
    settingsHeader:SetText("Settings")
    yOffset = yOffset - 25

    -- Forward-declare so cross-referencing callbacks can capture the locals
    local minDelaySlider, maxDelaySlider

    -- Cooldown Slider
    _, _, yOffset = self:CreateSlider(outerContent, "Cooldown (seconds)", 1, 30, 1, self.db.settings.cooldown, yOffset, function(value)
        Hooter.db.settings.cooldown = value
    end)

    -- Min Delay Slider
    minDelaySlider, _, yOffset = self:CreateSlider(outerContent, "Min Delay (seconds)", 0.0, 5.0, 0.1, self.db.settings.minDelay, yOffset, function(value)
        Hooter.db.settings.minDelay = value
        -- Clamp max delay if min exceeds it
        if value > Hooter.db.settings.maxDelay then
            Hooter.db.settings.maxDelay = value
            maxDelaySlider:SetValue(value)
        end
    end)

    -- Max Delay Slider
    maxDelaySlider, _, yOffset = self:CreateSlider(outerContent, "Max Delay (seconds)", 0.0, 10.0, 0.1, self.db.settings.maxDelay, yOffset, function(value)
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
    local trigHeader = outerContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    trigHeader:SetPoint("TOPLEFT", 16, yOffset)
    trigHeader:SetText("Triggers")
    yOffset = yOffset - 25

    -- Button row: Add Trigger, Import, Export
    local addBtn = CreateFrame("Button", nil, outerContent, "UIPanelButtonTemplate")
    addBtn:SetSize(100, 22)
    addBtn:SetPoint("TOPLEFT", 16, yOffset)
    addBtn:SetText("Add Trigger")
    addBtn:SetScript("OnClick", function()
        StaticPopup_Show("HOOTER_ADD_TRIGGER")
    end)

    local importBtn = CreateFrame("Button", nil, outerContent, "UIPanelButtonTemplate")
    importBtn:SetSize(80, 22)
    importBtn:SetPoint("LEFT", addBtn, "RIGHT", 8, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        Hooter:Cmd_import("")
    end)

    local exportBtn = CreateFrame("Button", nil, outerContent, "UIPanelButtonTemplate")
    exportBtn:SetSize(80, 22)
    exportBtn:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)
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
    -- Trigger Scroll List
    ---------------------------------------------------------------------------
    local triggerScroll = CreateFrame("ScrollFrame", "HooterTriggerScroll", outerContent, "UIPanelScrollFrameTemplate")
    triggerScroll:SetPoint("TOPLEFT", 16, yOffset)
    triggerScroll:SetPoint("TOPRIGHT", -48, yOffset)
    triggerScroll:SetHeight(200)

    triggerListContent = CreateFrame("Frame", nil, triggerScroll)
    triggerListContent:SetSize(1, 1)
    triggerScroll:SetScrollChild(triggerListContent)

    triggerScroll:SetScript("OnSizeChanged", function(frame)
        local width = frame:GetWidth()
        if width > 0 then
            triggerListContent:SetWidth(width)
            Hooter:RefreshTriggerList()
        end
    end)

    yOffset = yOffset - 210

    ---------------------------------------------------------------------------
    -- Response Editor (shown when trigger selected)
    ---------------------------------------------------------------------------
    local respHeader = outerContent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    respHeader:SetPoint("TOPLEFT", 16, yOffset)
    respHeader:SetText("Responses")
    self.respHeaderLabel = respHeader
    yOffset = yOffset - 25

    local respScroll = CreateFrame("ScrollFrame", "HooterResponseScroll", outerContent, "UIPanelScrollFrameTemplate")
    respScroll:SetPoint("TOPLEFT", 16, yOffset)
    respScroll:SetPoint("TOPRIGHT", -48, yOffset)
    respScroll:SetHeight(120)

    responseListContent = CreateFrame("Frame", nil, respScroll)
    responseListContent:SetSize(1, 1)
    respScroll:SetScrollChild(responseListContent)

    respScroll:SetScript("OnSizeChanged", function(frame)
        local width = frame:GetWidth()
        if width > 0 then
            responseListContent:SetWidth(width)
            Hooter:RefreshResponseList()
        end
    end)

    yOffset = yOffset - 130

    -- Add Response editbox + button
    local addRespBox = CreateFrame("EditBox", "HooterAddRespBox", outerContent, "InputBoxTemplate")
    addRespBox:SetSize(300, 20)
    addRespBox:SetPoint("TOPLEFT", 20, yOffset)
    addRespBox:SetAutoFocus(false)

    local addRespBtn = CreateFrame("Button", nil, outerContent, "UIPanelButtonTemplate")
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

    self.triggerListContent = triggerListContent
    self.responseListContent = responseListContent

    -- Set outer scroll child height so the scrollbar knows the content size
    outerContent:SetHeight(math.abs(yOffset) + 16)

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
-- Trigger List
---------------------------------------------------------------------------
function Hooter:RefreshTriggerList()
    if not self.triggerListContent then return end
    local content = self.triggerListContent
    local contentWidth = content:GetWidth()
    if contentWidth < 1 then return end

    ReleaseFrames(triggerFramePool, activeTriggerFrames)

    local yOff = 0
    local triggers = self:GetAllTriggers()

    local sortedKeys = {}
    for word in pairs(triggers) do
        table.insert(sortedKeys, word)
    end
    table.sort(sortedKeys)

    for _, word in ipairs(sortedKeys) do
        local data = triggers[word]
        local row = AcquireFrame(triggerFramePool, content)
        table.insert(activeTriggerFrames, row)
        row:SetSize(contentWidth, 24)
        row:SetPoint("TOPLEFT", 0, yOff)

        if not row.initialized then
            row.cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.cb:SetSize(24, 24)
            row.cb:SetPoint("LEFT", 0, 0)

            row.nameLabel = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            row.nameLabel:SetPoint("LEFT", row.cb, "RIGHT", 4, 0)
            row.nameLabel:SetPoint("RIGHT", row, "RIGHT", -115, 0)
            row.nameLabel:SetJustifyH("LEFT")
            row.nameLabel:SetWordWrap(false)

            row.editBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.editBtn:SetSize(50, 20)
            row.editBtn:SetPoint("RIGHT", row, "RIGHT", -60, 0)
            row.editBtn:SetText("Edit")

            row.delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.delBtn:SetSize(55, 20)
            row.delBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            row.delBtn:SetText("Delete")

            row.initialized = true
        end

        row.cb:SetChecked(data.enabled)
        row.cb:SetScript("OnClick", function()
            Hooter:SetTriggerEnabled(word, row.cb:GetChecked())
        end)
        row.nameLabel:SetText("|cff00ccff!" .. word .. "|r  (" .. #data.responses .. " responses)")
        row.editBtn:SetScript("OnClick", function()
            selectedTrigger = word
            Hooter.respHeaderLabel:SetText("Responses for |cff00ccff!" .. word .. "|r")
            Hooter:RefreshResponseList()
        end)
        row.delBtn:SetScript("OnClick", function()
            Hooter:RemoveTrigger(word)
            if selectedTrigger == word then
                selectedTrigger = nil
                Hooter:RefreshResponseList()
            end
            Hooter:RefreshTriggerList()
        end)

        yOff = yOff - 26
    end

    content:SetHeight(math.max(1, math.abs(yOff)))
end

---------------------------------------------------------------------------
-- Response List
---------------------------------------------------------------------------
function Hooter:RefreshResponseList()
    if not self.responseListContent then return end
    local content = self.responseListContent
    local contentWidth = content:GetWidth()
    if contentWidth < 1 then return end

    ReleaseFrames(responseFramePool, activeResponseFrames)

    if not selectedTrigger then
        self.respHeaderLabel:SetText("Responses (select a trigger)")
        return
    end

    local trigger = self:GetTrigger(selectedTrigger)
    if not trigger then
        selectedTrigger = nil
        self.respHeaderLabel:SetText("Responses (select a trigger)")
        return
    end

    local yOff = 0
    for i, resp in ipairs(trigger.responses) do
        local row = AcquireFrame(responseFramePool, content)
        table.insert(activeResponseFrames, row)
        row:SetSize(contentWidth, 22)
        row:SetPoint("TOPLEFT", 0, yOff)

        if not row.initialized then
            row.idx = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            row.idx:SetPoint("LEFT", 4, 0)

            row.respText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            row.respText:SetPoint("LEFT", 24, 0)
            row.respText:SetPoint("RIGHT", row, "RIGHT", -60, 0)
            row.respText:SetJustifyH("LEFT")
            row.respText:SetWordWrap(false)

            row.delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.delBtn:SetSize(55, 20)
            row.delBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            row.delBtn:SetText("Delete")

            row.initialized = true
        end

        row.idx:SetText(i .. ".")
        row.respText:SetText(resp)
        row.delBtn:SetScript("OnClick", function()
            Hooter:RemoveResponse(selectedTrigger, i)
            if not Hooter:GetTrigger(selectedTrigger) then
                selectedTrigger = nil
                Hooter:RefreshTriggerList()
            end
            Hooter:RefreshResponseList()
        end)

        yOff = yOff - 24
    end

    content:SetHeight(math.max(1, math.abs(yOff)))
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
            local word = dialog.editBox:GetText()
            if word and word ~= "" then
                word = word:lower():gsub("[^%w]", "")
                if word ~= "" then
                    if not Hooter.db.triggers[word] then
                        Hooter.db.triggers[word] = { enabled = true, responses = {} }
                    end
                    selectedTrigger = word
                    Hooter:RefreshTriggerList()
                    Hooter:RefreshResponseList()
                    Hooter.respHeaderLabel:SetText("Responses for |cff00ccff!" .. word .. "|r")
                end
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end
