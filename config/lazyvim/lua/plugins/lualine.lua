-- Custom lualine configuration to add keyboard layout warning indicator
return {
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = function(_, opts)
      -- Cache for keyboard layout check to avoid performance issues
      local keyboard_layout_cache = { output = "", timestamp = 0 }
      local cache_duration = 2 -- seconds

      -- Function to get keyboard layout warning
      local function get_keyboard_layout()
        local now = os.time()
        if now - keyboard_layout_cache.timestamp < cache_duration then
          return keyboard_layout_cache.output
        end

        -- Execute check-keyboard-layout script
        local handle = io.popen("~/.local/bin/check-keyboard-layout 2>/dev/null")
        if not handle then
          keyboard_layout_cache.output = ""
          keyboard_layout_cache.timestamp = now
          return ""
        end

        local result = handle:read("*a") or ""
        handle:close()

        -- Script outputs warning text when non-English, nothing when English
        -- Remove trailing newline and store result
        local output = result:gsub("%s+$", "") -- trim trailing whitespace/newlines
        keyboard_layout_cache.output = output
        keyboard_layout_cache.timestamp = now

        return keyboard_layout_cache.output
      end

      -- Add keyboard layout component to lualine_x (right side, before file info)
      table.insert(opts.sections.lualine_x, 1, {
        get_keyboard_layout,
        color = { fg = "#ffc777" }, -- Tokyo Night Moon warning color (yellow)
      })
    end,
  },
}
