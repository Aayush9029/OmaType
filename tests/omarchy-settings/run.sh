#!/usr/bin/env bash
set -euo pipefail
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
export OMATYPE_SETTINGS_TEST_DIR="$TEST_DIR"
printf '%s\n' '{"key":"F13","mode":"hybrid","enabled":true,"audio_device":"default"}' > "$TEST_DIR/state.json"
cp "$(dirname "$0")/shell.qml" "$(dirname "$0")/backend.py" "$TEST_DIR/"
cp "$(dirname "$0")/../../contrib/omarchy/omatype/SettingsStore.qml" "$TEST_DIR/"
QT_QPA_PLATFORM=offscreen timeout 20 qs -p "$TEST_DIR/shell.qml" 2>&1 | tee "$TEST_DIR/log"
! grep -q 'FAIL:' "$TEST_DIR/log"
grep -q 'PASS: rapid edits' "$TEST_DIR/log"
python3 - "$TEST_DIR/events.jsonl" <<'PY'
import json, sys
writes = 0
for line in open(sys.argv[1]):
    event = json.loads(line)
    if len(event['args']) <= 2: continue
    if event['event'] == 'start':
        writes += 1
        # A timed out F23 is killed without logging its end.
        if event['args'][2:] == ['--key', 'F22']: writes -= 1
        assert writes == 1, 'overlapping settings writers'
    else: writes -= 1
print('PASS: only one settings writer at a time')
PY
