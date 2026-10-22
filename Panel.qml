import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "components"
import "Analytics.js" as A

// The bar button and its popup. The popup has two pages: a glance that
// needs no interaction, and a details report one step away. This file only
// owns state, keyboard, IPC and the page switch; the pages draw themselves.
Panel {
  id: root
  moduleName: "omarchy.agents"
  ipcTarget: "omarchy.agents"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color surface: Color.popups.background

  readonly property var providers: usage.enabledProviders
  // The selection follows the provider, not its slot, so an agent whose
  // first scan lands while the panel is open does not swap what you read.
  property string selectedProviderId: ""
  readonly property int providerIndex: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === selectedProviderId) return i
    return 0
  }
  readonly property var provider: providers.length > 0 ? providers[providerIndex] : null

  property string page: "glance"
  property string periodKind: "7d"
  property int periodOffset: 0
  property string customStart: ""
  property string customEnd: ""
  property string expandedSessionId: ""

  // Countdowns and "today" read this clock, so a panel left open keeps
  // telling the truth, across midnight too.
  property double nowMs: Date.now()
  readonly property string todayIso: {
    var d = new Date(nowMs)
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0")
  }

  readonly property string glancePeriod: {
    var value = String(setting("glancePeriod", "Today")).toLowerCase()
    return ["today", "7d", "30d", "cycle"].indexOf(value) >= 0 ? value : "today"
  }
  readonly property bool showAccount: setting("showAccount", true) !== false

  property var publishedPricing: ({})
  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
      + "/omarchy/agents/api-pricing.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.publishedPricing = JSON.parse(text()).models || ({}) }
      catch (error) { root.publishedPricing = ({}) }
    }
  }

  // The bar shows the session and weekly windows of the selected agent.
  readonly property var barLimits: {
    var windows = A.limitWindows(provider), session = null, weekly = null
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].title === "Session" && !session) session = windows[i]
      if (windows[i].title === "Weekly" && !weekly) weekly = windows[i]
    }
    return [session, weekly].filter(function(w) { return w !== null })
  }

  function usageColor(value) {
    if (!isFinite(value) || value < 0) return root.foreground
    if (value >= 0.95) return "#f7768e"
    if (value >= 0.90) return "#ff9e64"
    if (value >= 0.75) return "#e0af68"
    if (value >= 0.50) return "#c0ca75"
    if (value >= 0.25) return "#73daca"
    return "#9ece6a"
  }

  function selectProvider(index) {
    if (providers.length === 0) return
    var wrapped = ((index % providers.length) + providers.length) % providers.length
    selectedProviderId = providers[wrapped].providerId
    expandedSessionId = ""
  }

  function refreshNow() {
    nowMs = Date.now()
    usage.refreshProvider(provider ? provider.providerId : "")
  }

  function showDetails() {
    page = "details"
    flick.contentY = 0
  }

  function showGlance() {
    page = "glance"
    flick.contentY = 0
    keyCatcher.forceActiveFocus()
  }

  function pickPeriod(kind) {
    keyCatcher.forceActiveFocus()
    periodKind = kind
    periodOffset = 0
    if (kind === "custom" && customStart === "") {
      customEnd = todayIso
      var start = new Date(nowMs); start.setDate(start.getDate() - 29)
      customStart = start.getFullYear() + "-" + String(start.getMonth() + 1).padStart(2, "0")
        + "-" + String(start.getDate()).padStart(2, "0")
    }
  }

  function stepPeriod(delta) {
    var range = A.resolvePeriod(periodKind, periodOffset, todayIso, provider ? provider.subscriptionEndsAt : "", customStart, customEnd)
    if (range.kind !== periodKind) { periodKind = range.kind; periodOffset = 0 }
    if (delta < 0 && range.canStepBack) periodOffset--
    if (delta > 0 && range.canStepForward) periodOffset = Math.min(0, periodOffset + 1)
  }

  function scrollBy(steps) {
    flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + steps * Style.space(56)))
  }

  visible: providers.length > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      nowMs = Date.now()
      usage.refreshLimits()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      page = "glance"
      flick.contentY = 0
    }
  }

  Main {
    id: usage
    settings: root.settings
  }

  Timer {
    interval: 1000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function next(): string { root.selectProvider(root.providerIndex + 1); return "ok" }
    function details(): void { root.open(); root.showDetails() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󱚣"
    labelVisible: false
    fixedWidth: barContent.implicitWidth + Style.space(8)
    tooltipText: {
      var lines = [root.provider ? root.provider.providerName : "Agents"]
      for (var i = 0; i < root.barLimits.length; i++)
        lines.push(root.barLimits[i].title + ": " + Math.round(root.barLimits[i].percent * 100) + "% used")
      if (!root.barLimits.length) lines.push("Limits unavailable")
      if (usage.refreshing) lines.push("Refreshing usage…")
      if (usage.refreshFailed || (root.provider && root.provider.limitsStale))
        lines.push("Refresh failed — showing last known limits (stale)")
      if (root.provider && root.provider.usageStatusText) lines.push(root.provider.usageStatusText)
      lines.push("Left-click: open · Right-click: refresh")
      return lines.join("\n")
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refreshNow()
      else if (buttonCode === Qt.LeftButton) root.toggle()
    }

    Row {
      id: barContent
      anchors.centerIn: parent
      spacing: Style.space(5)

      ProviderMark {
        size: Style.bar.iconCanvas
        anchors.verticalCenter: parent.verticalCenter
        providerId: root.provider ? root.provider.providerId : ""
        surface: Color.bar.background
        fallbackText: button.text
        foreground: root.foreground
        fontFamily: root.fontFamily
      }
      Repeater {
        model: root.barLimits.length ? root.barLimits : [{ percent: -1 }]
        delegate: Row {
          required property var modelData
          required property int index
          spacing: Style.space(5)
          Text {
            visible: index > 0
            text: "|"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: button.fontSize
          }
          Text {
            text: modelData.percent >= 0 ? Math.round(modelData.percent * 100) + "%" : "—"
            color: root.usageColor(modelData.percent)
            font.family: root.fontFamily
            font.pixelSize: button.fontSize
          }
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(
      (root.page === "glance" ? glance.implicitHeight : details.implicitHeight) + Style.space(2), Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.page === "details" && details.editing

      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.page === "glance" ? root.selectProvider(root.providerIndex + dx) : root.stepPeriod(dx)
        if (dy !== 0) root.scrollBy(dy)
      }
      onActivateRequested: if (root.page === "glance") root.showDetails()
      onCloseRequested: root.page === "details" ? root.showGlance() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshNow()
        else if (root.page === "details" && (t === "\b" || t === "\x7f")) root.showGlance()
        else if (root.page === "details" && t >= "1" && t <= "9" && Number(t) <= details.pills.length)
          root.pickPeriod(details.pills[Number(t) - 1].kind)
      }

      Text {
        visible: root.providers.length === 0
        anchors.centerIn: parent
        width: parent.width
        text: "No AI coding subscriptions found.\nAgents show up here once you've used them."
        color: Qt.darker(root.foreground, 1.55)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: root.page === "glance" ? glance.implicitHeight : details.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        // Both pages sit side by side; switching slides one in.
        Item {
          id: pages
          width: flick.width
          height: flick.contentHeight
          x: root.page === "glance" ? 0 : -flick.width
          Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

          GlanceView {
            id: glance
            width: flick.width
            visible: root.page === "glance" || pages.x !== -flick.width
            provider: root.provider
            providers: root.providers
            selectedIndex: root.providerIndex
            published: root.publishedPricing
            todayIso: root.todayIso
            nowMs: root.nowMs
            glancePeriod: root.glancePeriod
            showAccount: root.showAccount
            refreshing: usage.refreshing
            fallbackGlyph: button.text
            footer: usage.syncStatusText
            surface: root.surface
            foreground: root.foreground
            fontFamily: root.fontFamily
            friendlyModelName: usage.friendlyModelName
            onProviderPicked: function(index) { root.selectProvider(index) }
            onRefreshRequested: root.refreshNow()
            onDetailsRequested: root.showDetails()
          }

          DetailsView {
            id: details
            x: flick.width
            width: flick.width
            visible: root.page === "details" || pages.x !== 0
            provider: root.provider
            published: root.publishedPricing
            todayIso: root.todayIso
            nowMs: root.nowMs
            periodKind: root.periodKind
            periodOffset: root.periodOffset
            customStart: root.customStart
            customEnd: root.customEnd
            expandedSessionId: root.expandedSessionId
            refreshing: usage.refreshing
            foreground: root.foreground
            fontFamily: root.fontFamily
            friendlyModelName: usage.friendlyModelName
            onBackRequested: root.showGlance()
            onPeriodPicked: function(kind) { root.pickPeriod(kind) }
            onStepRequested: function(delta) { root.stepPeriod(delta) }
            onCustomChanged: function(start, end) {
              root.customStart = start
              root.customEnd = end
              keyCatcher.forceActiveFocus()
            }
            onSessionToggled: function(id) { root.expandedSessionId = root.expandedSessionId === id ? "" : id }
            onRefreshRequested: root.refreshNow()
          }
        }
      }
    }
  }
}
