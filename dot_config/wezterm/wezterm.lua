-- ~/.wezterm.lua
local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- ============================================
-- PERFORMANCE (CRITICAL FOR M2)
-- ============================================
config.front_end = "WebGpu" -- Uses native Metal on M2
config.max_fps = 60
config.animation_fps = 60

-- ============================================
-- SHELL
-- ============================================
config.default_prog = { "/opt/homebrew/bin/fish" }

-- ============================================
-- FONT
-- ============================================
config.font = wezterm.font("JetBrains Mono")
config.font_size = 13.0

-- ============================================
-- COLORS
-- ============================================
config.color_scheme = "Tokyo Night"

-- ============================================
-- UI CLEANUP
-- ============================================
config.enable_tab_bar = false -- You use tmux
config.window_decorations = "RESIZE"

config.window_padding = {
	left = 10,
	right = 10,
	top = 10,
	bottom = 10,
}

-- ============================================
-- CURSOR
-- ============================================
config.default_cursor_style = "SteadyBar"
config.cursor_blink_rate = 0

-- ============================================
-- SCROLLBACK
-- ============================================
config.scrollback_lines = 10000

return config
