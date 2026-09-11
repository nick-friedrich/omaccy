-- Follows the Omaccy theme. scripts/theme.sh writes the chosen name to
-- ~/.omaccy/theme, and each theme file in ~/.omaccy/config/sketchybar/themes
-- names its Neovim colorscheme in NVIM_COLORSCHEME and its light or dark in
-- APPEARANCE. Both are read at startup, and ~/.omaccy is watched so that every
-- running nvim repaints the moment the theme changes -- no restart, and no
-- socket for theme.sh to find.

local M = {}

local uv = vim.uv or vim.loop
local omaccy_dir = vim.env.OMACCY_DIR or (vim.env.HOME .. "/.omaccy")
local default_theme = "catppuccin"
-- A theme file from before NVIM_COLORSCHEME, or a custom one without it.
local fallback = "astrodark"

local function first_line(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local line = file:read "*l"
  file:close()
  return line and vim.trim(line) or nil
end

-- Theme files are shell, but only ever KEY="value" lines, so the one value
-- can be read without running them.
local function theme_value(path, key)
  local file = io.open(path, "r")
  if not file then return nil end
  local value
  for line in file:lines() do
    value = line:match("^%s*" .. key .. '="([^"]*)"')
    if value then break end
  end
  file:close()
  return value
end

function M.current()
  local name = first_line(omaccy_dir .. "/theme")
  if not name or name == "" then name = default_theme end
  local theme_file = omaccy_dir .. "/config/sketchybar/themes/" .. name .. ".sh"
  local colorscheme = theme_value(theme_file, "NVIM_COLORSCHEME")
  return {
    colorscheme = (colorscheme and colorscheme ~= "") and colorscheme or fallback,
    background = theme_value(theme_file, "APPEARANCE") == "light" and "light" or "dark",
  }
end

function M.apply()
  local theme = M.current()
  if vim.g.colors_name == theme.colorscheme and vim.o.background == theme.background then return end
  vim.o.background = theme.background
  if not pcall(vim.cmd.colorscheme, theme.colorscheme) then
    vim.notify(("Omaccy theme: no colorscheme named %s"):format(theme.colorscheme), vim.log.levels.WARN)
    pcall(vim.cmd.colorscheme, fallback)
  end
end

-- The directory rather than the file: a watch on a file follows its inode,
-- and a theme written by replacing the file would go unseen. theme.sh
-- truncates before it writes, so changes settle briefly before being read.
function M.watch()
  if M.watcher then return end
  local watcher, timer = uv.new_fs_event(), uv.new_timer()
  if not watcher or not timer then return end
  local ok = watcher:start(omaccy_dir, {}, function(err, filename)
    if err or not filename or filename:match "[^/]+$" ~= "theme" then return end
    timer:stop()
    timer:start(100, 0, vim.schedule_wrap(M.apply))
  end)
  if ok then M.watcher = watcher end
end

return M
