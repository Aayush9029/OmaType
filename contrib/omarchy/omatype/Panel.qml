import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "local.omatype"
  ipcTarget: "local.omatype"
  manageIpc: false

  property var status: ({ alt: "stopped", model: "", backend: "" })
  property var historyEntries: []
  property string lastError: ""
  property string copiedEntryId: ""
  property string pendingDeleteId: ""
  property int selectedEntry: 0
  property bool cursorActive: false

  readonly property string state: String(status.alt || "stopped")
  readonly property bool recording: state === "recording" || state === "streaming"
  readonly property bool working: state === "transcribing"
  readonly property bool ready: state !== "stopped"
  readonly property bool busy: recording || working
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.58)
  readonly property color faint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
  readonly property color accent: recording ? "#fb7185" : (working ? "#fbbf24" : Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function commandFor(args) {
    return [String(settings.command || "voxtype")].concat(args)
  }

  function refreshStatus() {
    if (statusProc.running) return
    statusProc.command = commandFor(["status", "--format", "json", "--extended", "--icon-theme", "omarchy"])
    statusProc.running = true
  }

  function refreshHistory() {
    if (historyProc.running) return
    historyProc.command = commandFor([
      "history", "list", "--json", "--limit", String(Number(settings.historyLimit || 12))
    ])
    historyProc.running = true
  }

  function runAction(args) {
    if (actionProc.running) return
    lastError = ""
    actionProc.command = commandFor(args)
    actionProc.running = true
  }

  function toggleRecording() {
    if (working) return
    runAction(["record", "toggle"])
  }

  function copyEntry(entry) {
    if (!entry || !entry.id) return
    copiedEntryId = String(entry.id)
    runAction(["history", "copy", copiedEntryId])
    copiedReset.restart()
  }

  function requestDelete(entry) {
    if (!entry || !entry.id) return
    var id = String(entry.id)
    if (pendingDeleteId === id) {
      pendingDeleteId = ""
      runAction(["history", "delete", id])
    } else {
      pendingDeleteId = id
      deleteReset.restart()
    }
  }

  function stateTitle() {
    if (lastError !== "") return "OmaType unavailable"
    if (state === "recording") return "Recording"
    if (state === "streaming") return "Typing live"
    if (state === "transcribing") return "Finishing transcript"
    if (state === "idle") return "Ready"
    return "Daemon stopped"
  }

  function stateDetail() {
    if (lastError !== "") return lastError
    if (recording) return state === "streaming" ? "Release Home to finish" : "Tap Home again to finish"
    if (working) return "Parakeet is processing the complete recording"
    var model = String(status.model || "")
    return model !== "" ? model : "Tap Home for batch · hold for live"
  }

  function durationText(seconds) {
    var total = Math.max(0, Math.round(Number(seconds || 0)))
    if (total < 60) return total + "s"
    return Math.floor(total / 60) + ":" + String(total % 60).padStart(2, "0")
  }

  function relativeTime(value) {
    var then = new Date(String(value || "")).getTime()
    if (!isFinite(then)) return ""
    var seconds = Math.max(0, Math.floor((Date.now() - then) / 1000))
    if (seconds < 60) return "now"
    if (seconds < 3600) return Math.floor(seconds / 60) + "m"
    if (seconds < 86400) return Math.floor(seconds / 3600) + "h"
    return Math.floor(seconds / 86400) + "d"
  }

  function normalizedText(value) {
    return String(value || "").replace(/[\r\n]+/g, " ").trim()
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: {
    refreshStatus()
    refreshHistory()
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    selectedEntry = 0
    pendingDeleteId = ""
    refreshStatus()
    refreshHistory()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Timer {
    interval: Math.max(250, Number(settings.refreshIntervalMs || 750))
    running: true
    repeat: true
    onTriggered: root.refreshStatus()
  }

  Timer {
    id: copiedReset
    interval: 1200
    onTriggered: root.copiedEntryId = ""
  }

  Timer {
    id: deleteReset
    interval: 3000
    onTriggered: root.pendingDeleteId = ""
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.status = JSON.parse(String(text || "{}"))
          root.lastError = ""
        } catch (error) {
          root.lastError = "Invalid status response"
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.lastError = String(text).trim()
    }
  }

  Process {
    id: historyProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "[]"))
          root.historyEntries = Array.isArray(parsed) ? parsed : []
          root.selectedEntry = Math.max(0, Math.min(root.selectedEntry, root.historyEntries.length - 1))
        } catch (error) {
          root.lastError = "Invalid history response"
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.lastError = String(text).trim()
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.lastError = String(text).trim()
    }
    onRunningChanged: if (!running) {
      root.refreshStatus()
      root.refreshHistory()
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshStatus(); root.refreshHistory(); return "ok" }
    function record(): string { root.toggleRecording(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.recording ? "󰑊" : (root.working ? "󰔟" : "󰍬")
    fontFamily: "JetBrainsMono Nerd Font"
    foreground: root.muted
    activeColor: root.accent
    active: root.busy
    tooltipText: root.stateTitle() + "\n" + root.stateDetail()
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.toggleRecording()
      else if (mouseButton === Qt.MiddleButton) { root.refreshStatus(); root.refreshHistory() }
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(590))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (root.historyEntries.length === 0 || dy === 0) return
        root.cursorActive = true
        root.selectedEntry = Math.max(0, Math.min(root.historyEntries.length - 1, root.selectedEntry + dy))
      }
      onActivateRequested: if (root.historyEntries.length > 0) root.copyEntry(root.historyEntries[root.selectedEntry])
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === " " || text === "r" || text === "R") root.toggleRecording()
        else if ((text === "d" || text === "D") && root.historyEntries.length > 0)
          root.requestDelete(root.historyEntries[root.selectedEntry])
        else if (text === "c" || text === "C") {
          if (root.historyEntries.length > 0) root.copyEntry(root.historyEntries[root.selectedEntry])
        }
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "OmaType"
          meta: root.stateTitle()
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: root.ready ? 1.0 : 0.45
          iconComponent: Component {
            Text {
              text: root.recording ? "󰑊" : (root.working ? "󰔟" : "󰍬")
              color: root.accent
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.display
            }
          }
        }

        Rectangle {
          width: parent.width
          implicitHeight: statusColumn.implicitHeight + Style.space(24)
          radius: Style.space(12)
          color: root.faint

          Column {
            id: statusColumn
            anchors.fill: parent
            anchors.margins: Style.space(12)
            spacing: Style.space(5)

            RowLayout {
              width: parent.width
              spacing: Style.space(8)
              Rectangle {
                width: Style.space(7)
                height: width
                radius: width / 2
                color: root.accent
              }
              Text {
                text: root.stateTitle()
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Item { Layout.fillWidth: true }
              Text {
                text: root.recording ? "LIVE" : (root.working ? "WORKING" : "LOCAL")
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            Text {
              width: parent.width
              text: root.stateDetail()
              color: root.muted
              elide: Text.ElideMiddle
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        RowLayout {
          width: parent.width
          Text {
            text: "RECENT TRANSCRIPTS"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Item { Layout.fillWidth: true }
          Text {
            text: String(root.historyEntries.length)
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Rectangle {
          visible: root.historyEntries.length === 0
          width: parent.width
          implicitHeight: emptyColumn.implicitHeight + Style.space(32)
          radius: Style.space(12)
          color: root.faint

          Column {
            id: emptyColumn
            anchors.centerIn: parent
            spacing: Style.space(4)
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "󰍭"
              color: root.muted
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.display
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Your transcripts will appear here"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Flickable {
          visible: root.historyEntries.length > 0
          width: parent.width
          height: Math.min(historyColumn.implicitHeight, Style.space(330))
          contentHeight: historyColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: historyColumn
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.historyEntries
              delegate: Rectangle {
                id: transcriptRow
                required property var modelData
                required property int index
                width: historyColumn.width
                implicitHeight: transcriptColumn.implicitHeight + Style.space(20)
                radius: Style.space(10)
                color: transcriptMouse.containsMouse || (root.cursorActive && root.selectedEntry === index)
                  ? Style.selectedFillFor(root.foreground, Color.accent)
                  : root.faint

                Column {
                  id: transcriptColumn
                  anchors.left: parent.left
                  anchors.right: actions.left
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(4)

                  Text {
                    width: parent.width
                    text: root.normalizedText(transcriptRow.modelData.text)
                    color: root.foreground
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    width: parent.width
                    text: root.relativeTime(transcriptRow.modelData.timestamp)
                      + "  ·  " + root.durationText(transcriptRow.modelData.duration_secs)
                      + "  ·  " + String(transcriptRow.modelData.mode || "batch")
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Row {
                  id: actions
                  z: 2
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(3)

                  MiniButton {
                    glyph: root.copiedEntryId === String(transcriptRow.modelData.id) ? "󰄬" : "󰆏"
                    tint: root.copiedEntryId === String(transcriptRow.modelData.id) ? "#34d399" : root.muted
                    tooltip: "Copy transcript"
                    onClicked: root.copyEntry(transcriptRow.modelData)
                  }
                  MiniButton {
                    glyph: root.pendingDeleteId === String(transcriptRow.modelData.id) ? "󰜺" : "󰆴"
                    tint: root.pendingDeleteId === String(transcriptRow.modelData.id) ? "#fb7185" : root.muted
                    tooltip: root.pendingDeleteId === String(transcriptRow.modelData.id)
                      ? "Click again to delete" : "Delete transcript"
                    onClicked: root.requestDelete(transcriptRow.modelData)
                  }
                }

                MouseArea {
                  id: transcriptMouse
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton
                  hoverEnabled: true
                  z: 1
                  onClicked: {
                    root.selectedEntry = transcriptRow.index
                    root.copyEntry(transcriptRow.modelData)
                  }
                }
              }
            }
          }
        }

        ActionButton {
          width: parent.width
          text: root.recording ? "Stop recording" : "Start recording"
          glyph: root.recording ? "󰓛" : "󰐊"
          enabled: root.ready && !root.working && !actionProc.running
          destructive: root.recording
          onClicked: root.toggleRecording()
        }

        Text {
          width: parent.width
          text: "Enter copies  ·  D deletes  ·  Space records  ·  Esc closes"
          color: root.muted
          horizontalAlignment: Text.AlignHCenter
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  component MiniButton: Rectangle {
    id: mini
    property string glyph: ""
    property color tint: root.muted
    property string tooltip: ""
    signal clicked()

    width: Style.space(28)
    height: width
    radius: Style.space(7)
    color: miniMouse.containsMouse ? root.faint : "transparent"

    Text {
      anchors.centerIn: parent
      text: mini.glyph
      color: mini.tint
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: Style.font.body
    }
    MouseArea {
      id: miniMouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: mini.clicked()
    }
    ToolTip.visible: miniMouse.containsMouse
    ToolTip.text: mini.tooltip
  }

  component ActionButton: Rectangle {
    id: action
    property string text: ""
    property string glyph: ""
    property bool destructive: false
    signal clicked()

    implicitHeight: Style.space(42)
    radius: Style.space(10)
    color: actionMouse.containsMouse
      ? Style.selectedFillFor(root.foreground, Color.accent)
      : root.faint
    opacity: enabled ? 1.0 : 0.4

    Row {
      anchors.centerIn: parent
      spacing: Style.space(7)
      Text {
        text: action.glyph
        color: action.destructive ? "#fb7185" : root.accent
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: Style.font.body
      }
      Text {
        text: action.text
        color: action.destructive ? "#fb7185" : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
    }
    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: action.enabled
      onClicked: action.clicked()
    }
  }
}
