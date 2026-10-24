import QtQuick
import qs.Commons
import qs.Ui
import "../Analytics.js" as A

// One pooled account: who, which plan, what state, and a mini meter per
// window. Idle accounts carry a checkbox (a kick would start their clock);
// clicking the row toggles it. Status never rides on color alone — every
// state has its glyph and word.
Item {
  id: row
  property var account: null
  property real nowMs: 0
  property bool selected: false
  property bool kicking: false
  property bool signedIn: false
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

  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property bool kickable: !!account && account.kickable
  readonly property var windows: account && account.windows ? account.windows : []
  readonly property string name: showEmail ? String(account ? account.email : "") : "Account " + ordinal

  readonly property var statusInfo: {
    var a = account || {}
    if (kicking) return { glyph: "◌", text: "kicking…", color: Color.accent }
    switch (a.status) {
    // Kickable idle is accent-colored (it's actionable); a quiet running
    // window is plain idle.
    case "idle": return { glyph: "○", text: "idle", color: Color.accent }
    case "quiet": return { glyph: "○", text: "idle", color: row.dim }
    case "running": return { glyph: "●", text: "in use", color: "#9ece6a" }
    case "limited": return { glyph: "■", text: a.freeInMs > 0 ? "full · " + A.formatDuration(a.freeInMs) : "full", color: "#ff9e64" }
    case "expired": return { glyph: "▲", text: "sign in again", color: Color.urgent }
    case "disabled": return { glyph: "–", text: "disabled", color: row.dim }
    default: return { glyph: "…", text: "checking", color: row.dim }
    }
  }

  readonly property string tooltip: {
    var a = account
    if (!a) return ""
    var lines = [a.email + " · " + a.planLabel + (a.priority ? " · priority " + a.priority : "")]
    if (signedIn) lines.push("Codex's own sign-in (plugins and apps use it)")
    for (var i = 0; i < a.windows.length; i++) {
      var w = a.windows[i]
      lines.push(w.short + ": " + Math.round(w.percent * 100) + "% used"
        + (w.started ? " · resets in " + A.formatDuration(w.resetMs) : " · not started"))
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
    return lines.join("\n")
  }

  implicitHeight: content.implicitHeight + Style.space(8)
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

      Rectangle {
        id: box
        width: Style.space(13)
        height: width
        radius: Style.space(3)
        anchors.left: parent.left
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
        anchors.leftMargin: Style.space(8)
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
        anchors.right: signedInText.left
        anchors.rightMargin: signedInText.visible ? Style.space(6) : 0
        anchors.verticalCenter: parent.verticalCenter
        visible: row.showPlan
        text: row.account && row.showPlan ? row.account.planLabel.toUpperCase() : ""
        color: row.dim
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
      }
      Text {
        id: signedInText
        visible: row.signedIn
        anchors.right: statusText.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        // Empty rather than just hidden, so it takes no room when absent.
        text: row.signedIn ? "SIGN-IN" : ""
        color: row.dim
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
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

    // Line two: a mini meter per window, lined up under the name.
    Row {
      x: nameText.x
      width: parent.width - x
      spacing: Style.space(12)
      visible: row.account && row.account.windows.length > 0

      Repeater {
        // Counted, not the array itself: a new array would rebuild every row.
        model: row.windows.length
        Row {
          required property int index
          // The row stays put across refreshes; only what it shows changes.
          readonly property var modelData: row.windows[index] || ({ short: "", percent: 0, started: false, resetMs: -1 })
          spacing: Style.space(5)
          width: (parent.width - Style.space(12) * Math.max(0, (row.account.windows.length - 1))) / Math.max(1, row.account.windows.length)

          Text {
            id: shortLabel
            width: Style.space(18)
            text: modelData.short
            color: row.dim
            font.family: row.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
          Meter {
            id: mini
            width: Math.max(Style.space(24), parent.width - shortLabel.width - pct.width - resetText.width - Style.space(15))
            thickness: Style.space(3)
            value: modelData.started ? modelData.percent : 0
            graded: true
            foreground: row.foreground
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            id: pct
            width: Style.space(30)
            horizontalAlignment: Text.AlignRight
            text: Math.round((modelData.started ? modelData.percent : 0) * 100) + "%"
            color: modelData.started ? mini.usageColor(modelData.percent) : row.dim
            font.family: row.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            id: resetText
            width: Style.space(46)
            text: modelData.started ? A.formatDuration(modelData.resetMs) : "idle"
            color: row.dim
            font.family: row.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }

    Text {
      visible: !!row.account && row.account.windows.length === 0 && row.account.note !== ""
      x: nameText.x
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
    cursorShape: row.kickable && row.selectable ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (row.kickable && row.selectable) row.toggled()
  }

  PanelToolTip {
    visible: area.containsMouse && row.tooltip !== ""
    text: row.tooltip
    fontFamily: row.fontFamily
  }
}
