-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Himalaya AI email actions
vim.keymap.set("n", "<leader>ms", function() require("himalaya-ai").summarize() end, { desc = "AI: Summarize email" })
vim.keymap.set("n", "<leader>mt", function() require("himalaya-ai").extract_todos() end, { desc = "AI: Extract action items" })
vim.keymap.set("n", "<leader>mr", function() require("himalaya-ai").draft_reply() end, { desc = "AI: Draft reply" })
vim.keymap.set("n", "<leader>mc", function() require("himalaya-ai").tldr() end, { desc = "AI: TL;DR + decision" })
vim.keymap.set("n", "<leader>mw", function() require("himalaya-ai").compose() end, { desc = "AI: Compose email" })
vim.keymap.set("n", "<leader>mp", function()
  local hai = require("himalaya-ai")
  vim.ui.select(
    { "Summarize", "Extract Todos", "Draft Reply", "TL;DR", "Compose" },
    { prompt = "AI Action:" },
    function(choice)
      if not choice then return end
      local actions = {
        Summarize = hai.summarize,
        ["Extract Todos"] = hai.extract_todos,
        ["Draft Reply"] = hai.draft_reply,
        ["TL;DR"] = hai.tldr,
        Compose = hai.compose,
      }
      actions[choice]()
    end
  )
end, { desc = "AI: Prompt picker" })
vim.keymap.set("n", "<leader>mi", function() vim.cmd("HimalayaAi status") end, { desc = "AI: Status info" })
vim.keymap.set("n", "<leader>mB", function()
  local hai = require("himalaya-ai")
  local backends = vim.tbl_keys(hai.config.backends)
  table.sort(backends)
  local current = hai.config.backend
  local idx = 1
  for i, b in ipairs(backends) do
    if b == current then idx = i; break end
  end
  local next_backend = backends[(idx % #backends) + 1]
  hai.config.backend = next_backend
  vim.notify("AI backend → " .. next_backend, vim.log.levels.INFO)
end, { desc = "AI: Toggle backend" })
