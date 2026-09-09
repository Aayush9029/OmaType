import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import qs.Ui as Ui

Panel {
  id: root
  moduleName: "local.omatype"
  ipcTarget: "local.omatype"
  manageIpc: false

  property var status: ({ alt: "stopped", engine: "", model: "", backend: "" })
  property var historyEntries: []
  property string lastError: ""
  property string copiedEntryId: ""
  property string pendingDeleteId: ""
  property int selectedEntry: 0
  property bool cursorActive: false
  property bool showingModels: false
  property string pendingModel: ""
  property string modelError: ""
  property bool showingSettings: false
  readonly property var hotkey: Object.assign({}, preferences.details, preferences.saved)
  readonly property string draftMode: preferences.values.mode
  readonly property bool draftEnabled: preferences.values.enabled
  readonly property string draftKey: preferences.values.key
  readonly property string draftDevice: preferences.values.audio_device
  readonly property var inputDevices: {
    var devices = [{value: "default", label: "System default"}].concat(preferences.details.input_devices || [])
    if (!devices.some(function(d) { return d.value === root.draftDevice }))
      devices.push({value: root.draftDevice, label: root.draftDevice + " (configured)"})
    return devices
  }
  SettingsStore {
    id: preferences
    command: String(root.settings.command || "omatype")
    blocked: root.busy || root.serviceBusy || root.capturing
    serviceOn: root.ready
    onApplied: root.refreshStatus()
  }
  property bool captureReady: false
  property string capturedKey: ""
  property bool captureCancelled: false
  property bool captureActive: false
  property string captureError: ""
  readonly property bool capturing: captureActive
  readonly property bool serviceBusy: serviceProc.running

  function toggleService() {
    if (serviceBusy || settingsBusy || capturing) return
    lastError = ""
    serviceProc.command = ["systemctl", "--user", ready ? "stop" : "start", "omatype.service"]
    serviceProc.running = true
  }

  function captureKey() {
    if (busy || capturing || serviceBusy || preferences.phase === "applying" || !hotkeyLoaded) return
    preferences.message = ""
    preferences.failed = false
    captureReady = false
    capturedKey = ""
    captureCancelled = false
    captureActive = true
    captureError = ""
    captureProc.command = commandFor(["config", "capture-hotkey"])
    captureProc.running = true
    hotkeyButton.forceActiveFocus()
  }

  function cancelCapture() {
    if (!captureActive || captureCancelled) return
    captureCancelled = true
    captureProc.signal(15)
    captureStopTimeout.restart()
    captureReady = false
  }

  Process {
    id: captureProc
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var result = JSON.parse(line)
          if (root.captureCancelled) return
          if (result.listening) root.captureReady = true
          if (result.key) {
            root.capturedKey = result.key
          }
          if (result.cancelled) preferences.message = "Shortcut unchanged"
        } catch (error) { }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.captureError = text.trim()
    }
    onExited: function(code) {
      captureStopTimeout.stop()
      root.captureReady = false
      root.captureActive = false
      if (root.captureCancelled) {
        preferences.message = "Shortcut unchanged"
      } else if (code === 0 && root.capturedKey) {
        preferences.edit("key", root.capturedKey)
      } else if (code !== 0) {
        preferences.failed = true
        preferences.message = root.captureError || "Capture timed out. Click the shortcut to try again."
      }
    }
  }

  Process {
    id: serviceProc
    stderr: StdioCollector { onStreamFinished: if (text.trim()) root.lastError = text.trim() }
    onExited: function(code) {
      if (code !== 0 && !root.lastError) root.lastError = "Could not change OmaType's power state"
      root.refreshStatus()
    }
  }
  readonly property string settingsMessage: preferences.message
  readonly property bool settingsFailed: preferences.failed
  readonly property bool hotkeyLoaded: preferences.loaded
  readonly property bool settingsBusy: preferences.busy
  readonly property string hotkeyLabel: String(hotkey.key === "F13" && hotkey.home_is_f13 ? "Home" : (hotkey.key || "shortcut"))

  function refreshHotkey() { preferences.refresh() }
  function openSettings() {
    open()
    showingModels = false
    showingSettings = true
    refreshHotkey()
    Qt.callLater(function() { hotkeyButton.forceActiveFocus() })
  }
  Timer {
    interval: 17000
    running: root.capturing
    onTriggered: {
      if (captureProc.running) captureProc.signal(9)
      else {
        root.captureActive = false
        preferences.failed = true
        preferences.message = "Could not start shortcut capture. Click the shortcut to retry."
      }
    }
  }
  Timer {
    id: captureStopTimeout
    interval: 300
    onTriggered: captureProc.signal(9)
  }

  readonly property var modelOptions: [
    {
      id: "parakeet-unified-en-0.6b-int8", engine: "parakeet",
      title: "Parakeet Live", size: "633 MB", languages: "English",
      detail: "Fastest · supports tap and live dictation", recommended: true
    },
    {
      id: "small", engine: "whisper",
      title: "Whisper Small", size: "466 MB", languages: "Multilingual",
      detail: "More languages · accurate tap mode", recommended: false
    },
    {
      id: "small", engine: "sensevoice",
      title: "SenseVoice Small", size: "239 MB", languages: "ZH · EN · JA · KO · YUE",
      detail: "Lightest multilingual option · tap mode", recommended: false
    }
  ]

  readonly property string state: String(status.alt || "stopped")
  readonly property bool recording: state === "recording" || state === "streaming"
  readonly property bool working: state === "transcribing"
  readonly property bool ready: state !== "stopped"
  readonly property bool busy: recording || working
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color muted: Qt.darker(foreground, 1.4)
  readonly property color faint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
  readonly property color accent: recording ? "#fb7185" : (working ? "#fbbf24" : Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function commandFor(args) {
    return [String(settings.command || "omatype")].concat(args)
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
    if (working || !ready || capturing || serviceBusy || settingsBusy) return
    runAction(["record", "toggle"])
  }

  function modelIsActive(option) {
    return String(status.engine || "") === option.engine
      && String(status.model || "") === option.id
  }

  function useModel(option) {
    if (modelProc.running || restartProc.running || modelIsActive(option)) return
    modelError = ""
    pendingModel = option.engine + ":" + option.id
    modelProc.command = commandFor([
      "--engine", option.engine, "setup", "--download", "--model", option.id, "--quiet"
    ])
    modelProc.running = true
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
    if (serviceBusy) return ready ? "Turning off" : "Starting up"
    if (lastError !== "") return "Needs attention"
    if (!ready) return "Dictation off"
    if (working) return "Finishing transcript"
    if (recording) {
      var held = hotkey.mode === "push_to_talk" || (hotkey.mode === "hybrid" && state === "streaming")
      return (held ? "Release " : "Tap ") + hotkeyLabel + " to finish"
    }
    if (!hotkey.enabled) return "Shortcut disabled"
    if (hotkey.keyboard_access === false) return "Keyboard access needed"
    return "Ready to dictate"
  }

  function stateDetail() {
    if (lastError !== "") return lastError
    for (var i = 0; i < modelOptions.length; i++) {
      if (modelIsActive(modelOptions[i])) return modelOptions[i].title
    }
    return String(status.model || "")
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

  function revealSelectedEntry() {
    if (!historyList.visible || root.historyEntries.length === 0) return
    var entry = historyRepeater.itemAt(root.selectedEntry)
    if (!entry) return

    var viewportTop = historyList.contentY
    var viewportBottom = viewportTop + historyList.height
    var entryTop = entry.y
    var entryBottom = entryTop + entry.height
    var nextY = viewportTop

    if (entryTop < viewportTop) nextY = entryTop
    else if (entryBottom > viewportBottom) nextY = entryBottom - historyList.height

    var maxY = Math.max(0, historyList.contentHeight - historyList.height)
    historyList.contentY = Math.max(0, Math.min(nextY, maxY))
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: {
    refreshStatus()
    refreshHistory()
    refreshHotkey()
  }

  onShowingSettingsChanged: if (!showingSettings) cancelCapture()
  onOpenedChanged: if (!opened) {
    cancelCapture()
  } else {
    cursorActive = false
    selectedEntry = 0
    pendingDeleteId = ""
    showingModels = false
    showingSettings = false
    refreshHotkey()
    refreshStatus()
    refreshHistory()
    Qt.callLater(function() {
      historyList.contentY = 0
      keyCatcher.forceActiveFocus()
    })
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
    id: modelProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.modelError = String(text).trim()
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.modelError = ""
        restartProc.command = ["systemctl", "--user", "restart", "omatype.service"]
        restartProc.running = true
      } else {
        root.pendingModel = ""
      }
    }
  }

  Process {
    id: restartProc
    onExited: function(exitCode) {
      root.pendingModel = ""
      if (exitCode !== 0) root.modelError = "Model installed, but the OmaType service could not restart"
      root.refreshStatus()
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
    function models(): void { root.open(); root.showingModels = true; root.showingSettings = false }
    function settings(): void { root.openSettings() }
    function refresh(): string { root.refreshStatus(); root.refreshHistory(); return "ok" }
    function record(): string { root.toggleRecording(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.recording ? "󰑊" : (root.working ? "󰔟" : "󰍬")
    fontFamily: "JetBrainsMono Nerd Font"
    foreground: root.foreground
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
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.showingSettings
      onMoveRequested: function(dx, dy) {
        if (root.showingModels) return
        if (root.historyEntries.length === 0 || dy === 0) return
        root.cursorActive = true
        root.selectedEntry = Math.max(0, Math.min(root.historyEntries.length - 1, root.selectedEntry + dy))
        Qt.callLater(function() { root.revealSelectedEntry() })
      }
      onActivateRequested: if (!root.showingModels && root.historyEntries.length > 0) root.copyEntry(root.historyEntries[root.selectedEntry])
      onCloseRequested: {
        if (root.showingSettings || root.showingModels) {
          root.showingSettings = false
          root.showingModels = false
          keyCatcher.forceActiveFocus()
        } else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "o" || text === "O") { root.toggleService(); return }
        if (text === "s" || text === "S") { root.openSettings(); return }
        if (root.showingModels) return
        if ((text === "d" || text === "D") && root.historyEntries.length > 0)
          root.requestDelete(root.historyEntries[root.selectedEntry])
        else if (text === "c" || text === "C") {
          if (root.historyEntries.length > 0) root.copyEntry(root.historyEntries[root.selectedEntry])
        }
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(14)

        PanelHero {
          width: parent.width
          title: "OmaType"
          meta: root.showingSettings ? "SETTINGS" : root.showingModels ? "MODELS" : root.stateTitle()
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: root.ready ? 1.0 : 0.45
          trailingControl: Component {
            Row {
              spacing: Style.space(8)
              PanelActionButton {
                visible: root.showingSettings || root.showingModels
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰁍"
                tooltipText: "Back to transcripts"
                foreground: root.foreground
                fontFamily: root.fontFamily
                focusable: root.showingSettings
                onClicked: { root.showingSettings = false; root.showingModels = false; keyCatcher.forceActiveFocus() }
              }
              ToggleSwitch {
                checked: root.ready
                busy: root.serviceBusy || root.settingsBusy || root.capturing
                foreground: root.foreground
                onToggled: root.toggleService()
                PanelToolTip {
                  visible: parent.containsMouse
                  text: root.ready ? "Turn dictation off" : "Turn dictation on"
                  fontFamily: root.fontFamily
                }
              }
            }
          }
          iconComponent: Component {
            Text {
              text: root.recording ? "󰑊" : (root.working ? "󰔟" : "󰍬")
              color: root.busy ? root.accent : root.foreground
              font.family: "JetBrainsMono Nerd Font"
              font.pixelSize: Style.font.display
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        Text {
          visible: root.lastError !== "" && !root.showingSettings
          width: parent.width
          text: root.lastError
          textFormat: Text.PlainText
          color: root.muted
          wrapMode: Text.Wrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Column {
          id: settingsContent
          visible: root.showingSettings
          width: parent.width
          spacing: Style.space(14)
          Keys.onEscapePressed: { if (root.capturing) root.cancelCapture(); else { root.showingSettings = false; keyCatcher.forceActiveFocus() } }

          RowLayout {
            width: parent.width
            PanelSectionHeader {
              text: "KEYBOARD SHORTCUT"
              foreground: root.foreground
              fontFamily: root.fontFamily
              Layout.fillWidth: true
            }
            ToggleSwitch {
              checked: root.draftEnabled
              foreground: root.foreground
              enabled: !root.busy && !root.serviceBusy && !root.capturing && root.hotkeyLoaded
              onToggled: preferences.edit("enabled", !root.draftEnabled)
            }
          }
          Ui.Button {
            id: hotkeyButton
            width: parent.width
            text: root.capturing ? (root.captureCancelled ? "Cancelling…" : (root.captureReady ? "Press a key…" : "Getting ready…"))
              : (root.draftKey === "F13" && root.hotkey.home_is_f13 ? "Home" : root.draftKey)
            iconText: "󰌌"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            focusable: true
            enabled: !root.busy && preferences.phase !== "applying" && !root.serviceBusy && root.hotkeyLoaded
            selected: root.capturing
            onClicked: root.capturing ? root.cancelCapture() : root.captureKey()
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              // The capture process reads the key; keep it from activating UI controls.
              if (root.capturing) event.accepted = true
            }
          }
          Text {
            width: parent.width
            text: root.capturing ? "Press and release your shortcut. Esc cancels."
              : "Click the shortcut, then press the key you want to use."
            wrapMode: Text.Wrap
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          PanelSeparator { foreground: root.foreground }
          PanelSectionHeader {
            text: "RECORDING MODE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
          Column {
            width: parent.width
            spacing: Style.space(4)
            Repeater {
              model: [
                {value: "hybrid", title: "Tap to toggle · hold for live"},
                {value: "toggle", title: "Tap to start / stop"},
                {value: "push_to_talk", title: "Hold to record"}
              ]
              delegate: Ui.Button {
                required property var modelData
                width: parent.width
                text: modelData.title
                iconText: root.draftMode === modelData.value ? "󰄬" : " "
                selected: root.draftMode === modelData.value
                leftAlign: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                focusable: true
                enabled: !root.busy && !root.serviceBusy && !root.capturing && root.hotkeyLoaded
                onClicked: preferences.edit("mode", modelData.value)
              }
            }
          }
          PanelSeparator { foreground: root.foreground }
          PanelSectionHeader {
            text: "MICROPHONE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
          Ui.Dropdown {
            id: microphonePicker
            width: parent.width
            showLabel: false
            value: root.draftDevice
            options: root.inputDevices
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: !root.busy && !root.serviceBusy && !root.capturing && root.hotkeyLoaded
            onChanged: function(value) { preferences.edit("audio_device", value) }
          }
          Text {
            visible: root.hotkey.keyboard_access === false
            width: parent.width
            text: "OmaType cannot read your keyboard. Run install-omarchy.sh to set up keyboard access, then restart OmaType."
            wrapMode: Text.Wrap
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          PanelSeparator { foreground: root.foreground }
          Text {
            visible: true
            width: parent.width
            text: root.busy ? "Finish recording to change settings." : (root.settingsMessage || "Changes save and apply automatically.")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.settingsFailed ? Color.accent : root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Ui.Button {
            visible: preferences.failed
            text: "Retry"
            foreground: root.foreground
            onClicked: preferences.retry()
          }
          Ui.Button {
            width: parent.width
            text: "All settings…"
            iconText: "󰒓"
            leftAlign: true
            focusable: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: { Quickshell.execDetached(["omarchy", "launch", "terminal"].concat(root.commandFor(["configure"]))); root.close() }
          }
        }

        RowLayout {
          visible: !root.showingSettings && !root.showingModels
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
          visible: !root.showingSettings && !root.showingModels && root.historyEntries.length === 0
          width: parent.width
          implicitHeight: emptyColumn.implicitHeight + Style.space(32)
          radius: Style.cornerRadius
          color: "transparent"

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
          id: historyList
          visible: !root.showingSettings && !root.showingModels && root.historyEntries.length > 0
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
              id: historyRepeater
              model: root.historyEntries
              delegate: Rectangle {
                id: transcriptRow
                required property var modelData
                required property int index
                width: historyColumn.width
                implicitHeight: transcriptColumn.implicitHeight + Style.space(20)
                radius: Style.cornerRadius
                color: transcriptMouse.containsMouse || (root.cursorActive && root.selectedEntry === index)
                  ? Style.selectedFillFor(root.foreground, Color.accent)
                  : "transparent"

                Column {
                  id: transcriptColumn
                  anchors.left: parent.left
                  anchors.right: actions.left
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(4)

                  Text {
                    textFormat: Text.PlainText
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

        RowLayout {
          visible: !root.showingSettings && !root.showingModels
          width: parent.width
          spacing: Style.space(8)

          ActionButton {
            Layout.fillWidth: true
            text: root.recording ? "Stop recording" : "Start recording"
            glyph: root.recording ? "󰓛" : "󰐊"
            enabled: root.ready && !root.working && !root.serviceBusy && !root.settingsBusy && !actionProc.running
            destructive: root.recording
            onClicked: root.toggleRecording()
          }
          ActionButton {
            Layout.preferredWidth: Style.space(110)
            text: "Models"
            glyph: "󰚩"
            enabled: !root.busy
            onClicked: root.showingModels = true
          }
        }

        Column {
          visible: !root.showingSettings && root.showingModels
          width: parent.width
          spacing: Style.space(8)

          RowLayout {
            width: parent.width
            Text {
              text: "CURATED MODELS"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Item { Layout.fillWidth: true }
          }

          Repeater {
            model: root.modelOptions
            delegate: ModelCard {
              required property var modelData
              width: parent.width
              option: modelData
            }
          }

          Text {
            visible: root.modelError !== ""
            width: parent.width
            text: root.modelError
            color: "#fb7185"
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          visible: !root.showingSettings
          width: parent.width
          text: root.showingModels
            ? "Models download locally · switching restarts OmaType"
            : "S settings  ·  O on / off  ·  Esc closes"
          color: root.muted
          horizontalAlignment: Text.AlignHCenter
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  component MiniButton: PanelActionButton {
    property alias glyph: mini.iconText
    property alias tint: mini.foreground
    property alias tooltip: mini.tooltipText
    id: mini
    foreground: root.muted
    fontFamily: root.fontFamily
  }

  component ModelCard: Rectangle {
    id: modelCard
    required property var option
    readonly property bool activeModel: root.modelIsActive(option)
    readonly property bool installing: root.pendingModel === option.engine + ":" + option.id

    implicitHeight: modelContent.implicitHeight + Style.space(20)
    radius: Style.cornerRadius
    color: activeModel ? Style.selectedFillFor(root.foreground, Color.accent) : "transparent"

    Column {
      id: modelContent
      anchors.left: parent.left
      anchors.right: modelAction.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(3)

      Row {
        spacing: Style.space(6)
        Text {
          text: modelCard.option.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Text {
          visible: modelCard.option.recommended
          text: "RECOMMENDED"
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
      Text {
        width: parent.width
        text: modelCard.option.detail
        color: root.muted
        elide: Text.ElideRight
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Text {
        text: modelCard.option.size + "  ·  " + modelCard.option.languages
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Rectangle {
      id: modelAction
      width: Style.space(82)
      height: Style.space(30)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      radius: Style.cornerRadius
      color: modelMouse.containsMouse ? Style.selectedFillFor(root.foreground, Color.accent) : "transparent"
      opacity: modelProc.running || restartProc.running ? (modelCard.installing ? 1.0 : 0.35) : 1.0

      Text {
        anchors.centerIn: parent
        text: modelCard.activeModel ? "ACTIVE" : (modelCard.installing ? "INSTALLING" : "USE")
        color: modelCard.activeModel || modelCard.installing ? Color.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      MouseArea {
        id: modelMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: !modelCard.activeModel && !modelProc.running && !restartProc.running
        onClicked: root.useModel(modelCard.option)
      }
    }
  }

  component ActionButton: Ui.Button {
    property alias glyph: action.iconText
    property bool destructive: false
    id: action
    foreground: destructive ? Color.accent : root.foreground
    fontFamily: root.fontFamily
    bordered: true
  }
}
