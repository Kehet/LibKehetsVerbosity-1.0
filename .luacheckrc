std = "lua51" -- WoW runs Lua 5.1
max_line_length = false
unused_args = false -- event handler and callback signatures are fixed by the API

exclude_files = {
    "tests/**", -- runs outside the game and defines the game globals itself
}

-- WoW API, FrameXML and libraries
read_globals = {
    "ChatTypeInfo",
    "CombatText_AddMessage",
    "CombatText_StandardScroll",
    "DEFAULT_CHAT_FRAME",
    "GetChatWindowInfo",
    "LibStub",
    "NUM_CHAT_WINDOWS",
    "PlaySound",
    "PlaySoundFile",
    "RaidBossEmoteFrame",
    "RaidNotice_AddMessage",
    "RaidWarningFrame",
    "UIErrorsFrame",
}
