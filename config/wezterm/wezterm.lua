local wezterm = require("wezterm")
local config = {}

-- config.font = wezterm.font 'Menlo'
-- config.font = wezterm.font 'JetBrains Mono'
config.font_size = 14.0

-- Import our new module (put this near the top of your wezterm.lua)
local appearance = require("appearance")

-- Use it!
if appearance.is_dark() then
	config.color_scheme = "rose-pine"
	config.window_background_opacity = 0.9
else
	config.color_scheme = "rose-pine-moon"
end

-- config.color_scheme = 'rose-pine'
-- config.color_scheme = 'tokyonight_moon'

config.audible_bell = "Disabled"

config.initial_rows = 30
config.initial_cols = 80

return config
