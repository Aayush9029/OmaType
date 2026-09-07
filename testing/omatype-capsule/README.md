## Capsule preview

With Quickshell installed, run from the repository root:

```bash
qs -p contrib/omarchy/omatype/preview.qml
```

The preview uses the production capsule component and simulated audio levels. It cycles through recording, live dictation, and processing without accessing the microphone, and closes after 90 seconds. Hover to try the stop and discard controls.

## Interaction checks

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input testing/omatype-capsule
```

Checks cover stop, discard confirmation, keeping a recording, pointer leave, processing, pending actions, and confirmation timeout.
