return {
  {
    "folke/lazydev.nvim",
    ft = "lua", -- only load on lua files
    opts = {
      library = {
        -- This tells LazyVim: "When I use 'wezterm', look up words in this library"
        { path = "wezterm-types", mods = { "wezterm" } },
      },
    },
  },
}
