pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Controls.Basic as Controls

// Shared by the live service and the standalone design preview. All microphone
// and daemon IO stays in service.qml; this component only presents that state.
Item {
  id: capsule

  property string daemonState: "recording"
  property var samples: []
  property real uiScale: 1
  property bool animationsEnabled: true
  property bool controlsEnabled: true
  property bool confirmDiscard: false
  readonly property bool controlsVisible: hover.hovered && active && !processing
  readonly property bool processing: daemonState === "transcribing"
  readonly property bool active: daemonState === "recording"
    || daemonState === "streaming" || processing
  property real phase: 0
  signal stopRequested()
  signal discardRequested()

  width: 166 * uiScale
  height: 46 * uiScale
  Accessible.role: Accessible.Pane
  Accessible.name: processing ? "Transcribing audio"
    : (daemonState === "streaming" ? "Live dictation" : "Recording")

  HoverHandler { id: hover }
  onControlsVisibleChanged: if (!controlsVisible) confirmDiscard = false
  Timer {
    interval: 4000
    running: capsule.confirmDiscard
    onTriggered: capsule.confirmDiscard = false
  }

  // A 24 fps dotted helix, following Petal's 2.8-second rotation. No idle
  // render loop, and processing continues even after audio frames stop.
  Timer {
    interval: 1000 / 24
    running: capsule.visible && capsule.active && capsule.processing && capsule.animationsEnabled
    repeat: true
    onTriggered: capsule.phase = (capsule.phase + Math.PI * 2 / (2.8 * 24)) % (Math.PI * 2)
  }
  onPhaseChanged: wave.requestPaint()
  onSamplesChanged: if (!processing) wave.requestPaint()
  onDaemonStateChanged: {
    confirmDiscard = false
    wave.requestPaint()
  }

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: "#f51c1c1c"
    border.width: 1
    border.color: "#454545"
    layer.enabled: true
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowColor: "#70000000"
      shadowBlur: 0.6
      shadowVerticalOffset: 4 * capsule.uiScale
      shadowHorizontalOffset: 0
    }
  }

  Canvas {
    id: wave
    x: 20 * capsule.uiScale
    width: 126 * capsule.uiScale
    height: 26 * capsule.uiScale
    anchors.verticalCenter: parent.verticalCenter
    opacity: capsule.controlsVisible ? 0.18 : 1
    Behavior on opacity {
      enabled: capsule.animationsEnabled
      NumberAnimation { duration: 180 }
    }
    layer.enabled: capsule.controlsVisible
    layer.effect: MultiEffect { blurEnabled: true; blur: 0.25; blurMax: 8 }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
      const ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      const columns = 32
      const rows = 9
      const pitchX = 4 * capsule.uiScale
      const pitchY = 3 * capsule.uiScale
      const radius = capsule.uiScale
      const center = height / 2

      function dot(column, row, opacity, tint) {
        ctx.fillStyle = tint
          ? Qt.rgba(tint.r, tint.g, tint.b, opacity)
          : Qt.rgba(0.93, 0.93, 0.92, opacity)
        ctx.beginPath()
        ctx.arc(column * pitchX + radius,
          center + (row - 4) * pitchY, radius, 0, Math.PI * 2)
        ctx.fill()
      }

      if (capsule.processing) {
        // Two turns, quantized onto a dot grid. Dim rungs and the far strand
        // give the helix depth without a colored outline or a progress claim.
        for (let i = 0; i < columns; i++) {
          const angle = capsule.phase + i / (columns - 1) * Math.PI * 4
          const front = Math.round((Math.sin(angle) + 1) * (rows - 1) / 2)
          const back = rows - front - 1
          if (i % 3 === 0) {
            for (let row = Math.min(front, back) + 1; row < Math.max(front, back); row++)
              dot(i, row, 0.25)
          }
          const near = Math.cos(angle) >= 0
          dot(i, front, near ? 1 : 0.32)
          if (front !== back) dot(i, back, near ? 0.32 : 1)
        }
        return
      }

      const values = capsule.samples.slice(-columns)
      const offset = columns - values.length
      for (let i = 0; i < columns; i++) {
        const value = i < offset ? 0 : Number(values[i - offset] || 0)
        const strength = Math.min(1, Math.sqrt(Math.max(0, value)) * 2.1)
        const half = Math.round(strength * 4)
        // Both capture modes use red, with the strongest peaks warming to
        // white. The processing helix keeps its separate neutral palette.
        const heat = Math.pow(Math.max(0, (strength - 0.5) * 2), 1.5)
        const tint = Qt.rgba(0.95 + heat * 0.03, 0.33 + heat * 0.64,
          0.4 + heat * 0.56, 1)
        for (let row = 4 - half; row <= 4 + half; row++)
          dot(i, row, half === 0 ? 0.4 : 0.65 + strength * 0.33, tint)
      }
    }
  }

  Row {
    anchors.centerIn: parent
    spacing: 6 * capsule.uiScale
    opacity: capsule.controlsVisible ? 1 : 0
    visible: opacity > 0
    enabled: capsule.controlsVisible && capsule.controlsEnabled
    Behavior on opacity {
      enabled: capsule.animationsEnabled
      NumberAnimation { duration: 180 }
    }

    ActionButton {
      objectName: "stopButton"
      symbol: capsule.confirmDiscard ? "back" : "stop"
      Accessible.name: capsule.confirmDiscard ? "Keep recording" : "Stop recording and transcribe"
      onClicked: {
        if (capsule.confirmDiscard) capsule.confirmDiscard = false
        else capsule.stopRequested()
      }
    }

    ActionButton {
      objectName: "discardButton"
      symbol: "trash"
      tint: "#f26675"
      armed: capsule.confirmDiscard
      Accessible.name: capsule.confirmDiscard ? "Confirm discard recording" : "Discard recording"
      onClicked: {
        if (capsule.confirmDiscard) {
          capsule.confirmDiscard = false
          capsule.discardRequested()
        } else capsule.confirmDiscard = true
      }
    }
  }

  component ActionButton: Controls.Button {
    id: button
    required property string symbol
    property color tint: "#ededeb"
    property bool armed: false
    width: 72 * capsule.uiScale
    height: 30 * capsule.uiScale
    padding: 0
    focusPolicy: Qt.NoFocus
    hoverEnabled: true
    background: Rectangle {
      radius: height / 2
      color: Qt.rgba(button.tint.r, button.tint.g, button.tint.b,
        button.down || button.armed ? 0.3 : (button.hovered ? 0.2 : 0.1))
      border.width: button.armed ? 1 : 0
      border.color: button.tint
    }
    contentItem: Item {
      Canvas {
        id: icon
        anchors.centerIn: parent
        width: 14 * capsule.uiScale
        height: width
        onWidthChanged: requestPaint()
        Connections {
          target: button
          function onSymbolChanged() { icon.requestPaint() }
          function onTintChanged() { icon.requestPaint() }
        }
        onPaint: {
          const ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)
          ctx.save()
          ctx.scale(width / 14, height / 14)
          ctx.strokeStyle = button.tint
          ctx.fillStyle = button.tint
          ctx.lineWidth = 1.4
          ctx.lineCap = "round"
          ctx.lineJoin = "round"
          if (button.symbol === "stop") {
            ctx.fillRect(2.5, 2.5, 9, 9)
          } else if (button.symbol === "back") {
            ctx.beginPath()
            ctx.moveTo(5, 2); ctx.lineTo(1.5, 5.5); ctx.lineTo(5, 9)
            ctx.moveTo(2, 5.5); ctx.lineTo(8, 5.5)
            ctx.quadraticCurveTo(13, 5.5, 12, 11.5)
            ctx.stroke()
          } else {
            ctx.beginPath()
            ctx.moveTo(2, 3.5); ctx.lineTo(12, 3.5)
            ctx.moveTo(5, 3.5); ctx.lineTo(5, 1.5); ctx.lineTo(9, 1.5); ctx.lineTo(9, 3.5)
            ctx.moveTo(3.5, 5); ctx.lineTo(4, 12); ctx.lineTo(10, 12); ctx.lineTo(10.5, 5)
            ctx.moveTo(6, 6); ctx.lineTo(6, 10)
            ctx.moveTo(8, 6); ctx.lineTo(8, 10)
            ctx.stroke()
          }
          ctx.restore()
        }
      }
    }
  }
}
