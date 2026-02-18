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
    "UIParent", "StaticPopupDialogs", "LibStub",
    "GameFontNormal", "GameFontNormalLarge",
    "GameFontHighlight", "GameFontHighlightSmall", "ChatFontNormal",
}

globals = {
    "Hooter", "HooterDB", "HooterCharDB",
    "SlashCmdList", "SLASH_HOOTER1", "SLASH_HOOTER2",
}
