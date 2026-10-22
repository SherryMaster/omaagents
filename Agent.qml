import QtQuick
import Quickshell.Io

// One agent's usage record, read straight off the data file that
// omarchy-agent-usage-update maintains. The panel never learns how the
// numbers were made — a record that appears in the usage directory is an
// agent, whoever wrote it.
Item {
  id: root
  visible: false

  property string agentId: ""
  property string path: ""
  property var record: null
  property var lastKnownLimits: []

  FileView {
    path: root.path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parse(text())
    onLoadFailed: root.record = null
  }

  function parse(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      if (!parsed || typeof parsed !== "object") throw new Error("Invalid usage record")
      var failed = parsed.retryAdvised === true || !!parsed.usageStatusText
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
