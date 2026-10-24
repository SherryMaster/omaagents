import QtQuick
import Quickshell
import Quickshell.Io

// Drives one agent's kick tool (codex-kick, claude-kick), the companion that
// starts an idle account's usage window with a one-word request. The panel
// only offers kicks this runner has vouched for: it finds the tool, asks it
// to `--probe` itself, and says plainly why kicking is off when the tool is
// missing or broken.
Item {
  id: runner
  visible: false

  property string provider: "codex"
  readonly property string tool: provider + "-kick"

  // "probing" | "ready" | "missing" | "empty" (no accounts to kick) | "broken"
  property string toolState: "probing"
  property string toolPath: ""
  property string problem: ""
  readonly property bool ready: toolState === "ready"
  readonly property bool running: kickProcess.running
  property var runningIds: ({})
  // The last kick's outcome: { atMs, ok, text }.
  property var lastResult: null
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache")
    + "/omarchy/agent-usage"
  signal kicked()

  // Why the kick control is off, in a sentence, or "" when it isn't.
  readonly property string unavailableReason: toolState === "probing" ? "Checking " + tool + "…"
    : toolState === "missing" ? tool + " isn't installed. Put it on your PATH or in ~/.local/bin to kick accounts from here."
    : toolState === "empty" ? "CPAMC holds no " + (provider === "claude" ? "Claude" : "Codex") + " accounts to kick."
    : toolState === "broken" ? tool + " is installed but failing: " + (problem || "unknown error")
    : ""

  function probe() {
    if (!probeProcess.running) probeProcess.running = true
  }

  // emails: the accounts to kick; empty kicks every idle one.
  function kick(emails, ids) {
    if (!ready || kickProcess.running) return
    var marks = {}
    for (var i = 0; i < ids.length; i++) marks[ids[i]] = true
    runningIds = marks
    kickProcess.command = [toolPath, "--json"].concat(emails)
    kickProcess.running = true
  }

  Component.onCompleted: probe()

  Process {
    id: probeProcess
    running: false
    command: ["sh", "-c",
      "p=$(command -v \"$0\" 2>/dev/null); [ -n \"$p\" ] || p=\"$HOME/.local/bin/$0\";"
      + " [ -x \"$p\" ] || exit 3; echo \"$p\"; exec \"$p\" --probe", runner.tool]
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    stderr: StdioCollector { id: probeErr; waitForEnd: true }
    onExited: function(exitCode) {
      var lines = String(probeOut.text || "").trim().split("\n")
      if (exitCode === 3) {
        runner.toolState = "missing"
        return
      }
      runner.toolPath = lines[0] || ""
      var status = null
      try { status = JSON.parse(lines[lines.length - 1]) } catch (e) {}
      if (exitCode === 0 && status && status.ok === true) {
        runner.toolState = "ready"
        runner.problem = ""
      } else if (status && status.accounts === 0) {
        runner.toolState = "empty"
        runner.problem = ""
      } else {
        runner.toolState = "broken"
        var err = String(probeErr.text || "").trim().split("\n").pop()
        runner.problem = status && status.error ? status.error : err || "exit code " + exitCode
      }
    }
  }

  Process {
    id: kickProcess
    running: false
    stdout: StdioCollector { id: kickOut; waitForEnd: true }
    stderr: StdioCollector { id: kickErr; waitForEnd: true }
    onExited: function(exitCode) {
      runner.runningIds = ({})
      var report = null
      try { report = JSON.parse(String(kickOut.text || "").trim().split("\n").pop()) } catch (e) {}
      runner.lastResult = runner.describe(report, exitCode, String(kickErr.text || "").trim())
      // Tell the pool reader to look again now instead of at its next slot.
      markStale.running = true
    }
  }

  Process {
    id: markStale
    running: false
    command: ["sh", "-c", "mkdir -p \"$0\" && touch \"$0/pool-$1.stale\"", runner.cacheDir, runner.provider]
    onExited: runner.kicked()
  }

  function shortEmail(email) {
    return String(email || "").split("@")[0]
  }

  function describe(report, exitCode, stderr) {
    var at = Date.now()
    if (!report || !Array.isArray(report.results))
      return { atMs: at, ok: false, text: tool + " failed: " + (stderr.split("\n").pop() || "exit code " + exitCode) }
    var kicked = [], skipped = [], failed = []
    for (var i = 0; i < report.results.length; i++) {
      var r = report.results[i]
      if (r.action === "kicked" || r.action === "would_kick") kicked.push(shortEmail(r.email))
      else if (r.action === "error") failed.push(shortEmail(r.email) + ": " + r.error)
      else if (r.action === "already_running" || r.action === "limit") skipped.push(shortEmail(r.email))
    }
    var parts = []
    if (kicked.length) parts.push((report.dryRun ? "Would kick " : "Kicked ") + kicked.join(", "))
    if (skipped.length) parts.push(skipped.length + " already counting down")
    if (failed.length) parts.push("failed " + failed.join("; "))
    if (!parts.length) parts.push("Nothing to kick")
    return { atMs: at, ok: failed.length === 0, text: parts.join(" · ") }
  }
}
