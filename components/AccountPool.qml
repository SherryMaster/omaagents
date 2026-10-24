import QtQuick
import qs.Commons
import qs.Ui
import "../Analytics.js" as A

// Every account CPAMC holds for the agent, grouped into routing tiers. The
// first tier (the one serving requests) is open; overflow tiers fold into a
// one-line summary until asked for. One action bar kicks either the selected
// accounts or every idle one, and says why when it can't.
Column {
  id: pool
  property var summary: null
  property real nowMs: 0
  property bool canKick: false          // this agent's accounts are kickable at all
  property var kicker: null             // KickRunner
  property var selection: ({})          // account id -> true
  property var expandedTiers: ({})      // priority -> bool
  property bool showEmail: true
  property real inUseMs: 180000
  property string signedInEmail: ""
  property string agentName: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal toggled(string id)
  signal kickRequested()
  signal selectionCleared()
  signal tierToggled(int priority, bool expanded)

  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property var tiers: summary ? summary.tiers : []
  readonly property bool single: !!summary && summary.single
  // Only idle accounts can be selected; one that started meanwhile drops out.
  readonly property int selectedCount: {
    var n = 0, list = summary ? summary.kickable : []
    for (var i = 0; i < list.length; i++) if (selection[list[i].id]) n++
    return n
  }
  readonly property int idleCount: summary ? summary.kickable.length : 0
  readonly property string blockedReason: !canKick ? "Kicking works for Codex accounts only (it uses codex-kick)."
    : kicker && kicker.unavailableReason !== "" ? kicker.unavailableReason
    : idleCount === 0 ? "Nothing to kick: every account's window has already started."
    : ""

  function tierExpanded(tier, index) {
    var value = expandedTiers[tier.priority]
    return value === undefined ? index === 0 : value === true
  }

  spacing: Style.space(8)

  PanelSeparator { foreground: pool.foreground }

  // ---------- Header and action bar
  Item {
    width: parent.width
    implicitHeight: Math.max(title.implicitHeight, kickButton.implicitHeight)

    Row {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)
      PanelSectionHeader {
        id: title
        text: pool.single ? "ACCOUNT" : "ACCOUNTS"
        foreground: pool.foreground
        fontFamily: pool.fontFamily
      }
      Text {
        anchors.baseline: title.baseline
        text: !pool.summary ? "" : (pool.single ? "" : pool.summary.open + "/" + pool.summary.total + " open · ")
          + (pool.summary.routed ? "CPAMC" : "not routed")
        color: pool.summary && !pool.summary.routed ? "#e0af68" : pool.dim
        font.family: pool.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Button {
        visible: pool.selectedCount > 0 && !(pool.kicker && pool.kicker.running)
        text: "Clear"
        fontSize: Style.font.caption
        foreground: pool.foreground
        fontFamily: pool.fontFamily
        verticalPadding: Style.space(2)
        onClicked: pool.selectionCleared()
      }
      Button {
        id: kickButton
        readonly property bool usable: pool.blockedReason === "" && !(pool.kicker && pool.kicker.running)
        bordered: true
        iconText: pool.kicker && pool.kicker.running ? "󰑓" : "󱐋"
        iconSpinning: !!pool.kicker && pool.kicker.running
        iconSize: Style.font.caption
        text: pool.kicker && pool.kicker.running ? "Kicking…"
          : pool.selectedCount > 0 ? "Kick " + pool.selectedCount + " selected"
          : "Kick" + (pool.idleCount > 0 && !pool.single ? " (" + pool.idleCount + ")" : "")
        fontSize: Style.font.caption
        foreground: pool.foreground
        fontFamily: pool.fontFamily
        verticalPadding: Style.space(2)
        opacity: usable || (pool.kicker && pool.kicker.running) ? 1 : 0.42
        tooltipText: pool.blockedReason !== "" ? pool.blockedReason
          : "Send a one-word request (~25 tokens) to start "
            + (pool.single ? "this account's" : pool.selectedCount > 0 ? "the selected accounts'"
              : "the " + pool.idleCount + " not-started accounts'")
            + " usage window, so it resets sooner. Shortcut: Shift+K"
        onClicked: if (usable) pool.kickRequested()
      }
    }
  }

  Text {
    visible: !!pool.summary && !pool.summary.routed
    width: parent.width
    text: pool.agentName + " isn't routed through CPAMC (" + (pool.summary ? pool.summary.endpoint : "")
      + "), so it doesn't draw from these accounts. The limits above are the signed-in account's."
    color: pool.dim
    font.family: pool.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  // ---------- Tiers
  Repeater {
    // Counted, not the array itself: a new array would rebuild every row.
    model: pool.tiers.length

    Column {
      id: tierBlock
      // The row stays put across refreshes; only what it shows changes.
      readonly property var modelData: pool.tiers[index] || ({ accounts: [], windows: [], plans: [], label: "", open: 0, total: 0, priority: 0 })
      required property int index
      readonly property bool expanded: pool.single || pool.tierExpanded(modelData, index)
      width: pool.width
      spacing: Style.space(2)

      // Tier header: label, open count, and — folded — its pooled meters.
      // With one account to work with there is nothing to group.
      Item {
        visible: !pool.single
        width: parent.width
        implicitHeight: tierLabel.implicitHeight + Style.space(6)

        Rectangle {
          anchors.fill: parent
          anchors.leftMargin: -Style.space(4)
          anchors.rightMargin: -Style.space(4)
          radius: Style.cornerRadius
          color: Qt.rgba(pool.foreground.r, pool.foreground.g, pool.foreground.b, tierArea.containsMouse ? 0.06 : 0)
        }
        Text {
          id: chevron
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(13)
          text: tierBlock.expanded ? "▾" : "▸"
          color: pool.dim
          font.pixelSize: Style.font.caption
        }
        Text {
          id: tierLabel
          anchors.left: chevron.right
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: tierBlock.modelData.label.toUpperCase() + "  " + tierBlock.modelData.open + "/" + tierBlock.modelData.total
            + (tierBlock.index === 0 ? "  serving" : "  overflow")
          color: pool.dim
          font.family: pool.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1
        }
        Row {
          visible: !tierBlock.expanded
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(10)
          Repeater {
            // Counted, not the array itself: a new array would rebuild every row.
            model: tierBlock.modelData.windows.length
            Row {
              required property int index
              // The row stays put across refreshes; only what it shows changes.
              readonly property var modelData: tierBlock.modelData.windows[index] || ({ short: "", percent: 0 })
              spacing: Style.space(4)
              Text {
                text: modelData.short
                color: pool.dim
                font.family: pool.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
              Meter {
                id: tierMeter
                width: Style.space(40)
                thickness: Style.space(3)
                value: modelData.percent
                graded: true
                foreground: pool.foreground
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                text: Math.round(modelData.percent * 100) + "%"
                color: tierMeter.usageColor(modelData.percent)
                font.family: pool.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }
        }
        MouseArea {
          id: tierArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: pool.tierToggled(tierBlock.modelData.priority, !tierBlock.expanded)
        }
      }

      Column {
        visible: tierBlock.expanded
        width: parent.width
        spacing: Style.space(1)
        Repeater {
          // Counted, not the array itself: a new array would rebuild every row.
          model: (tierBlock.expanded ? tierBlock.modelData.accounts : []).length
          AccountRow {
            required property int index
            // The row stays put across refreshes; only what it shows changes.
            readonly property var modelData: (tierBlock.expanded ? tierBlock.modelData.accounts : [])[index] || null
            width: pool.width
            account: modelData
            nowMs: pool.nowMs
            ordinal: pool.summary.accounts.indexOf(modelData) + 1
            showEmail: pool.showEmail
            showPlan: tierBlock.modelData.plans.length > 1
            inUseMs: pool.inUseMs
            selectable: !pool.single
            signedIn: pool.signedInEmail !== "" && modelData.email === pool.signedInEmail
            selected: pool.selection[modelData.id] === true
            kicking: !!pool.kicker && pool.kicker.runningIds[modelData.id] === true
            foreground: pool.foreground
            fontFamily: pool.fontFamily
            onToggled: pool.toggled(modelData.id)
          }
        }
      }
    }
  }

  // ---------- What the last kick did, or why kicking is off
  Text {
    readonly property var result: pool.kicker ? pool.kicker.lastResult : null
    readonly property bool fresh: !!result && pool.nowMs - result.atMs < 120000
    readonly property bool toolProblem: pool.canKick && !!pool.kicker
      && (pool.kicker.toolState === "missing" || pool.kicker.toolState === "broken")
    visible: text !== ""
    width: parent.width
    text: pool.kicker && pool.kicker.running ? "Kicking " + Object.keys(pool.kicker.runningIds).length + " account(s)…"
      : toolProblem ? pool.kicker.unavailableReason
      : fresh ? result.text + " · " + (pool.nowMs - result.atMs < 5000 ? "just now"
          : pool.nowMs - result.atMs < 60000 ? Math.floor((pool.nowMs - result.atMs) / 1000) + "s ago"
          : A.formatDuration(pool.nowMs - result.atMs) + " ago")
      : ""
    color: toolProblem && pool.kicker.toolState === "broken" || fresh && !result.ok ? Color.urgent
      : fresh && result.ok ? "#9ece6a" : pool.dim
    font.family: pool.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }
}
