import QtQuick
import Quickshell
import "." as OmaType

ShellRoot {
  id: test
  property int stage: 0
  property double since: Date.now()
  property double lastTick: Date.now()
  property int ticks: 0
  property int applies: 0
  property string backend: Qt.resolvedUrl("backend.py").toString().replace("file://", "")
  function check(ok, message) { if (!ok) { console.error("FAIL: " + message); Qt.quit() } }
  function next() { stage++; since = Date.now() }
  OmaType.SettingsStore {
    id: store
    command: test.backend
    applyCommand: [test.backend, "apply"]
    debounceMs: 30
    requestTimeoutMs: 900
    onApplied: test.applies++
  }
  Component.onCompleted: store.refresh()
  Timer {
    interval: 10; running: true; repeat: true
    onTriggered: {
      var now = Date.now()
      test.check(now - test.lastTick < 250, "event loop stalled")
      test.lastTick = now
      test.ticks++
      test.check(now - test.since < 5000, "stage " + test.stage + " timed out")
      switch (test.stage) {
      case 0:
        if (!store.loaded) break
        store.edit("mode", "toggle")
        test.check(store.values.mode === "toggle", "edit must appear immediately")
        test.next(); break
      case 1:
        if (store.phase !== "saving") break
        store.edit("enabled", false)
        store.edit("audio_device", "sysdefault:CARD=Test")
        store.blocked = true
        test.next(); break
      case 2:
        if (store.phase !== "idle") break
        test.check(store.pending, "newer edits lost when first save completed")
        test.check(store.saved.enabled === true && store.values.enabled === false, "snapshot isolation")
        test.check(test.applies === 0, "applied while blocked")
        if (now - test.since < 350) break
        store.blocked = false
        test.next(); break
      case 3:
        if (store.phase !== "applying") break
        store.edit("mode", "push_to_talk")
        test.next(); break
      case 4:
        if (store.busy) break
        test.check(store.saved.mode === "push_to_talk" && !store.saved.enabled, "edit during apply lost")
        test.check(test.applies === 2, "rapid edits should coalesce before restart")
        store.refresh()
        store.edit("mode", "hybrid")
        test.next(); break
      case 5:
        if (store.busy || store.loading) break
        test.check(store.values.mode === "hybrid", "stale read overwrote newer edit")
        store.edit("key", "F24")
        test.next(); break
      case 6:
        if (!store.failed) break
        test.check(store.pending && store.values.key === "F24", "failed save lost user edit")
        store.retry(); test.next(); break
      case 7:
        if (store.busy) break
        test.check(store.saved.key === "F24", "retry did not save retained edit")
        store.edit("key", "F23")
        test.next(); break
      case 8:
        if (!store.failed) break
        test.check(store.phase === "idle", "timeout left writer stuck")
        store.edit("key", "F22")
        test.next(); break
      case 9:
        if (store.busy) break
        test.check(store.saved.key === "F22", "edit after timeout failed")
        console.log("PASS: rapid edits, in-flight edits, deferred apply, stale reads, failure/retry, timeout recovery, UI heartbeat (" + test.ticks + " ticks)")
        Qt.quit()
      }
    }
  }
}
