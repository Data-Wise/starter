-- himalaya-ai.lua: AI-powered email actions for himalaya-vim
-- Result opens in split/tab with keybinds:
--   y=copy  s=save  f=fullscreen  q/Esc=close
--   p=paste into reply  o=obsidian  r=re-run  a=append
--   e=edit  c=revise  n=next action  t=send to todo
local M = {}

-- Defaults (overridden by ~/.config/himalaya-ai/config.lua)
local defaults = {
  backend = "claude",
  backends = {
    claude = { cmd = "/Users/dt/.local/bin/claude", flag = "-p" },
    gemini = { cmd = "/opt/homebrew/bin/gemini", flag = "-p" },
  },
  obsidian = {
    vault = "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Knowledge_Base",
    subfolder = "Inbox",
    format = "structured",
  },
  save_dir = "~",
  result_display = "split", -- "split" (bottom horizontal) or "tab" (new tab)
  todo_target = "ask", -- "obsidian" | "reminders" | "ask"
  ask_before = {
    draft_reply = true,
    compose = true,
    summarize = false,
    extract_todos = false,
    tldr = false,
  },
}

-- Per-action input hints shown in vim.ui.input
local input_hints = {
  draft_reply = "Reply instructions (Enter=default): ",
  compose = "What to write about: ",
  summarize = "Focus on (Enter=general): ",
  extract_todos = "Filter (Enter=all): ",
  tldr = "Context (Enter=default): ",
}

-- Load external config with fallback
local function load_config()
  local path = vim.fn.expand("~/.config/himalaya-ai/config.lua")
  local ok, ext = pcall(dofile, path)
  if ok and type(ext) == "table" then
    return vim.tbl_deep_extend("force", defaults, ext)
  end
  return vim.deepcopy(defaults)
end

M.config = load_config()

local prompts = {
  summarize = "Summarize this email in 2-3 concise bullet points."
    .. " Format your response as markdown with bullet points (- ).",
  extract_todos = "Extract all action items from this email as a markdown"
    .. " checklist using - [ ] syntax. Group by priority if there are more than 3 items.",
  draft_reply = "Draft a professional reply to this email. Be concise and friendly."
    .. " Format as markdown — use **bold** for key points"
    .. " and > blockquotes for any text you're referencing from the original.",
  tldr = table.concat({
    "You are an executive assistant triaging email."
      .. " Analyze this email and respond in EXACTLY this markdown format (no extra text):",
    "",
    "**TL;DR:** <one sentence, max 15 words>",
    "",
    "| Field | Value |",
    "| --- | --- |",
    "| **Urgency** | 🔴 urgent / 🟡 this week / 🟢 no rush |",
    "| **Action** | <what I need to do — or \"None\"> |",
    "| **Deadline** | <specific date/time if mentioned, else \"None\"> |",
    "| **Reply needed** | Yes / No |",
    "",
    "**Key details:**",
    "- <1-2 bullet points only if critical context would be lost without them>",
  }, "\n"),
}

-- Extract email metadata from buffer lines (best-effort parsing)
local function parse_email_headers(lines)
  local meta = { from = "", subject = "", date = "" }
  for _, line in ipairs(lines) do
    if line == "" then break end -- headers end at first blank line
    local k, v = line:match("^(%S+):%s*(.+)")
    if k then
      k = k:lower()
      if k == "from" then meta.from = v
      elseif k == "subject" then meta.subject = v
      elseif k == "date" then meta.date = v
      end
    end
  end
  return meta
end

-- Create structured Obsidian note content
local function make_obsidian_note(meta, ai_text, title)
  local date_str = meta.date ~= "" and meta.date or os.date("%Y-%m-%d")
  local subject = meta.subject ~= "" and meta.subject or title
  local lines = {
    "---",
    "type: email",
    "from: " .. meta.from,
    "date: " .. date_str,
    "subject: " .. subject,
    "tags: [email, ai-summary]",
    "---",
    "",
    "# " .. subject,
    "",
    "## AI Summary",
    "",
  }
  for _, l in ipairs(vim.split(ai_text, "\n")) do
    lines[#lines + 1] = l
  end
  return table.concat(lines, "\n")
end

-- Trim trailing empty strings from jobstart output (Neovim always appends one)
local function trim_trailing(tbl)
  while #tbl > 0 and tbl[#tbl] == "" do
    tbl[#tbl] = nil
  end
  return tbl
end

local function get_backend()
  local b = M.config.backends[M.config.backend]
  if not b then
    vim.notify("himalaya-ai: unknown backend '" .. M.config.backend .. "'", vim.log.levels.ERROR)
    return nil
  end
  return b
end

-- Merge custom prompts from config over built-in defaults
local function get_prompts()
  return vim.tbl_deep_extend("force", prompts, M.config.prompts or {})
end

-- Built-in sample email for validate fallback
local sample_email = table.concat({
  "From: Sarah Chen <sarah@example.edu>",
  "Subject: Re: Data science hiring — feedback needed by Friday",
  "Date: Tue, 11 Feb 2026 09:42:00 -0700",
  "",
  "Hi,",
  "",
  "Following up on our meeting about the data science position.",
  "The committee reviewed three candidates and needs our ranking.",
  "Could you review the materials and send me your top pick with",
  "a brief justification by Friday COB?",
  "",
  "Budget approved at $95-105k. Shared drive link below.",
  "",
  "Thanks,",
  "Sarah",
  "",
  "P.S. Department retreat confirmed for March 15 — can you check",
  "if the stats lab is available?",
}, "\n")

-- Persist a config value to config.lua (pattern matching preserves comments)
local function persist_config(key, value)
  local config_path = vim.fn.expand("~/.config/himalaya-ai/config.lua")
  local file = io.open(config_path, "r")
  if not file then return false, "Config file not found" end
  local content = file:read("*a")
  file:close()

  local old = content
  local parent, child = key:match("^([%w_]+)%.([%w_]+)$")
  local safe = value:gsub("%%", "%%%%")

  if parent and child then
    content = content:gsub("(" .. parent .. "%s*=%s*)(%b{})", function(pfx, block)
      return pfx .. block:gsub(
        "(" .. child .. "%s*=%s*)\"([^\"]-)\"",
        "%1\"" .. safe .. "\""
      )
    end)
  else
    content = content:gsub(
      "(" .. key .. "%s*=%s*)\"([^\"]-)\"",
      "%1\"" .. safe .. "\""
    )
  end

  if content == old then
    -- Check if key exists with the same value (no-op is success, not error)
    local pat = parent and (child .. "%s*=%s*\"" .. safe .. "\"")
                        or (key .. "%s*=%s*\"" .. safe .. "\"")
    if old:match(pat) then return true end
    return false, "Key '" .. key .. "' not found in config"
  end

  file = io.open(config_path, "w")
  if not file then return false, "Cannot write config file" end
  file:write(content)
  file:close()
  return true
end

-- Open a new buffer in configured display mode (split or tab)
local function open_display_buffer()
  if M.config.result_display == "tab" then
    vim.cmd("tabnew")
  else
    vim.cmd("botright new")
  end
end

-- Info buffer for status/prompts (lighter than open_result)
local function open_info_buffer(title, lines, opts)
  opts = opts or {}
  open_display_buffer()
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  pcall(vim.api.nvim_buf_set_name, buf, title .. " " .. os.date("%H:%M:%S"))
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].conceallevel = 2
  vim.bo[buf].filetype = "markdown"
  pcall(vim.api.nvim_exec_autocmds, "FileType", { buffer = buf, pattern = "markdown" })
  vim.bo[buf].modifiable = false

  for _, k in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", k, "<cmd>close<CR>", { buffer = buf, nowait = true })
  end
  if opts.keybinds then
    for k, fn in pairs(opts.keybinds) do
      vim.keymap.set("n", k, fn, { buffer = buf, nowait = true })
    end
  end
  vim.wo[win].statusline = opts.statusline or (" " .. title .. " %=q=close ")
end

-- :HimalayaAi edit — open config.lua in vsplit with auto-reload
local function cmd_edit()
  local config_path = vim.fn.expand("~/.config/himalaya-ai/config.lua")
  if vim.fn.filereadable(config_path) == 0 then
    vim.fn.mkdir(vim.fn.fnamemodify(config_path, ":h"), "p")
    local f = io.open(config_path, "w")
    if f then
      f:write("return {\n  backend = \"claude\",\n}\n")
      f:close()
    end
  end
  vim.cmd("vsplit " .. vim.fn.fnameescape(config_path))
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_create_autocmd("BufWritePost", {
    buffer = buf,
    callback = function()
      M.config = load_config()
      vim.notify("himalaya-ai: Config reloaded", vim.log.levels.INFO)
    end,
  })
end

-- :HimalayaAi set <key> <value>
local function cmd_set(key, value)
  if not key or key == "" then
    vim.notify("Usage: :HimalayaAi set <key> <value>", vim.log.levels.WARN)
    return
  end
  if not value or value == "" then
    vim.notify("Usage: :HimalayaAi set " .. key .. " <value>", vim.log.levels.WARN)
    return
  end

  if key == "backend" then
    local b = M.config.backends[value]
    if not b then
      vim.notify("Unknown backend: " .. value .. " (available: " ..
        table.concat(vim.tbl_keys(M.config.backends), ", ") .. ")", vim.log.levels.ERROR)
      return
    end
    if vim.fn.executable(b.cmd) ~= 1 then
      vim.notify(value .. " not found at " .. b.cmd, vim.log.levels.ERROR)
      return
    end
    M.config.backend = value
    local ok, err = persist_config("backend", value)
    vim.notify("Backend → " .. value .. (ok and " (persisted)" or " (memory only: " .. (err or "") .. ")"),
      vim.log.levels.INFO)

  elseif key == "vault" then
    local expanded = vim.fn.expand(value)
    if vim.fn.isdirectory(expanded) ~= 1 then
      vim.notify("Directory not found: " .. expanded, vim.log.levels.ERROR)
      return
    end
    M.config.obsidian.vault = value
    local ok, err = persist_config("obsidian.vault", value)
    vim.notify("Vault → " .. value .. (ok and " (persisted)" or " (memory only: " .. (err or "") .. ")"),
      vim.log.levels.INFO)

  elseif key == "save_dir" then
    local expanded = vim.fn.expand(value)
    if vim.fn.isdirectory(expanded) ~= 1 then
      vim.notify("Directory not found: " .. expanded, vim.log.levels.ERROR)
      return
    end
    M.config.save_dir = value
    local ok, err = persist_config("save_dir", value)
    vim.notify("Save dir → " .. value .. (ok and " (persisted)" or " (memory only: " .. (err or "") .. ")"),
      vim.log.levels.INFO)

  elseif key == "format" then
    if value ~= "structured" and value ~= "simple" then
      vim.notify("Format must be 'structured' or 'simple'", vim.log.levels.ERROR)
      return
    end
    M.config.obsidian.format = value
    local ok, err = persist_config("obsidian.format", value)
    vim.notify("Format → " .. value .. (ok and " (persisted)" or " (memory only: " .. (err or "") .. ")"),
      vim.log.levels.INFO)

  elseif key == "result_display" then
    if value ~= "split" and value ~= "tab" then
      vim.notify("Result display must be 'split' or 'tab'", vim.log.levels.ERROR)
      return
    end
    M.config.result_display = value
    local ok, err = persist_config("result_display", value)
    vim.notify("Result display → " .. value .. (ok and " (persisted)" or " (memory only: " .. (err or "") .. ")"),
      vim.log.levels.INFO)

  elseif key == "todo_target" then
    if value ~= "obsidian" and value ~= "reminders" and value ~= "ask" then
      vim.notify("Todo target must be 'obsidian', 'reminders', or 'ask'", vim.log.levels.ERROR)
      return
    end
    M.config.todo_target = value
    local ok, err = persist_config("todo_target", value)
    vim.notify("Todo target → " .. value .. (ok and " (persisted)" or " (memory only: " .. (err or "") .. ")"),
      vim.log.levels.INFO)

  else
    vim.notify("Unknown setting: " .. key .. " (try: backend, vault, save_dir, format, result_display, todo_target)",
      vim.log.levels.ERROR)
  end
end

-- :HimalayaAi validate [prompt_name]
local function cmd_validate(prompt_name)
  local all_prompts = get_prompts()

  local function run_validate(name)
    local prompt_text = all_prompts[name]
    if not prompt_text then
      vim.notify("Unknown prompt: " .. name, vim.log.levels.ERROR)
      return
    end
    local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local email_text, source = nil, "sample"
    for i = 1, math.min(5, #buf_lines) do
      if buf_lines[i]:match("^From:") or buf_lines[i]:match("^Subject:") then
        email_text = table.concat(buf_lines, "\n")
        source = "buffer"
        break
      end
    end
    email_text = email_text or sample_email
    local meta = parse_email_headers(vim.split(email_text, "\n"))
    vim.notify("Validating '" .. name .. "' against " .. source .. " email...", vim.log.levels.INFO)
    M._run_ai_custom(prompt_text, email_text, "Validate: " .. name, meta)
  end

  if prompt_name then
    run_validate(prompt_name)
  else
    local names = vim.tbl_keys(all_prompts)
    table.sort(names)
    vim.ui.select(names, { prompt = "Validate which prompt?" }, function(choice)
      if choice then run_validate(choice) end
    end)
  end
end

-- :HimalayaAi status
local function cmd_status()
  local cfg = M.config
  local b = cfg.backends[cfg.backend] or {}
  local binary_ok = b.cmd and vim.fn.executable(b.cmd) == 1
  local config_path = vim.fn.expand("~/.config/himalaya-ai/config.lua")
  local config_exists = vim.fn.filereadable(config_path) == 1
  local all_prompts = get_prompts()

  local lines = {
    "HimalayaAi Status",
    "==================",
    "Backend:     " .. cfg.backend .. " (" .. (b.cmd or "?") .. ") " ..
      (binary_ok and "[OK]" or "[MISSING]"),
    "Vault:       " .. vim.fn.expand(cfg.obsidian.vault) .. "/" .. cfg.obsidian.subfolder,
    "Save dir:    " .. cfg.save_dir,
    "Note format: " .. cfg.obsidian.format,
    "Display:     " .. (cfg.result_display or "split"),
    "Config:      " .. config_path .. " " .. (config_exists and "[loaded]" or "[using defaults]"),
    "",
  }

  local names = vim.tbl_keys(all_prompts)
  table.sort(names)
  lines[#lines + 1] = "Prompts (" .. #names .. "):"
  for _, name in ipairs(names) do
    local preview = all_prompts[name]:sub(1, 40):gsub("\n", " ")
    lines[#lines + 1] = string.format("  %-14s %s...", name, preview)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "[q] close"

  open_info_buffer("HimalayaAi Status", lines)
end

-- :HimalayaAi prompts (interactive buffer)
local function cmd_prompts()
  local all_prompts = get_prompts()
  local names = vim.tbl_keys(all_prompts)
  table.sort(names)

  local lines = {
    "HimalayaAi Prompts",
    "====================",
  }
  for _, name in ipairs(names) do
    local preview = all_prompts[name]:sub(1, 40):gsub("\n", " ")
    lines[#lines + 1] = string.format("  %-14s %s...", name, preview)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "[e] edit config   [v] validate   [q] close"

  open_info_buffer("HimalayaAi Prompts", lines, {
    keybinds = {
      e = function() vim.cmd("close") cmd_edit() end,
      v = function()
        vim.cmd("close")
        vim.ui.select(names, { prompt = "Validate which prompt?" }, function(choice)
          if choice then cmd_validate(choice) end
        end)
      end,
    },
    statusline = " HimalayaAi Prompts %=e=edit  v=validate  q=close ",
  })
end

-- Exposed as M._open_result for headless testing
local function open_result(title, lines, ctx)
  ctx = ctx or {}
  open_display_buffer()
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  -- Unique buffer name to avoid conflicts on repeated runs
  pcall(vim.api.nvim_buf_set_name, buf, title .. " " .. os.date("%H:%M:%S"))
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].conceallevel = 2

  -- Set filetype to markdown for syntax highlighting + render-markdown.nvim
  vim.bo[buf].filetype = "markdown"
  -- Re-fire FileType so render-markdown.nvim attaches to this nofile buffer
  pcall(vim.api.nvim_exec_autocmds, "FileType", { buffer = buf, pattern = "markdown" })

  vim.bo[buf].modifiable = false

  local is_fullscreen = false

  -- Helper: read current buffer text (picks up edits after 'e' toggle)
  local function get_buf_text()
    return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  end

  -- Close: q / Esc
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, "<cmd>close<CR>", { buffer = buf, nowait = true })
  end

  -- y: Copy to clipboard
  vim.keymap.set("n", "y", function()
    vim.fn.setreg("+", get_buf_text())
    vim.notify("Copied to clipboard", vim.log.levels.INFO)
  end, { buffer = buf, nowait = true })

  -- s: Save to file
  vim.keymap.set("n", "s", function()
    local default_dir = vim.fn.expand(M.config.save_dir)
    local default_path = default_dir .. "/ai-email-" .. os.date("%Y%m%d-%H%M") .. ".md"
    vim.ui.input({ prompt = "Save to: ", default = default_path }, function(path)
      if not path or path == "" then return end
      path = vim.fn.expand(path)
      local f = io.open(path, "w")
      if f then
        f:write("# " .. title .. "\n\n" .. get_buf_text() .. "\n")
        f:close()
        vim.notify("Saved to " .. path, vim.log.levels.INFO)
      else
        vim.notify("Failed to write " .. path, vim.log.levels.ERROR)
      end
    end)
  end, { buffer = buf, nowait = true })

  -- f: Toggle fullscreen
  vim.keymap.set("n", "f", function()
    if is_fullscreen then
      vim.cmd("wincmd =")
      is_fullscreen = false
    else
      vim.cmd("wincmd |")
      vim.cmd("wincmd _")
      is_fullscreen = true
    end
  end, { buffer = buf, nowait = true })

  -- a: Append to file
  vim.keymap.set("n", "a", function()
    vim.ui.input({ prompt = "Append to: ", completion = "file" }, function(path)
      if not path or path == "" then return end
      path = vim.fn.expand(path)
      local f = io.open(path, "a")
      if f then
        f:write("\n## " .. title .. " (" .. os.date("%Y-%m-%d %H:%M") .. ")\n\n" .. get_buf_text() .. "\n")
        f:close()
        vim.notify("Appended to " .. path, vim.log.levels.INFO)
      else
        vim.notify("Failed to append to " .. path, vim.log.levels.ERROR)
      end
    end)
  end, { buffer = buf, nowait = true })

  -- o: Send to Obsidian
  vim.keymap.set("n", "o", function()
    local cfg = M.config.obsidian
    local vault = vim.fn.expand(cfg.vault)
    local dir = vault .. "/" .. cfg.subfolder
    -- Ensure directory exists
    vim.fn.mkdir(dir, "p")

    local meta = ctx.email_meta or { from = "", subject = "", date = "" }
    local slug = (meta.subject ~= "" and meta.subject or title)
      :gsub("[^%w%s%-]", ""):gsub("%s+", "-"):sub(1, 50):lower()
    local filename = dir .. "/" .. os.date("%Y%m%d") .. "-" .. slug .. ".md"

    local current = get_buf_text()
    local content
    if cfg.format == "structured" then
      content = make_obsidian_note(meta, current, title)
    else
      content = "# " .. title .. "\n\n" .. current .. "\n"
    end

    local f = io.open(filename, "w")
    if f then
      f:write(content)
      f:close()
      vim.notify("Obsidian note: " .. filename, vim.log.levels.INFO)
    else
      vim.notify("Failed to write Obsidian note", vim.log.levels.ERROR)
    end
  end, { buffer = buf, nowait = true })

  -- r: Re-run with edited prompt
  if ctx.prompt_text and ctx.email_text then
    vim.keymap.set("n", "r", function()
      vim.ui.input({ prompt = "Edit prompt: ", default = ctx.prompt_text }, function(new_prompt)
        if not new_prompt or new_prompt == "" then return end
        -- Close current result split
        vim.cmd("close")
        -- Re-run with custom prompt
        M._run_ai_custom(new_prompt, ctx.email_text, title, ctx.email_meta)
      end)
    end, { buffer = buf, nowait = true })
  end

  -- p: Paste into reply
  if ctx.source_win and ctx.email_text then
    vim.keymap.set("n", "p", function()
      local current = get_buf_text()
      vim.fn.setreg('"', current)
      vim.fn.setreg("+", current)
      -- Switch to original email window
      if vim.api.nvim_win_is_valid(ctx.source_win) then
        vim.api.nvim_set_current_win(ctx.source_win)
      else
        vim.cmd("wincmd w")
      end
      -- Trigger himalaya reply
      local ok_reply, err = pcall(function()
        vim.cmd("normal gr")
      end)
      if ok_reply then
        -- Wait briefly for compose buffer to open, then paste
        vim.defer_fn(function()
          vim.cmd('normal! Go')
          vim.cmd('normal! "+p')
          vim.notify("AI draft pasted into reply", vim.log.levels.INFO)
        end, 300)
      else
        vim.notify("Reply failed: " .. tostring(err), vim.log.levels.WARN)
      end
    end, { buffer = buf, nowait = true })
  end

  -- e: Toggle editable (edits are picked up by y/s/a/o/p)
  vim.keymap.set("n", "e", function()
    local modifiable = vim.bo[buf].modifiable
    vim.bo[buf].modifiable = not modifiable
    vim.bo[buf].readonly = modifiable
    vim.notify(
      modifiable and "Read-only" or "Editable (edits apply to y/s/a/o/p)",
      vim.log.levels.INFO
    )
  end, { buffer = buf, nowait = true })

  -- c: Revise with instruction
  vim.keymap.set("n", "c", function()
    vim.ui.input({ prompt = "Revise: " }, function(instruction)
      if not instruction or instruction == "" then return end
      local current = get_buf_text()
      local revise_prompt = "Here is a previous AI-generated response:\n\n"
        .. current .. "\n\nRevise this response with the following instruction: "
        .. instruction .. "\n\nReturn only the revised version."
      vim.cmd("close")
      M._run_ai_custom(revise_prompt, ctx.email_text or "", title .. " (revised)", ctx.email_meta)
    end)
  end, { buffer = buf, nowait = true })

  -- n: Next action (chain AI actions)
  vim.keymap.set("n", "n", function()
    local actions = {
      { label = "Summarize", key = "summarize" },
      { label = "Extract Todos", key = "extract_todos" },
      { label = "Draft Reply", key = "draft_reply" },
      { label = "TL;DR", key = "tldr" },
    }
    local labels = {}
    for _, a in ipairs(actions) do labels[#labels + 1] = a.label end

    vim.ui.select(labels, { prompt = "Next AI action:" }, function(choice)
      if not choice then return end
      local key
      for _, a in ipairs(actions) do
        if a.label == choice then key = a.key; break end
      end
      if not key then return end

      vim.ui.select(
        { "Original email", "Current AI result" },
        { prompt = "Use as input:" },
        function(source)
          if not source then return end
          local input = source == "Original email" and ctx.email_text or get_buf_text()
          local p = get_prompts()[key]

          if key == "draft_reply" then
            vim.ui.input({ prompt = "Reply instructions (Enter=default): " }, function(instr)
              if instr == nil then return end
              if instr ~= "" then
                p = p .. "\n\nUser instructions: " .. instr
              end
              vim.cmd("close")
              M._run_ai_custom(p, input, choice, ctx.email_meta)
            end)
          else
            vim.cmd("close")
            M._run_ai_custom(p, input, choice, ctx.email_meta)
          end
        end
      )
    end)
  end, { buffer = buf, nowait = true })

  -- t: Send to todo (Obsidian daily note or macOS Reminders)
  vim.keymap.set("n", "t", function()
    local function send_obsidian(content)
      local cfg = M.config.obsidian
      local vault = vim.fn.expand(cfg.vault)
      local daily = vault .. "/Daily/" .. os.date("%Y-%m-%d") .. ".md"
      vim.fn.mkdir(vim.fn.fnamemodify(daily, ":h"), "p")
      local f = io.open(daily, "a")
      if f then
        f:write("\n## " .. title .. " (" .. os.date("%H:%M") .. ")\n\n" .. content .. "\n")
        f:close()
        vim.notify("Added to daily note: " .. daily, vim.log.levels.INFO)
      else
        vim.notify("Failed to write daily note", vim.log.levels.ERROR)
      end
    end

    local function send_reminders(content)
      local clean_title = title:gsub('"', '\\"'):gsub("'", "'\\''")
      local clean_body = content:gsub('"', '\\"'):gsub("'", "'\\''")
      vim.fn.jobstart({
        "osascript", "-e",
        'tell application "Reminders" to make new reminder with properties '
          .. '{name:"' .. clean_title .. '", body:"' .. clean_body .. '"}'
      }, {
        on_exit = function(_, code)
          vim.schedule(function()
            if code == 0 then
              vim.notify("Added to Reminders", vim.log.levels.INFO)
            else
              vim.notify("Failed to add to Reminders", vim.log.levels.ERROR)
            end
          end)
        end
      })
    end

    vim.ui.select({ "Full text", "Action items only" },
      { prompt = "What to send:" },
      function(format)
        if not format then return end
        local content = get_buf_text()
        if format == "Action items only" then
          local items = {}
          for line in content:gmatch("[^\n]+") do
            if line:match("^%s*[%-*]") or line:match("^%s*%d+[%.)]") then
              table.insert(items, line)
            end
          end
          content = #items > 0 and table.concat(items, "\n") or content
        end

        local target = M.config.todo_target or "ask"
        if target == "obsidian" then send_obsidian(content)
        elseif target == "reminders" then send_reminders(content)
        else
          vim.ui.select({ "Obsidian daily note", "macOS Reminders" },
            { prompt = "Send to:" },
            function(dest)
              if dest == "Obsidian daily note" then send_obsidian(content)
              elseif dest == "macOS Reminders" then send_reminders(content)
              end
            end)
        end
      end)
  end, { buffer = buf, nowait = true })

  -- Statusline with all keybinds
  vim.wo[win].statusline = " " .. title
    .. " %=e=edit  c=revise  n=next  t=todo  y=copy  s=save  o=obsidian  p=reply  r=rerun  q=close "
end

-- Core AI runner (used by named actions)
local function run_ai(prompt_key, title, instructions)
  local backend = get_backend()
  if not backend then return end

  local source_win = vim.api.nvim_get_current_win()
  local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local email = table.concat(buf_lines, "\n")
  if email:match("^%s*$") then
    open_result(title, { "Error: buffer is empty." })
    return
  end

  local meta = parse_email_headers(buf_lines)
  local prompt_text = get_prompts()[prompt_key]

  -- Merge user instructions into prompt
  if instructions and instructions ~= "" then
    prompt_text = prompt_text .. "\n\nUser instructions: " .. instructions
  end

  vim.notify("Running " .. title .. "... (waiting for " .. M.config.backend .. ")", vim.log.levels.INFO)

  local stdout = {}
  local stderr = {}

  local cmd = { backend.cmd }
  if backend.extra_args then
    for _, arg in ipairs(backend.extra_args) do
      cmd[#cmd + 1] = arg
    end
  end
  cmd[#cmd + 1] = backend.flag
  cmd[#cmd + 1] = prompt_text
  local job = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          stdout[#stdout + 1] = line
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then stderr[#stderr + 1] = line end
        end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        local ctx = {
          prompt_text = prompt_text,
          email_text = email,
          email_meta = meta,
          source_win = source_win,
        }
        trim_trailing(stdout)
        if code ~= 0 or #stdout == 0 then
          local err_lines = { M.config.backend .. " exited with code " .. code, "" }
          if #stderr > 0 then
            table.insert(err_lines, "stderr:")
            for _, l in ipairs(stderr) do table.insert(err_lines, "  " .. l) end
          end
          if #stdout > 0 then
            table.insert(err_lines, "")
            table.insert(err_lines, "stdout:")
            for _, l in ipairs(stdout) do table.insert(err_lines, "  " .. l) end
          end
          open_result(title .. " (ERROR)", err_lines, ctx)
        else
          open_result(title, stdout, ctx)
        end
      end)
    end,
  })

  vim.fn.chansend(job, email)
  vim.fn.chanclose(job, "stdin")
end

-- Custom prompt runner (for re-run action)
function M._run_ai_custom(prompt_text, email, title, meta)
  local backend = get_backend()
  if not backend then return end

  local source_win = vim.api.nvim_get_current_win()
  vim.notify("Re-running with custom prompt...", vim.log.levels.INFO)

  local stdout = {}
  local stderr = {}

  local cmd = { backend.cmd }
  if backend.extra_args then
    for _, arg in ipairs(backend.extra_args) do
      cmd[#cmd + 1] = arg
    end
  end
  cmd[#cmd + 1] = backend.flag
  cmd[#cmd + 1] = prompt_text
  local job = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          stdout[#stdout + 1] = line
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then stderr[#stderr + 1] = line end
        end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        local ctx = {
          prompt_text = prompt_text,
          email_text = email,
          email_meta = meta or {},
          source_win = source_win,
        }
        trim_trailing(stdout)
        if code ~= 0 or #stdout == 0 then
          local err_lines = { M.config.backend .. " exited with code " .. code, "" }
          if #stderr > 0 then
            table.insert(err_lines, "stderr:")
            for _, l in ipairs(stderr) do table.insert(err_lines, "  " .. l) end
          end
          open_result(title .. " (ERROR)", err_lines, ctx)
        else
          open_result(title, stdout, ctx)
        end
      end)
    end,
  })

  vim.fn.chansend(job, email)
  vim.fn.chanclose(job, "stdin")
end

-- Wrapper: optionally ask for instructions via vim.ui.input before running AI
local function run_ai_with_input(prompt_key, title)
  local should_ask = M.config.ask_before and M.config.ask_before[prompt_key]
  if should_ask then
    vim.ui.input({ prompt = input_hints[prompt_key] or "Instructions: " }, function(input)
      if input == nil then return end -- Esc cancels
      run_ai(prompt_key, title, input ~= "" and input or nil)
    end)
  else
    run_ai(prompt_key, title)
  end
end

function M.summarize() run_ai_with_input("summarize", "AI Summary") end
function M.extract_todos() run_ai_with_input("extract_todos", "Action Items") end
function M.draft_reply() run_ai_with_input("draft_reply", "Draft Reply") end
function M.tldr() run_ai_with_input("tldr", "TL;DR + Decision") end

function M.compose()
  vim.ui.input({ prompt = input_hints.compose }, function(input)
    if not input or input == "" then
      vim.notify("Compose cancelled", vim.log.levels.WARN)
      return
    end
    local prompt = "Write a professional email about: " .. input
      .. "\nFormat as markdown. Be concise and friendly."
    local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local email = table.concat(buf_lines, "\n")
    local meta = parse_email_headers(buf_lines)
    M._run_ai_custom(prompt, email, "Compose", meta)
  end)
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

-- Register :HimalayaAi command with context-aware tab completion
vim.api.nvim_create_user_command("HimalayaAi", function(opts)
  local subcmd = opts.fargs[1]
  if subcmd == "status" then
    cmd_status()
  elseif subcmd == "prompts" then
    cmd_prompts()
  elseif subcmd == "edit" then
    cmd_edit()
  elseif subcmd == "validate" then
    cmd_validate(opts.fargs[2])
  elseif subcmd == "set" then
    local value_parts = {}
    for i = 3, #opts.fargs do value_parts[#value_parts + 1] = opts.fargs[i] end
    cmd_set(opts.fargs[2], #value_parts > 0 and table.concat(value_parts, " ") or nil)
  else
    vim.notify("Usage: :HimalayaAi {status|prompts|edit|validate|set}", vim.log.levels.WARN)
  end
end, {
  nargs = "*",
  desc = "Himalaya AI: manage prompts and settings",
  complete = function(arg_lead, cmd_line, _)
    local parts = vim.split(cmd_line, "%s+")
    if #parts == 2 then
      return vim.tbl_filter(function(c) return vim.startswith(c, arg_lead) end,
        { "status", "prompts", "edit", "validate", "set" })
    end
    local subcmd = parts[2]
    if subcmd == "validate" and #parts == 3 then
      local names = vim.tbl_keys(get_prompts())
      table.sort(names)
      return vim.tbl_filter(function(n) return vim.startswith(n, arg_lead) end, names)
    end
    if subcmd == "set" and #parts == 3 then
      return vim.tbl_filter(function(k) return vim.startswith(k, arg_lead) end,
        { "backend", "vault", "save_dir", "format", "result_display", "todo_target" })
    end
    if subcmd == "set" and #parts == 4 then
      local key = parts[3]
      if key == "backend" then
        local names = vim.tbl_keys(M.config.backends)
        return vim.tbl_filter(function(b) return vim.startswith(b, arg_lead) end, names)
      elseif key == "format" then
        return vim.tbl_filter(function(f) return vim.startswith(f, arg_lead) end,
          { "structured", "simple" })
      elseif key == "result_display" then
        return vim.tbl_filter(function(d) return vim.startswith(d, arg_lead) end,
          { "split", "tab" })
      elseif key == "todo_target" then
        return vim.tbl_filter(function(t) return vim.startswith(t, arg_lead) end,
          { "obsidian", "reminders", "ask" })
      end
    end
    return {}
  end,
})

M._open_result = open_result

return M
