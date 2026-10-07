-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Let Herdr's nvim-links plugin find this editor without sending terminal keystrokes.
-- Register early, including when Neovim starts with no file (LazyVim's later
-- autocmds.lua loading is deferred in that case). RPC stays on a local socket.
if vim.env.HERDR_ENV == "1" and vim.env.HERDR_PANE_ID then
  local ok, err = pcall(function()
    local server = vim.v.servername
    if server == "" then
      server = vim.fn.serverstart()
    end
    local cache = vim.env.XDG_CACHE_HOME
    if not cache or cache == "" then
      cache = vim.fn.expand("~/.cache")
    end
    local dir = cache .. "/herdr-nvim-links"
    vim.fn.mkdir(dir, "p", 448) -- 0700
    local record = dir .. "/" .. vim.fn.getpid() .. ".json"
    local temporary = record .. ".tmp"
    vim.fn.writefile({
      vim.json.encode({
        pid = vim.fn.getpid(),
        pane_id = vim.env.HERDR_PANE_ID,
        herdr_socket = vim.env.HERDR_SOCKET_PATH,
        server = server,
      }),
    }, temporary)
    assert(vim.fn.rename(temporary, record) == 0, "Could not register Neovim RPC")
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = vim.api.nvim_create_augroup("herdr_nvim_links", { clear = true }),
      callback = function()
        vim.fn.delete(record)
      end,
    })
  end)
  if not ok then
    vim.schedule(function()
      vim.notify("Herdr link registration: " .. tostring(err), vim.log.levels.WARN)
    end)
  end
end
