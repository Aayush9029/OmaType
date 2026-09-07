import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Run `qs -p contrib/omarchy/omatype/preview.qml` to preview the production component
// without recording audio or changing the daemon's state. Closes after 90s.
ShellRoot {
  id: preview
  property string stage: "recording"
  property var samples: []
  property int ticks: 0
  property bool cycling: true

  Timer {
    interval: 40
    running: true
    repeat: true
    onTriggered: {
      preview.ticks++
      const t = preview.ticks * 0.04
      const next = preview.samples.slice(-45)
      const envelope = Math.max(0, Math.sin(t * 2.1))
      next.push(envelope * (0.04 + 0.12 * Math.pow(Math.sin(t * 17), 2)))
      preview.samples = next
    }
  }
  Timer {
    interval: 6000
    running: preview.cycling
    repeat: true
    onTriggered: preview.stage = preview.stage === "recording" ? "streaming"
      : (preview.stage === "streaming" ? "transcribing" : "recording")
  }
  Timer { interval: 90000; running: true; onTriggered: Qt.quit() }

  IpcHandler {
    target: "preview"
    function state(value: string): void {
      preview.cycling = false
      preview.stage = value
    }
    function close(): void { Qt.quit() }
    function capture(path: string): void {
      artwork.grabToImage(function(result) { result.saveToFile(path) }, Qt.size(360, 94))
    }
  }

  PanelWindow {
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omatype-capsule-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    Item {
      id: artwork
      width: 360
      height: 94
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 44

      FloatingCapsule {
        id: capsule
        anchors.centerIn: parent
        daemonState: preview.stage
        samples: preview.samples
        elapsedSeconds: Math.floor(preview.ticks / 25)
        visible: active
      }
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: artwork.bottom
      text: "DESIGN PREVIEW · NO MICROPHONE"
      font.pixelSize: 9
      font.letterSpacing: 1
      color: "#a6a6a4"
    }
  }
}
