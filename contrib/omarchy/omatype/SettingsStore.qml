import QtQuick
import Quickshell.Io

// One writer, immutable snapshots, and a separate desired state: a completed
// request can never overwrite edits made while it was running.
QtObject {
  id: root
  property string command: "omatype"
  property var applyCommand: ["systemctl", "--user", "try-restart", "omatype.service"]
  property bool blocked: false
  property bool serviceOn: false
  property int debounceMs: 300
  property int requestTimeoutMs: 5000
  property int applyTimeoutMs: 30000
  property var values: ({key: "", mode: "hybrid", enabled: true, audio_device: "default"})
  property var saved: ({})
  property var details: ({})
  property bool loaded: false
  property string phase: "idle"
  property string message: ""
  property bool failed: false
  property int revision: 0
  property int readRevision: 0
  property var snapshot: ({})
  property bool needsApply: false
  property bool appliedWhileOn: false
  property bool loading: false
  readonly property bool pending: loaded && changedFields().length > 0
  readonly property bool busy: phase !== "idle" || pending || needsApply
  signal applied()

  function copy(value) { return JSON.parse(JSON.stringify(value)) }
  function changedFields() {
    return ["key", "mode", "enabled", "audio_device"].filter(function(key) {
      return root.values[key] !== root.saved[key]
    })
  }
  function refresh() {
    if (loading || busy) return
    readRevision = revision
    readProc.command = [command, "config", "hotkey"]
    loading = true
    readProc.running = true
  }
  function edit(key, value) {
    if (!loaded || values[key] === value) return
    var next = copy(values)
    next[key] = value
    values = next
    revision++
    failed = false
    message = "Saving…"
    debounce.restart()
  }
  function retry() {
    failed = false
    if (!loaded) refresh()
    else pump()
  }
  function pump() {
    if (!loaded || blocked || failed || phase !== "idle" || debounce.running) return
    if (pending) {
      snapshot = copy(values)
      var args = [command, "config", "hotkey"]
      changedFields().forEach(function(key) {
        args.push("--" + key.replace(/_/g, "-"), String(root.snapshot[key]))
      })
      phase = "saving"
      message = "Saving…"
      writeProc.command = args
      writeProc.running = true
    } else if (needsApply) {
      phase = "applying"
      message = "Applying…"
      appliedWhileOn = serviceOn
      applyProc.command = applyCommand
      applyProc.running = true
    } else if (!failed) {
      message = "Changes save and apply automatically."
    }
  }
  onBlockedChanged: if (!blocked) Qt.callLater(pump)

  property Timer debounce: Timer {
    interval: root.debounceMs
    onTriggered: root.pump()
  }
  property Process readProc: Process {
    stdout: StdioCollector { id: readOutput }
    stderr: StdioCollector { }
    onExited: function(code) {
      root.loading = false
      // A slow read must not replace a newer user edit or saved snapshot.
      if (root.readRevision !== root.revision) return
      if (code !== 0) {
        root.failed = true
        root.message = "Could not load settings. Click Retry."
        return
      }
      try {
        var data = JSON.parse(readOutput.text)
        root.details = data
        root.values = {key: data.key, mode: data.mode, enabled: data.enabled,
          audio_device: data.audio_device || "default"}
        root.saved = root.copy(root.values)
        root.loaded = true
        root.failed = false
      } catch (error) {
        root.failed = true
        root.message = "Could not read settings. Click Retry."
      }
    }
  }
  property Process writeProc: Process {
    stdout: StdioCollector { }
    stderr: StdioCollector { id: writeError }
    onExited: function(code) {
      root.phase = "idle"
      if (code !== 0) {
        root.failed = true
        root.message = writeError.text.trim() || "Could not save settings. Click Retry."
        return
      }
      root.saved = root.copy(root.snapshot)
      root.needsApply = true
      Qt.callLater(root.pump)
    }
  }
  property Process applyProc: Process {
    stdout: StdioCollector { }
    stderr: StdioCollector { }
    onExited: function(code) {
      root.phase = "idle"
      root.failed = code !== 0
      if (code !== 0) {
        root.message = "Settings saved; could not apply them. Click Retry."
        return
      }
      root.needsApply = false
      root.message = root.appliedWhileOn ? "Saved and applied" : "Saved · applies when dictation is on"
      root.applied()
      if (root.pending) Qt.callLater(root.pump)
    }
  }
  // Bound failures without blocking the UI or leaving an invisible busy state.
  property Timer readTimeout: Timer {
    interval: root.requestTimeoutMs
    running: root.loading
    onTriggered: {
      if (readProc.running) readProc.signal(9)
      else {
        root.loading = false
        root.failed = true
        root.message = "Could not start settings reader. Click Retry."
      }
    }
  }
  property Timer writeTimeout: Timer {
    interval: root.requestTimeoutMs
    running: root.phase === "saving"
    onTriggered: {
      if (writeProc.running) writeProc.signal(9)
      else {
        root.phase = "idle"
        root.failed = true
        root.message = "Could not start settings writer. Click Retry."
      }
    }
  }
  property Timer applyTimeout: Timer {
    interval: root.applyTimeoutMs
    running: root.phase === "applying"
    onTriggered: {
      if (applyProc.running) applyProc.signal(9)
      else {
        root.phase = "idle"
        root.failed = true
        root.message = "Could not start settings apply. Click Retry."
      }
    }
  }
}
