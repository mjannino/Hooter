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

local COMMANDS = {
    enable   = "Cmd_enable",
    disable  = "Cmd_disable",
    add      = "Cmd_add",
    remove   = "Cmd_remove",
    list     = "Cmd_list",
    export   = "Cmd_export",
    import   = "Cmd_import",
    share    = "Cmd_share",
    cooldown = "Cmd_cooldown",
    delay    = "Cmd_delay",
    unique   = "Cmd_unique",
    help     = "PrintHelp",
}

function Hooter:HandleCommand(input)
    local cmd, rest = input:match("^(%S+)%s*(.*)$")
    if not cmd then
        self:OpenOptions()
        return
    end
    local handler = COMMANDS[cmd:lower()]
    if handler then
        self[handler](self, rest)
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
    print("  /hooter share !word [channel] - Share trigger as clickable chat link")
    print("  /hooter cooldown <sec>  - Set trigger cooldown")
    print("  /hooter delay <min> <max> - Set response delay range")
    print("  /hooter unique !word [silent|wrap] - Toggle force unique responses")
end

function Hooter:OpenOptions()
    Settings.OpenToCategory(self.settingsCategory:GetID())
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
    self.exportDialog.editBox:SetText(str)
    self.exportDialog:Show()
    self.exportDialog.editBox:HighlightText()
    self.exportDialog.editBox:SetFocus()
    self:Print("Export string for |cff00ccff!" .. word:lower() .. "|r generated. Press Ctrl+C to copy.")
end

function Hooter:Cmd_import(rest)
    if not rest or rest == "" then
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

function Hooter:Cmd_share(rest)
    local word, channel = rest:match("^!(%w+)%s*(%S*)$")
    if not word then
        self:PrintError("Usage: /hooter share !word [channel]")
        return
    end
    word = word:lower()
    if not self:GetTrigger(word) then
        self:PrintError("Trigger !" .. word .. " not found.")
        return
    end
    local chatType, err = self:ResolveShareChannel(channel)
    if not chatType then
        self:PrintError(err)
        return
    end
    self:SendShareData(word, chatType)
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

function Hooter:Cmd_unique(rest)
    local word, overflow = rest:match("^!(%w+)%s*(%w*)$")
    if not word then
        self:PrintError("Usage: /hooter unique !word [silent|wrap]")
        return
    end
    word = word:lower()
    local trigger = self:GetTrigger(word)
    if not trigger then
        self:PrintError("Trigger !" .. word .. " not found.")
        return
    end

    -- Toggle forceUnique
    trigger.forceUnique = not trigger.forceUnique

    -- Set overflow policy if provided
    if overflow == "silent" or overflow == "wrap" then
        trigger.uniqueOverflow = overflow
    end

    local status = trigger.forceUnique and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local overflowStr = trigger.forceUnique and (" (overflow: " .. (trigger.uniqueOverflow or "silent") .. ")") or ""
    self:Print("Force unique for |cff00ccff!" .. word .. "|r: " .. status .. overflowStr)
end
