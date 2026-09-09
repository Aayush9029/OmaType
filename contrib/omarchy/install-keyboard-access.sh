#!/bin/bash
# Give the active local desktop session access to keyboards for OmaType's
# evdev hotkey listener. logind revokes access when the session is inactive.
set -euo pipefail
if (( EUID != 0 )); then
  echo 'Run this helper as root (sudo or pkexec).' >&2
  exit 1
fi
install -d -m 0755 /etc/udev/rules.d
rule=/etc/udev/rules.d/70-omatype-keyboard.rules
if [[ -f "$rule" ]]; then
  cp -p -- "$rule" "$rule.bak.$(date +%s)"
fi
printf '%s\n' '# OmaType hotkeys: access for the active local session only.' \
  'SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_KEYBOARD}=="1", TAG+="uaccess"' > "$rule"
chmod 0644 "$rule"
udevadm control --reload-rules
udevadm trigger --action=change --subsystem-match=input
udevadm settle
