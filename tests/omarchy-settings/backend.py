#!/usr/bin/env python3
"""Delayed/failing CLI fixture. Never accesses the user's config or service."""
import json
import os
from pathlib import Path
import sys
import time

root = Path(os.environ['OMATYPE_SETTINGS_TEST_DIR'])
state = root / 'state.json'
args = sys.argv[1:]
def log(event):
    with (root / 'events.jsonl').open('a') as out:
        out.write(json.dumps({'event': event, 'args': args, 'time': time.monotonic()}) + '\n')
log('start')
if args == ['apply']:
    time.sleep(.25)
else:
    data = json.loads(state.read_text())
    if len(args) == 2:
        # Return a stale snapshot after an edit has had time to save.
        time.sleep(.5)
        print(json.dumps(data))
    else:
        time.sleep(.2)
        changes = dict(zip(args[2::2], args[3::2]))
        if changes.get('--key') == 'F24' and not (root / 'failed-once').exists():
            (root / 'failed-once').touch()
            log('failed')
            sys.exit(1)
        if changes.get('--key') == 'F23':
            time.sleep(10)
        for key, value in changes.items():
            data[key[2:].replace('-', '_')] = value == 'true' if key == '--enabled' else value
        state.write_text(json.dumps(data))
log('end')
