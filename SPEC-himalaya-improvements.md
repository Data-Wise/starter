# SPEC: Himalaya Neovim Improvements

> **Date:** 2026-02-18
> **Branch:** `feature/himalaya-improvements`
> **Status:** Implemented
> **From Brainstorm:** `~/BRAINSTORM-nvim-himalaya-improvements-2026-02-18.md`

## Summary

Two enhancements to the LazyVim himalaya email integration: generic backend `extra_args` support (fixing Gemini CLI latency), and a keybind-based AI backend toggle with lualine indicator.

A third planned feature (floating terminal via Snacks) was dropped — himalaya CLI is non-interactive and exits immediately, making `Snacks.terminal.toggle` unusable.

## Implemented

### 1. Generic `extra_args` Backend Support

**Problem:** Gemini CLI loads 8+ extensions on every invocation (~5-8s startup). Passing `-e none` reduces this to ~1-2s, but `himalaya-ai.lua` only supported `cmd` and `flag` per backend.

**Solution:** Added optional `extra_args` table to backend config, inserted between `cmd` and `flag` in the `vim.fn.jobstart()` command array.

**Files changed:**
- `lua/himalaya-ai.lua` — modified `run_ai()` (line ~787) and `_run_ai_custom()` (line ~855)
- `~/.config/himalaya-ai/config.lua` — added `extra_args = { "-e", "none" }` to gemini backend

**Implementation:**
```lua
local cmd = { backend.cmd }
if backend.extra_args then
  for _, arg in ipairs(backend.extra_args) do
    cmd[#cmd + 1] = arg
  end
end
cmd[#cmd + 1] = backend.flag
cmd[#cmd + 1] = prompt_text
vim.fn.jobstart(cmd, { ... })
```

**Result:** Gemini responds in ~1-2s instead of ~5-8s. Backward-compatible — backends without `extra_args` work unchanged.

---

### 2. Backend Toggle Keybind + Lualine Indicator

**Problem:** Switching AI backend required `:HimalayaAi set backend gemini` — too much typing.

**Solution:**
- `<leader>mB` — cycles through sorted backend names with notification
- Lualine component in `lualine_x` showing active backend with mail icon

**Files changed:**
- `lua/config/keymaps.lua` — added `<leader>mB` toggle keybind
- `lua/plugins/himalaya.lua` — added lualine.nvim spec with backend indicator

**Result:** `<leader>mB` cycles backend, lualine updates immediately. Uses `pcall` guard so lualine doesn't error before himalaya-ai is loaded.

---

### 3. Floating Terminal — DROPPED

**Original plan:** `Snacks.terminal.toggle("himalaya")` for a lazygit-style floating TUI.

**Why it was dropped:** himalaya CLI v1.x is a non-interactive command — it prints output and exits. There is no TUI/interactive mode. `Snacks.terminal.toggle` opened a terminal, himalaya printed its envelope list, exited, and the terminal closed immediately.

**What we kept instead:**
- Dashboard `e` button → `<cmd>Himalaya<CR>` (buffer mode, which IS the interactive email experience provided by himalaya-vim)
- `<leader>em` → same `:Himalaya` buffer mode

**Lesson learned:** alpha-nvim's `button()` function requires `<cmd>...<CR>` string notation for keybinds — it defaults to `noremap=true`, which prevents `<leader>...` references from triggering other mappings.

---

## Keybind Map (Final)

| Keybind | Action | Status |
|---------|--------|--------|
| `<leader>em` | Open Himalaya (buffer mode) | NEW |
| `<leader>mB` | Toggle AI backend | NEW |
| `<leader>ms` | AI: Summarize | Existing |
| `<leader>mt` | AI: Extract todos | Existing |
| `<leader>mr` | AI: Draft reply | Existing |
| `<leader>mc` | AI: TL;DR | Existing |
| `<leader>mw` | AI: Compose | Existing |
| `<leader>mp` | AI: Prompt picker | Existing |
| `<leader>mi` | AI: Status | Existing |
| Lualine | Shows active backend (claude/gemini) | NEW |
| Dashboard `e` | Opens `:Himalaya` | Existing (preserved) |

## Decisions Made

- `<leader>mB` is **memory-only** — does not persist to config file on toggle. Restarts reset to config default (claude).
- Dashboard `e` button opens buffer mode (`:Himalaya`), not a floating terminal.
- `extra_args` are inserted between `cmd` and `flag` (e.g., `gemini -e none -p "prompt"`), not appended at the end.

## Review Checklist

- [x] extra_args doesn't break existing Claude backend
- [x] Gemini with `-e none` responds correctly to email prompts
- [x] Backend toggle cycles correctly with 2+ backends
- [x] Lualine component doesn't error when himalaya-ai not loaded
- [x] Dashboard `e` button works (uses `<cmd>Himalaya<CR>`)
- [x] No keybind conflicts with existing LazyVim defaults
- [x] All 43 automated tests pass
