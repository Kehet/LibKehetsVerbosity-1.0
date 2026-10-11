# LibKehetsVerbosity-1.0

A library for World of Warcraft addons that lets the player decide which messages an addon shows, and where.

The addon declares its message types. The library shows each message where the player wants it, and builds the settings for it.

For each message type the player can set:

- Show: turn the message on or off.
- Show in: one or more of the chat windows, the error frame, the raid warning frame, the boss emote frame and the floating combat text.
- Play sound: turn the sound of the message on or off, if the addon gave the type a sound.

One more setting, Mute all messages, turns off all messages and sounds of the addon.

Use message types for messages that the addon shows by itself, such as a login message, an alert or debug output. Print the answer to a slash command with `self:Print`, so that it always shows.

## Usage

The addon must be an AceAddon-3.0 addon with AceConsole-3.0, and must keep its AceDB-3.0 database in `self.db`.

Name the library in `NewAddon`, then declare the message types:

```lua
local MyAddon = LibStub("AceAddon-3.0"):NewAddon("MyAddon", "AceConsole-3.0", "LibKehetsVerbosity-1.0")

MyAddon:RegisterMessageTypes({
    banner = { name = "Login message", order = 1 },
    alert = {
        name = "Alerts",
        desc = "A currency is almost full.",
        order = 2,
        outputs = { "chat", "raid" },
        sound = { kit = SOUNDKIT.ALARM_CLOCK_WARNING_2 },
    },
    debug = { name = "Debug output", order = 3, shown = false, tag = "|cFF66B2FF[Debug]|r" },
})
```

Show a message:

```lua
self:Notify("alert", "Justice Points soon full!")
```

Add the settings to the AceConfig options table of the addon:

```lua
options.args.messages = self:GetMessageOptions()
```

If the addon has no settings page, let the library register one. The addon must embed AceConfig-3.0 and AceGUI-3.0.

```lua
self:RegisterMessagePage()
```

## Message type fields

| Field | Default | Meaning |
|---|---|---|
| `name` | The key | Title in the settings |
| `desc` | None | Description in the settings |
| `order` | By key | Position in the settings |
| `shown` | `true` | Whether the message is on until the player changes it |
| `outputs` | `{ "chat" }` | Where the message is shown until the player changes it. See Outputs. |
| `tag` | None | Text put in front of each message |
| `sound` | None | `{ kit = soundKitID }` or `{ file = pathOrFileID }`, with an optional `channel` (default `"Master"`) |

## Outputs

| Output | Place |
|---|---|
| `"chat"` | The default chat window. The player can choose any open chat window. |
| `"errors"` | The error frame, at the top of the screen |
| `"raid"` | The raid warning frame, in the middle of the screen |
| `"emote"` | The boss emote frame |
| `"combat"` | The floating combat text. It is listed only while the player has it turned on. |

The settings also list the outputs of these addons while the addon is loaded. An addon cannot declare them as a default.

| Addon | Outputs |
|---|---|
| Parrot | Each scroll area, in the normal style and in the sticky style |
| MikScrollingBattleText | Each scroll area, in the normal style and in the sticky style |
| BigWigs | Messages and Emphasized messages. BigWigs shows them only where it is active, such as in an instance. |
| DBM | Warnings and Special warnings. Special warnings show without their sound. |

The settings list the chat windows by their names. Only chat messages have the name of the addon in front.

If none of the chosen outputs can show the message, for example because the chat window is closed or BigWigs is not active, the message goes to the default chat window.

## Functions

| Function | Action |
|---|---|
| `self:RegisterMessageTypes(types)` | Declare the message types. Call it once, before the first `Notify`. |
| `self:Notify(key, message, options)` | Show the message and play the sound of the type. Returns `true` if the text was shown. A `nil` message only plays the sound. `{ force = true }` as options shows the text also when the type is off or all messages are muted. |
| `self:IsMessageShown(key)` | Return whether `Notify` would show text of the type. |
| `self:SetMessageShown(key, shown)` | Turn the text of the type on or off. |
| `self:GetMessageOptions()` | Return the AceConfig group with the settings. |
| `self:RegisterMessagePage()` | Register a settings page that has only the message settings. |
| `self:OpenMessagePage()` | Open that page in a window. |

## Saved settings

The settings are saved in `self.db.profile.verbosity`, so they follow the profile. Only the settings that the player changed are saved.

Before the addon creates its database, the declared defaults apply.

## Add the library to an addon

1. Add the library to the externals in `.pkgmeta`, with the tag of the version you want:

    ```yaml
    externals:
      Libs/LibKehetsVerbosity-1.0:
        url: https://github.com/Kehet/LibKehetsVerbosity-1.0
        tag: 1.0.0
    ```

2. Add the library to `embeds.xml`:

    ```xml
    <Include file="Libs\LibKehetsVerbosity-1.0\LibKehetsVerbosity-1.0.xml"/>
    ```

3. Add `LibKehetsVerbosity-1.0` to `## OptionalDeps` in the `.toc` file.

## Development

The library is not published as an addon. To run an addon from a git checkout, link this repository into the AddOns folder of the game. The Ace3 addon must be installed, because it supplies LibStub.

```sh
ln -s /path/to/LibKehetsVerbosity-1.0 "/path/to/World of Warcraft/_classic_/Interface/AddOns/LibKehetsVerbosity-1.0"
```

Run the tests with Lua 5.1:

```sh
lua5.1 tests/test.lua
```

To release a version, increase `MINOR` in `LibKehetsVerbosity-1.0.lua` and tag the commit. LibStub keeps the copy with the highest `MINOR` when more than one addon loads the library.

## Requirements

- World of Warcraft: Mists of Pandaria Classic
- AceAddon-3.0, AceConsole-3.0 and AceDB-3.0
- AceConfig-3.0 and AceGUI-3.0 for the settings

## License

Public domain (The Unlicense). See `LICENSE`.
