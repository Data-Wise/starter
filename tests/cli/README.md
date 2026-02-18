# Himalaya Improvements — Test Suites

## Automated Tests (CI-ready)

```bash
bash tests/cli/automated-tests.sh
```

Validates: Lua syntax, luacheck, module structure, extra_args implementation, keybind definitions, plugin spec structure, Snacks config, headless nvim load, external config, CLI backend smoke test.

**Exit code:** 0 if all pass, 1 if any fail.

## Interactive Tests (Dogfooding)

```bash
bash tests/cli/interactive-tests.sh
```

14 human-guided QA tests covering:
- Floating terminal open/close/toggle
- Dashboard button behavior
- Backend toggle + lualine indicator
- AI actions with Claude and Gemini
- Edge cases (keybind conflicts, cold start)

**Keys:** y=pass, n=fail, s=skip, q=quit

## Logs

Both suites write timestamped logs to `tests/cli/logs/`.
