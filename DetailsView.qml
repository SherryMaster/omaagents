import QtQuick
import qs.Commons
import qs.Ui
import "components"
import "Analytics.js" as A

// One scrolling report for one period: pick the period once and every
// section follows it, with cost and tokens side by side throughout.
Column {
  id: details
  property var provider: null
  property var published: ({})
  property string todayIso: ""
  property real nowMs: 0
  property string periodKind: "7d"
  property int periodOffset: 0
  property string customStart: ""
  property string customEnd: ""
  property string expandedSessionId: ""
  property bool refreshing: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property var friendlyModelName: function(id) { return id }
  signal backRequested()
  signal periodPicked(string kind)
  signal stepRequested(int delta)
  signal customChanged(string start, string end)
  signal sessionToggled(string id)
  signal refreshRequested()

  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string renewal: provider ? String(provider.subscriptionEndsAt || "") : ""
  readonly property bool cycleAvailable: A.periodRange("cycle", 0, todayIso, renewal, "", "").available
  readonly property var range: A.resolvePeriod(periodKind, periodOffset, todayIso, renewal, customStart, customEnd)
  readonly property bool pricedProvider: A.providerPriced(provider, published)
  readonly property var days: provider ? A.daysInRange(provider.dailyUsage || [], range) : []
  readonly property var stats: A.summary(days, range, todayIso, published, pricedProvider)
  // A date field has focus: the panel's key handler must let typing through.
  readonly property bool editing: startField.activeFocus || endField.activeFocus
  readonly property var buckets: A.chartBuckets(days, range, todayIso, published, 3)
  readonly property var models: A.modelRows(A.sumUsage(days), published)
  readonly property var chartModels: {
    var names = []
    for (var i = 0; i < Math.min(3, models.length); i++) names.push(models[i].id)
    return names
  }
  readonly property var sessions: provider ? A.sessionRows(provider.recentSessions || [], range, published, 5) : []
  readonly property string unit: buckets.length ? buckets[0].unit.toUpperCase() : "DAY"
  readonly property var pills: {
    var out = [{ kind: "today", label: "Today" }, { kind: "7d", label: "7D" }, { kind: "30d", label: "30D" }]
    if (cycleAvailable) out.push({ kind: "cycle", label: "Cycle" })
    out.push({ kind: "all", label: "All" }, { kind: "custom", label: "…" })
    return out
  }

  function money(value) { return A.formatMoney(value) }
  function shortDay(iso) {
    var d = new Date(iso + "T00:00:00")
    return isNaN(d.getTime()) ? iso : d.toLocaleDateString(Qt.locale(), "ddd MMM d")
  }

  spacing: Style.spacing.lg

  // ---------- Header
  Item {
    width: parent.width
    implicitHeight: Math.max(backText.implicitHeight, refresh.height)

    Text {
      id: backText
      text: "‹  " + (details.provider ? details.provider.providerName : "") + " "
      color: Color.accent
      font.family: details.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
      anchors.verticalCenter: parent.verticalCenter
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: details.backRequested()
      }
    }
    Text {
      text: "details"
      color: details.dim
      font.family: details.fontFamily
      font.pixelSize: Style.font.title
      anchors.left: backText.right
      anchors.baseline: backText.baseline
    }
    RefreshButton {
      id: refresh
      anchors.right: parent.right
      busy: details.refreshing
      foreground: details.foreground
      fontFamily: details.fontFamily
      onTriggered: details.refreshRequested()
    }
  }

  // ---------- Period: one row of pills, one range line
  Column {
    width: parent.width
    spacing: Style.space(8)

    Row {
      id: pillRow
      width: parent.width
      spacing: Style.space(4)
      Repeater {
        model: details.pills
        Button {
          required property var modelData
          required property int index
          width: (pillRow.width - pillRow.spacing * (details.pills.length - 1)) / details.pills.length
          text: modelData.label
          tooltipText: modelData.kind === "custom" ? "Custom range" : ""
          selected: details.range.kind === modelData.kind
          bordered: true
          foreground: details.foreground
          fontFamily: details.fontFamily
          fontSize: Style.font.caption
          verticalPadding: Style.space(4)
          onClicked: details.periodPicked(modelData.kind)
        }
      }
    }

    Item {
      width: parent.width
      implicitHeight: Style.space(22)

      Text {
        id: stepBack
        visible: details.range.canStepBack
        text: "‹"
        color: details.foreground
        font.family: details.fontFamily
        font.pixelSize: Style.font.title
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: details.stepRequested(-1) }
      }
      Text {
        visible: details.range.kind !== "custom"
        text: details.range.label
        color: details.foreground
        font.family: details.fontFamily
        font.pixelSize: Style.font.bodySmall
        anchors.centerIn: parent
      }
      Text {
        visible: details.range.canStepBack
        text: "›"
        opacity: details.range.canStepForward ? 1 : 0.3
        color: details.foreground
        font.family: details.fontFamily
        font.pixelSize: Style.font.title
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        MouseArea {
          anchors.fill: parent; anchors.margins: -6
          enabled: details.range.canStepForward
          cursorShape: Qt.PointingHandCursor
          onClicked: details.stepRequested(1)
        }
      }

      // Custom: the range line becomes its own two date fields. They are
      // fixed items, not a Repeater, so committing a date never destroys
      // the field that holds focus.
      Row {
        visible: details.range.kind === "custom"
        anchors.fill: parent
        spacing: Style.space(8)
        TextField {
          id: startField
          width: (parent.width - parent.spacing) / 2
          height: parent.height
          text: details.customStart
          inputMask: "9999-99-99"
          foreground: details.foreground
          font.family: details.fontFamily
          font.pixelSize: Style.font.caption
          verticalPadding: 0
          onEditingFinished: details.customChanged(text, details.customEnd)
        }
        TextField {
          id: endField
          width: (parent.width - parent.spacing) / 2
          height: parent.height
          text: details.customEnd
          inputMask: "9999-99-99"
          foreground: details.foreground
          font.family: details.fontFamily
          font.pixelSize: Style.font.caption
          verticalPadding: 0
          onEditingFinished: details.customChanged(details.customStart, text)
        }
      }
    }
  }

  // ---------- KPIs
  Grid {
    id: tiles
    width: parent.width
    columns: 2
    columnSpacing: Style.space(6)
    rowSpacing: Style.space(6)

    readonly property real cellWidth: (width - columnSpacing) / 2

    StatTile {
      width: tiles.cellWidth
      label: "Cost · API equivalent"
      value: details.money(details.stats.cost)
      detail: details.stats.unpricedModels > 0 ? details.stats.unpricedModels + " unpriced excluded" : ""
      foreground: details.foreground
      fontFamily: details.fontFamily
    }
    StatTile {
      width: tiles.cellWidth
      label: "Tokens"
      value: A.formatTokens(details.stats.tokens)
      detail: details.stats.activeDays + (details.stats.activeDays === 1 ? " active day" : " active days")
      foreground: details.foreground
      fontFamily: details.fontFamily
    }
    StatTile {
      width: tiles.cellWidth
      label: "Daily average"
      value: details.stats.activeDays === 0 ? "—"
        : (details.stats.priced ? details.money(details.stats.avgCost) : A.formatTokens(details.stats.avgTokens))
      detail: {
        var s = details.stats
        if (s.projectionDate !== "")
          return "proj. " + (s.priced ? details.money(s.projection) : A.formatTokens(s.projectionTokens))
            + " by " + details.shortDay(s.projectionDate).replace(/^\w+ /, "")
        if (s.peak)
          return "peak " + details.shortDay(s.peak.date).split(" ")[0] + " "
            + (s.priced ? details.money(s.peak.cost) : A.formatTokens(s.peak.tokens))
        return ""
      }
      foreground: details.foreground
      fontFamily: details.fontFamily
    }
    StatTile {
      width: tiles.cellWidth
      label: "Cache hit"
      value: details.stats.hitRate >= 0 ? Math.round(details.stats.hitRate * 100) + "%" : "—"
      detail: details.stats.savings >= 0 ? details.money(details.stats.savings) + " saved" : "of prompt tokens"
      foreground: details.foreground
      fontFamily: details.fontFamily
    }
  }

  // ---------- Timeline
  Section {
    title: "BY " + details.unit
    note: details.chartModels.length > 1 ? "stacked by model" : ""
    ColumnChart {
      width: details.width
      buckets: details.buckets
      models: details.chartModels
      useCost: details.stats.priced
      leftLabel: details.buckets.length ? details.buckets[0].label : ""
      rightLabel: details.buckets.length ? details.buckets[details.buckets.length - 1].label : ""
      tooltipFor: function(b) {
        var head = (b.first === b.last ? details.shortDay(b.first) : details.shortDay(b.first) + " – " + details.shortDay(b.last))
          + "\n" + A.formatTokens(b.tokens) + " tokens" + (details.stats.priced ? " · " + A.formatMoney(b.cost) : "")
        var lines = b.segments.map(function(s) {
          return (s.model === "other" ? "Other" : details.friendlyModelName(s.model)) + "  "
            + A.formatTokens(s.tokens) + (details.stats.priced ? " · " + A.formatMoney(s.cost) : "")
        })
        return lines.length > 1 ? head + "\n" + lines.join("\n") : head
      }
      foreground: details.foreground
      fontFamily: details.fontFamily
    }
  }

  // ---------- Models
  Section {
    visible: details.models.length > 0
    title: "MODELS"
    note: "cost · tokens"
    Repeater {
      model: details.models
      ModelRow {
        required property var modelData
        width: details.width
        row: modelData
        name: details.friendlyModelName(modelData.id)
        foreground: details.foreground
        fontFamily: details.fontFamily
      }
    }
  }

  // ---------- Mix
  Section {
    visible: details.stats.tokens > 0
    title: "MIX"
    note: details.stats.priced ? "of cost" : "of tokens"
    MixBar {
      width: details.width
      rows: details.stats.mix
      priced: details.stats.priced
      foreground: details.foreground
      fontFamily: details.fontFamily
    }
  }

  // ---------- Sessions
  Section {
    visible: details.sessions.length > 0
    title: "SESSIONS"
    note: "latest " + details.sessions.length
    Repeater {
      model: details.sessions
      SessionRow {
        required property var modelData
        width: details.width
        row: modelData
        expanded: details.expandedSessionId === modelData.id
        nameFor: details.friendlyModelName
        foreground: details.foreground
        fontFamily: details.fontFamily
        onToggled: details.sessionToggled(modelData.id)
      }
    }
  }

  Text {
    visible: details.stats.tokens === 0
    width: parent.width
    text: "No usage in this period."
    color: details.dim
    font.family: details.fontFamily
    font.pixelSize: Style.font.caption
    horizontalAlignment: Text.AlignHCenter
  }

  // A titled block: small caps title, a dim note on the right, then content.
  component Section: Column {
    id: section
    property string title: ""
    property string note: ""
    default property alias content: body.data
    width: details.width
    spacing: Style.space(8)

    Item {
      width: parent.width
      implicitHeight: heading.implicitHeight
      PanelSectionHeader {
        id: heading
        text: section.title
        foreground: details.foreground
        fontFamily: details.fontFamily
      }
      Text {
        text: section.note
        color: details.dim
        font.family: details.fontFamily
        font.pixelSize: Style.font.caption
        anchors.right: parent.right
        anchors.verticalCenter: heading.verticalCenter
      }
    }
    Column {
      id: body
      width: parent.width
      spacing: Style.space(8)
    }
  }
}
