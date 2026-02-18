-- dashboard.lua — Custom alpha-nvim dashboard buttons + floating email terminal

return {
  {
    "goolord/alpha-nvim",
    opts = function(_, dashboard)
      local btn = require("alpha.themes.dashboard").button

      local email_btn = btn("e", "󰇮  Email", function()
        Snacks.terminal.toggle("himalaya", {
          cwd = vim.fn.expand("~"),
          win = { style = "himalaya" },
        })
      end)
      email_btn.opts.hl = "AlphaButtons"
      email_btn.opts.hl_shortcut = "AlphaShortcut"
      table.insert(dashboard.section.buttons.val, 5, email_btn)
    end,
  },
  {
    "folke/snacks.nvim",
    opts = {
      styles = {
        himalaya = {
          width = 0.85,
          height = 0.85,
          border = "rounded",
          title = " Email ",
          title_pos = "center",
        },
      },
    },
    keys = {
      {
        "<leader>em",
        function()
          Snacks.terminal.toggle("himalaya", {
            cwd = vim.fn.expand("~"),
            win = { style = "himalaya" },
          })
        end,
        desc = "Email (floating)",
      },
    },
  },
}
