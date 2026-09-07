import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property string daemonState: "idle"
  property var samples: []
  property double lastVisualSampleMs: -1
  property real pendingVisualPeak: 0

  readonly property bool active: daemonState === "recording"
    || daemonState === "streaming"
    || daemonState === "transcribing"
  function updateState(raw) {
    try {
      const data = JSON.parse(String(raw || "{}"))
      const next = String(data.alt || data.class || "idle")
      if (next !== daemonState) {
        if ((next === "recording" || next === "streaming")
            && daemonState !== "recording" && daemonState !== "streaming") {
          lastVisualSampleMs = -1
          pendingVisualPeak = 0
          samples = []
        } else if (next === "idle" || next === "stopped") {
          lastVisualSampleMs = -1
          pendingVisualPeak = 0
          samples = []
        }
        daemonState = next
      }
    } catch (error) {
      daemonState = "stopped"
    }
  }

  function updateAudio(raw) {
    const line = String(raw || "").trim()
    if (line === "") return
    try {
      const data = JSON.parse(line)
      if (typeof data.peak !== "number") return
      const nextPeak = Math.max(0, Math.min(1, Number(data.peak)))
      const sampleMs = Number(data.ts_ms || 0)
      pendingVisualPeak = Math.max(pendingVisualPeak, nextPeak)

      // The daemon publishes at 100 Hz, which makes a 46-bar history race
      // across the screen in under half a second. Keep the audio path at full
      // fidelity while sampling the visualizer at ~25 FPS instead.
      if (lastVisualSampleMs >= 0 && sampleMs - lastVisualSampleMs < 40) return
      lastVisualSampleMs = sampleMs
      const next = samples.slice()
      next.push(pendingVisualPeak)
      pendingVisualPeak = 0
      while (next.length > 46) next.shift()
      samples = next
    } catch (error) {}
  }

  Process {
    id: statusProc
    command: ["omatype", "status", "--follow", "--format", "json"]
    running: true
    stdout: SplitParser {
      onRead: function(data) { root.updateState(data) }
    }
  }

  Process {
    id: bridgeProc
    command: ["omatype-audio-bridge"]
    running: true
    stdout: SplitParser {
      onRead: function(data) { root.updateAudio(data) }
    }
  }

  function requestAction(action) {
    if (!active || daemonState === "transcribing" || actionProc.running) return
    actionProc.command = ["omatype", "record", action]
    actionProc.running = true
  }

  Process { id: actionProc }

  PanelWindow {
    id: window
    visible: root.active || card.opacity > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omatype-waveform"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Only the capsule accepts pointer input; the desktop stays interactive.
    mask: Region { item: card }

    FloatingCapsule {
      id: card
      daemonState: root.daemonState
      samples: root.samples
      controlsEnabled: !actionProc.running
      onStopRequested: root.requestAction("stop")
      onDiscardRequested: root.requestAction("cancel")
      uiScale: Style.space(100) / 100
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(68)
      opacity: root.active ? 1 : 0
      scale: root.active ? 1 : 0.94
      Behavior on opacity { NumberAnimation { duration: 150 } }
      Behavior on scale {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
      }
    }
  }
}
