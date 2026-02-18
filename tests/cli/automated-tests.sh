#!/bin/bash
# Automated Test Suite for: nvim himalaya-improvements
# Generated: 2026-02-18
# Tests Lua syntax, module structure, and nvim headless validation
#
# Usage: bash tests/cli/automated-tests.sh

set -uo pipefail

PASS=0
FAIL=0
SKIP=0
TOTAL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_FILE="$(dirname "$0")/logs/automated-$(date +%Y%m%d-%H%M%S).log"

pass() { ((PASS++)); ((TOTAL++)); echo -e "  ${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"; }
fail() { ((FAIL++)); ((TOTAL++)); echo -e "  ${RED}✗${NC} $1" | tee -a "$LOG_FILE"; echo "    $2" | tee -a "$LOG_FILE"; }
skip() { ((SKIP++)); ((TOTAL++)); echo -e "  ${YELLOW}○${NC} $1 (skipped: $2)" | tee -a "$LOG_FILE"; }
section() { echo -e "\n${BOLD}── $1 ──${NC}" | tee -a "$LOG_FILE"; }

echo "Automated Tests: nvim himalaya-improvements" | tee "$LOG_FILE"
echo "Project: $PROJECT_ROOT" | tee -a "$LOG_FILE"
echo "Date: $(date)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# ── 1. Lua Syntax Validation ──
section "Lua Syntax Validation"

for f in "$PROJECT_ROOT"/lua/himalaya-ai.lua \
         "$PROJECT_ROOT"/lua/config/keymaps.lua \
         "$PROJECT_ROOT"/lua/plugins/himalaya.lua \
         "$PROJECT_ROOT"/lua/plugins/dashboard.lua; do
  name="$(basename "$f")"
  if [[ ! -f "$f" ]]; then
    fail "$name exists" "File not found: $f"
    continue
  fi
  if luajit -bl "$f" /dev/null 2>/dev/null; then
    pass "$name — valid Lua syntax"
  else
    err=$(luajit -bl "$f" /dev/null 2>&1)
    fail "$name — valid Lua syntax" "$err"
  fi
done

# ── 2. Luacheck Static Analysis ──
section "Luacheck Static Analysis"

if command -v luacheck &>/dev/null; then
  for f in "$PROJECT_ROOT"/lua/himalaya-ai.lua \
           "$PROJECT_ROOT"/lua/config/keymaps.lua \
           "$PROJECT_ROOT"/lua/plugins/himalaya.lua \
           "$PROJECT_ROOT"/lua/plugins/dashboard.lua; do
    name="$(basename "$f")"
    # Allow vim/Snacks globals, ignore line length
    result=$(luacheck "$f" --globals vim Snacks --no-max-line-length --no-unused-args 2>&1)
    if [[ $? -eq 0 ]]; then
      pass "$name — luacheck clean"
    else
      warnings=$(echo "$result" | grep -c "warning" || true)
      errors=$(echo "$result" | grep -c "error" || true)
      if [[ $errors -gt 0 ]]; then
        fail "$name — luacheck" "$errors error(s)"
      else
        pass "$name — luacheck ($warnings warnings, 0 errors)"
      fi
    fi
  done
else
  skip "luacheck analysis" "luacheck not installed"
fi

# ── 3. Module Structure Checks ──
section "Module Structure (himalaya-ai.lua)"

HAI="$PROJECT_ROOT/lua/himalaya-ai.lua"

if grep -q 'local M = {}' "$HAI"; then
  pass "Module table M defined"
else
  fail "Module table M defined" "Missing 'local M = {}'"
fi

if grep -q 'return M' "$HAI"; then
  pass "Module returns M"
else
  fail "Module returns M" "Missing 'return M'"
fi

for func in summarize extract_todos draft_reply tldr compose setup _run_ai_custom _open_result; do
  if grep -q "function M\.$func" "$HAI" || grep -q "M\.$func = " "$HAI"; then
    pass "M.$func exposed"
  else
    fail "M.$func exposed" "Function not found on module"
  fi
done

# ── 4. extra_args Support ──
section "extra_args Implementation"

# Count how many jobstart calls use the new cmd-building pattern
cmd_build_count=$(grep -c 'local cmd = { backend.cmd }' "$HAI" || true)
if [[ $cmd_build_count -eq 2 ]]; then
  pass "Both jobstart sites use cmd-building pattern (found $cmd_build_count)"
else
  fail "Both jobstart sites use cmd-building pattern" "Expected 2, found $cmd_build_count"
fi

if grep -q 'backend.extra_args' "$HAI"; then
  pass "extra_args field referenced"
else
  fail "extra_args field referenced" "No reference to backend.extra_args"
fi

# Ensure no old-style inline jobstart remains for AI calls
old_style=$(grep -c "jobstart({ backend.cmd, backend.flag" "$HAI" || true)
if [[ $old_style -eq 0 ]]; then
  pass "No old-style inline jobstart for AI backends"
else
  fail "No old-style inline jobstart for AI backends" "Found $old_style old-style call(s)"
fi

# ── 5. Keybind Definitions ──
section "Keybind Definitions"

KEYMAPS="$PROJECT_ROOT/lua/config/keymaps.lua"
DASHBOARD="$PROJECT_ROOT/lua/plugins/dashboard.lua"

for binding in '<leader>ms' '<leader>mt' '<leader>mr' '<leader>mc' '<leader>mw' '<leader>mp' '<leader>mi' '<leader>mB'; do
  if grep -qF "$binding" "$KEYMAPS"; then
    pass "$binding defined in keymaps.lua"
  else
    fail "$binding defined in keymaps.lua" "Not found"
  fi
done

if grep -qF '<leader>em' "$DASHBOARD"; then
  pass "<leader>em defined in dashboard.lua"
else
  fail "<leader>em defined in dashboard.lua" "Not found"
fi

if grep -qF '<leader>eM' "$PROJECT_ROOT/lua/plugins/himalaya.lua"; then
  pass "<leader>eM defined in himalaya.lua"
else
  fail "<leader>eM defined in himalaya.lua" "Not found"
fi

# ── 6. Plugin Spec Structure ──
section "Plugin Spec Structure"

HIMALAYA_PLUGIN="$PROJECT_ROOT/lua/plugins/himalaya.lua"

if grep -q 'pimalaya/himalaya-vim' "$HIMALAYA_PLUGIN"; then
  pass "himalaya-vim plugin spec present"
else
  fail "himalaya-vim plugin spec present" "Not found"
fi

if grep -q 'nvim-lualine/lualine.nvim' "$HIMALAYA_PLUGIN"; then
  pass "lualine plugin spec present"
else
  fail "lualine plugin spec present" "Not found"
fi

if grep -q 'lualine_x' "$HIMALAYA_PLUGIN"; then
  pass "lualine_x component configured"
else
  fail "lualine_x component configured" "Not found"
fi

if grep -q 'pcall(require, "himalaya-ai")' "$HIMALAYA_PLUGIN"; then
  pass "Lualine uses defensive pcall"
else
  fail "Lualine uses defensive pcall" "Missing pcall guard"
fi

# ── 7. Dashboard + Snacks ──
section "Dashboard + Snacks Floating Terminal"

if grep -q 'folke/snacks.nvim' "$DASHBOARD"; then
  pass "Snacks plugin spec present"
else
  fail "Snacks plugin spec present" "Not found"
fi

if grep -q 'Snacks.terminal.toggle' "$DASHBOARD"; then
  pass "Snacks.terminal.toggle used"
else
  fail "Snacks.terminal.toggle used" "Not found"
fi

snacks_toggle_count=$(grep -c 'Snacks.terminal.toggle' "$DASHBOARD" || true)
if [[ $snacks_toggle_count -eq 2 ]]; then
  pass "Both dashboard button and keybind use Snacks.terminal.toggle"
else
  fail "Both entry points use Snacks.terminal.toggle" "Expected 2, found $snacks_toggle_count"
fi

if grep -q 'style = "himalaya"' "$DASHBOARD"; then
  pass "Custom himalaya Snacks style defined"
else
  fail "Custom himalaya Snacks style defined" "Not found"
fi

if grep -q 'width = 0.85' "$DASHBOARD" && grep -q 'height = 0.85' "$DASHBOARD"; then
  pass "Floating window size is 85%"
else
  fail "Floating window size is 85%" "Expected width/height 0.85"
fi

# ── 8. Neovim Headless Load Test ──
section "Neovim Headless Load Test"

if command -v nvim &>/dev/null; then
  # Test that himalaya-ai.lua loads without errors in headless nvim
  load_result=$(nvim --headless --noplugin \
    -c "lua local ok, err = pcall(dofile, '$HAI'); if ok then print('LOAD_OK') else print('LOAD_FAIL: ' .. tostring(err)) end" \
    -c "qa!" 2>&1)
  if echo "$load_result" | grep -q "LOAD_OK"; then
    pass "himalaya-ai.lua loads in headless nvim"
  else
    fail "himalaya-ai.lua loads in headless nvim" "$load_result"
  fi
else
  skip "headless nvim load test" "nvim not found"
fi

# ── 9. External Config ──
section "External Config"

AI_CONFIG="$HOME/.config/himalaya-ai/config.lua"

if [[ -f "$AI_CONFIG" ]]; then
  pass "himalaya-ai config.lua exists"
else
  fail "himalaya-ai config.lua exists" "Not found at $AI_CONFIG"
fi

if grep -q 'extra_args' "$AI_CONFIG"; then
  pass "extra_args configured in config.lua"
else
  fail "extra_args configured in config.lua" "No extra_args found"
fi

if grep -q 'gemini' "$AI_CONFIG"; then
  pass "Gemini backend defined in config"
else
  fail "Gemini backend defined in config" "Not found"
fi

if grep -q 'claude' "$AI_CONFIG"; then
  pass "Claude backend defined in config"
else
  fail "Claude backend defined in config" "Not found"
fi

# ── 10. CLI Backend Smoke Test ──
section "CLI Backend Smoke Test"

if command -v /opt/homebrew/bin/gemini &>/dev/null; then
  gemini_stdout=$(echo "hello" | timeout 15 /opt/homebrew/bin/gemini -e none -p "Reply with just the word OK" 2>/dev/null)
  gemini_exit=$?
  if [[ $gemini_exit -eq 0 ]] && [[ -n "$gemini_stdout" ]]; then
    pass "Gemini CLI responds with -e none flag"
  else
    fail "Gemini CLI responds with -e none flag" "exit=$gemini_exit stdout='$gemini_stdout'"
  fi
else
  skip "Gemini CLI smoke test" "gemini not found"
fi

if command -v /Users/dt/.local/bin/claude &>/dev/null; then
  pass "Claude CLI binary exists"
else
  skip "Claude CLI binary check" "claude not found at expected path"
fi

# ── Summary ──
echo ""
echo -e "${BOLD}════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
echo -e "${BOLD}  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$SKIP skipped${NC} / $TOTAL total${NC}" | tee -a "$LOG_FILE"
echo -e "${BOLD}════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
echo "Log: $LOG_FILE"

[[ $FAIL -eq 0 ]]
