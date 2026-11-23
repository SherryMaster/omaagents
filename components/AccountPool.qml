import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../Analytics.js" as A

// Every account CPAMC holds for the agent, grouped into routing tiers, then
// the agent's direct sign-ins (accounts it uses by itself, outside CPAMC).
// The first tier (the one serving requests) is open; overflow tiers fold into
// a one-line summary until asked for. Each account folds to one line too
// (folded by default once a group holds more than four), and a long list
// scrolls inside its own box. One action bar kicks either the selected CPAMC
// accounts or every live one, whatever their state, and says why when it can't.
Column {
  id: pool
  property var summary: null
  property real nowMs: 0
  property bool canKick: false          // this agent's accounts are kickable at all
  property var kicker: null             // KickRunner
  property var loginRunner: null        // LoginRunner, shared by every agent
  property string agentId: ""           // codex | claude: what CPAMC calls these accounts
  property var selection: ({})          // account id -> true
  property var expandedTiers: ({})      // priority -> bool
  property var collapsedAccounts: ({})  // account id -> bool
  // Past this height the account list scrolls in place.
  property real maxListHeight: Style.space(330)
  property bool showEmail: true
  property real inUseMs: 180000
  property string agentName: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal toggled(string id)
  signal kickRequested()
  signal selectionCleared()
  signal tierToggled(int priority, bool expanded)
  signal accountCollapseToggled(string id, bool collapsed)

  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property var tiers: summary ? summary.tiers : []
  readonly property var directAccounts: summary ? summary.direct : []
  readonly property bool hasCpamc: !!summary && summary.accounts.length > 0
  readonly property bool single: !!summary && summary.single
  // Any account can be selected, whatever its state.
  readonly property int selectedCount: {
    var n = 0, list = summary ? summary.kickable : []
    for (var i = 0; i < list.length; i++) if (selection[list[i].id]) n++
    return n
  }
  readonly property int liveCount: summary
    ? summary.kickable.filter(function(a) { return a.status !== "disabled" && a.status !== "expired" }).length : 0
  readonly property string blockedReason: !canKick ? "Kicking isn't available for " + agentName + " accounts."
    : kicker && kicker.unavailableReason !== "" ? kicker.unavailableReason
    : ""

  function accountCollapsed(account, groupSize) {
    var value = account ? collapsedAccounts[account.id] : undefined
    return value === undefined ? groupSize > 4 : value === true
  }

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
        text: pool.single && pool.directAccounts.length === 0 ? "ACCOUNT" : "ACCOUNTS"
        foreground: pool.foreground
        fontFamily: pool.fontFamily
      }
      Text {
        anchors.baseline: title.baseline
        text: !pool.summary ? "" : !pool.hasCpamc ? pool.directAccounts.length + " direct"
          : (pool.single ? "" : pool.summary.open + "/" + pool.summary.total + " open · ")
          + (pool.summary.routed ? "CPAMC" : "not routed")
          + (pool.directAccounts.length ? " + " + pool.directAccounts.length + " direct" : "")
        color: pool.summary && pool.hasCpamc && !pool.summary.routed ? "#e0af68" : pool.dim
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
        visible: pool.hasCpamc && pool.canKick
        readonly property bool usable: pool.blockedReason === "" && !(pool.kicker && pool.kicker.running)
        bordered: true
        iconText: pool.kicker && pool.kicker.running ? "󰑓" : "󱐋"
        iconSpinning: !!pool.kicker && pool.kicker.running
        iconSize: Style.font.caption
        text: pool.kicker && pool.kicker.running ? "Kicking…"
          : pool.selectedCount > 0 ? "Kick " + pool.selectedCount + " selected"
          : "Kick" + (pool.liveCount > 0 && !pool.single ? " all (" + pool.liveCount + ")" : "")
        fontSize: Style.font.caption
        foreground: pool.foreground
        fontFamily: pool.fontFamily
        verticalPadding: Style.space(2)
        opacity: usable || (pool.kicker && pool.kicker.running) ? 1 : 0.42
        tooltipText: pool.blockedReason !== "" ? pool.blockedReason
          : "Send a one-word request (~25 tokens) to "
            + (pool.single ? "this account" : pool.selectedCount > 0 ? "the selected accounts"
              : "all " + pool.liveCount + " accounts")
            + ", whatever their state; a window that hasn't started starts counting down. Shortcut: Shift+K"
        onClicked: if (usable) pool.kickRequested()
      }
    }
  }

  Text {
    visible: pool.hasCpamc && !pool.summary.routed
    width: parent.width
    text: pool.agentName + " isn't routed through CPAMC (" + (pool.summary ? pool.summary.endpoint : "")
      + "), so it doesn't draw from these accounts. The limits above are the signed-in account's."
    color: pool.dim
    font.family: pool.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  // ---------- The accounts, scrolling in place once the list grows long
  Flickable {
    id: listFlick
    width: parent.width
    height: Math.min(list.implicitHeight, pool.maxListHeight)
    contentWidth: width
    contentHeight: list.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    interactive: contentHeight > height
    ScrollBar.vertical: ScrollBar { policy: listFlick.interactive ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }

  Column {
    id: list
    // Room for the scrollbar once there is one.
    width: listFlick.width - (listFlick.interactive ? Style.space(10) : 0)
    spacing: Style.space(8)

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
      width: list.width
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
          // A folded tier must not hide a dead login.
          Text {
            readonly property int count: tierBlock.modelData.accounts.filter(function(a) { return a.status === "expired" }).length
            visible: count > 0
            text: "▲ " + count + " to sign in"
            color: Color.urgent
            font.family: pool.fontFamily
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
          Repeater {
            // Counted, not the array itself: a new array would rebuild every row.
            model: tierBlock.modelData.windows.length
            Row {
              required property int index
              // The row stays put across refreshes; only what it shows changes.
              readonly property var modelData: tierBlock.modelData.windows[index] || ({ short: "", percent: 0, pace: -1 })
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
                pace: isFinite(modelData.pace) ? modelData.pace : -1
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
            width: list.width
            account: modelData
            nowMs: pool.nowMs
            ordinal: pool.summary.accounts.indexOf(modelData) + 1
            showEmail: pool.showEmail
            showPlan: tierBlock.modelData.plans.length > 1
            inUseMs: pool.inUseMs
            selectable: !pool.single && pool.canKick
            collapsed: pool.accountCollapsed(modelData, tierBlock.modelData.accounts.length)
            onCollapseToggled: pool.accountCollapseToggled(modelData.id, !collapsed)
            selected: pool.selection[modelData.id] === true
            kicking: !!pool.kicker && pool.kicker.runningIds[modelData.id] === true
            // cpamc-login signs in Codex and Claude accounts.
            canSignIn: !!pool.loginRunner && (pool.agentId === "codex" || pool.agentId === "claude")
            signingIn: !!pool.loginRunner && pool.loginRunner.running
              && pool.loginRunner.provider === pool.agentId && pool.loginRunner.email === modelData.email
            foreground: pool.foreground
            fontFamily: pool.fontFamily
            onToggled: pool.toggled(modelData.id)
            onSignInRequested: {
              var answer = pool.loginRunner.toggle(pool.agentId, modelData.email)
              if (answer !== "ok" && answer !== "cancelled") pool.loginRunner.lastResult = { atMs: Date.now(), ok: false, provider: pool.agentId, text: answer }
            }
          }
        }
      }
    }
  }

  // ---------- Direct sign-ins: accounts the agent uses by itself
  Column {
    visible: pool.directAccounts.length > 0
    width: list.width
    spacing: Style.space(2)

    Item {
      width: parent.width
      implicitHeight: directLabel.implicitHeight + Style.space(6)
      Text {
        id: directLabel
        anchors.left: parent.left
        anchors.leftMargin: Style.space(21)
        anchors.verticalCenter: parent.verticalCenter
        text: "DIRECT  " + pool.directAccounts.length
        color: "#7aa2f7"
        font.family: pool.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1
      }
      Text {
        anchors.left: directLabel.right
        anchors.leftMargin: Style.space(8)
        anchors.right: parent.right
        anchors.baseline: directLabel.baseline
        text: "own sign-in, outside CPAMC"
        color: pool.dim
        font.family: pool.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Repeater {
      // Counted, not the array itself: a new array would rebuild every row.
      model: pool.directAccounts.length
      AccountRow {
        required property int index
        // The row stays put across refreshes; only what it shows changes.
        readonly property var modelData: pool.directAccounts[index] || null
        width: list.width
        account: modelData
        nowMs: pool.nowMs
        ordinal: index + 1
        showEmail: pool.showEmail
        inUseMs: pool.inUseMs
        selectable: false
        collapsed: pool.accountCollapsed(modelData, pool.directAccounts.length)
        onCollapseToggled: pool.accountCollapseToggled(modelData.id, !collapsed)
        foreground: pool.foreground
        fontFamily: pool.fontFamily
      }
    }
  }
  }  // list
  }  // listFlick

  // ---------- What the last sign-in did
  Text {
    readonly property var runner: pool.loginRunner
    readonly property var result: runner ? runner.lastResult : null
    readonly property bool mine: !!runner && (runner.running ? runner.provider === pool.agentId
      : !!result && result.provider === pool.agentId)
    readonly property bool fresh: !!result && pool.nowMs - result.atMs < 120000
    visible: text !== ""
    width: parent.width
    text: !mine ? ""
      : runner.running ? "Signing in " + runner.shortEmail(runner.email) + "… click Continue in the browser window that opened"
      : fresh ? result.text : ""
    color: runner && runner.running ? pool.dim : fresh && result.ok ? "#9ece6a" : Color.urgent
    font.family: pool.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
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
