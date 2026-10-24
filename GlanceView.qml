import QtQuick
import qs.Commons
import qs.Ui
import "components"
import "Analytics.js" as A

// The first screen: who and which agent, how much of each limit is used,
// and the chosen period's tokens and cost. No control stands between the
// panel opening and these numbers; everything deeper is one "Details ›".
Column {
  id: glance
  property var provider: null
  property var providers: []
  property int selectedIndex: 0
  property var published: ({})
  property string todayIso: ""
  property real nowMs: 0
  property string glancePeriod: "today"
  property bool showAccount: true
  property real inUseMs: 180000
  property string fallbackGlyph: ""
  property string footer: ""
  property color surface: Color.background
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property var friendlyModelName: function(id) { return id }
  property var kicker: null
  property var kickSelection: ({})
  property var expandedTiers: ({})
  signal providerPicked(int index)
  signal detailsRequested()
  signal accountToggled(string id)
  signal kickRequested()
  signal kickSelectionCleared()
  signal tierToggled(int priority, bool expanded)

  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property var limits: A.limitWindows(provider)
  readonly property var poolSummary: provider && provider.pool ? A.poolSummary(provider.pool, nowMs, inUseMs) : null
  readonly property var renewal: provider ? String(provider.subscriptionEndsAt || "") : ""
  readonly property var range: {
    var r = A.periodRange(glancePeriod, 0, todayIso, renewal, "", "")
    return r.available ? r : A.periodRange("today", 0, todayIso, renewal, "", "")
  }
  readonly property var days: provider ? A.daysInRange(provider.dailyUsage || [], range) : []
  readonly property bool pricedProvider: A.providerPriced(provider, published)
  readonly property var stats: A.summary(days, range, todayIso, published, pricedProvider)
  readonly property var week: A.periodRange("7d", 0, todayIso, "", "", "")
  readonly property var weekBuckets: provider
    ? A.chartBuckets(A.daysInRange(provider.dailyUsage || [], week), week, todayIso, published, 3) : []
  readonly property string accountLine: {
    if (!provider) return ""
    var parts = []
    if (provider.pooled && poolSummary.single)
      parts.push((showAccount ? poolSummary.only.email : "1 account") + " via CPAMC")
    else if (provider.pooled) parts.push(poolSummary.total + " accounts via CPAMC")
    else if (showAccount && String(provider.accountLabel || "") !== "") parts.push(provider.accountLabel)
    if (provider.syncEnabled && provider.syncDeviceCount > 0)
      parts.push(provider.syncDeviceCount + (provider.syncDeviceCount === 1 ? " device" : " devices"))
    return parts.join(" · ")
  }

  spacing: Style.spacing.lg

  // ---------- Header: mark · name / account / plan · chips
  Item {
    width: parent.width
    implicitHeight: Math.max(identity.implicitHeight, controls.implicitHeight)

    ProviderMark {
      id: mark
      size: Style.font.display
      providerId: glance.provider ? glance.provider.providerId : ""
      surface: glance.surface
      fallbackText: glance.fallbackGlyph
      foreground: glance.foreground
      fontFamily: glance.fontFamily
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.topMargin: Style.space(2)
    }

    Column {
      id: identity
      anchors.left: mark.right
      anchors.leftMargin: Style.space(12)
      anchors.right: controls.left
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(1)

      Text {
        width: parent.width
        text: glance.provider ? glance.provider.providerName : ""
        color: glance.foreground
        font.family: glance.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        visible: text !== ""
        width: parent.width
        text: glance.accountLine
        color: glance.dim
        font.family: glance.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
      }
      Text {
        visible: text !== ""
        width: parent.width
        text: (glance.provider && glance.provider.pooled ? A.poolPlanLine(glance.provider.pool, glance.nowMs)
          : A.planLine(glance.provider, glance.nowMs)).toUpperCase()
        color: glance.provider && String(glance.provider.usageStatusText || "") !== "" ? Color.urgent : glance.dim
        font.family: glance.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
        elide: Text.ElideRight
      }
    }

    Row {
      id: controls
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(8)

      ProviderChips {
        providers: glance.providers
        selectedIndex: glance.selectedIndex
        surface: glance.surface
        fallbackText: glance.fallbackGlyph
        foreground: glance.foreground
        fontFamily: glance.fontFamily
        onPicked: function(index) { glance.providerPicked(index) }
      }
    }
  }

  // ---------- Auth/endpoint trouble
  BorderSurface {
    visible: !!glance.provider && String(glance.provider.usageStatusText || "") !== ""
      && String(glance.provider.authHelpText || "") !== ""
    width: parent.width
    implicitHeight: help.implicitHeight + Style.spacing.xl * 2
    color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.10)
    borderSpec: Border.flat(Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.35), 1)
    radius: Style.cornerRadius
    Text {
      id: help
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      text: glance.provider ? String(glance.provider.authHelpText || "") : ""
      color: glance.dim
      font.family: glance.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  // ---------- Limits, or the prepaid balance
  Column {
    visible: glance.limits.length > 0 || !!(glance.provider && glance.provider.balance)
    width: parent.width
    spacing: Style.space(12)

    PanelSeparator { foreground: glance.foreground }

    BalanceBlock {
      visible: !!(glance.provider && glance.provider.balance)
      width: parent.width
      balance: glance.provider ? glance.provider.balance : null
      amountText: balance ? A.formatMoney(balance.remaining) : ""
      detail: balance && balance.funded > 0
        ? A.formatMoney(balance.spent) + " spent of " + A.formatMoney(balance.funded) + " funded"
          + (balance.estimated ? " · estimated" : "") : ""
      alarming: !!balance && balance.funded > 0 && balance.remaining / balance.funded <= 0.1
      foreground: glance.foreground
      fontFamily: glance.fontFamily
    }

    Repeater {
      // Counted, not the array itself: a new array would rebuild every row.
      model: glance.limits.length
      LimitRow {
        required property int index
        // The row stays put across refreshes; only what it shows changes.
        readonly property var modelData: glance.limits[index] || null
        width: glance.width
        window: modelData
        pace: A.paceFor(modelData, glance.nowMs)
        detail: A.limitDetail(modelData, glance.nowMs)
        foreground: glance.foreground
        fontFamily: glance.fontFamily
      }
    }

    // Limits refresh on their own; this says how old they are, and why
    // when the provider refused the last check.
    Text {
      visible: text !== "" && glance.limits.length > 0
      width: parent.width
      text: A.limitsFreshness(glance.provider, glance.nowMs)
      // A refused check is routine; numbers older than ten minutes are not.
      color: glance.provider && glance.provider.limitsStale === true
        && glance.nowMs - Number(glance.provider.limitsFetchedAtMs || 0) > 600000 ? Color.urgent : glance.dim
      font.family: glance.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  // ---------- The accounts behind the limits, when CPAMC pools them
  AccountPool {
    visible: !!glance.poolSummary
    width: parent.width
    summary: glance.poolSummary
    nowMs: glance.nowMs
    canKick: !!glance.provider && glance.provider.providerId === "codex"
    kicker: glance.kicker
    selection: glance.kickSelection
    expandedTiers: glance.expandedTiers
    showEmail: glance.showAccount
    inUseMs: glance.inUseMs
    signedInEmail: glance.provider ? String(glance.provider.accountLabel || "") : ""
    agentName: glance.provider ? glance.provider.providerName : ""
    foreground: glance.foreground
    fontFamily: glance.fontFamily
    onToggled: function(id) { glance.accountToggled(id) }
    onKickRequested: glance.kickRequested()
    onSelectionCleared: glance.kickSelectionCleared()
    onTierToggled: function(priority, expanded) { glance.tierToggled(priority, expanded) }
  }

  // ---------- The period's figures
  Column {
    visible: !!glance.provider
    width: parent.width
    spacing: Style.space(10)

    PanelSeparator { foreground: glance.foreground }

    PanelSectionHeader {
      text: glance.range.label.toUpperCase()
      foreground: glance.foreground
      fontFamily: glance.fontFamily
    }

    Item {
      width: parent.width
      implicitHeight: tokensFigure.implicitHeight

      Text {
        id: tokensFigure
        text: A.formatTokens(glance.stats.tokens)
        color: glance.foreground
        font.family: glance.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
      }
      Text {
        text: "tokens"
        color: glance.dim
        font.family: glance.fontFamily
        font.pixelSize: Style.font.caption
        anchors.left: tokensFigure.right
        anchors.leftMargin: Style.space(6)
        anchors.baseline: tokensFigure.baseline
      }
      Text {
        visible: glance.stats.cost >= 0
        text: A.formatMoney(glance.stats.cost)
        color: glance.foreground
        font.family: glance.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
        anchors.right: parent.right
        anchors.baseline: tokensFigure.baseline
      }
    }

    ColumnChart {
      width: parent.width
      chartHeight: Style.space(30)
      stacked: false
      buckets: glance.weekBuckets
      rightLabel: "Today"
      tooltipFor: function(b) {
        var text = b.label + " " + b.first.slice(5).replace("-", "/") + " · " + A.formatTokens(b.tokens) + " tokens"
          + (glance.pricedProvider ? " · " + A.formatMoney(b.cost) : "")
        // Prompt and session counts only exist for today, and billing-API
        // agents never count them.
        if (b.isToday && glance.provider && glance.provider.hasPromptStats !== false)
          text += "\n" + Number(glance.provider.todayPrompts || 0) + " prompts · "
            + Number(glance.provider.todaySessions || 0) + " sessions"
        return text
      }
      foreground: glance.foreground
      fontFamily: glance.fontFamily
    }
  }

  // ---------- Way in to the details
  Column {
    visible: !!glance.provider
    width: parent.width
    spacing: Style.space(10)

    PanelSeparator { foreground: glance.foreground }

    Item {
      width: parent.width
      implicitHeight: detailsLink.implicitHeight + Style.space(4)

      Rectangle {
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        radius: Style.cornerRadius
        color: Qt.rgba(glance.foreground.r, glance.foreground.g, glance.foreground.b, detailsArea.containsMouse ? 0.06 : 0)
      }
      Text {
        id: detailsLink
        text: "Details ›"
        color: Color.accent
        font.family: glance.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        text: "models · sessions · mix"
        color: glance.dim
        font.family: glance.fontFamily
        font.pixelSize: Style.font.caption
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
      MouseArea {
        id: detailsArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: glance.detailsRequested()
      }
    }
  }

  Text {
    visible: text !== ""
    width: parent.width
    text: glance.footer
    color: glance.dim
    font.family: glance.fontFamily
    font.pixelSize: Style.font.caption
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
  }
}
