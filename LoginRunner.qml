import QtQuick
import Quickshell
import Quickshell.Io

// Drives cpamc-login, the companion that signs a CPAMC account in again: it
// opens the account's own browser profile on CPAMC's sign-in page and waits
// for the click on "Continue". One sign-in at a time; asking for the same
// account again cancels it.
Item {
  id: runner
  visible: false

  readonly property string tool: "cpamc-login"
  property string email: ""         // the account being signed in, "" when idle
  property string provider: ""
  readonly property bool running: loginProcess.running
  // The last sign-in's outcome: { atMs, ok, text, provider }.
  property var lastResult: null
  signal finished(string provider)

  function signingIn(agent, address) {
    return running && provider === agent && email === address
  }

  // Starts a sign-in, or cancels it when it's the one already waiting.
  // Returns "ok" or why nothing started.
  function toggle(agent, address) {
    if (signingIn(agent, address)) {
      cancel()
      return "cancelled"
    }
    if (running) return "Finish signing in " + shortEmail(email) + " first (click it again to cancel)."
    provider = agent
    email = address
    lastResult = null
    // --notify: the bubble says which window to look at, even with the panel closed.
    loginProcess.command = ["sh", "-c",
      "p=$(command -v \"$0\" 2>/dev/null); [ -n \"$p\" ] || p=\"$HOME/.local/bin/$0\";"
      + " [ -x \"$p\" ] || exit 3; exec \"$p\" --json --notify \"$1\"", tool, agent + ":" + address]
    loginProcess.running = true
    return "ok"
  }

  function cancel() {
    if (loginProcess.running) loginProcess.signal(15)
  }

  function shortEmail(address) {
    return String(address || "").split("@")[0]
  }

  Process {
    id: loginProcess
    running: false
    stdout: StdioCollector { id: loginOut; waitForEnd: true }
    stderr: StdioCollector { id: loginErr; waitForEnd: true }
    onExited: function(exitCode) {
      var who = runner.shortEmail(runner.email)
      var report = null
      try { report = JSON.parse(String(loginOut.text || "").trim().split("\n").pop()) } catch (e) {}
      var result = report && Array.isArray(report.results) ? report.results[0] : null
      var at = Date.now()
      if (exitCode === 3)
        runner.lastResult = { atMs: at, ok: false, provider: runner.provider,
          text: runner.tool + " isn't installed. Put it in ~/.local/bin to sign accounts in from here." }
      else if (result && result.ok)
        runner.lastResult = { atMs: at, ok: true, provider: runner.provider,
          text: who + " is signed in again" + (result.disabled ? " (still turned off in CPAMC)" : "") }
      else if (exitCode === 130 || exitCode === 143 || exitCode === -1)
        runner.lastResult = { atMs: at, ok: false, provider: runner.provider, text: "Stopped signing in " + who }
      else
        runner.lastResult = { atMs: at, ok: false, provider: runner.provider,
          text: "Couldn't sign in " + who + ": " + (result ? result.error : report && report.error
            ? report.error : String(loginErr.text || "").trim().split("\n").pop() || "exit code " + exitCode) }
      var agent = runner.provider
      runner.email = ""
      runner.finished(agent)
    }
  }
}
