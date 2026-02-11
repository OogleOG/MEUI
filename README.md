# MEUI — MemoryError UI Library

A helper library for building ImGui interfaces in MemoryError Lua scripts. Instead of writing hundreds of lines of ImGui boilerplate for every script, MEUI lets you define your entire GUI declaratively in a few lines.

It handles theming, widget layout, config save/load, tab architecture, runtime stats, and all the repetitive ImGui plumbing — so you can focus on your script logic.

## Installation

Drop `MEUI.lua` into your `Lua_Scripts` folder (next to `api.lua`). Then require it:

```lua
local MEUI = require("MEUI")
```

---

## Quick Start

Here's a complete, working script GUI in under 30 lines:

```lua
local API = require("api")
local MEUI = require("MEUI")

-- 1. Create a window with a theme
local ui = MEUI.Window("My Boss Killer", "purple")

-- 2. Define your config fields
ui:addSection("Combat", "Configure your combat settings.")
ui:addCheckbox("usePrayer", "Use Prayer", true)
ui:addCombo("prayer", "Prayer Style", 0, {"Sorrow", "Ruination"})

ui:addSection("Health", "When to eat food and drink potions.")
ui:addSlider("eatAt", "Eat Food (%)", 50, 0, 100, "%d%%")
ui:addSlider("brewAt", "Brew (%)", 30, 0, 100, "%d%%")

ui:addSection("Options")
ui:addCheckbox("campBoss", "Camp Boss", false, "Stay at boss instead of banking")
ui:addInput("bankPin", "Bank PIN", "")

-- 3. Add state colors for the info tab
ui:addStateColor("Fighting", 1.0, 0.4, 0.3)
ui:addStateColor("Banking", 0.3, 0.8, 0.4)
ui:addStateColor("Looting", 0.4, 0.85, 0.9)

-- 4. Load saved config
ui:loadConfig()

-- 5. Main loop
while API.Read_LoopyLoop() do
    ui:draw({
        state = "Fighting",
        kills = 12,
        killsPerHour = 24,
        bossHealth = 300000,
        bossMaxHealth = 600000,
        bossName = "Rasial",
    })

    if not ui:isStarted() then goto continue end
    if ui:isPaused() then goto continue end
    if ui:isStopped() then break end

    -- Your script logic here
    local cfg = ui:getConfig()
    if cfg.usePrayer then
        -- activate prayer
    end

    ::continue::
    API.RandomSleep2(100, 50, 50)
end
```

That's it. MEUI handles the themed window, config tab with all your controls, info tab with stats, warnings tab, start/pause/stop buttons, and JSON config save/load — automatically.

---

## Themes

MEUI comes with 7 built-in colour themes. Each theme is a 5-layer palette from dark to bright:

| Theme | Style | Good For |
|-------|-------|----------|
| `teal` | Cyan/teal | General purpose, water bosses |
| `purple` | Necromancy purple | Necro scripts, dark themes |
| `crimson` | Deep red | Melee scripts, aggressive themes |
| `inferno` | Orange/fire | Zuk, fire-themed content |
| `emerald` | Green | Skilling, nature content |
| `gold` | Golden yellow | GP trackers, treasure |
| `ice` | Blue/frost | Glacor, ice-themed content |

```lua
-- Use a built-in theme by name
local ui = MEUI.Window("My Script", "crimson")

-- Or create your own custom theme
local ui = MEUI.Window("My Script", {
    dark   = { 0.06, 0.08, 0.10 },   -- Window background
    medium = { 0.08, 0.18, 0.25 },   -- Frames, tabs, inputs
    light  = { 0.15, 0.35, 0.45 },   -- Hover states
    bright = { 0.25, 0.55, 0.65 },   -- Active elements, sliders
    glow   = { 0.40, 0.80, 0.90 },   -- Highlights, checkmarks, headers
})
```

---

## Config Fields

Fields appear in the Config tab in the order you add them. Each field creates a config key with a default value.

### Section Headers

Group your fields visually with section headers. The title uses your theme's glow colour.

```lua
ui:addSection("Combat Settings", "Optional description text appears below.")
```

### Checkbox

A simple on/off toggle. Stores a `boolean`.

```lua
ui:addCheckbox("campBoss", "Camp Boss", false, "Optional description")
--              key         label       default  desc
```

### Slider

An integer slider with min/max range. Stores a `number`.

```lua
ui:addSlider("eatAt", "Eat Food", 50, 0, 100, "%d%%", "HP percent to eat at")
--            key      label      def  min max  format  desc
```

Format examples: `"%d"` (plain number), `"%d%%"` (with percent sign), `"%d HP"` (with unit).

### Combo Box (Dropdown)

A dropdown selector. Stores a `number` (0-based index).

```lua
ui:addCombo("prayer", "Prayer", 0, {"Sorrow", "Ruination"}, "Which curse to use")
--           key       label    default  options               desc
```

To get the selected string value:

```lua
local options = {"Sorrow", "Ruination"}
local selectedName = options[ui:get("prayer") + 1]  -- +1 because Lua is 1-indexed
```

### Text Input

A text field. Stores a `string`.

```lua
ui:addInput("bankPin", "Bank PIN", "", "Your 4-digit PIN", 4)
--           key        label      default  desc             maxLength
```

### Visual Separators and Spacing

```lua
ui:addSeparator()  -- Horizontal line
ui:addSpacing()    -- Vertical gap
```

---

## Reading Config Values

```lua
-- Get all config as a table
local cfg = ui:getConfig()
print(cfg.campBoss)    -- true/false
print(cfg.eatAt)       -- 50

-- Get a single value
local val = ui:get("campBoss")

-- Set a value programmatically
ui:set("campBoss", true)
```

---

## Config Save & Load

Config automatically saves to JSON when the user clicks "Start". You can also load previously saved config at startup:

```lua
ui:loadConfig()  -- Call after adding all fields, before main loop
```

Configs are saved to: `%USERPROFILE%\MemoryError\Lua_Scripts\configs\<scriptname>.config.json`

---

## Script State

MEUI manages the standard start/pause/stop flow:

```lua
ui:isStarted()    -- true after user clicks "Start"
ui:isPaused()     -- true while paused (toggle via UI button)
ui:isStopped()    -- true when user clicks "Stop"
ui:isCancelled()  -- true when user clicks "Cancel" (before starting)
```

Standard main loop pattern:

```lua
while API.Read_LoopyLoop() do
    ui:draw(data)

    if ui:isCancelled() or ui:isStopped() then break end
    if not ui:isStarted() or ui:isPaused() then
        API.RandomSleep2(100, 50, 50)
        goto continue
    end

    -- Your logic here

    ::continue::
    API.RandomSleep2(100, 50, 50)
end
```

---

## Info Tab — Runtime Data

The Info tab appears automatically once the script starts. Pass a data table to `ui:draw()` with any of these fields:

```lua
ui:draw({
    -- State (displayed with color)
    state = "Fighting",

    -- Boss health bar
    bossName = "Rasial",
    bossHealth = 450000,
    bossMaxHealth = 900000,

    -- Kill stats
    kills = 15,
    killsPerHour = 30,
    deaths = 2,

    -- GP tracking
    gp = 5000000,
    gpPerHour = 10000000,

    -- Kill times
    killTimer = "01:23",
    fastestKill = "00:45",
    slowestKill = "02:10",
    averageKill = "01:15",

    -- Recent kill history (shows last 5)
    killData = {
        { fightDuration = "01:12" },
        { fightDuration = "00:58" },
        { fightDuration = "01:30" },
    },

    -- Unique drops
    uniquesLooted = { "Omni Guard", "Death Guard" },
})
```

All fields are optional — only sections with data will be displayed.

### State Colors

Register custom colors for your state names:

```lua
ui:addStateColor("Fighting",       1.0, 0.4, 0.3)   -- Red
ui:addStateColor("Banking",        0.3, 0.8, 0.4)   -- Green
ui:addStateColor("Looting",        0.4, 0.85, 0.9)  -- Cyan
ui:addStateColor("Teleporting",    0.6, 0.9, 1.0)   -- Light blue
ui:addStateColor("War's Retreat",  0.3, 0.8, 0.4)   -- Green
```

`"Idle"`, `"Paused"`, and `"Dead"` are built-in with default colors.

---

## Custom Info Tab

If the default info tab doesn't fit your needs, you can override it entirely:

```lua
ui:setCustomInfoTab(function(data, palette, h)
    -- h contains helper functions bound to your theme:
    -- h.label(text)                    -- White label text
    -- h.sectionHeader(text)            -- Glow-colored header
    -- h.flavorText(text)               -- Subtle description text
    -- h.row(label, value, lr,lg,lb, vr,vg,vb)  -- Table row (inside BeginTable)
    -- h.progressBar(pct, height, text, r, g, b)
    -- h.button(label, r, g, b, width, height)   -- Returns true if clicked
    -- h.formatNumber(n)                -- 1234 → "1.2K"
    -- h.formatTime(seconds)            -- 3661 → "01:01:01"
    -- h.perHour(count, seconds)        -- Calculate per-hour rate

    h.sectionHeader("Custom Stats")

    if ImGui.BeginTable("##custom", 2) then
        ImGui.TableSetupColumn("l", ImGuiTableColumnFlags.WidthStretch, 0.4)
        ImGui.TableSetupColumn("v", ImGuiTableColumnFlags.WidthStretch, 0.6)

        h.row("Phase", data.phase or "N/A")
        h.row("Stacks", tostring(data.stacks or 0))
        h.row("DPS", h.formatNumber(data.dps or 0))

        ImGui.EndTable()
    end

    h.progressBar(data.adren / 100, 20,
        string.format("Adrenaline: %d%%", data.adren),
        0.9, 0.7, 0.1)
end)
```

---

## Summary Rows

Show a config summary on the Config tab while the script is running:

```lua
ui:setSummaryRows(function(cfg)
    local prayers = {"Sorrow", "Ruination"}
    return {
        {"Prayer", prayers[cfg.prayer + 1]},
        {"Eat At", cfg.eatAt .. "%"},
        {"Camp Boss", cfg.campBoss and "Yes" or "No"},
    }
end)
```

---

## Warnings

Push warnings to show them in a dedicated Warnings tab:

```lua
ui:addWarning("Low prayer potions!")
ui:addWarning("Failed to find bank chest")
ui:clearWarnings()  -- Clear all
```

The tab label shows the count: `Warnings (3)`. Max 50 warnings stored (oldest removed first).

---

## Tab Control

Programmatically switch tabs:

```lua
ui:showInfoTab()    -- Switch to Info tab next frame
ui:showConfigTab()  -- Switch to Config tab next frame
```

---

## Standalone Draw Helpers

If you don't want the full Window builder (e.g. adding elements to an existing GUI), you can use the draw helpers directly:

```lua
-- Colored text
MEUI.Draw.text("Hello world", 0.4, 0.8, 0.9)

-- Section header using a theme palette
MEUI.Draw.sectionHeader("Stats", MEUI.Themes.purple)

-- Table row (must be inside ImGui.BeginTable / EndTable)
MEUI.Draw.row("Kills", "42", 1,1,1, 0.3,0.85,0.45)

-- Progress bar
MEUI.Draw.progressBar(0.75, 20, "HP: 75%", 0.3, 0.85, 0.45)

-- Themed button (returns true if clicked)
if MEUI.Draw.button("Click Me##btn", 0.4, 0.2, 0.5) then
    -- handle click
end

-- Apply a full theme manually
local popTheme = MEUI.Draw.pushTheme("teal")
-- ... your ImGui code here ...
popTheme()  -- Always call this when done
```

---

## Utility Functions

```lua
MEUI.formatNumber(1234567)       -- "1.2M"
MEUI.formatNumber(1234)          -- "1.2K"
MEUI.formatNumber(42)            -- "42"

MEUI.formatTime(3661)            -- "01:01:01"

MEUI.perHour(15, 1800)           -- 30 (kills/hour from 15 kills in 30 minutes)
```

---

## Full Example — Boss Killer Script

```lua
local API = require("api")
local MEUI = require("MEUI")

-- Build GUI
local ui = MEUI.Window("Rasial Killer", "purple", 380)

ui:addSection("Combat Rotation")
ui:addCombo("rotation", "Rotation Preset", 0, {"Standard", "Speed", "Safe"})

ui:addSection("Health Thresholds", "When to eat food and drink potions.")
ui:addSlider("healthFood", "Eat Food (%)", 50, 0, 100, "%d%%")
ui:addSlider("healthBrew", "Drink Brew (%)", 30, 0, 100, "%d%%")

ui:addSection("Prayer")
ui:addCombo("prayer", "Damage Prayer", 0, {"Sorrow", "Ruination"})
ui:addSlider("prayerRestore", "Restore Prayer (%)", 30, 0, 100, "%d%%")

ui:addSection("War's Retreat", "Preparation options before entering the fight.")
ui:addCheckbox("useAdren", "Use Adrenaline Crystal", true)
ui:addCheckbox("useBonfire", "Use Bonfire", true)

ui:addSection("Debug")
ui:addCheckbox("debugMain", "Main Script", true)
ui:addCheckbox("debugRotation", "Rotation", false)

-- State colors
ui:addStateColor("War's Retreat",  0.3, 0.8, 0.4)
ui:addStateColor("Entering Fight", 0.5, 0.3, 0.7)
ui:addStateColor("Phase 1",       1.0, 0.8, 0.2)
ui:addStateColor("Phase 2",       1.0, 0.5, 0.3)
ui:addStateColor("Looting",       0.8, 0.5, 1.0)
ui:addStateColor("Teleporting",   0.6, 0.9, 1.0)

-- Summary rows when running
ui:setSummaryRows(function(cfg)
    local rotations = {"Standard", "Speed", "Safe"}
    local prayers = {"Sorrow", "Ruination"}
    return {
        {"Rotation", rotations[cfg.rotation + 1]},
        {"Prayer", prayers[cfg.prayer + 1]},
        {"Eat At", cfg.healthFood .. "%"},
    }
end)

-- Load saved config
ui:loadConfig()

-- Script state
local kills = 0
local deaths = 0
local state = "War's Retreat"
local startTime = os.time()

-- Main loop
while API.Read_LoopyLoop() do
    local elapsed = os.time() - startTime

    ui:draw({
        state = state,
        kills = kills,
        killsPerHour = MEUI.perHour(kills, elapsed),
        deaths = deaths,
        bossName = "Rasial",
        bossHealth = 500000,
        bossMaxHealth = 900000,
    })

    if ui:isCancelled() or ui:isStopped() then break end
    if not ui:isStarted() or ui:isPaused() then
        API.RandomSleep2(100, 50, 50)
        goto continue
    end

    -- Access config
    local cfg = ui:getConfig()

    -- Your script logic here...
    -- if API.GetHPrecent() < cfg.healthFood then eatFood() end

    ::continue::
    API.RandomSleep2(100, 50, 50)
end
```

---

## API Reference

### MEUI

| Function | Description |
|----------|-------------|
| `MEUI.Window(title, theme, width?)` | Create a new window builder |
| `MEUI.formatNumber(n)` | Format number: 1234 → "1.2K" |
| `MEUI.formatTime(seconds)` | Format seconds: 3661 → "01:01:01" |
| `MEUI.perHour(count, seconds)` | Calculate per-hour rate |
| `MEUI.Themes` | Table of built-in theme palettes |
| `MEUI.VERSION` | Library version string |

### Window Builder

| Method | Description |
|--------|-------------|
| `ui:addSection(label, desc?)` | Add a section header |
| `ui:addCheckbox(key, label, default, desc?)` | Add a checkbox (boolean) |
| `ui:addSlider(key, label, default, min, max, fmt?, desc?)` | Add an integer slider |
| `ui:addCombo(key, label, default, options, desc?)` | Add a dropdown (0-based index) |
| `ui:addInput(key, label, default, desc?, maxLen?)` | Add a text input |
| `ui:addSeparator()` | Add a horizontal line |
| `ui:addSpacing()` | Add vertical space |
| `ui:addStateColor(state, r, g, b)` | Register a state display colour |
| `ui:setCustomInfoTab(fn)` | Override the info tab draw function |
| `ui:setSummaryRows(fn)` | Set running config summary rows |
| `ui:draw(data?)` | Draw the window (call every frame) |
| `ui:getConfig()` | Get all config values as a table |
| `ui:get(key)` | Get a single config value |
| `ui:set(key, value)` | Set a config value |
| `ui:saveConfig()` | Save config to JSON file |
| `ui:loadConfig()` | Load config from JSON file |
| `ui:isStarted()` | Check if user clicked Start |
| `ui:isPaused()` | Check if script is paused |
| `ui:isStopped()` | Check if user clicked Stop |
| `ui:isCancelled()` | Check if user clicked Cancel |
| `ui:addWarning(msg)` | Push a warning message |
| `ui:clearWarnings()` | Clear all warnings |
| `ui:showInfoTab()` | Switch to Info tab |
| `ui:showConfigTab()` | Switch to Config tab |
| `ui:reset()` | Reset all state to defaults |

### Standalone Draw Helpers

| Function | Description |
|----------|-------------|
| `MEUI.Draw.text(text, r?, g?, b?)` | Draw coloured text |
| `MEUI.Draw.sectionHeader(text, palette?)` | Draw a glow-coloured header |
| `MEUI.Draw.row(label, value, lr?,lg?,lb?, vr?,vg?,vb?)` | Draw a table row |
| `MEUI.Draw.progressBar(pct, height, text, r, g, b)` | Draw a coloured progress bar |
| `MEUI.Draw.button(label, r, g, b, width?, height?)` | Draw a themed button |
| `MEUI.Draw.pushTheme(theme)` | Apply full theme, returns pop function |
