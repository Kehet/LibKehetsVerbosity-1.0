-- Message types an addon declares, printed where the player chose, with the settings group to choose it
local MAJOR, MINOR = "LibKehetsVerbosity-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
    return
end

-- Kept on the library so a newer copy that loads later takes over what older copies registered
lib.embeds = lib.embeds or {}
lib.types = lib.types or {}

local COMBAT_LOG_WINDOW = 2

-- Colour of the text in the frames that do not have a colour of their own
local TEXT_COLOR = { r = 1, g = 0.82, b = 0 }

-- Outputs other than the chat windows. The settings list them by key, after the chat windows.
local FRAME_OUTPUTS = {
    combat = {
        name = "Floating combat text",
        -- The combat text is loaded only while the player has it turned on
        IsAvailable = function() return CombatText_AddMessage ~= nil end,
        Show = function(text)
            CombatText_AddMessage(text, CombatText_StandardScroll, TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b)
        end,
    },
    emote = {
        name = "Boss emote frame",
        IsAvailable = function() return RaidNotice_AddMessage ~= nil and RaidBossEmoteFrame ~= nil end,
        Show = function(text)
            RaidNotice_AddMessage(RaidBossEmoteFrame, text, ChatTypeInfo["RAID_BOSS_EMOTE"])
        end,
    },
    errors = {
        name = "Error frame",
        IsAvailable = function() return UIErrorsFrame ~= nil end,
        Show = function(text)
            UIErrorsFrame:AddMessage(text, TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b)
        end,
    },
    raid = {
        name = "Raid warning frame",
        IsAvailable = function() return RaidNotice_AddMessage ~= nil and RaidWarningFrame ~= nil end,
        Show = function(text)
            RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
        end,
    },
}

local function GetType(addon, key)
    local types = lib.types[addon]
    local messageType = types and types[key]
    if not messageType then
        error(MAJOR .. ": message type '" .. tostring(key) .. "' is not registered", 3)
    end
    return messageType
end

-- Nil until the addon has created its database, which Kehet's CurrencyAlert does a few seconds after login
local function GetProfile(addon)
    return addon.db and addon.db.profile
end

local function GetSaved(addon)
    local profile = GetProfile(addon)
    return profile and profile.verbosity
end

local function IsMuted(addon)
    local saved = GetSaved(addon)
    return saved ~= nil and saved.mute == true
end

local function SetMuted(addon, muted)
    local profile = GetProfile(addon)
    if not profile then
        return
    end

    local saved = profile.verbosity or {}
    saved.mute = muted or nil
    profile.verbosity = next(saved) and saved or nil
end

local function GetSetting(addon, key, field)
    local saved = GetSaved(addon)
    local settings = saved and saved.types and saved.types[key]
    if settings and settings[field] ~= nil then
        return settings[field]
    end
    return lib.types[addon][key].defaults[field]
end

-- Only what differs from the declaration is saved, so a profile reset brings the declared defaults back
local function SetSetting(addon, key, field, value)
    local profile = GetProfile(addon)
    if not profile then
        return
    end
    if value == lib.types[addon][key].defaults[field] then
        value = nil
    end

    local saved = profile.verbosity or {}
    saved.types = saved.types or {}
    local settings = saved.types[key] or {}
    settings[field] = value
    saved.types[key] = next(settings) and settings or nil
    if not next(saved.types) then
        saved.types = nil
    end
    profile.verbosity = next(saved) and saved or nil
end

-- Other addons whose message frames or scroll areas are outputs while the addon is loaded. GetAreas
-- returns them as key = name, or nil without the addon. Show returns false when the addon cannot show
-- the message now. With hasSticky each area is also listed in the sticky style, which the scrolling
-- text addons use for critical hits.
local MESSAGE_ADDONS = {
    bigwigs = {
        name = "BigWigs",
        GetAreas = function()
            if type(_G.BigWigsLoader) ~= "table" or type(_G.BigWigsLoader.SendMessage) ~= "function" then
                return nil
            end
            return { normal = "Messages", emphasized = "Emphasized messages" }
        end,
        -- BigWigs loads its message frames only where it has boss modules, such as in an instance
        Show = function(area, sticky, text)
            local messages = _G.BigWigs and _G.BigWigs:GetPlugin("Messages", true)
            if not messages or not messages:IsEnabled() then
                return false
            end
            _G.BigWigsLoader:SendMessage("BigWigs_Message", nil, nil, text, TEXT_COLOR, nil, area == "emphasized")
        end,
    },
    dbm = {
        name = "DBM",
        GetAreas = function()
            local dbm = _G.DBM
            if type(dbm) ~= "table" or type(dbm.AddWarning) ~= "function" or type(dbm.AddSpecialWarning) ~= "function" then
                return nil
            end
            return { warning = "Warnings", special = "Special warnings" }
        end,
        Show = function(area, sticky, text)
            if area == "special" then
                _G.DBM:AddSpecialWarning(text, nil, nil, nil, nil, true)
            else
                _G.DBM:AddWarning(text)
            end
        end,
    },
    msbt = {
        name = "MSBT",
        hasSticky = true,
        GetAreas = function()
            local msbt = _G.MikSBT
            if type(msbt) ~= "table" or type(msbt.IterateScrollAreas) ~= "function" or type(msbt.DisplayMessage) ~= "function" then
                return nil
            end
            local areas = {}
            for area, name in msbt.IterateScrollAreas() do
                areas[area] = name
            end
            return areas
        end,
        -- MSBT takes colours from 0 to 255
        Show = function(area, sticky, text)
            _G.MikSBT.DisplayMessage(text, area, sticky, TEXT_COLOR.r * 255, TEXT_COLOR.g * 255, TEXT_COLOR.b * 255)
        end,
    },
    parrot = {
        name = "Parrot",
        hasSticky = true,
        GetAreas = function()
            local parrot = _G.Parrot
            if type(parrot) ~= "table" or type(parrot.GetScrollAreasChoices) ~= "function" or type(parrot.ShowMessage) ~= "function" then
                return nil
            end
            return parrot:GetScrollAreasChoices()
        end,
        Show = function(area, sticky, text)
            _G.Parrot:ShowMessage(text, area, sticky, TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b)
        end,
    },
}

-- The calls are protected, so an addon that is missing, turned off or changed never stops a message
local function GetAddonAreas(messageAddon)
    local ok, areas = pcall(messageAddon.GetAreas)
    return ok and type(areas) == "table" and areas or nil
end

-- An output of another addon is "<addon>:<area>", or "<addon>sticky:<area>"
local function ShowInAddon(output, text)
    local kind, area = output:match("^(%a+):(.+)$")
    local sticky = kind and kind:match("^(%a+)sticky$")
    local messageAddon = MESSAGE_ADDONS[sticky or kind]
    local areas = messageAddon and GetAddonAreas(messageAddon)
    if not areas or not areas[area] then
        return false
    end
    local ok, shown = pcall(messageAddon.Show, area, sticky ~= nil, text)
    return ok and shown ~= false
end

-- A chat window is in use when it is shown or is a tab in the dock
local function IsWindowOpen(index)
    if index == COMBAT_LOG_WINDOW or not _G["ChatFrame" .. index] then
        return false
    end
    local name, _, _, _, _, _, shown, _, docked = GetChatWindowInfo(index)
    return name ~= nil and name ~= "" and (shown or docked) and true or false
end

-- A declaration says "chat" for the default chat window, which is saved and listed as the window it is
local function GetDefaultOutputs(messageType)
    local outputs = {}
    for _, output in ipairs(messageType.outputs) do
        if output == "chat" then
            output = "chat" .. DEFAULT_CHAT_FRAME:GetID()
        end
        outputs[output] = true
    end
    return outputs
end

local function GetOutputs(addon, key)
    return GetSetting(addon, key, "outputs") or GetDefaultOutputs(lib.types[addon][key])
end

local function SetOutput(addon, key, output, state)
    local outputs, isDefault = {}, true
    for current in pairs(GetOutputs(addon, key)) do
        outputs[current] = true
    end
    outputs[output] = state or nil

    local defaults = GetDefaultOutputs(lib.types[addon][key])
    for current in pairs(outputs) do
        isDefault = isDefault and defaults[current] == true
    end
    for current in pairs(defaults) do
        isDefault = isDefault and outputs[current] == true
    end
    SetSetting(addon, key, "outputs", not isDefault and outputs or nil)
end

-- The outputs that can show a message now: the open chat windows by their names, the frames,
-- and the message frames and scroll areas of other addons
local function GetOutputNames()
    local names = {}
    for index = 1, NUM_CHAT_WINDOWS do
        if IsWindowOpen(index) then
            names["chat" .. index] = GetChatWindowInfo(index)
        end
    end
    for output, frame in pairs(FRAME_OUTPUTS) do
        if frame.IsAvailable() then
            names[output] = frame.name
        end
    end
    for key, messageAddon in pairs(MESSAGE_ADDONS) do
        for area, name in pairs(GetAddonAreas(messageAddon) or {}) do
            local label = messageAddon.name .. ": " .. tostring(name)
            names[key .. ":" .. area] = label
            if messageAddon.hasSticky then
                names[key .. "sticky:" .. area] = label .. " (sticky)"
            end
        end
    end
    return names
end

-- An output that is not there now, such as a closed chat window, stays saved. When none of the
-- chosen outputs is there the message goes to the default chat window, so it is not lost.
local function ShowText(addon, key, text)
    local outputs = GetOutputs(addon, key)
    local shown = false
    for output in pairs(outputs) do
        local window = tonumber(output:match("^chat(%d+)$"))
        local frame = FRAME_OUTPUTS[output]
        if window and IsWindowOpen(window) then
            addon:Print(_G["ChatFrame" .. window], text)
            shown = true
        elseif frame and frame.IsAvailable() then
            frame.Show(text)
            shown = true
        elseif ShowInAddon(output, text) then
            shown = true
        end
    end

    if not shown and next(outputs) then
        addon:Print(text)
        shown = true
    end
    return shown
end

local function PlayTypeSound(sound)
    if sound.kit then
        PlaySound(sound.kit, sound.channel or "Master")
    else
        PlaySoundFile(sound.file, sound.channel or "Master")
    end
end

--- Declare the message types of the addon. Call it once, before the first Notify.
-- @param types Table of key = { name, desc, order, shown, outputs, tag, sound }.
-- shown (default true) and outputs (default { "chat" }) are what the player gets until they change it.
-- An output is "chat" for the default chat window, "errors", "raid", "emote" or "combat".
-- tag is put in front of each message. sound is { kit = soundKitID } or { file = pathOrFileID },
-- with an optional channel.
function lib:RegisterMessageTypes(types)
    local registered = {}
    for key, declaration in pairs(types) do
        local outputs = declaration.outputs or { "chat" }
        for _, output in ipairs(outputs) do
            if output ~= "chat" and not FRAME_OUTPUTS[output] then
                error(MAJOR .. ": message type '" .. tostring(key) .. "' has unknown output '" .. tostring(output) .. "'", 2)
            end
        end

        registered[key] = {
            name = declaration.name or key,
            desc = declaration.desc,
            order = declaration.order,
            tag = declaration.tag,
            sound = declaration.sound,
            outputs = outputs,
            defaults = {
                shown = declaration.shown ~= false,
                sound = true,
            },
        }
    end
    lib.types[self] = registered
end

--- Show a message of a declared type where the player wants it, and play the sound of the type.
-- @param message Text to show, or nil to only play the sound.
-- @param options Optional { force = true } to show the text also when the type is off or everything is muted.
-- @return true if the text was shown.
function lib:Notify(key, message, options)
    local messageType = GetType(self, key)
    local muted = IsMuted(self)

    if messageType.sound and not muted and GetSetting(self, key, "sound") then
        PlayTypeSound(messageType.sound)
    end

    local force = options and options.force
    if message == nil or not force and (muted or not GetSetting(self, key, "shown")) then
        return false
    end

    local text = tostring(message)
    if messageType.tag then
        text = messageType.tag .. " " .. text
    end

    return ShowText(self, key, text)
end

--- Whether Notify would show text of this type. Use it to skip work that only builds a message.
function lib:IsMessageShown(key)
    GetType(self, key)
    return not IsMuted(self) and GetSetting(self, key, "shown")
end

--- Turn the text of a type on or off, for example to carry over a setting the addon had before.
function lib:SetMessageShown(key, shown)
    GetType(self, key)
    SetSetting(self, key, "shown", shown and true or false)
end

local function BuildTypeOptions(addon, key, order)
    local messageType = lib.types[addon][key]

    -- A control with its own disabled function does not follow its group, so each one checks the mute itself
    local function IsMutedNow()
        return IsMuted(addon)
    end
    local function IsTextOff()
        return IsMuted(addon) or not GetSetting(addon, key, "shown")
    end

    local args = {
        shown = {
            type = "toggle",
            name = "Show",
            desc = "Show this message.",
            order = 1,
            disabled = IsMutedNow,
            get = function() return GetSetting(addon, key, "shown") end,
            set = function(_, value) SetSetting(addon, key, "shown", value) end,
        },
        outputs = {
            type = "multiselect",
            name = "Show in",
            desc = "Where the message is shown. You can choose more than one place.",
            order = 2,
            values = GetOutputNames,
            disabled = IsTextOff,
            get = function(_, output) return GetOutputs(addon, key)[output] == true end,
            set = function(_, output, state) SetOutput(addon, key, output, state) end,
        },
    }

    if messageType.desc then
        args.desc = {
            type = "description",
            name = messageType.desc,
            order = 0,
        }
    end

    if messageType.sound then
        args.sound = {
            type = "toggle",
            name = "Play sound",
            desc = "Play the sound of this message. The sound plays also when the message is not shown.",
            order = 3,
            disabled = IsMutedNow,
            get = function() return GetSetting(addon, key, "sound") end,
            set = function(_, value) SetSetting(addon, key, "sound", value) end,
        }
    end

    return {
        type = "group",
        name = messageType.name,
        inline = true,
        order = order,
        args = args,
    }
end

--- AceConfig group with the settings of every declared type, to put in the options table of the addon.
-- Each call builds a new table, so the caller can set its order and name.
function lib:GetMessageOptions()
    local addon = self
    local types = lib.types[addon] or {}

    local group = {
        type = "group",
        name = "Messages",
        args = {
            mute = {
                type = "toggle",
                name = "Mute all messages",
                desc = "Turn off every message and sound on this page. Answers to slash commands still print.",
                order = 0,
                width = "full",
                get = function() return IsMuted(addon) end,
                set = function(_, value) SetMuted(addon, value) end,
            },
        },
    }

    local keys = {}
    for key in pairs(types) do
        table.insert(keys, key)
    end
    table.sort(keys, function(a, b)
        local orderA, orderB = types[a].order or math.huge, types[b].order or math.huge
        if orderA ~= orderB then
            return orderA < orderB
        end
        return a < b
    end)

    for index, key in ipairs(keys) do
        group.args["type_" .. key] = BuildTypeOptions(addon, key, index)
    end

    return group
end

--- Register a settings page that holds only the message settings, for an addon without a page of its own.
-- The addon must embed AceConfig-3.0 and AceGUI-3.0.
function lib:RegisterMessagePage()
    local addon = self
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addon.name, function()
        local options = addon:GetMessageOptions()
        options.name = addon.name
        return options
    end)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addon.name, addon.name)
end

--- Open the page of RegisterMessagePage in a standalone window.
function lib:OpenMessagePage()
    LibStub("AceConfigDialog-3.0"):Open(self.name)
end

local MIXINS = {
    "RegisterMessageTypes",
    "Notify",
    "IsMessageShown",
    "SetMessageShown",
    "GetMessageOptions",
    "RegisterMessagePage",
    "OpenMessagePage",
}

-- AceAddon calls this for a library named in NewAddon. The target needs AceConsole-3.0 and an AceDB in self.db.
function lib:Embed(target)
    for _, name in ipairs(MIXINS) do
        target[name] = lib[name]
    end
    lib.embeds[target] = true
    return target
end

for target in pairs(lib.embeds) do
    lib:Embed(target)
end
