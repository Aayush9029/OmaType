import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property string daemonState: "idle"
  property var samples: []
  property real peak: 0
  property bool voiceActive: false
  property double startedAt: 0

  readonly property bool active: daemonState === "recording"
    || daemonState === "streaming"
    || daemonState === "transcribing"
  readonly property color stateColor: daemonState === "streaming"
    ? Color.accent
    : (daemonState === "transcribing" ? "#fbbf24" : "#fb7185")
  readonly property string stateLabel: daemonState === "streaming"
    ? "LIVE DICTATION"
    : (daemonState === "transcribing" ? "POLISHING" : "LISTENING")
  readonly property int elapsedSeconds: startedAt > 0
    ? Math.max(0, Math.floor((Date.now() - startedAt) / 1000))
    : 0

  function updateState(raw) {
    try {
      const data = JSON.parse(String(raw || "{}"))
      const next = String(data.alt || data.class || "idle")
      if (next !== daemonState) {
        if ((next === "recording" || next === "streaming")
            && daemonState !== "recording" && daemonState !== "streaming") {
          startedAt = Date.now()
          samples = []
        } else if (next === "idle" || next === "stopped") {
          startedAt = 0
          samples = []
          peak = 0
          voiceActive = false
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
      peak = Math.max(0, Math.min(1, Number(data.peak)))
      voiceActive = !!data.vad
      const next = samples.slice()
      next.push(peak)
      while (next.length > 46) next.shift()
      samples = next
      wave.requestPaint()
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

  Timer {
    interval: 1000
    running: root.active
    repeat: true
    onTriggered: elapsedText.text = root.formatElapsed(root.elapsedSeconds)
  }

  function formatElapsed(value) {
    return Math.floor(value / 60) + ":" + String(value % 60).padStart(2, "0")
  }

  PanelWindow {
    id: window
    visible: root.active
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omatype-waveform"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    BorderSurface {
      id: card
      width: Style.space(356)
      height: Style.space(64)
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(68)
      color: Util.alpha(Color.background, 0.96)
      borderSpec: Border.surfaceSpec("popups", "border", root.stateColor, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius

      Row {
        anchors.fill: parent
        anchors.margins: Style.space(12)
        spacing: Style.space(10)

        Rectangle {
          width: Style.space(38)
          height: width
          anchors.verticalCenter: parent.verticalCenter
          radius: width / 2
          color: Util.alpha(root.stateColor, root.voiceActive ? 0.24 : 0.12)

          Text {
            anchors.centerIn: parent
            text: root.daemonState === "transcribing" ? "󰔟" : "󰍬"
            color: root.stateColor
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: Style.font.display
          }

          SequentialAnimation on scale {
            running: root.voiceActive && root.daemonState !== "transcribing"
            loops: Animation.Infinite
            NumberAnimation { to: 1.08; duration: 180; easing.type: Easing.OutCubic }
            NumberAnimation { to: 1.0; duration: 260; easing.type: Easing.InCubic }
          }
        }

        Column {
          width: Style.space(88)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            text: root.stateLabel
            color: root.stateColor
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Text {
            id: elapsedText
            text: root.formatElapsed(root.elapsedSeconds)
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }
        }

        Canvas {
          id: wave
          width: Style.space(184)
          height: Style.space(36)
          anchors.verticalCenter: parent.verticalCenter

          onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const center = height / 2
            const values = root.samples
            const count = 46
            const gap = 2
            const barWidth = Math.max(1.5, (width - gap * (count - 1)) / count)
            const offset = count - values.length

            ctx.lineCap = "round"
            for (let i = 0; i < count; i++) {
              const value = i < offset ? 0 : Number(values[i - offset] || 0)
              const strength = Math.min(1, Math.sqrt(value) * 2.1)
              const half = Math.max(1.5, strength * (center - 2))
              const x = i * (barWidth + gap) + barWidth / 2
              ctx.strokeStyle = i >= count - 4
                ? root.stateColor
                : Util.alpha(Color.popups.text, 0.30 + strength * 0.58)
              ctx.lineWidth = barWidth
              ctx.beginPath()
              ctx.moveTo(x, center - half)
              ctx.lineTo(x, center + half)
              ctx.stroke()
            }
          }
        }
      }
    }
  }
}
