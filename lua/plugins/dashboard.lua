-- dashboard.lua — Custom alpha-nvim dashboard buttons

return {
  {
    "goolord/alpha-nvim",
    opts = function(_, dashboard)
      local btn = require("alpha.themes.dashboard").button

      local email_btn = btn("e", "󰇮  Email", "<leader>em")
      email_btn.opts.hl = "AlphaButtons"
      email_btn.opts.hl_shortcut = "AlphaShortcut"
      table.insert(dashboard.section.buttons.val, 5, email_btn)
    end,
  },
}
