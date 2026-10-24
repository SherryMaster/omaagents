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
  moduleName: "io.github.sherrymaster.omaagents"
  ipcTarget: "omaagents"
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
  property var kickSelection: ({})
  property var expandedTiers: ({})

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
  readonly property real inUseMs: Math.max(1, Number(setting("inUseMinutes", 3)) || 3) * 60000

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
    var picked = [session, weekly].filter(function(w) { return w !== null })
    // A pool of monthly-window accounts (Free only) has neither; show its own.
    return picked.length ? picked : windows.slice(0, 2)
  }

  // What the bar prints: the limits, or one dash when there are none.
  readonly property var barSlots: barLimits.length ? barLimits : [{ percent: -1 }]

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
    kickSelection = ({})
  }

  // The kick tool for an agent, or null when it has none.
  function kickerFor(id) {
    return id === "codex" ? codexKicker : id === "claude" ? claudeKicker : null
  }

  // Kicks the selected idle accounts, or every idle one when none is picked.
  // Only accounts the panel shows as idle are ever sent.
  function kickAccounts() {
    var kicker = provider ? kickerFor(provider.providerId) : null
    if (!kicker || !provider.pool || !kicker.ready || kicker.running) return
    var idle = A.poolSummary(provider.pool, Date.now(), inUseMs).kickable
    var chosen = idle.filter(function(a) { return root.kickSelection[a.id] === true })
    if (chosen.length === 0) chosen = idle
    if (chosen.length === 0) return
    kicker.kick(chosen.map(function(a) { return a.email }), chosen.map(function(a) { return a.id }))
    kickSelection = ({})
  }

  function toggleKickSelection(id) {
    var next = Object.assign({}, kickSelection)
    if (next[id]) delete next[id]
    else next[id] = true
    kickSelection = next
  }

  // Background passes run all the time; only a refresh someone asked for
  // is worth a "Refreshing…" line.
  property double manualRefreshAtMs: 0
  function refreshNow() {
    nowMs = Date.now()
    manualRefreshAtMs = nowMs
    usage.refreshProvider(provider ? provider.providerId : "")
  }

  readonly property bool refreshing: provider ? usage.isRefreshing(provider.providerId) : false

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
      codexKicker.probe()
      claudeKicker.probe()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      page = "glance"
      flick.contentY = 0
    }
  }

  Main {
    id: usage
    settings: root.settings
    panelOpen: root.opened
  }

  // These live outside the popup so a kick finishes even if the panel closes.
  KickRunner {
    id: codexKicker
    provider: "codex"
    onKicked: usage.refreshProvider("codex")
  }
  KickRunner {
    id: claudeKicker
    provider: "claude"
    onKicked: usage.refreshProvider("claude")
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
    function kick(): string {
      var kicker = root.provider ? root.kickerFor(root.provider.providerId) : null
      if (!kicker) return "no kick tool for this agent"
      root.kickAccounts()
      return kicker.ready ? "ok" : kicker.unavailableReason
    }
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
      var pool = root.provider && root.provider.pooled ? A.poolSummary(root.provider.pool, Date.now(), root.inUseMs) : null
      if (pool) lines[0] += pool.single ? " · via CPAMC" : " · pool of " + pool.total + " via CPAMC"
      for (var i = 0; i < root.barLimits.length; i++)
        lines.push(root.barLimits[i].title + ": " + Math.round(root.barLimits[i].percent * 100) + "% used"
          + (root.barLimits[i].pool ? " (" + A.poolDetail(root.barLimits[i], Date.now()).split(" · ")[0] + ")" : ""))
      if (pool) {
        for (var t = 1; t < pool.tiers.length; t++)
          lines.push("Overflow: " + pool.tiers[t].open + "/" + pool.tiers[t].total + " " + pool.tiers[t].label + " open")
        var busy = pool.accounts.filter(function(a) { return a.status === "running" }).length
        if (!pool.single) lines.push(busy + " in use now")
        if (pool.kickable.length) lines.push(pool.kickable.length + " not started — kick from the panel (Shift+K)")
      }
      if (!root.barLimits.length) lines.push("Limits unavailable")
      if (root.refreshing && Date.now() - root.manualRefreshAtMs < 20000) lines.push("Refreshing usage…")
      var freshness = A.limitsFreshness(root.provider, Date.now())
      if (freshness !== "") lines.push(freshness)
      else if (root.provider && (root.provider.limitsStale || usage.refreshFailed(root.provider.providerId)))
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
        // Counted, not the array itself: a new array would rebuild every row.
        model: root.barSlots.length
        delegate: Row {
          // The row stays put across refreshes; only what it shows changes.
          readonly property var modelData: root.barSlots[index] || ({ percent: -1 })
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

      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.page === "glance" ? root.selectProvider(root.providerIndex + dx) : root.stepPeriod(dx)
        if (dy !== 0) root.scrollBy(dy)
      }
      onActivateRequested: if (root.page === "glance") root.showDetails()
      onCloseRequested: root.page === "details" ? root.showGlance() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshNow()
        // Plain k scrolls (the shell's vim keys), so the kick is Shift+K.
        else if (t === "K" && root.page === "glance") root.kickAccounts()
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
            inUseMs: root.inUseMs
            fallbackGlyph: button.text
            footer: usage.syncStatusText
            surface: root.surface
            foreground: root.foreground
            fontFamily: root.fontFamily
            friendlyModelName: usage.friendlyModelName
            kicker: root.provider ? root.kickerFor(root.provider.providerId) : null
            kickSelection: root.kickSelection
            expandedTiers: root.expandedTiers
            onProviderPicked: function(index) { root.selectProvider(index) }
            onDetailsRequested: root.showDetails()
            onAccountToggled: function(id) { root.toggleKickSelection(id) }
            onKickRequested: root.kickAccounts()
            onKickSelectionCleared: root.kickSelection = ({})
            onTierToggled: function(priority, expanded) {
              var next = Object.assign({}, root.expandedTiers)
              next[priority] = expanded
              root.expandedTiers = next
            }
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
          }
        }
      }
    }
  }
}
