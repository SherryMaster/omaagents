import QtQuick
import Quickshell.Io

// One agent's usage record, read straight off the data file that
// usage-update maintains, and the lane of collector runs that writes it. The
// panel never learns how the numbers were made — a record that appears in the
// usage directory is an agent, whoever wrote it.
Item {
  id: root
  visible: false

  property string agentId: ""
  property string path: ""
  property string updatePath: ""
  property var record: null
  property var lastKnownLimits: []
  // The record minus its write stamp: a pass that changed nothing else
  // leaves everything downstream alone.
  property string lastContentKey: ""
  readonly property alias lane: lane

  function refresh(kind) { lane.request(kind) }

  UpdateLane {
    id: lane
    updatePath: root.updatePath
    args: [root.agentId]
  }

  FileView {
    path: root.path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parse(text())
    onLoadFailed: root.record = null
  }

  function parse(content) {
    var key = String(content || "").replace(/"updatedAt":"[^"]*"/, "")
    if (root.record && key === root.lastContentKey) return
    root.lastContentKey = key
    try {
      var parsed = JSON.parse(String(content || ""))
      if (!parsed || typeof parsed !== "object") throw new Error("Invalid usage record")
      var failed = parsed.retryAdvised === true || !!parsed.usageStatusText || parsed.limitsStale === true
      var incoming = Array.isArray(parsed.limits) ? parsed.limits : []
      if (failed && incoming.length === 0 && lastKnownLimits.length > 0) {
        parsed.limits = lastKnownLimits
        parsed.limitsStale = true
      } else if (!failed) {
        lastKnownLimits = incoming
      }
      root.record = parsed
    } catch (e) {
      console.warn("agents", "Ignoring bad usage record", root.path, e)
      root.record = null
    }
  }
}
