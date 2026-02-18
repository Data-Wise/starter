#!/bin/bash
# Interactive Dogfooding Test Suite for: nvim himalaya-improvements
# Generated: 2026-02-18
# Human-guided QA — run each test in Neovim and judge pass/fail
#
# Usage: bash tests/cli/interactive-tests.sh

set -uo pipefail

PASS=0
FAIL=0
SKIP=0
TOTAL=14
CURRENT=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

LOG_FILE="$(dirname "$0")/logs/interactive-$(date +%Y%m%d-%H%M%S).log"

echo "Interactive Dogfooding Tests: nvim himalaya-improvements" | tee "$LOG_FILE"
echo "Date: $(date)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo -e "${DIM}For each test: perform the action in Neovim, then judge the result.${NC}"
echo -e "${DIM}Keys: y=pass  n=fail  s=skip  q=quit${NC}"
echo ""

run_test() {
  local name="$1"
  local action="$2"
  local expected="$3"

  ((CURRENT++))

  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}TEST $CURRENT/$TOTAL:${NC} ${BOLD}$name${NC}"
  echo -e "${DIM}Action:${NC}   $action"
  echo -e "${DIM}Expected:${NC} $expected"
  echo ""

  while true; do
    echo -ne "  Result? [${GREEN}y${NC}=pass ${RED}n${NC}=fail ${YELLOW}s${NC}=skip ${DIM}q${NC}=quit]: "
    read -r -n1 key
    echo ""
    case "$key" in
      y|Y) ((PASS++)); echo -e "  ${GREEN}✓ PASS${NC}"; echo "PASS: $name" >> "$LOG_FILE"; break ;;
      n|N) ((FAIL++)); echo -e "  ${RED}✗ FAIL${NC}"
           echo -ne "  Notes (optional): "; read -r notes
           echo "FAIL: $name — $notes" >> "$LOG_FILE"; break ;;
      s|S) ((SKIP++)); echo -e "  ${YELLOW}○ SKIP${NC}"; echo "SKIP: $name" >> "$LOG_FILE"; break ;;
      q|Q) echo -e "\n${YELLOW}Aborted at test $CURRENT/$TOTAL${NC}"; print_summary; exit 0 ;;
      *)   echo -e "  ${DIM}Invalid key. Use y/n/s/q${NC}" ;;
    esac
  done
  echo ""
}

print_summary() {
  echo "" | tee -a "$LOG_FILE"
  echo -e "${BOLD}════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
  echo -e "${BOLD}  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$SKIP skipped${NC} / $TOTAL total${NC}" | tee -a "$LOG_FILE"
  echo -e "${BOLD}════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
  echo "Log: $LOG_FILE"
}

# ── Floating Terminal Tests ──

echo -e "\n${BOLD}── Floating Terminal ──${NC}\n"

run_test "Floating terminal opens" \
  "Press <leader>em in normal mode" \
  "An 85% floating window opens with himalaya TUI inside, rounded border, ' Email ' title centered"

run_test "Floating terminal toggles" \
  "Press <leader>em again while the float is open" \
  "The floating window closes cleanly, no orphaned buffers"

run_test "Floating terminal re-opens" \
  "Press <leader>em a third time" \
  "The floating window re-opens, himalaya session preserved (same state as before)"

run_test "Dashboard email button" \
  "Quit nvim, reopen with 'nvim', press 'e' on the alpha dashboard" \
  "Floating himalaya TUI opens (same as <leader>em), NOT buffer mode"

run_test "Buffer mode still works" \
  "Press <leader>eM (capital M)" \
  "Himalaya opens in buffer mode (full buffer, not floating) — this is the old behavior"

# ── Backend Toggle Tests ──

echo -e "\n${BOLD}── Backend Toggle ──${NC}\n"

run_test "Toggle to Gemini" \
  "Press <leader>mB in normal mode" \
  "Notification appears: 'AI backend → gemini'"

run_test "Lualine shows Gemini" \
  "Look at the lualine statusbar (bottom right area)" \
  "Shows '󰇮 gemini' with blue color in lualine_x section"

run_test "Toggle back to Claude" \
  "Press <leader>mB again" \
  "Notification: 'AI backend → claude', lualine updates to '󰇮 claude'"

run_test "Toggle without email buffer" \
  "Navigate to any non-email buffer, press <leader>mB" \
  "Toggle works without errors — backend switches and notification shows"

# ── AI Actions with extra_args ──

echo -e "\n${BOLD}── AI Actions (extra_args) ──${NC}\n"

run_test "Claude TL;DR" \
  "Open an email (<leader>eM → navigate to message), press <leader>mc" \
  "TL;DR result appears in split/tab with formatted markdown (urgency table, action items)"

run_test "Gemini TL;DR (speed test)" \
  "Switch to Gemini (<leader>mB), open an email, press <leader>mc. TIME IT." \
  "Response completes in ~1-3s (NOT 5-8s). Result appears with similar formatting."

run_test "AI result buffer keybinds" \
  "In the AI result buffer, press 'y' to copy, then 'q' to close" \
  "Clipboard contains the AI result text. Buffer closes cleanly."

# ── Edge Cases ──

echo -e "\n${BOLD}── Edge Cases ──${NC}\n"

run_test "No keybind conflicts" \
  "Press <leader>e and wait for which-key menu" \
  "Both 'm' (floating email) and 'M' (buffer email) appear without conflicting with other <leader>e bindings"

run_test "Cold start lualine" \
  "Quit nvim, reopen, check lualine BEFORE any AI action" \
  "Lualine does NOT show backend indicator (it only appears after himalaya-ai is loaded)"

# ── Summary ──

print_summary
