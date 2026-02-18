# SPEC: Himalaya Neovim Improvements

> **Date:** 2026-02-18
> **Branch:** `feature/himalaya-improvements`
> **Status:** Draft
> **From Brainstorm:** `~/BRAINSTORM-nvim-himalaya-improvements-2026-02-18.md`

## Summary

Three enhancements to the LazyVim himalaya email integration: generic backend extra_args support (fixing Gemini CLI latency), a keybind-based AI backend toggle with lualine indicator, and a lazygit-style floating terminal for quick inbox triage.

## Requirements

### 1. Generic `extra_args` Backend Support

**Problem:** Gemini CLI loads 8+ extensions on every invocation (~5-8s startup). Passing `-e none` reduces this to ~1-2s, but `himalaya-ai.lua` only supports `cmd` and `flag` per backend.

**Solution:** Add optional `extra_args` table to backend config. Spread into `vim.fn.jobstart()` call.

**Files:**
- `lua/himalaya-ai.lua` — modify `run_ai()` and `_run_ai_custom()` job command construction
- `~/.config/himalaya-ai/config.lua` — add `extra_args = { "-e", "none" }` to gemini backend

**Config change:**
```lua
-- Before:
gemini = { cmd = "/opt/homebrew/bin/gemini", flag = "-p" },

-- After:
gemini = { cmd = "/opt/homebrew/bin/gemini", flag = "-p", extra_args = { "-e", "none" } },
```

**Code change (himalaya-ai.lua):**
```lua
-- Before:
vim.fn.jobstart({ backend.cmd, backend.flag, prompt_text }, { ... })

-- After:
local cmd = { backend.cmd, backend.flag, prompt_text }
if backend.extra_args then
  for i, arg in ipairs(backend.extra_args) do
    table.insert(cmd, i + 1, arg)  -- insert after cmd, before flag
  end
end
vim.fn.jobstart(cmd, { ... })
```

**Acceptance:** `echo "test" | gemini -e none -p "say hi"` completes in <3s (vs ~8s without `-e none`).

---

### 2. Backend Toggle Keybind + Lualine Indicator

**Problem:** Switching AI backend requires `:HimalayaAi set backend gemini` — too much typing.

**Solution:**
- `<leader>mB` — cycles `claude → gemini → claude` with notification
- Lualine component showing active backend name

**Files:**
- `lua/config/keymaps.lua` — add toggle keybind
- `lua/plugins/himalaya.lua` or new `lua/plugins/lualine-himalaya.lua` — lualine component

**Keybind:**
```lua
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
```

**Lualine component:**
```lua
{
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    table.insert(opts.sections.lualine_x, 1, {
      function()
        local ok, hai = pcall(require, "himalaya-ai")
        if ok then return hai.config.backend end
        return ""
      end,
      cond = function()
        local ok, hai = pcall(require, "himalaya-ai")
        return ok and hai.config.backend ~= nil
      end,
      icon = "󰇮",
      color = { fg = "#7aa2f7" },
    })
  end,
}
```

**Acceptance:** `<leader>mB` cycles backend, lualine updates immediately.

---

### 3. Floating Terminal Himalaya (`<leader>em`)

**Problem:** No quick inbox scan without leaving current buffer. `:Himalaya` opens in a buffer (good for AI features, but heavy for a quick check).

**Solution:** `Snacks.terminal.toggle("himalaya")` — same UX as lazygit's `<leader>gg`.

**Files:**
- `lua/plugins/dashboard.lua` — add Snacks style + keybind + update dashboard button

**Implementation:**
```lua
-- Snacks style
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
}
```

**Dashboard button update:** Point the `e` button to the floating terminal instead of `:Himalaya`.

**Acceptance:** `<leader>em` opens/closes himalaya TUI in 85% floating window. Dashboard `e` button does the same.

---

## Keybind Map (After Implementation)

| Keybind | Action | Mode |
|---------|--------|------|
| `<leader>em` | Floating TUI (quick inbox) | NEW |
| `<leader>eM` | Buffer mode (for AI features) | Existing |
| `<leader>mB` | Toggle AI backend | NEW |
| `<leader>ms` | AI: Summarize | Existing |
| `<leader>mt` | AI: Extract todos | Existing |
| `<leader>mr` | AI: Draft reply | Existing |
| `<leader>mc` | AI: TL;DR | Existing |
| `<leader>mw` | AI: Compose | Existing |
| `<leader>mp` | AI: Prompt picker | Existing |
| `<leader>mi` | AI: Status | Existing |
| Lualine | Shows active backend (claude/gemini) | NEW |

## Implementation Order

1. **extra_args** (prerequisite — makes Gemini usable)
2. **backend toggle + lualine** (uses extra_args-enabled Gemini)
3. **floating terminal** (independent, but nice to test with both backends)

## Open Questions

- Should `<leader>mB` persist the choice to `~/.config/himalaya-ai/config.lua`? (Currently: memory only, resets on restart)
- Should the dashboard `e` button open floating TUI or buffer mode?

## Review Checklist

- [ ] extra_args doesn't break existing Claude backend
- [ ] Gemini with `-e none` responds correctly to email prompts
- [ ] Backend toggle cycles correctly with 2+ backends
- [ ] Lualine component doesn't error when himalaya-ai not loaded
- [ ] Floating terminal opens/closes cleanly
- [ ] No keybind conflicts with existing LazyVim defaults
