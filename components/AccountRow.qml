import QtQuick
import qs.Commons
import qs.Ui
import "../Analytics.js" as A

// One account: who, which plan, what state, and — unless folded — one line
// per limit window, each with a full-width meter carrying that account's own
// pace tick. The chevron folds it to its header line (which then names the
// fullest window). An account carries a checkbox for a kick (on an idle one
// it starts the clock); clicking the row toggles it. Clicking an account whose
// login died signs it in again. Status never rides on color alone — every
// state has its glyph and word.
Item {
  id: row
  property var account: null
  property real nowMs: 0
  property bool selected: false
  property bool kicking: false
  property bool signingIn: false
  // Off when no sign-in tool is around; the row then only says what's wrong.
  property bool canSignIn: false
  property bool collapsed: false
  property bool showEmail: true
  // Off when the tier header already names the one plan.
  property bool showPlan: true
  // Off when this is the only account: the kick can only mean it.
  property bool selectable: true
  property real inUseMs: 180000
  property int ordinal: 0
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal toggled()
  signal signInRequested()
  signal collapseToggled()

  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property bool kickable: !!account && account.kickable
  readonly property bool needsSignIn: !!account && account.status === "expired" && canSignIn
  readonly property var windows: account && account.windows ? account.windows : []
  readonly property bool hasGroups: windows.some(function(w) { return w.group !== "" })
  readonly property string name: showEmail ? String(account ? account.email : "") : "Account " + ordinal
  // The fullest started window, for the folded header.
  readonly property var peak: {
    var best = null
    for (var i = 0; i < windows.length; i++)
      if (windows[i].started && (!best || windows[i].percent > best.percent)) best = windows[i]
    return best
  }

  readonly property var statusInfo: {
    var a = account || {}
    if (kicking) return { glyph: "◌", text: "kicking…", color: Color.accent }
    if (signingIn) return { glyph: "◌", text: "signing in…", color: Color.accent }
    switch (a.status) {
    // Kickable idle is accent-colored (it's actionable); a quiet running
    // window is plain idle.
    case "idle": return { glyph: "○", text: "idle", color: Color.accent }
    case "quiet": return { glyph: "○", text: "idle", color: row.dim }
    case "running": return { glyph: "●", text: "in use", color: "#9ece6a" }
    case "limited": return { glyph: "■", text: a.freeInMs > 0 ? "full · " + A.formatDuration(a.freeInMs) : "full", color: "#ff9e64" }
    case "expired": return { glyph: "▲", text: row.needsSignIn ? "sign in →" : "sign in again", color: Color.urgent }
    case "disabled": return { glyph: "–", text: "disabled", color: row.dim }
    case "ok": return { glyph: "○", text: "ok", color: row.dim }
    default: return { glyph: "…", text: "checking", color: row.dim }
    }
  }

  readonly property string tooltip: {
    var a = account
    if (!a) return ""
    var lines = [a.email + " · " + a.planLabel + (a.priority ? " · priority " + a.priority : "")]
    for (var i = 0; i < a.windows.length; i++) {
      var w = a.windows[i]
      var paceText = w.started ? A.paceWords(w.percent, w.pace) : ""
      lines.push(w.name + ": " + Math.round(w.percent * 100) + "% used"
        + (w.started ? " · resets in " + A.formatDuration(w.resetMs) : " · not started")
        + (paceText !== "" ? " · " + paceText : ""))
    }
    if (a.status === "running") lines.push("In use — " + (a.recentTokens > 0
      ? A.formatTokens(a.recentTokens) + " tokens in the last " + A.formatDuration(row.inUseMs)
      : "usage rose " + A.formatDuration(Math.max(60000, a.quietMs)) + " ago"))
    else if (a.status === "quiet") lines.push(a.lastActiveMs > 0 ? "Idle for " + A.formatDuration(a.quietMs) + " — its window is still counting down"
      : "No use seen lately — its window is still counting down")
    else if (a.status === "idle") lines.push("Window not started — a kick starts it")
    if (a.note) lines.push(a.note)
    if (a.stale) lines.push("Last check failed — numbers may be old")
    if (kickable && selectable) lines.push(selected ? "Click to deselect" : "Click to select for a kick")
    lines.push(collapsed ? "Click ▸ to show its windows" : "Click ▾ to fold it to one line")
    if (signingIn) lines.push("Waiting for you to click Continue in its browser window — click here to stop")
    else if (needsSignIn) lines.push("Click to sign in again — opens this account's own browser window")
    return lines.join("\n")
  }

  implicitHeight: content.implicitHeight + Style.space(8)

  // Only lends its usage colors to the folded header.
  Meter { id: palette; visible: false }
  opacity: account && account.status === "disabled" ? 0.5 : 1

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: -Style.space(4)
    anchors.rightMargin: -Style.space(4)
    radius: Style.cornerRadius
    color: row.selected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
      : Qt.rgba(row.foreground.r, row.foreground.g, row.foreground.b, area.containsMouse ? 0.06 : 0)
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(3)

    // Line one: checkbox, name, plan, status.
    Item {
      width: parent.width
      implicitHeight: Math.max(nameText.implicitHeight, box.height)

      Text {
        id: chevron
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(13)
        text: row.collapsed ? "▸" : "▾"
        color: chevronArea.containsMouse ? row.foreground : row.dim
        font.pixelSize: Style.font.caption
      }
      Rectangle {
        id: box
        width: visible ? Style.space(13) : 0
        height: Style.space(13)
        radius: Style.space(3)
        anchors.left: chevron.right
        anchors.leftMargin: visible ? Style.space(4) : 0
        anchors.verticalCenter: parent.verticalCenter
        visible: row.kickable && row.selectable
        color: row.selected ? Color.accent : "transparent"
        border.width: 1
        border.color: row.selected ? Color.accent : Qt.rgba(row.foreground.r, row.foreground.g, row.foreground.b, 0.45)
        Text {
          anchors.centerIn: parent
          visible: row.selected
          text: "✓"
          color: Color.popups.background
          font.pixelSize: Style.space(10)
          font.bold: true
        }
      }

      Text {
        id: nameText
        anchors.left: box.right
        anchors.leftMargin: Style.space(6)
        anchors.right: planText.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: row.name
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideMiddle
      }
      Text {
        id: planText
        anchors.right: peakText.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        visible: row.showPlan
        text: row.account && row.showPlan ? row.account.planLabel.toUpperCase() : ""
        color: row.dim
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
      }
      Text {
        id: peakText
        // Folded, the header still says how full the fullest window is.
        visible: row.collapsed && !!row.peak
        anchors.right: statusText.left
        anchors.rightMargin: visible ? Style.space(8) : 0
        anchors.verticalCenter: parent.verticalCenter
        text: visible ? row.peak.short + " " + Math.round(row.peak.percent * 100) + "%" : ""
        color: visible ? palette.usageColor(row.peak.percent) : row.dim
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
      }
      Text {
        id: statusText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: row.statusInfo.glyph + " " + row.statusInfo.text + (row.account && row.account.stale ? " ·?" : "")
        color: row.statusInfo.color
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // One line per window: its name, a full-width meter with this account's
    // pace tick, how much is used, and when it resets.
    Column {
      x: chevron.width + Style.space(4)
      width: parent.width - x
      spacing: Style.space(3)
      visible: !row.collapsed && row.windows.length > 0

      Repeater {
        // Counted, not the array itself: a new array would rebuild every row.
        model: row.collapsed ? 0 : row.windows.length
        Item {
          required property int index
          // The row stays put across refreshes; only what it shows changes.
          readonly property var modelData: row.windows[index] || ({ name: "", short: "", percent: 0, started: false, resetMs: -1, pace: -1 })
          width: parent.width
          implicitHeight: Math.max(windowLabel.implicitHeight, mini.height)

          Text {
            id: windowLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(row.hasGroups ? 96 : 52)
            text: modelData.name
            color: row.dim
            font.family: row.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
          Meter {
            id: mini
            anchors.left: windowLabel.right
            anchors.leftMargin: Style.space(6)
            anchors.right: pct.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            thickness: Style.space(4)
            value: modelData.started ? modelData.percent : 0
            // This account's own pace: where its use would sit if spread
            // evenly over the time its window has run.
            pace: modelData.started && isFinite(modelData.pace) ? modelData.pace : -1
            graded: true
            foreground: row.foreground
          }
          Text {
            id: pct
            anchors.right: resetText.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(32)
            horizontalAlignment: Text.AlignRight
            text: Math.round((modelData.started ? modelData.percent : 0) * 100) + "%"
            color: modelData.started ? mini.usageColor(modelData.percent) : row.dim
            font.family: row.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            id: resetText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(48)
            horizontalAlignment: Text.AlignRight
            text: modelData.started ? A.formatDuration(modelData.resetMs) : "idle"
            color: row.dim
            font.family: row.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }

    Text {
      visible: !row.collapsed && !!row.account && row.account.windows.length === 0 && row.account.note !== ""
      x: chevron.width + Style.space(4)
      width: parent.width - x
      text: row.account ? row.account.note : ""
      color: row.account && row.account.status === "expired" ? Color.urgent : row.dim
      font.family: row.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: row.kickable && row.selectable || row.needsSignIn || row.signingIn ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: {
      if (row.needsSignIn || row.signingIn) row.signInRequested()
      else if (row.kickable && row.selectable) row.toggled()
    }
  }

  MouseArea {
    id: chevronArea
    // The fold control: the chevron and a little room around it.
    x: -Style.space(4)
    y: 0
    width: Style.space(21)
    height: Style.space(8) + Style.font.body * 1.4
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: row.collapseToggled()
  }

  PanelToolTip {
    visible: (area.containsMouse || chevronArea.containsMouse) && row.tooltip !== ""
    text: row.tooltip
    fontFamily: row.fontFamily
  }
}
