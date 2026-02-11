--[[
    MEUI.lua — MemoryError UI Library
    Version: 1.0.0
    Author: Oogle

    A helper library for building ImGui interfaces in ME Lua scripts.
    Handles theming, common widgets, layout patterns, config save/load,
    and the standard tab architecture used across all ME scripts.

    Usage:
        local MEUI = require("MEUI")

        -- Create a themed window builder
        local ui = MEUI.Window("My Script", "teal")

        -- Add config fields
        ui:addCheckbox("campBoss", "Camp Boss", false, "Stay at the boss instead of banking")
        ui:addSlider("healthFood", "Eat Food (%)", 60, 0, 100, "%d%%", "HP threshold to eat solid food")
        ui:addCombo("prayer", "Prayer", 0, {"Sorrow", "Ruination"}, "Which damage prayer to use")
        ui:addInput("bankPin", "Bank PIN", "", "Your bank PIN for auto-entry")

        -- Add sections to organise config tab
        ui:addSection("Combat")
        ui:addCheckbox(...)
        ui:addSection("Health Thresholds")
        ui:addSlider(...)

        -- Add state colors for the info tab
        ui:addStateColor("Fighting", 1.0, 0.4, 0.3)
        ui:addStateColor("Banking", 0.3, 0.8, 0.4)

        -- In your main loop:
        ui:draw(data)   -- data = { state="Fighting", kills=5, ... }

        -- Access config values:
        local cfg = ui:getConfig()
        if cfg.campBoss then ... end

        -- Check script state:
        if ui:isStarted() then ... end
        if ui:isPaused() then ... end
        if ui:isStopped() then ... end
]]

local API = require("api")

local MEUI = {}
MEUI.VERSION = "1.0.0"

-------------------------------------------------------------------------------
--# BUILT-IN THEMES
-- Each theme is a 5-layer palette: dark → medium → light → bright → glow
-- You can pass a custom table with the same structure to Window()
-------------------------------------------------------------------------------

MEUI.Themes = {
    teal = {
        dark   = { 0.06, 0.08, 0.10 },
        medium = { 0.08, 0.18, 0.25 },
        light  = { 0.15, 0.35, 0.45 },
        bright = { 0.25, 0.55, 0.65 },
        glow   = { 0.40, 0.80, 0.90 },
    },
    purple = {
        dark   = { 0.09, 0.09, 0.09 },
        medium = { 0.18, 0.08, 0.25 },
        light  = { 0.35, 0.18, 0.45 },
        bright = { 0.55, 0.28, 0.65 },
        glow   = { 0.75, 0.45, 0.85 },
    },
    crimson = {
        dark   = { 0.09, 0.06, 0.06 },
        medium = { 0.25, 0.08, 0.10 },
        light  = { 0.45, 0.15, 0.18 },
        bright = { 0.65, 0.25, 0.28 },
        glow   = { 0.90, 0.40, 0.40 },
    },
    inferno = {
        dark   = { 0.08, 0.05, 0.02 },
        medium = { 0.30, 0.12, 0.04 },
        light  = { 0.55, 0.22, 0.08 },
        bright = { 0.75, 0.35, 0.10 },
        glow   = { 1.00, 0.55, 0.15 },
    },
    emerald = {
        dark   = { 0.05, 0.08, 0.06 },
        medium = { 0.06, 0.20, 0.12 },
        light  = { 0.12, 0.38, 0.22 },
        bright = { 0.20, 0.58, 0.35 },
        glow   = { 0.35, 0.85, 0.50 },
    },
    gold = {
        dark   = { 0.08, 0.07, 0.04 },
        medium = { 0.25, 0.20, 0.06 },
        light  = { 0.45, 0.38, 0.12 },
        bright = { 0.70, 0.58, 0.18 },
        glow   = { 1.00, 0.85, 0.30 },
    },
    ice = {
        dark   = { 0.06, 0.07, 0.10 },
        medium = { 0.08, 0.15, 0.28 },
        light  = { 0.15, 0.30, 0.50 },
        bright = { 0.25, 0.50, 0.75 },
        glow   = { 0.45, 0.75, 1.00 },
    },
}

--- Format large numbers: 1234567 → "1.2M", 1234 → "1.2K", 123 → "123"
function MEUI.formatNumber(n)
    if n >= 1000000 then
        return string.format("%.1fM", n / 1000000)
    elseif n >= 1000 then
        return string.format("%.1fK", n / 1000)
    end
    return string.format("%d", n)
end

--- Format seconds into HH:MM:SS
function MEUI.formatTime(seconds)
    seconds = math.floor(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end

--- Calculate per-hour rate from a count and elapsed seconds
function MEUI.perHour(count, elapsedSeconds)
    if not elapsedSeconds or elapsedSeconds < 1 then return 0 end
    return math.floor(count * 3600 / elapsedSeconds)
end

local Window = {}
Window.__index = Window

--- Create a new window builder.
---@param title string              Window title shown in title bar
---@param theme string|table        Theme name ("teal","purple",...) or custom palette table
---@param width? number             Window width in pixels (default 360)
---@return table                    Window builder instance
function MEUI.Window(title, theme, width)
    local palette = theme
    if type(theme) == "string" then
        palette = MEUI.Themes[theme]
        if not palette then
            error("[MEUI] Unknown theme '" .. tostring(theme) .. "'. Available: teal, purple, crimson, inferno, emerald, gold, ice")
        end
    end

    local self = setmetatable({}, Window)
    self._title = title or "Script"
    self._width = width or 360
    self._palette = palette
    self._id = title:gsub("%s+", "")

    -- State
    self.open = true
    self.started = false
    self.paused = false
    self.stopped = false
    self.cancelled = false
    self.warnings = {}
    self._selectConfigTab = true
    self._selectInfoTab = false
    self._selectWarningsTab = false

    -- Config fields (ordered list)
    self._fields = {}      -- { {type, key, label, default, ...}, ... }
    self._config = {}      -- { key = value, ... }

    -- State colors for info tab
    self._stateColors = {
        ["Idle"]    = { 0.7, 0.7, 0.7 },
        ["Paused"]  = { 1.0, 0.8, 0.2 },
        ["Dead"]    = { 0.5, 0.5, 0.5 },
    }

    -- Custom info tab draw function (optional override)
    self._customInfoDraw = nil

    -- Custom summary rows for config tab when running (optional)
    self._summaryRows = nil

    -- Config file
    self._configDir = os.getenv("USERPROFILE") .. "\\MemoryError\\Lua_Scripts\\configs\\"
    self._configPath = self._configDir .. self._id:lower() .. ".config.json"

    return self
end

--- Add a visual section header to the config tab.
---@param label string      Section title (displayed in theme glow color)
---@param desc? string      Optional description text below the header
function Window:addSection(label, desc)
    self._fields[#self._fields + 1] = { type = "section", label = label, desc = desc }
end

--- Add a checkbox toggle.
---@param key string         Config key name (e.g. "campBoss")
---@param label string       Display label
---@param default boolean    Default value
---@param desc? string       Optional tooltip/description
function Window:addCheckbox(key, label, default, desc)
    self._config[key] = default
    self._fields[#self._fields + 1] = {
        type = "checkbox", key = key, label = label, default = default, desc = desc
    }
end

--- Add an integer slider.
---@param key string         Config key name
---@param label string       Display label
---@param default number     Default value
---@param min number         Minimum value
---@param max number         Maximum value
---@param fmt? string        Format string (default "%d")
---@param desc? string       Optional description
function Window:addSlider(key, label, default, min, max, fmt, desc)
    self._config[key] = default
    self._fields[#self._fields + 1] = {
        type = "slider", key = key, label = label, default = default,
        min = min, max = max, fmt = fmt or "%d", desc = desc
    }
end

--- Add a dropdown combo box.
---@param key string         Config key name (stores 0-based index)
---@param label string       Display label
---@param default number     Default index (0-based)
---@param options table      Array of string options
---@param desc? string       Optional description
function Window:addCombo(key, label, default, options, desc)
    self._config[key] = default
    self._fields[#self._fields + 1] = {
        type = "combo", key = key, label = label, default = default,
        options = options, desc = desc
    }
end

--- Add a text input field.
---@param key string         Config key name
---@param label string       Display label
---@param default string     Default value
---@param desc? string       Optional description
---@param maxLen? number     Max input length (default 64)
function Window:addInput(key, label, default, desc, maxLen)
    self._config[key] = default
    self._fields[#self._fields + 1] = {
        type = "input", key = key, label = label, default = default,
        desc = desc, maxLen = maxLen or 64
    }
end

--- Add a visual separator line between fields.
function Window:addSeparator()
    self._fields[#self._fields + 1] = { type = "separator" }
end

--- Add a spacer (vertical gap).
function Window:addSpacing()
    self._fields[#self._fields + 1] = { type = "spacing" }
end

--- Register a state color for the info tab state display.
---@param state string       State name (e.g. "Fighting")
---@param r number           Red (0-1)
---@param g number           Green (0-1)
---@param b number           Blue (0-1)
function Window:addStateColor(state, r, g, b)
    self._stateColors[state] = { r, g, b }
end

--- Set a custom draw function for the info tab.
--- Your function receives (data, palette, helpers) where helpers has
--- row(), progressBar(), label(), sectionHeader(), flavorText(), formatNumber().
---@param fn function
function Window:setCustomInfoTab(fn)
    self._customInfoDraw = fn
end

--- Set summary rows shown on the config tab while running.
--- Should be a function(config) returning { {"Label", "Value"}, ... }
---@param fn function
function Window:setSummaryRows(fn)
    self._summaryRows = fn
end

--- Save current config to JSON file.
function Window:saveConfig()
    local data = {}
    for _, field in ipairs(self._fields) do
        if field.key then
            data[field.key] = self._config[field.key]
        end
    end
    local ok, json = pcall(API.JsonEncode, data)
    if not ok or not json then return end
    os.execute('mkdir "' .. self._configDir:gsub("/", "\\") .. '" 2>nul')
    local file = io.open(self._configPath, "w")
    if not file then return end
    file:write(json)
    file:close()
end

--- Load config from JSON file (merges with defaults).
function Window:loadConfig()
    local file = io.open(self._configPath, "r")
    if not file then return end
    local content = file:read("*a")
    file:close()
    if not content or content == "" then return end
    local ok, saved = pcall(API.JsonDecode, content)
    if not ok or not saved then return end

    for _, field in ipairs(self._fields) do
        if field.key and saved[field.key] ~= nil then
            local v = saved[field.key]
            if type(v) == type(field.default) then
                self._config[field.key] = v
            end
        end
    end
end

--- Get the current config as a table. Returns a shallow copy.
---@return table
function Window:getConfig()
    local copy = {}
    for k, v in pairs(self._config) do
        copy[k] = v
    end
    return copy
end

--- Get a single config value by key.
---@param key string
---@return any
function Window:get(key)
    return self._config[key]
end

--- Set a config value programmatically.
---@param key string
---@param value any
function Window:set(key, value)
    self._config[key] = value
end

function Window:isStarted()  return self.started   end
function Window:isPaused()   return self.paused     end
function Window:isStopped()  return self.stopped    end
function Window:isCancelled() return self.cancelled end

function Window:addWarning(msg)
    self.warnings[#self.warnings + 1] = msg
    if #self.warnings > 50 then
        table.remove(self.warnings, 1)
    end
end

function Window:clearWarnings()
    self.warnings = {}
end

function Window:reset()
    self.open = true
    self.started = false
    self.paused = false
    self.stopped = false
    self.cancelled = false
    self.warnings = {}
    self._selectConfigTab = true
    self._selectInfoTab = false
    self._selectWarningsTab = false
end

--- Switch to the Info tab on next frame.
function Window:showInfoTab()
    self._selectInfoTab = true
end

--- Switch to the Config tab on next frame.
function Window:showConfigTab()
    self._selectConfigTab = true
end

local function _label(text)
    ImGui.PushStyleColor(ImGuiCol.Text, 0.9, 0.9, 0.9, 1.0)
    ImGui.TextWrapped(text)
    ImGui.PopStyleColor(1)
end

local function _sectionHeader(palette, text)
    ImGui.PushStyleColor(ImGuiCol.Text, palette.glow[1], palette.glow[2], palette.glow[3], 1.0)
    ImGui.TextWrapped(text)
    ImGui.PopStyleColor(1)
end

local function _flavorText(palette, text)
    local g = palette.glow
    ImGui.PushStyleColor(ImGuiCol.Text, g[1] * 0.6, g[2] * 0.6, g[3] * 0.6, 1.0)
    ImGui.TextWrapped(text)
    ImGui.PopStyleColor(1)
end

local function _row(label, value, lr, lg, lb, vr, vg, vb)
    ImGui.TableNextRow()
    ImGui.TableNextColumn()
    ImGui.PushStyleColor(ImGuiCol.Text, lr or 1.0, lg or 1.0, lb or 1.0, 1.0)
    ImGui.TextWrapped(label)
    ImGui.PopStyleColor(1)
    ImGui.TableNextColumn()
    if vr then
        ImGui.PushStyleColor(ImGuiCol.Text, vr, vg, vb, 1.0)
        ImGui.TextWrapped(value)
        ImGui.PopStyleColor(1)
    else
        ImGui.TextWrapped(value)
    end
end

local function _progressBar(progress, height, text, r, g, b)
    ImGui.PushStyleColor(ImGuiCol.PlotHistogram, r * 0.7, g * 0.7, b * 0.7, 0.9)
    ImGui.PushStyleColor(ImGuiCol.FrameBg, r * 0.2, g * 0.2, b * 0.2, 0.8)
    ImGui.ProgressBar(progress, -1, height, text)
    ImGui.PopStyleColor(2)
end

local function _button(label, r, g, b, width, height)
    width = width or -1
    height = height or 28
    ImGui.PushStyleColor(ImGuiCol.Button, r, g, b, 0.9)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, r * 1.2, g * 1.2, b * 1.2, 1.0)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, r * 1.4, g * 1.4, b * 1.4, 1.0)
    local clicked = ImGui.Button(label, width, height)
    ImGui.PopStyleColor(3)
    return clicked
end

--- Build a helpers table bound to a palette (passed to custom draw functions).
local function buildHelpers(palette)
    return {
        label         = _label,
        sectionHeader = function(text) _sectionHeader(palette, text) end,
        flavorText    = function(text) _flavorText(palette, text) end,
        row           = _row,
        progressBar   = _progressBar,
        button        = _button,
        formatNumber  = MEUI.formatNumber,
        formatTime    = MEUI.formatTime,
        perHour       = MEUI.perHour,
    }
end

local function drawConfigTab(self)
    local cfg = self._config
    local p = self._palette

    if self.started then
        -- Running mode: show summary + controls
        local statusText = self.paused and "PAUSED" or "Running"
        local sc = self.paused and { 1.0, 0.8, 0.2 } or { 0.4, 0.8, 0.4 }
        ImGui.PushStyleColor(ImGuiCol.Text, sc[1], sc[2], sc[3], 1.0)
        ImGui.TextWrapped(statusText)
        ImGui.PopStyleColor(1)
        ImGui.Spacing()
        ImGui.Separator()

        -- Summary rows
        if self._summaryRows then
            local rows = self._summaryRows(cfg)
            if rows and #rows > 0 then
                if ImGui.BeginTable("##cfgsummary" .. self._id, 2) then
                    ImGui.TableSetupColumn("lbl", ImGuiTableColumnFlags.WidthStretch, 0.4)
                    ImGui.TableSetupColumn("val", ImGuiTableColumnFlags.WidthStretch, 0.6)
                    for _, r in ipairs(rows) do
                        _row(r[1], r[2])
                    end
                    ImGui.EndTable()
                end
                ImGui.Spacing()
                ImGui.Separator()
                ImGui.Spacing()
            end
        end

        -- Pause / Resume
        if self.paused then
            if _button("Resume Script##resume" .. self._id, 0.2, 0.5, 0.2) then
                self.paused = false
            end
        else
            if _button("Pause Script##pause" .. self._id, 0.4, 0.4, 0.4) then
                self.paused = true
            end
        end
        ImGui.Spacing()

        -- Stop
        if _button("Stop Script##stop" .. self._id, 0.5, 0.15, 0.15) then
            self.stopped = true
        end
        return
    end

    -- Pre-start config mode
    ImGui.PushItemWidth(-1)

    for _, field in ipairs(self._fields) do
        if field.type == "section" then
            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()
            _sectionHeader(p, field.label)
            if field.desc then _flavorText(p, field.desc) end
            ImGui.Spacing()

        elseif field.type == "separator" then
            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()

        elseif field.type == "spacing" then
            ImGui.Spacing()

        elseif field.type == "checkbox" then
            if field.desc then _flavorText(p, field.desc) end
            local changed, val = ImGui.Checkbox(field.label .. "##" .. field.key, cfg[field.key])
            if changed then cfg[field.key] = val end

        elseif field.type == "slider" then
            _label(field.label)
            if field.desc then _flavorText(p, field.desc) end
            local changed, val = ImGui.SliderInt("##" .. field.key, cfg[field.key], field.min, field.max, field.fmt)
            if changed then cfg[field.key] = val end

        elseif field.type == "combo" then
            _label(field.label)
            if field.desc then _flavorText(p, field.desc) end
            local changed, val = ImGui.Combo("##" .. field.key, cfg[field.key], field.options, #field.options)
            if changed then cfg[field.key] = val end

        elseif field.type == "input" then
            _label(field.label)
            if field.desc then _flavorText(p, field.desc) end
            local changed, val = ImGui.InputText("##" .. field.key, cfg[field.key], field.maxLen)
            if changed then cfg[field.key] = val end
        end
    end

    ImGui.PopItemWidth()
    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    -- Start button (theme colored)
    if _button("Start " .. self._title .. "##start" .. self._id,
               p.bright[1], p.bright[2], p.bright[3], -1, 32) then
        self:saveConfig()
        self.started = true
        self._selectInfoTab = true
    end
    ImGui.Spacing()

    -- Cancel button
    if _button("Cancel##cancel" .. self._id, 0.4, 0.4, 0.4) then
        self.cancelled = true
    end
end

local function drawDefaultInfoTab(self, data)
    local p = self._palette

    -- State display
    local stateText = data.state or "Idle"
    if self.paused then stateText = "Paused" end
    local sc = self._stateColors[stateText] or { 0.7, 0.7, 0.7 }
    ImGui.PushStyleColor(ImGuiCol.Text, sc[1], sc[2], sc[3], 1.0)
    ImGui.TextWrapped(stateText)
    ImGui.PopStyleColor(1)

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    -- Boss health bar (if data provides it)
    if data.bossHealth and data.bossMaxHealth and data.bossHealth > 0 then
        local pct = math.max(0, math.min(1, data.bossHealth / data.bossMaxHealth))
        local healthText = string.format("%s: %s / %s (%.1f%%)",
            data.bossName or "Boss",
            MEUI.formatNumber(data.bossHealth),
            MEUI.formatNumber(data.bossMaxHealth),
            pct * 100)
        _progressBar(pct, 28, healthText, p.glow[1], p.glow[2], p.glow[3])
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()
    end

    -- Stats table (if data provides common fields)
    local hasStats = data.kills or data.deaths or data.killTimer or data.gp
    if hasStats then
        if ImGui.BeginTable("##infostats" .. self._id, 2) then
            ImGui.TableSetupColumn("lbl", ImGuiTableColumnFlags.WidthStretch, 0.35)
            ImGui.TableSetupColumn("val", ImGuiTableColumnFlags.WidthStretch, 0.65)

            if data.kills then
                local kph = data.killsPerHour or 0
                _row("Kills", string.format("%d (%s/hr)", data.kills, tostring(kph)))
            end
            if data.deaths then
                _row("Deaths", tostring(data.deaths))
            end
            if data.gp then
                local gph = data.gpPerHour or 0
                _row("GP", string.format("%s (%s/hr)", MEUI.formatNumber(data.gp), MEUI.formatNumber(gph)))
            end
            if data.killTimer then
                _row("Kill Timer", tostring(data.killTimer))
            end
            if data.fastestKill then
                _row("Fastest", data.fastestKill, 1, 1, 1, 0.3, 0.85, 0.45)
            end
            if data.slowestKill then
                _row("Slowest", data.slowestKill, 1, 1, 1, 1.0, 0.5, 0.3)
            end
            if data.averageKill then
                _row("Average", data.averageKill)
            end

            ImGui.EndTable()
        end
    end

    -- Recent kills
    if data.killData and #data.killData > 0 then
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()
        _sectionHeader(p, "Recent Kills")
        if ImGui.BeginTable("##recentkills" .. self._id, 2) then
            ImGui.TableSetupColumn("kc", ImGuiTableColumnFlags.WidthStretch, 0.3)
            ImGui.TableSetupColumn("dur", ImGuiTableColumnFlags.WidthStretch, 0.7)
            _row("Kill #", "Duration", 1, 1, 1, 1, 1, 1)
            for i = math.max(1, #data.killData - 4), #data.killData do
                local kill = data.killData[i]
                _row(tostring(i), kill.fightDuration or "--", 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
            end
            ImGui.EndTable()
        end
    end

    -- Unique drops
    if data.uniquesLooted and #data.uniquesLooted > 0 then
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()
        _sectionHeader(p, "Unique Drops")
        for _, drop in ipairs(data.uniquesLooted) do
            local name = type(drop) == "table" and drop[1] or tostring(drop)
            ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 1.0, 1.0, 1.0)
            ImGui.TextWrapped(name)
            ImGui.PopStyleColor(1)
        end
    end
end

local function drawInfoTab(self, data)
    if self._customInfoDraw then
        local helpers = buildHelpers(self._palette)
        self._customInfoDraw(data, self._palette, helpers)
    else
        drawDefaultInfoTab(self, data)
    end
end

local function drawWarningsTab(self)
    if #self.warnings == 0 then
        ImGui.PushStyleColor(ImGuiCol.Text, 0.6, 0.6, 0.65, 1.0)
        ImGui.TextWrapped("No warnings.")
        ImGui.PopStyleColor(1)
        return
    end

    for _, warning in ipairs(self.warnings) do
        ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.75, 0.2, 1.0)
        ImGui.TextWrapped("! " .. warning)
        ImGui.PopStyleColor(1)
        ImGui.Spacing()
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    if _button("Dismiss Warnings##clearwarn" .. self._id, 0.5, 0.45, 0.1) then
        self.warnings = {}
    end
end

local function drawContent(self, data)
    if ImGui.BeginTabBar("##maintabs" .. self._id, 0) then
        -- Config tab
        local cfgFlags = self._selectConfigTab and ImGuiTabItemFlags.SetSelected or 0
        self._selectConfigTab = false
        if ImGui.BeginTabItem("Config###config" .. self._id, nil, cfgFlags) then
            ImGui.Spacing()
            drawConfigTab(self)
            ImGui.EndTabItem()
        end

        -- Info tab (only when started)
        if self.started then
            local infoFlags = self._selectInfoTab and ImGuiTabItemFlags.SetSelected or 0
            self._selectInfoTab = false
            if ImGui.BeginTabItem("Info###info" .. self._id, nil, infoFlags) then
                ImGui.Spacing()
                drawInfoTab(self, data or {})
                ImGui.EndTabItem()
            end
        end

        -- Warnings tab (only when warnings exist)
        if #self.warnings > 0 then
            local warnLabel = "Warnings (" .. #self.warnings .. ")###warnings" .. self._id
            local warnFlags = self._selectWarningsTab and ImGuiTabItemFlags.SetSelected or 0
            if ImGui.BeginTabItem(warnLabel, nil, warnFlags) then
                self._selectWarningsTab = false
                ImGui.Spacing()
                drawWarningsTab(self)
                ImGui.EndTabItem()
            end
        end

        ImGui.EndTabBar()
    end
end

local function pushTheme(p)
    ImGui.PushStyleColor(ImGuiCol.WindowBg,        p.dark[1],            p.dark[2],            p.dark[3],            0.97)
    ImGui.PushStyleColor(ImGuiCol.TitleBg,          p.medium[1] * 0.6,   p.medium[2] * 0.6,   p.medium[3] * 0.6,   1.0)
    ImGui.PushStyleColor(ImGuiCol.TitleBgActive,    p.medium[1],          p.medium[2],          p.medium[3],          1.0)
    ImGui.PushStyleColor(ImGuiCol.Separator,        p.light[1],           p.light[2],           p.light[3],           0.4)
    ImGui.PushStyleColor(ImGuiCol.Tab,              p.medium[1] * 0.7,   p.medium[2] * 0.7,   p.medium[3] * 0.7,   1.0)
    ImGui.PushStyleColor(ImGuiCol.TabHovered,       p.light[1],           p.light[2],           p.light[3],           1.0)
    ImGui.PushStyleColor(ImGuiCol.TabActive,        p.bright[1] * 0.7,   p.bright[2] * 0.7,   p.bright[3] * 0.7,   1.0)
    ImGui.PushStyleColor(ImGuiCol.FrameBg,          p.medium[1] * 0.5,   p.medium[2] * 0.5,   p.medium[3] * 0.5,   0.9)
    ImGui.PushStyleColor(ImGuiCol.FrameBgHovered,   p.light[1] * 0.7,    p.light[2] * 0.7,    p.light[3] * 0.7,    1.0)
    ImGui.PushStyleColor(ImGuiCol.FrameBgActive,    p.bright[1] * 0.5,   p.bright[2] * 0.5,   p.bright[3] * 0.5,   1.0)
    ImGui.PushStyleColor(ImGuiCol.SliderGrab,       p.bright[1],          p.bright[2],          p.bright[3],          1.0)
    ImGui.PushStyleColor(ImGuiCol.SliderGrabActive, p.glow[1],            p.glow[2],            p.glow[3],            1.0)
    ImGui.PushStyleColor(ImGuiCol.CheckMark,        p.glow[1],            p.glow[2],            p.glow[3],            1.0)
    ImGui.PushStyleColor(ImGuiCol.Header,           p.medium[1],          p.medium[2],          p.medium[3],          0.8)
    ImGui.PushStyleColor(ImGuiCol.HeaderHovered,    p.light[1],           p.light[2],           p.light[3],           1.0)
    ImGui.PushStyleColor(ImGuiCol.HeaderActive,     p.bright[1],          p.bright[2],          p.bright[3],          1.0)
    ImGui.PushStyleColor(ImGuiCol.Text,             1.0, 1.0, 1.0, 1.0)

    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 14, 10)
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 6, 4)
    ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 4)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 6)
    ImGui.PushStyleVar(ImGuiStyleVar.TabRounding, 4)
end

local function popTheme()
    ImGui.PopStyleVar(5)
    ImGui.PopStyleColor(17)
end

--- Draw the window. Call this every frame from your main loop.
---@param data? table    Runtime data for the info tab (state, kills, bossHealth, etc.)
---@return boolean       Whether the window is still open
function Window:draw(data)
    ImGui.SetNextWindowSize(self._width, 0, ImGuiCond.Always)
    ImGui.SetNextWindowPos(100, 100, ImGuiCond.FirstUseEver)

    pushTheme(self._palette)

    local titleText = self._title .. " - " .. API.ScriptRuntimeString() .. "###" .. self._id
    local visible = ImGui.Begin(titleText, 0)

    if visible then
        local ok, err = pcall(drawContent, self, data)
        if not ok then
            ImGui.TextColored(1.0, 0.3, 0.3, 1.0, "UI Error: " .. tostring(err))
        end
    end

    popTheme()
    ImGui.End()

    return self.open
end

MEUI.Draw = {}

--- Draw colored text.
function MEUI.Draw.text(text, r, g, b)
    if r then
        ImGui.PushStyleColor(ImGuiCol.Text, r, g, b, 1.0)
        ImGui.TextWrapped(text)
        ImGui.PopStyleColor(1)
    else
        ImGui.TextWrapped(text)
    end
end

--- Draw a section header in a given palette's glow color.
function MEUI.Draw.sectionHeader(text, palette)
    local g = palette and palette.glow or { 0.8, 0.8, 0.8 }
    ImGui.PushStyleColor(ImGuiCol.Text, g[1], g[2], g[3], 1.0)
    ImGui.TextWrapped(text)
    ImGui.PopStyleColor(1)
end

--- Draw a table row (must be inside BeginTable/EndTable).
MEUI.Draw.row = _row

--- Draw a progress bar with custom colors.
MEUI.Draw.progressBar = _progressBar

--- Draw a themed button. Returns true if clicked.
MEUI.Draw.button = _button

--- Apply a full theme. Returns a pop function to call when done.
---@param theme string|table
---@return function popFn    Call this when you're done: popFn()
function MEUI.Draw.pushTheme(theme)
    local palette = theme
    if type(theme) == "string" then
        palette = MEUI.Themes[theme]
    end
    pushTheme(palette)
    return popTheme
end

return MEUI
