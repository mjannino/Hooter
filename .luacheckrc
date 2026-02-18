std = "lua51"
max_line_length = false
unused_args = false
allow_defined_top = true

exclude_files = {
    "Libs/**",
}

read_globals = {
    "CreateFrame", "C_ChatInfo", "C_Timer", "GetTime",
    "UnitName", "Ambiguate", "CopyTable",
    "StaticPopup_Show", "Settings",
    "UIParent", "LibStub",
    "GameFontNormal", "GameFontNormalLarge",
    "GameFontHighlight", "GameFontHighlightSmall", "ChatFontNormal",
    "UIDropDownMenu_Initialize", "UIDropDownMenu_SetWidth",
    "UIDropDownMenu_SetText", "UIDropDownMenu_SetSelectedValue",
    "UIDropDownMenu_CreateInfo", "UIDropDownMenu_AddButton",
}

globals = {
    "Hooter", "HooterDB", "HooterCharDB",
    "SlashCmdList", "SLASH_HOOTER1", "SLASH_HOOTER2",
    "StaticPopupDialogs",
}
