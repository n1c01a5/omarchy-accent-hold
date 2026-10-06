#!/bin/bash
# End-to-end test on a running Omarchy session with the plugin enabled.
#
# Opens a throwaway foot window running `cat`, presses real keys through
# ydotool (uinput, so Hyprland resolves binds as for a physical keyboard)
# and compares what the application received. Every key press first checks
# that the test window still has focus, so keys never land anywhere else.
#
# Needs: foot, ydotool with a running ydotoold, jq.

set -uo pipefail

CLASS=accent-hold-test
WORK=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/accent-hold-test.XXXXXX")
FIFO="$WORK/typed"
PASS=0
FAIL=0

# Linux input event codes.
E=18 X=45 B=48 ONE=2 TWO=3 ENTER=28 ESC=1 SHIFT=42 RIGHT=106 KP2=80

# Wait until the plugin service has loaded its binds into Hyprland.
for _ in {1..50}; do
  hyprctl binds -j | jq -e 'any(.[]; .description == "Accent Hold: e")' >/dev/null && break
  sleep 0.1
done
hyprctl binds -j | jq -e 'any(.[]; .description == "Accent Hold: e")' >/dev/null \
  || { echo "Accent Hold binds are not loaded; is the plugin enabled?" >&2; exit 2; }

foot --app-id "$CLASS" -e bash -c "stty -echoctl; cat > '$FIFO'" 2>/dev/null &
FOOT=$!
trap 'kill $FOOT 2>/dev/null; rm -rf "$WORK"' EXIT

for _ in {1..50}; do
  hyprctl clients -j | jq -e --arg c "$CLASS" '.[] | select(.class == $c)' >/dev/null && break
  sleep 0.1
done
hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'class:$CLASS' }))" >/dev/null
sleep 0.3

guard() {
  if [[ $(hyprctl activewindow -j | jq -r .class) != "$CLASS" ]]; then
    echo "test window lost focus, aborting before typing anywhere else" >&2
    exit 2
  fi
}

down() { guard; ydotool key "$1:1" >/dev/null; }
up() { ydotool key "$1:0" >/dev/null; }
tap() { down "$1"; up "$1"; sleep 0.05; }
hold() { down "$1"; sleep "$2"; up "$1"; sleep 0.15; }

line_count() { wc -l < "$FIFO" 2>/dev/null || echo 0; }

# Runs the key steps, ends the line with Return and compares the line cat wrote.
check() {
  local name=$1 expected=$2
  shift 2
  local before
  before=$(line_count)
  "$@"
  sleep 0.15
  tap $ENTER
  sleep 0.3
  local got
  got=$(sed -n "$((before + 1))p" "$FIFO")
  if [[ $got == "$expected" ]]; then
    PASS=$((PASS + 1)); echo "ok   $name"
  else
    FAIL=$((FAIL + 1)); echo "FAIL $name: expected '$expected', got '$got'"
  fi
}

t_number() { hold $E 0.7; tap $TWO; }
t_keypad() { hold $E 0.7; tap $KP2; }
# A human keeps the digit down a while; wtype must not type before it is up.
t_slow_one() { hold $E 0.7; down $ONE; sleep 0.2; up $ONE; sleep 0.3; }
t_shift_number() { hold $E 0.7; down $SHIFT; tap $TWO; up $SHIFT; }
t_tap() { tap $E; }
t_escape() { hold $E 0.7; tap $ESC; }
t_other_key() { hold $E 0.7; tap $X; }
t_shift() { down $SHIFT; hold $E 0.7; up $SHIFT; tap $TWO; }
t_arrows() { hold $E 0.7; tap $RIGHT; tap $RIGHT; tap $ENTER; }
t_no_variants() { hold $B 0.7; }
t_rollover() { down $E; sleep 0.05; down $X; sleep 0.05; up $X; sleep 0.4; up $E; sleep 0.15; }

check "number picks a variant (F12)" "é" t_number
check "numeric keypad picks a variant, NumLock on or off (F12)" "é" t_keypad
check "1 held down like a human picks the first variant (F12)" "è" t_slow_one
check "shifted number row (@) picks a variant (F12)" "é" t_shift_number
check "quick tap types the letter (F3)" "e" t_tap
check "escape keeps the letter (F16)" "e" t_escape
check "other key keeps the letter and types it (F17)" "ex" t_other_key
check "shift shows uppercase (F11)" "É" t_shift
check "arrows then return confirm (F14, F15)" "é" t_arrows
check "rollover cancels the hold (F4)" "ex" t_rollover

# Letters without variants keep auto-repeat (F6).
before=$(line_count)
t_no_variants; sleep 0.1; tap $ENTER; sleep 0.3
got=$(sed -n "$((before + 1))p" "$FIFO")
if [[ $got =~ ^bbb+$ ]]; then
  PASS=$((PASS + 1)); echo "ok   letters without variants repeat (F6)"
else
  FAIL=$((FAIL + 1)); echo "FAIL letters without variants repeat (F6): got '$got'"
fi

echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
