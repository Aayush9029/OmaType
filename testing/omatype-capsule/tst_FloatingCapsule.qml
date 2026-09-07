import QtQuick
import QtTest
import "../../contrib/omarchy/omatype" as OmaType

TestCase {
  id: testCase
  name: "FloatingCapsule"
  when: windowShown
  width: 400
  height: 200
  visible: true

  OmaType.FloatingCapsule {
    id: capsule
    anchors.centerIn: parent
    animationsEnabled: false
  }
  SignalSpy { id: stopSpy; target: capsule; signalName: "stopRequested" }
  SignalSpy { id: discardSpy; target: capsule; signalName: "discardRequested" }

  function init() {
    mouseMove(testCase, 0, 0)
    capsule.daemonState = "recording"
    capsule.controlsEnabled = true
    capsule.confirmDiscard = false
    stopSpy.clear()
    discardSpy.clear()
  }

  function hover() {
    mouseMove(capsule, capsule.width / 2, capsule.height / 2)
    tryCompare(capsule, "controlsVisible", true)
  }

  function test_stop() {
    hover()
    mouseClick(findChild(capsule, "stopButton"))
    compare(stopSpy.count, 1)
    compare(discardSpy.count, 0)
  }

  function test_discardRequiresConfirmation() {
    hover()
    const discard = findChild(capsule, "discardButton")
    mouseClick(discard)
    compare(capsule.confirmDiscard, true)
    compare(discardSpy.count, 0)
    mouseClick(discard)
    compare(discardSpy.count, 1)
    compare(stopSpy.count, 0)
  }

  function test_keepRecording() {
    hover()
    mouseClick(findChild(capsule, "discardButton"))
    mouseClick(findChild(capsule, "stopButton"))
    compare(capsule.confirmDiscard, false)
    compare(stopSpy.count, 0)
    compare(discardSpy.count, 0)
  }

  function test_leaveClearsConfirmation() {
    hover()
    mouseClick(findChild(capsule, "discardButton"))
    mouseMove(testCase, 0, 0)
    tryCompare(capsule, "controlsVisible", false)
    compare(capsule.confirmDiscard, false)
  }

  function test_processingHidesControls() {
    hover()
    capsule.daemonState = "transcribing"
    compare(capsule.controlsVisible, false)
    compare(capsule.confirmDiscard, false)
    compare(stopSpy.count, 0)
    compare(discardSpy.count, 0)
  }

  function test_pendingActionDisablesButtons() {
    hover()
    capsule.controlsEnabled = false
    mouseClick(findChild(capsule, "stopButton"))
    mouseClick(findChild(capsule, "discardButton"))
    compare(stopSpy.count, 0)
    compare(capsule.confirmDiscard, false)
    compare(discardSpy.count, 0)
  }

  function test_confirmationExpires() {
    hover()
    mouseClick(findChild(capsule, "discardButton"))
    tryCompare(capsule, "confirmDiscard", false, 4500)
    compare(discardSpy.count, 0)
  }
}
