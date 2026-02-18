# Himalaya Email Integration — Architecture

## File Map

| File | Purpose | Loaded |
|------|---------|--------|
| `lua/himalaya-ai.lua` | AI module: prompts, backends, result buffer | On first require |
| `lua/config/keymaps.lua` | AI keybinds (`<leader>m*`, `<leader>mB`) | VeryLazy event |
| `lua/plugins/himalaya.lua` | himalaya-vim spec + lualine backend indicator | Startup |
| `lua/plugins/dashboard.lua` | Alpha-nvim email button | VimEnter |
| `~/.config/himalaya-ai/config.lua` | User config (backends, prompts, obsidian) | On module load |

## Data Flow

### AI Action Flow
```
User presses <leader>mc (TL;DR)
  → keymaps.lua calls require("himalaya-ai").tldr()
  → run_ai_with_input() checks ask_before config
  → run_ai() gets current buffer text
  → Builds command: { cmd, [extra_args...], flag, prompt }
  → vim.fn.jobstart() pipes email via stdin
  → on_exit callback opens result buffer
  → Result buffer provides y/s/o/r/c/n/t/p/e keybinds
```

### Backend Toggle Flow
```
User presses <leader>mB
  → keymaps.lua cycles through sorted backend keys
  → Sets hai.config.backend (memory only)
  → vim.notify shows new backend
  → Lualine component re-reads hai.config.backend
```

### Config Loading
```
Module load → load_config()
  → dofile("~/.config/himalaya-ai/config.lua")
  → vim.tbl_deep_extend("force", defaults, user_config)
  → M.config = merged result
```

## Module API

### Public Functions
| Function | Purpose |
|----------|---------|
| `M.summarize()` | Summarize email buffer |
| `M.extract_todos()` | Extract action items |
| `M.draft_reply()` | Draft a reply |
| `M.tldr()` | TL;DR with urgency/action table |
| `M.compose()` | Compose new email |
| `M.setup(opts)` | Override config programmatically |
| `M._run_ai_custom(prompt, email, title, meta)` | Run arbitrary prompt |
| `M._open_result` | Exposed for testing |

### Internal Functions
| Function | Purpose |
|----------|---------|
| `load_config()` | Load and merge external config |
| `get_backend()` | Get current backend config or error |
| `get_prompts()` | Merge built-in + custom prompts |
| `run_ai(key, title, instructions)` | Core AI runner |
| `run_ai_with_input(key, title)` | Wrapper with optional input |
| `open_result(title, lines, ctx)` | Create result buffer with keybinds |
| `open_info_buffer(title, lines, opts)` | Lighter info display |
| `parse_email_headers(lines)` | Extract From/Subject/Date |
| `persist_config(key, value)` | Write setting to config file |
| `trim_trailing(tbl)` | Clean jobstart output |

## Plugin Specs in himalaya.lua

1. **pimalaya/himalaya-vim** — Email client (lazy: cmd Himalaya)
   - Binary detection, folder picker config, bufwidth patch
   - Key: `<leader>em` → `:Himalaya`

2. **nvim-lualine/lualine.nvim** — Backend indicator
   - Shows `hai.config.backend` in lualine_x
   - Guarded with pcall

## Dependencies

- himalaya CLI v1.x (email)
- claude CLI or gemini CLI (AI backends)
- himalaya-vim plugin (Neovim buffer integration)
- alpha-nvim (dashboard button)
- lualine.nvim (statusbar indicator)
