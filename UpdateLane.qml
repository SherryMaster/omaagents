import QtQuick
import Quickshell.Io

// One queue of usage-update runs. Runs in a lane never overlap, so a record
// has one writer at a time; lanes run side by side, so a slow Codex RPC never
// holds Claude's numbers back. A request that lands while a run is busy
// merges into one follow-up, the strongest kind winning — a normal pass does
// everything a fast one does. A fast request while busy is simply dropped:
// the next tick asks again.
Item {
  id: lane
  visible: false

  property string updatePath: ""
  property var args: []
  property string activeKind: ""
  property string pendingKind: ""
  property bool failed: false
  property double lastStartMs: 0
  property double lastNormalStartMs: 0
  readonly property bool busy: process.running
  readonly property bool refreshing: process.running && activeKind !== "fast" || pendingKind !== ""
  signal finished()

  function rank(kind) { return ["fast", "normal", "force"].indexOf(kind) }

  function request(kind) {
    if (process.running) {
      if (kind !== "fast" && rank(kind) > rank(pendingKind)) pendingKind = kind
      return
    }
    var command = [updatePath]
    if (kind === "fast") command.push("--fast")
    if (kind === "force") command.push("--force")
    process.command = command.concat(args)
    activeKind = kind
    lastStartMs = Date.now()
    if (kind !== "fast") lastNormalStartMs = lastStartMs
    process.running = true
  }

  Process {
    id: process
    running: false
    onExited: function(exitCode, exitStatus) {
      lane.failed = exitCode !== 0 || exitStatus !== 0
      lane.activeKind = ""
      var next = lane.pendingKind
      lane.pendingKind = ""
      lane.finished()
      if (next !== "") lane.request(next)
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("agents", text.trim())
    }
  }
}
