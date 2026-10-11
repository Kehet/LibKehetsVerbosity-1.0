-- Runs the library outside the game with stand-ins for the WoW API: lua5.1 tests/test.lua
local libraries = {}

LibStub = setmetatable({}, {
    __call = function(_, major)
        return libraries[major] or error("Library " .. major .. " is not loaded")
    end,
})

function LibStub:NewLibrary(major, minor)
    local library = libraries[major]
    if library and library.minor >= minor then
        return nil
    end
    library = library or {}
    library.minor = minor
    libraries[major] = library
    return library
end

local played, shownIn = {}, {}
local openWindows = {}

NUM_CHAT_WINDOWS = 10
ChatTypeInfo = { RAID_WARNING = {}, RAID_BOSS_EMOTE = {} }
RaidWarningFrame = { name = "raid" }
RaidBossEmoteFrame = { name = "emote" }
UIErrorsFrame = {}

function UIErrorsFrame:AddMessage(text)
    table.insert(shownIn, "errors: " .. text)
end

function CombatText_AddMessage(text)
    table.insert(shownIn, "combat: " .. text)
end

function PlaySound(kit, channel)
    table.insert(played, "kit " .. kit .. " " .. channel)
end

function PlaySoundFile(file, channel)
    table.insert(played, "file " .. file .. " " .. channel)
end

function RaidNotice_AddMessage(frame, text)
    table.insert(shownIn, frame.name .. ": " .. text)
end

function GetChatWindowInfo(index)
    local window = openWindows[index]
    if not window then
        return "", 12, 1, 1, 1, 0, false, false, nil
    end
    return window.name, 12, 1, 1, 1, 0, window.shown, false, window.docked
end

local function OpenWindow(index, name, shown, docked)
    openWindows[index] = { name = name, shown = shown, docked = docked }
    _G["ChatFrame" .. index] = { AddMessage = function() end, index = index, GetID = function() return index end }
end

OpenWindow(1, "General", true, 1)
OpenWindow(2, "Combat Log", false, 2)
OpenWindow(3, "Loot", false, 3)
DEFAULT_CHAT_FRAME = ChatFrame1

dofile("LibKehetsVerbosity-1.0.lua")
local lib = LibStub("LibKehetsVerbosity-1.0")

local printed = {}

-- Print works like the one of AceConsole: a chat frame may come before the text
local function NewAddon(db)
    local addon = lib:Embed({ name = "Test", db = db })
    function addon:Print(frame, text)
        if text == nil then
            frame, text = nil, frame
        end
        table.insert(printed, (frame and frame.index or "default") .. ": " .. text)
    end
    return addon
end

local function Reset()
    printed, played, shownIn = {}, {}, {}
end

local function Equal(actual, expected, what)
    if actual ~= expected then
        error(what .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local TYPES = {
    roll = { name = "Rolls", order = 1 },
    alert = { name = "Alerts", order = 2, outputs = { "chat", "raid" }, sound = { kit = 12 } },
    debug = { name = "Debug", order = 3, shown = false, tag = "[Debug]" },
}

local profile = {}
local addon = NewAddon({ profile = profile })
addon:RegisterMessageTypes(TYPES)
local options = addon:GetMessageOptions()

local function Set(key, field, value)
    options.args["type_" .. key].args[field].set(nil, value)
end

local function SetOutput(key, output, state)
    options.args["type_" .. key].args.outputs.set(nil, output, state)
end

local function HasOutput(key, output)
    return options.args["type_" .. key].args.outputs.get(nil, output)
end

local function IsDisabled(key, field)
    return options.args["type_" .. key].args[field].disabled()
end

-- Declared defaults
Reset()
Equal(addon:Notify("roll", "Need |Hitem:1|h[Sword]|h 100%"), true, "shown type returns true")
Equal(printed[1], "1: Need |Hitem:1|h[Sword]|h 100%", "text is passed through unchanged")
Equal(addon:Notify("debug", "hidden"), false, "type that is off returns false")
Equal(#printed, 1, "type that is off prints nothing")
Equal(addon:IsMessageShown("roll"), true, "roll is shown")
Equal(addon:IsMessageShown("debug"), false, "debug is not shown")

-- Force prints a type that is off, with its tag
Reset()
Equal(addon:Notify("debug", "forced", { force = true }), true, "forced type returns true")
Equal(printed[1], "1: [Debug] forced", "tag is put in front")

-- Chat, raid warning and sound together
Reset()
addon:Notify("alert", "Valor Points is full!")
Equal(printed[1], "1: Valor Points is full!", "prints to the default chat window")
Equal(shownIn[1], "raid: Valor Points is full!", "shows the raid warning")
Equal(played[1], "kit 12 Master", "sound plays")
Equal(HasOutput("alert", "chat1"), true, "default chat window is ticked")
Equal(HasOutput("alert", "raid"), true, "raid warning is ticked")
Equal(HasOutput("alert", "errors"), false, "error frame is not ticked")

-- The sound has its own switch, and plays also when the text is off
Reset()
Set("alert", "shown", false)
addon:Notify("alert", "text")
Equal(#printed + #shownIn, 0, "text is off")
Equal(#played, 1, "sound still plays")
Equal(IsDisabled("alert", "outputs"), true, "outputs are disabled while the text is off")
Set("alert", "sound", false)
addon:Notify("alert", "text")
Equal(#played, 1, "sound is off")
Set("alert", "shown", true)
Set("alert", "sound", true)
Equal(profile.verbosity, nil, "settings back at their defaults are not saved")

-- Sound without text
Reset()
Equal(addon:Notify("alert"), false, "no text returns false")
Equal(#played, 1, "sound plays without text")
Equal(#printed + #shownIn, 0, "nothing is shown without text")

-- Every frame
Reset()
SetOutput("roll", "chat1", false)
SetOutput("roll", "errors", true)
SetOutput("roll", "emote", true)
SetOutput("roll", "combat", true)
SetOutput("roll", "raid", true)
addon:Notify("roll", "everywhere")
table.sort(shownIn)
Equal(table.concat(shownIn, ", "), "combat: everywhere, emote: everywhere, errors: everywhere, raid: everywhere", "shows in every frame")
Equal(#printed, 0, "chat is not ticked")
Equal(profile.verbosity.types.roll.outputs.errors, true, "changed outputs are saved")

-- A frame that is not there is left out
Reset()
local combatText = CombatText_AddMessage
CombatText_AddMessage = nil
addon:Notify("roll", "no combat text")
Equal(#shownIn, 3, "missing frame is skipped")
Equal(options.args.type_roll.args.outputs.values().combat, nil, "missing frame is not listed")
CombatText_AddMessage = combatText
for _, output in ipairs({ "errors", "emote", "combat", "raid" }) do
    SetOutput("roll", output, false)
end

-- Parrot scroll areas are outputs while Parrot is loaded
Reset()
Equal(options.args.type_roll.args.outputs.values()["parrot:Notification"], nil, "no Parrot areas without Parrot")
Parrot = {
    GetScrollAreasChoices = function() return { Notification = "Notification", Incoming = "Incoming" } end,
    ShowMessage = function(_, text, area, sticky)
        table.insert(shownIn, "parrot " .. area .. (sticky and " sticky" or "") .. ": " .. text)
    end,
}
Equal(options.args.type_roll.args.outputs.values()["parrot:Notification"], "Parrot: Notification", "Parrot areas are listed")
SetOutput("roll", "parrot:Notification", true)
Equal(addon:Notify("roll", "caw"), true, "shown in Parrot")
Equal(shownIn[1], "parrot Notification: caw", "goes to the chosen scroll area")
Equal(#printed, 0, "Parrot only does not print to chat")
Reset()
Equal(options.args.type_roll.args.outputs.values()["parrotsticky:Incoming"], "Parrot: Incoming (sticky)", "sticky areas are listed")
SetOutput("roll", "parrot:Notification", false)
SetOutput("roll", "parrotsticky:Incoming", true)
addon:Notify("roll", "caw")
Equal(shownIn[1], "parrot Incoming sticky: caw", "goes to the scroll area as sticky")
SetOutput("roll", "parrotsticky:Incoming", false)
SetOutput("roll", "parrot:Notification", true)

-- A Parrot that fails or is gone does not stop the message
Reset()
Parrot.ShowMessage = function() error("broken") end
Equal(addon:Notify("roll", "broken"), true, "broken Parrot still shows the message")
Equal(printed[1], "default: broken", "broken Parrot falls back to chat")
Parrot = nil
Reset()
Equal(addon:Notify("roll", "gone"), true, "missing Parrot still shows the message")
Equal(printed[1], "default: gone", "missing Parrot falls back to chat")
SetOutput("roll", "parrot:Notification", false)

-- MSBT scroll areas work the same way, with colours from 0 to 255
Reset()
MikSBT = {
    IterateScrollAreas = function() return pairs({ Notification = "Notification", Static = "Static" }) end,
    DisplayMessage = function(text, area, sticky, r)
        table.insert(shownIn, "msbt " .. area .. (sticky and " sticky" or "") .. " " .. r .. ": " .. text)
    end,
}
local names = options.args.type_roll.args.outputs.values()
Equal(names["msbt:Static"], "MSBT: Static", "MSBT areas are listed")
Equal(names["msbtsticky:Static"], "MSBT: Static (sticky)", "sticky MSBT areas are listed")
SetOutput("roll", "msbt:Notification", true)
SetOutput("roll", "msbtsticky:Static", true)
addon:Notify("roll", "mik")
table.sort(shownIn)
Equal(table.concat(shownIn, ", "), "msbt Notification 255: mik, msbt Static sticky 255: mik", "goes to the chosen MSBT areas")
MikSBT = nil
Reset()
Equal(addon:Notify("roll", "gone"), true, "missing MSBT still shows the message")
Equal(printed[1], "default: gone", "missing MSBT falls back to chat")
SetOutput("roll", "msbt:Notification", false)
SetOutput("roll", "msbtsticky:Static", false)

-- BigWigs shows messages only while its Messages plugin is enabled
Reset()
local bigWigsEnabled = false
BigWigsLoader = {
    SendMessage = function(_, event, _, _, text, _, _, emphasized)
        table.insert(shownIn, event .. (emphasized and " emphasized" or "") .. ": " .. text)
    end,
}
BigWigs = {
    GetPlugin = function() return { IsEnabled = function() return bigWigsEnabled end } end,
}
names = options.args.type_roll.args.outputs.values()
Equal(names["bigwigs:normal"], "BigWigs: Messages", "BigWigs messages are listed")
Equal(names["bigwigs:emphasized"], "BigWigs: Emphasized messages", "BigWigs emphasized messages are listed")
Equal(names["bigwigssticky:normal"], nil, "BigWigs has no sticky style")
SetOutput("roll", "bigwigs:emphasized", true)
addon:Notify("roll", "wig")
Equal(#shownIn, 0, "BigWigs that is not enabled shows nothing")
Equal(printed[1], "default: wig", "BigWigs that is not enabled falls back to chat")
Reset()
bigWigsEnabled = true
addon:Notify("roll", "wig")
Equal(shownIn[1], "BigWigs_Message emphasized: wig", "goes to the BigWigs emphasized messages")
Equal(#printed, 0, "enabled BigWigs does not print to chat")
SetOutput("roll", "bigwigs:emphasized", false)
BigWigs, BigWigsLoader = nil, nil

-- DBM
Reset()
DBM = {
    AddWarning = function(_, text) table.insert(shownIn, "dbm warning: " .. text) end,
    AddSpecialWarning = function(_, text, _, _, _, _, noSound)
        table.insert(shownIn, "dbm special" .. (noSound and " silent" or "") .. ": " .. text)
    end,
}
names = options.args.type_roll.args.outputs.values()
Equal(names["dbm:warning"], "DBM: Warnings", "DBM warnings are listed")
Equal(names["dbm:special"], "DBM: Special warnings", "DBM special warnings are listed")
SetOutput("roll", "dbm:warning", true)
SetOutput("roll", "dbm:special", true)
addon:Notify("roll", "pull")
table.sort(shownIn)
Equal(table.concat(shownIn, ", "), "dbm special silent: pull, dbm warning: pull", "goes to the DBM frames")
SetOutput("roll", "dbm:warning", false)
SetOutput("roll", "dbm:special", false)
DBM = nil

-- No output is the same as off
Reset()
Equal(addon:Notify("roll", "nowhere"), false, "no output returns false")
Equal(#printed + #shownIn, 0, "no output shows nothing")
SetOutput("roll", "chat1", true)
Equal(profile.verbosity, nil, "outputs back at their defaults are not saved")

-- Chat windows
Reset()
SetOutput("roll", "chat3", true)
addon:Notify("roll", "to both")
table.sort(printed)
Equal(table.concat(printed, ", "), "1: to both, 3: to both", "prints to every chosen window")
SetOutput("roll", "chat1", false)
openWindows[3] = nil
Reset()
Equal(addon:Notify("roll", "to default"), true, "closed window still shows the message")
Equal(printed[1], "default: to default", "closed window falls back to the default")
Equal(profile.verbosity.types.roll.outputs.chat3, true, "closed window stays saved")
names = options.args.type_roll.args.outputs.values()
Equal(names.chat1, "General", "list has open windows by name")
Equal(names.chat2, nil, "list leaves out the combat log")
Equal(names.chat3, nil, "list leaves out closed windows")
Equal(names.raid, "Raid warning frame", "list has the raid warning frame")
Equal(names.emote, "Boss emote frame", "list has the boss emote frame")
Equal(names.errors, "Error frame", "list has the error frame")
Equal(names.combat, "Floating combat text", "list has the floating combat text")
SetOutput("roll", "chat3", false)
SetOutput("roll", "chat1", true)
Equal(profile.verbosity, nil, "outputs back at their defaults are not saved")

-- Mute
Reset()
options.args.mute.set(nil, true)
Equal(options.args.mute.get(), true, "mute is saved")
Equal(addon:Notify("alert", "muted"), false, "muted type returns false")
Equal(#printed + #shownIn + #played, 0, "mute stops text and sound")
Equal(addon:IsMessageShown("roll"), false, "nothing is shown while muted")
Equal(addon:Notify("roll", "dry run", { force = true }), true, "force goes through the mute")
Equal(IsDisabled("roll", "shown"), true, "controls are disabled while muted")
options.args.mute.set(nil, false)
Equal(profile.verbosity, nil, "mute off is not saved")

-- SetMessageShown
addon:SetMessageShown("debug", true)
Equal(addon:IsMessageShown("debug"), true, "debug is turned on")
Equal(IsDisabled("debug", "outputs"), false, "outputs are enabled for a shown type")
addon:SetMessageShown("debug", false)
Equal(profile.verbosity, nil, "debug back at its default is not saved")

-- Before the database exists the declared defaults apply and settings do nothing
Reset()
local early = NewAddon(nil)
early:RegisterMessageTypes(TYPES)
Equal(early:Notify("roll", "early"), true, "prints without a database")
Equal(early:IsMessageShown("debug"), false, "defaults apply without a database")
early:SetMessageShown("debug", true)
Equal(early:GetMessageOptions().args.type_debug.args.shown.get(), false, "settings do nothing without a database")

-- Options group
Equal(options.args.type_roll.order, 1, "types follow their order")
Equal(options.args.type_debug.order, 3, "types follow their order")
Equal(options.args.type_roll.args.sound, nil, "no sound toggle without a sound")
Equal(options.args.type_alert.args.sound ~= nil, true, "sound toggle with a sound")

-- Errors
Equal(pcall(addon.Notify, addon, "missing", "text"), false, "unknown type is an error")
Equal(pcall(addon.RegisterMessageTypes, NewAddon(nil), { bad = { outputs = { "nowhere" } } }), false, "unknown output is an error")

-- Sound file
Reset()
local filed = NewAddon(nil)
filed:RegisterMessageTypes({ join = { sound = { file = 550773, channel = "SFX" } } })
filed:Notify("join")
Equal(played[1], "file 550773 SFX", "sound file plays on its channel")

-- Settings page
local registered, opened = {}, {}
libraries["AceConfig-3.0"] = {
    RegisterOptionsTable = function(_, appName, optionsTable) registered[appName] = optionsTable end,
}
libraries["AceConfigDialog-3.0"] = {
    AddToBlizOptions = function(_, appName, displayName) registered.display = displayName end,
    Open = function(_, appName) table.insert(opened, appName) end,
}
addon:RegisterMessagePage()
Equal(registered.Test().name, "Test", "page is named after the addon")
Equal(registered.display, "Test", "page is listed under the addon name")
addon:OpenMessagePage()
Equal(opened[1], "Test", "page opens")

-- A copy of the same version loads without replacing what is registered
dofile("LibKehetsVerbosity-1.0.lua")
Equal(addon:IsMessageShown("roll"), true, "types survive a second copy")

print("All tests passed")
