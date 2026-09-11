-- The colorscheme follows the Omaccy theme; see lua/omaccy/theme.lua. One
-- plugin per theme, each lazy so only the one in use is ever loaded --
-- lazy.nvim loads a colorscheme plugin when its colorscheme is applied. They
-- are all installed up front so switching themes never waits on a download.

---@type LazySpec
return {
  {
    "AstroNvim/astroui",
    ---@param opts AstroUIOpts
    opts = function(_, opts)
      local theme = require "omaccy.theme"
      local current = theme.current()
      vim.o.background = current.background
      opts.colorscheme = current.colorscheme
      theme.watch()
    end,
  },
  { "catppuccin/nvim", name = "catppuccin", lazy = true },
  { "Mofiqul/dracula.nvim", lazy = true },
  {
    "sainnhe/everforest",
    lazy = true,
    -- Ghostty's Everforest Dark Hard, to match the terminal around it.
    init = function() vim.g.everforest_background = "hard" end,
  },
  { "projekt0n/github-nvim-theme", name = "github-theme", lazy = true },
  { "ellisonleao/gruvbox.nvim", lazy = true },
  { "rebelot/kanagawa.nvim", lazy = true },
  { "gbprod/nord.nvim", lazy = true },
  { "navarasu/onedark.nvim", lazy = true },
  { "rose-pine/neovim", name = "rose-pine", lazy = true },
  { "maxmx03/solarized.nvim", lazy = true },
  { "folke/tokyonight.nvim", lazy = true },
}
