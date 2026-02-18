# Himalaya AI — Quick Reference

## Email Navigation
| Key | Action |
|-----|--------|
| `<leader>em` | Open Himalaya email list |

## AI Actions (from email buffer)
| Key | Action | Asks for input? |
|-----|--------|-----------------|
| `<leader>ms` | Summarize email | No (configurable) |
| `<leader>mt` | Extract action items | No (configurable) |
| `<leader>mr` | Draft reply | Yes |
| `<leader>mc` | TL;DR + decision | No (configurable) |
| `<leader>mw` | Compose new email | Yes |
| `<leader>mp` | Prompt picker | — |
| `<leader>mi` | Status info | — |
| `<leader>mB` | Toggle backend (claude/gemini) | — |

## Result Buffer Keys
| Key | Action |
|-----|--------|
| `y` | Copy to clipboard |
| `s` | Save to file |
| `f` | Toggle fullscreen |
| `q`/`Esc` | Close |
| `p` | Paste into reply |
| `o` | Send to Obsidian |
| `r` | Re-run (edit prompt) |
| `a` | Append to file |
| `e` | Toggle editable |
| `c` | Revise with instruction |
| `n` | Chain next AI action |
| `t` | Send to todo |

## Commands
| Command | Action |
|---------|--------|
| `:HimalayaAi status` | Show config and backend info |
| `:HimalayaAi prompts` | Browse/validate prompts |
| `:HimalayaAi edit` | Edit config.lua |
| `:HimalayaAi validate [name]` | Test prompt with sample email |
| `:HimalayaAi set <key> <val>` | Change setting (persisted) |

## Settings (`:HimalayaAi set`)
| Key | Values | Default |
|-----|--------|---------|
| `backend` | claude, gemini | claude |
| `result_display` | split, tab | split |
| `format` | structured, simple | structured |
| `todo_target` | obsidian, reminders, ask | ask |
| `vault` | path | ~/...Knowledge_Base |
| `save_dir` | path | ~ |

## Config File
`~/.config/himalaya-ai/config.lua`

## Lualine
Shows active AI backend with 󰇮 icon in statusbar.
