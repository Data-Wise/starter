-- himalaya.lua — Himalaya email client integration for Neovim
-- Plugin: pimalaya/himalaya-vim (VimScript + Lua pickers)
-- Requires: himalaya CLI v1.x configured with ~/.config/himalaya/config.toml

return {
  {
    "pimalaya/himalaya-vim",

    -- Lazy-load: only when the user invokes the command
    cmd = { "Himalaya" },

    init = function()
      -- Find himalaya binary (check both homebrew and cargo paths)
      local paths = {
        "/opt/homebrew/bin/himalaya",
        vim.fn.expand("~/.cargo/bin/himalaya"),
        "himalaya", -- fallback to PATH
      }
      for _, p in ipairs(paths) do
        if vim.fn.executable(p) == 1 then
          vim.g.himalaya_executable = p
          break
        end
      end

      vim.g.himalaya_folder_picker = "native"
      vim.g.himalaya_always_confirm = 1

      -- Patch s:bufwidth() to subtract 2 columns for UTF-8 safety margin.
      -- Prevents comfy-table crash when truncating multi-byte chars at exact width.
      -- Idempotent: only patches if the original unpatched line is found.
      local email_vim = vim.fn.stdpath("data")
        .. "/lazy/himalaya-vim/autoload/himalaya/domain/email.vim"
      if vim.fn.filereadable(email_vim) == 1 then
        local lines = vim.fn.readfile(email_vim)
        for i, line in ipairs(lines) do
          if line:find("return width - numwidth - foldwidth - signwidth", 1, true)
            and not line:find("- 2", 1, true) then
            lines[i] = "  return max([40, width - numwidth - foldwidth - signwidth - 2])"
            vim.fn.writefile(lines, email_vim)
            break
          end
        end
      end
    end,

    config = function()
      -- No-op: himalaya-vim sets up its own commands via plugin/*.vim
      -- init() already configured g: variables before plugin load
    end,

    keys = {
      {
        "<leader>eM",
        function()
          local ok, err = pcall(vim.cmd, "Himalaya")
          if not ok then
            local msg = "himalaya-vim error:\n" .. tostring(err)
            vim.fn.setreg("+", msg)
            vim.notify(msg .. "\n\n(copied to clipboard)", vim.log.levels.ERROR)
          end
        end,
        desc = "Open Himalaya (Email)",
      },
    },
  },
}
