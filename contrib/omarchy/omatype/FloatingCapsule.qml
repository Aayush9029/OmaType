pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// Shared by the live service and the standalone design preview. All microphone
// and daemon IO stays in service.qml; this component only presents that state.
Item {
  id: capsule

  property string daemonState: "recording"
  property var samples: []
  property int elapsedSeconds: 0
  property real uiScale: 1
  property string fontFamily: "sans-serif"
  property bool animationsEnabled: true
  readonly property bool processing: daemonState === "transcribing"
  readonly property bool active: daemonState === "recording"
    || daemonState === "streaming" || processing
  property real phase: 0

  width: (processing ? 256 : 288) * uiScale
  height: 46 * uiScale
  Accessible.role: Accessible.Indicator
  Accessible.name: processing ? "Transcribing audio"
    : (daemonState === "streaming" ? "Live dictation" : "Recording")

  Behavior on width {
    enabled: capsule.animationsEnabled
    NumberAnimation { duration: 240; easing.type: Easing.InOutCubic }
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
  onDaemonStateChanged: wave.requestPaint()

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

  Rectangle {
    x: 18 * capsule.uiScale
    anchors.verticalCenter: parent.verticalCenter
    width: 6 * capsule.uiScale
    height: width
    radius: width / 2
    color: "#ededeb"
    visible: !capsule.processing
  }

  Text {
    x: (capsule.processing ? 20 : 32) * capsule.uiScale
    anchors.verticalCenter: parent.verticalCenter
    text: capsule.processing ? "Processing"
      : (capsule.daemonState === "streaming" ? "LIVE" : "REC")
    color: "#ededeb"
    font.family: capsule.fontFamily
    font.pixelSize: (capsule.processing ? 12 : 11) * capsule.uiScale
    font.weight: Font.Medium
    font.letterSpacing: (capsule.processing ? 0 : 0.8) * capsule.uiScale
  }

  Canvas {
    id: wave
    x: (capsule.processing ? 110 : 82) * capsule.uiScale
    width: 126 * capsule.uiScale
    height: 26 * capsule.uiScale
    anchors.verticalCenter: parent.verticalCenter
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

      function dot(column, row, opacity) {
        ctx.fillStyle = Qt.rgba(0.93, 0.93, 0.92, opacity)
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
        for (let row = 4 - half; row <= 4 + half; row++)
          dot(i, row, half === 0 ? 0.24 : 0.48 + strength * 0.5)
      }
    }
  }

  Rectangle {
    x: 224 * capsule.uiScale
    anchors.verticalCenter: parent.verticalCenter
    width: capsule.uiScale
    height: 14 * capsule.uiScale
    color: "#424242"
    visible: !capsule.processing
  }

  Text {
    anchors.right: parent.right
    anchors.rightMargin: 17 * capsule.uiScale
    anchors.verticalCenter: parent.verticalCenter
    text: Math.floor(capsule.elapsedSeconds / 60) + ":"
      + String(capsule.elapsedSeconds % 60).padStart(2, "0")
    color: "#a6a6a4"
    font.family: "monospace"
    font.pixelSize: 11 * capsule.uiScale
    visible: !capsule.processing
  }
}
