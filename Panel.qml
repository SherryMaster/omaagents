import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy.agents"
  ipcTarget: "omarchy.agents"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var providers: usage.enabledProviders
  // The selection follows the provider, not the slot it happens to sit in: a
  // provider whose first scan lands while the panel is open would otherwise
  // shift the list underneath you and swap out what you were reading.
  property string selectedProviderId: ""
  readonly property int providerIndex: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === selectedProviderId) return i
    return 0
  }
  readonly property var provider: providers.length > 0 ? providers[providerIndex] : null

  property bool cursorActive: false
  property string analyticsMode: "tokens"
  property string analyticsView: "day"
  // Switching to an agent without prices or sessions must not leave the
  // panel on a view it cannot fill.
  onCostAvailableChanged: if (!costAvailable && analyticsMode === "cost") analyticsMode = "tokens"
  onProviderChanged: {
    var sessionCount = provider && Array.isArray(provider.recentSessions) ? provider.recentSessions.length : 0
    if (analyticsView === "sessions" && sessionCount === 0) analyticsView = "day"
  }
  property string timeScope: "week"
  property int periodOffset: 0
  property string customStart: ""
  property string customEnd: ""
  readonly property var scopeOptions: ["day", "week", "month", "year", "subscription", "all", "custom"]

  // Countdowns and "updated" read this instead of Date.now() so the
  // panel keeps telling the truth while it sits open.
  property double nowMs: Date.now()

  readonly property var limits: limitWindows(provider)
  readonly property var analyticsDays: scopedDays(provider)
  readonly property var analyticsUsage: usageForDays(analyticsDays)
  readonly property var models: modelRowsFromUsage(analyticsUsage)
  readonly property var sessions: sessionRows(provider)
  readonly property var costEstimate: costForUsage(analyticsUsage)
  property var publishedPricing: ({})
  FileView {
    id: pricingFile
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
  readonly property var headline: bindingWindow(provider)
  readonly property var balance: provider ? (provider.balance || null) : null
  // A prepaid account runs low the way a subscription window fills up: the
  // last 10% of the funded credits lights the same alarm.
  readonly property bool balanceAlarming: !!balance && balance.funded > 0
    && balance.remaining / balance.funded <= 0.1
  readonly property bool alarming: (!!headline && headline.percent >= 0.9) || balanceAlarming

  readonly property var barLimits: {
    var session = null, weekly = null
    for (var i = 0; i < limits.length; i++) {
      if (limits[i].title === "Session" && !session) session = limits[i]
      if (limits[i].title === "Weekly" && !weekly) weekly = limits[i]
    }
    return [session, weekly].filter(function(w) { return w !== null })
  }

  // Thresholds are percentage used: 75/50/25/10/5% remaining.
  function usageColor(value) {
    if (!isFinite(value) || value < 0) return root.foreground
    if (value >= 0.95) return "#f7768e"
    if (value >= 0.90) return "#ff9e64"
    if (value >= 0.75) return "#e0af68"
    if (value >= 0.50) return "#c0ca75"
    if (value >= 0.25) return "#73daca"
    return "#9ece6a"
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function selectProvider(index) {
    if (providers.length === 0) return
    var wrapped = ((index % providers.length) + providers.length) % providers.length
    selectedProviderId = providers[wrapped].providerId
  }

  function refreshNow() {
    root.nowMs = Date.now()
    usage.refreshProvider(root.provider ? root.provider.providerId : "")
  }

  function launchAgent() {
    if (root.bar) root.bar.run("omarchy-agent --pick")
    root.close()
  }

  // ---------------------------------------------------------------- limits
  //
  // Both providers report the same two shapes: a short rolling session window
  // and a long weekly one. Everything below normalizes them into one record so
  // the meters and the hero speak a single language.

  // Claude spells its windows out ("Session (5-hour)"), Codex abbreviates
  // them ("5h window", "30m window"). Both have to land on the same record.
  function windowIsLong(text) {
    return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0
      || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0
  }

  function windowSpanMs(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0) return 30 * 24 * 3600 * 1000
    if (windowIsLong(text)) return 7 * 24 * 3600 * 1000
    var hours = text.match(/(\d+)\s*-?\s*h(?:our)?\b/)
    if (hours) return Number(hours[1]) * 3600 * 1000
    var minutes = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/)
    if (minutes) return Number(minutes[1]) * 60 * 1000
    return 0
  }

  function windowTitle(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0) return "Monthly"
    if (windowIsLong(text)) return "Weekly"
    if (text.indexOf("session") >= 0 || windowSpanMs(label) > 0) return "Session"
    var plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim()
    return plain === "" ? "Limit" : plain
  }

  // A collector that already knows which window a limit belongs to says so,
  // and that beats reading it back out of the label: a model-scoped limit is
  // titled after its model, and a name like "Opus 5 (1M context)" would parse
  // as a one-minute window.
  function limitWindow(label, percent, resetAt, title) {
    return {
      title: String(title || "") !== "" ? String(title) : windowTitle(label),
      percent: Number(percent),
      resetAt: String(resetAt || ""),
      spanMs: windowSpanMs(label)
    }
  }

  // How much of the window has elapsed: usage at this mark is exactly on pace
  // to run out as the window resets.
  function paceFor(w) {
    var remaining = resetMsFor(w)
    if (!w || !(w.spanMs > 0) || remaining < 0) return -1
    return clamp(1 - remaining / w.spanMs, 0, 1)
  }

  function paceText(w) {
    var pace = paceFor(w)
    if (pace < 0 || !w || w.percent < 0) return ""
    var delta = Math.round((w.percent - pace) * 100)
    if (Math.abs(delta) < 3) return "on pace"
    return Math.abs(delta) + "% " + (delta > 0 ? "ahead of pace" : "under pace")
  }

  function limitWindows(p) {
    if (!p) return []
    var out = []
    var list = p.limits || []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i] || {}
      var percent = Number(entry.percent)
      if (entry.percent !== null && entry.percent !== undefined && isFinite(percent) && percent >= 0) out.push(limitWindow(entry.label, percent, entry.resetsAt, entry.title))
    }
    return out
  }

  // The window that decides how much room is left — the fullest one, since
  // that is what stops the next prompt.
  function bindingWindow(p) {
    var windows = limitWindows(p)
    var best = null
    for (var i = 0; i < windows.length; i++) {
      if (!best || windows[i].percent > best.percent) best = windows[i]
    }
    return best
  }

  function resetMsFor(w) {
    if (!w || w.resetAt === "") return -1
    var ms = new Date(w.resetAt).getTime()
    return isFinite(ms) ? ms - root.nowMs : -1
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  // ---------------------------------------------------------------- balance
  //
  // Prepaid agents report a credit ledger instead of rate-limit windows: the
  // record's balance object carries remaining, funded, and spent amounts.

  function currencyPrefix(currency) {
    var code = String(currency || "USD").toUpperCase()
    if (code === "USD") return "$"
    if (code === "EUR") return "€"
    if (code === "GBP") return "£"
    return code + " "
  }

  function formatMoney(value, currency) {
    var amount = Number(value)
    if (!isFinite(amount)) amount = 0
    return currencyPrefix(currency) + amount.toFixed(2)
  }

  function balanceDetailText(b) {
    if (!b || !(b.funded > 0)) return ""
    var text = formatMoney(b.spent, b.currency) + " spent of " + formatMoney(b.funded, b.currency) + " funded"
    if (b.estimated) text += " · estimated"
    return text
  }

  // ---------------------------------------------------------------- content

  // The plan you pay for, under the name of the tool it pays for. Limits live
  // in their own section; the hero just says what this is.
  function heroMeta(p) {
    if (!p) return ""
    if (String(p.usageStatusText || "") !== "") return p.usageStatusText
    var tier = String(p.tierLabel || "")
    var label = tier === "" ? "Subscription" : tier.charAt(0).toUpperCase() + tier.slice(1)
    var remaining = subscriptionTimeLeft(p)
    return remaining === "" ? label : label + " · " + remaining
  }

  // Use elapsed time, not calendar-day rounding. The clock property makes
  // this binding update even when the account record has not changed.
  function subscriptionTimeLeft(p) {
    var value = p ? String(p.subscriptionEndsAt || "") : ""
    if (value === "") return ""
    var endMs = new Date(value).getTime()
    if (!isFinite(endMs)) return ""
    var remainingMs = endMs - root.nowMs
    // The collector refreshes the entitlement after renewal. Do not show
    // misleading expiry messages while fresh account data is pending.
    if (remainingMs <= 0) return ""
    var days = Math.floor(remainingMs / 86400000)
    if (days >= 1) return days + (days === 1 ? " day left" : " days left")
    var hours = Math.floor(remainingMs / 3600000)
    if (hours >= 1) return hours + (hours === 1 ? "hr left" : "hrs left")
    var minutes = Math.floor(remainingMs / 60000)
    if (minutes >= 1) return minutes + (minutes === 1 ? "min left" : "mins left")
    return "Less than 1 min left"
  }

  // Local calendar date, recomputed from nowMs so a panel left open across
  // midnight moves the "Today" row with the clock.
  function todayDate() {
    var now = new Date(root.nowMs)
    return now.getFullYear()
      + "-" + String(now.getMonth() + 1).padStart(2, "0")
      + "-" + String(now.getDate()).padStart(2, "0")
  }

  function isoDate(date) {
    return date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0")
      + "-" + String(date.getDate()).padStart(2, "0")
  }

  function parsedDay(text) {
    var date = new Date(String(text || "") + "T00:00:00")
    return isNaN(date.getTime()) ? null : date
  }

  function periodBounds() {
    var now = new Date(root.nowMs)
    var start = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    var end = new Date(start)
    if (timeScope === "day") {
      start.setDate(start.getDate() + periodOffset); end = new Date(start)
    } else if (timeScope === "week") {
      var mondayOffset = (start.getDay() + 6) % 7
      start.setDate(start.getDate() - mondayOffset + periodOffset * 7)
      end = new Date(start); end.setDate(end.getDate() + 6)
    } else if (timeScope === "month") {
      start = new Date(now.getFullYear(), now.getMonth() + periodOffset, 1)
      end = new Date(start.getFullYear(), start.getMonth() + 1, 0)
    } else if (timeScope === "year") {
      start = new Date(now.getFullYear() + periodOffset, 0, 1)
      end = new Date(start.getFullYear(), 11, 31)
    } else if (timeScope === "subscription") {
      // The current billing cycle: the month that ends the day before renewal.
      var renews = provider ? new Date(String(provider.subscriptionEndsAt || "")) : null
      if (!renews || isNaN(renews.getTime())) return { start: "", end: "" }
      end = new Date(renews.getFullYear(), renews.getMonth(), renews.getDate() - 1)
      start = new Date(renews.getFullYear(), renews.getMonth() - 1, renews.getDate())
    } else if (timeScope === "custom") {
      start = parsedDay(customStart); end = parsedDay(customEnd)
      if (!start || !end) return { start: "", end: "" }
      if (start.getTime() > end.getTime()) { var swap = start; start = end; end = swap }
    } else {
      return { start: "", end: "" }
    }
    return { start: isoDate(start), end: isoDate(end) }
  }

  function scopedDays(p) {
    var source = p ? (p.dailyUsage || p.recentDays || []) : []
    var bounds = periodBounds()
    var out = []
    for (var i = 0; i < source.length; i++) {
      var day = source[i] || {}
      var date = String(day.date || "")
      if ((bounds.start === "" || date >= bounds.start) && (bounds.end === "" || date <= bounds.end)) out.push(day)
    }
    out.sort(function(a, b) { return String(a.date).localeCompare(String(b.date)) })
    return out
  }

  function scopeLabel() {
    if (timeScope === "all") return "All time"
    if (timeScope === "custom") return "Custom"
    var bounds = periodBounds()
    var start = parsedDay(bounds.start), end = parsedDay(bounds.end)
    if (!start) return timeScope === "subscription" ? "Subscription" : timeScope
    if (timeScope === "subscription")
      return "Cycle · " + start.toLocaleDateString(Qt.locale(), "MMM d") + " – " + end.toLocaleDateString(Qt.locale(), "MMM d")
    if (timeScope === "day") return periodOffset === 0 ? "Today" : start.toLocaleDateString(Qt.locale(), "MMM d, yyyy")
    if (timeScope === "month") return start.toLocaleDateString(Qt.locale(), "MMMM yyyy")
    if (timeScope === "year") return String(start.getFullYear())
    return start.toLocaleDateString(Qt.locale(), "MMM d") + " – " + end.toLocaleDateString(Qt.locale(), "MMM d")
  }

  function cycleScope(delta) {
    var index = scopeOptions.indexOf(timeScope)
    timeScope = scopeOptions[(index + delta + scopeOptions.length) % scopeOptions.length]
    periodOffset = 0
    if (timeScope === "custom" && customStart === "") {
      var end = new Date(root.nowMs), start = new Date(root.nowMs); start.setDate(start.getDate() - 29)
      customStart = isoDate(start); customEnd = isoDate(end)
    }
  }

  function shiftPeriod(delta) {
    if (timeScope === "day" || timeScope === "week" || timeScope === "month" || timeScope === "year")
      periodOffset += delta
  }

  function dayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime())) return String(date || "")
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()]
  }

  function dayLabel(date, today) {
    if (today) return "Today"
    return dayName(date)
  }

  function dayTooltip(day, today) {
    if (!day) return ""
    var parsed = new Date(String(day.date) + "T00:00:00")
    var label = isNaN(parsed.getTime())
      ? String(day.date)
      : dayName(day.date) + " " + (parsed.getMonth() + 1) + "/" + parsed.getDate()
    var text = label + " · " + usage.formatTokenCount(Number(day.messageCount || 0)) + " tokens"
    if (root.costAvailable)
      text += " · " + formatMoney(dayCost(day), "USD")
    // Prompt and session counts only exist for today, so they ride along here
    // instead of taking a section of their own. Billing-API agents never
    // count prompts, and "0 prompts" would read as a quiet day, not a gap.
    if (today && provider && provider.hasPromptStats !== false)
      text += " · " + Number(provider.todayPrompts || 0) + " prompts · "
        + Number(provider.todaySessions || 0) + " sessions"
    return text
  }

  function weekPeak(p) {
    var days = p ? (p.recentDays || []) : []
    var peak = 0
    for (var i = 0; i < days.length; i++) peak = Math.max(peak, Number(days[i].messageCount || 0))
    return peak
  }

  function tokenTotal(p) {
    var byModel = p ? (p.modelUsage || {}) : {}
    var total = 0
    for (var id in byModel) {
      var bucket = byModel[id] || {}
      total += Number(bucket.inputTokens || 0) + Number(bucket.outputTokens || 0)
        + Number(bucket.cacheReadInputTokens || 0) + Number(bucket.cacheCreationInputTokens || 0)
    }
    return total
  }

  function usageForDays(days) {
    var result = {}
    days = days || []
    for (var i = 0; i < days.length; i++) {
      var byModel = (days[i] || {}).modelUsage || {}
      for (var id in byModel) {
        var source = byModel[id] || {}
        var bucket = result[id]
        if (!bucket) bucket = result[id] = { inputTokens: 0, outputTokens: 0, cacheReadInputTokens: 0,
          cacheCreationInputTokens: 0, cacheCreation1hInputTokens: 0 }
        bucket.inputTokens += Number(source.inputTokens || 0)
        bucket.outputTokens += Number(source.outputTokens || 0)
        bucket.cacheReadInputTokens += Number(source.cacheReadInputTokens || 0)
        bucket.cacheCreationInputTokens += Number(source.cacheCreationInputTokens || 0)
        bucket.cacheCreation1hInputTokens += Number(source.cacheCreation1hInputTokens || 0)
      }
    }
    return result
  }

  function costForUsage(byModel) {
    var result = { total: 0, pricedModels: 0, unpricedModels: 0 }
    byModel = byModel || {}
    for (var id in byModel) {
      var bucket = byModel[id] || {}
      var rates = apiPricing(id)
      if (!rates) {
        if (Number(bucket.inputTokens || 0) + Number(bucket.outputTokens || 0)
            + Number(bucket.cacheReadInputTokens || 0) + Number(bucket.cacheCreationInputTokens || 0) > 0)
          result.unpricedModels++
        continue
      }
      result.pricedModels++
      result.total += bucketCost(bucket, rates)
    }
    return result
  }

  // cacheCreation1hInputTokens is the part of the cache writes made with the
  // 1-hour TTL (Claude Code's default), which bills at its own, higher rate.
  function bucketCost(bucket, rates) {
    var cacheWrite = Number(bucket.cacheCreationInputTokens || 0)
    var longWrite = Math.min(cacheWrite, Number(bucket.cacheCreation1hInputTokens || 0))
    var longRate = isFinite(rates.cacheWrite1h) ? rates.cacheWrite1h : rates.cacheWrite
    return (Number(bucket.inputTokens || 0) * rates.input
      + Number(bucket.outputTokens || 0) * rates.output
      + Number(bucket.cacheReadInputTokens || 0) * rates.cached
      + (cacheWrite - longWrite) * rates.cacheWrite
      + longWrite * longRate) / 1000000
  }

  // Cost needs at least one model this provider has used to have a price;
  // judged on the provider, not the period, so browsing an empty week does
  // not flip the view back to tokens.
  readonly property bool costAvailable: {
    if (!provider) return false
    if (costForUsage(provider.modelUsage).pricedModels > 0) return true
    var days = provider.dailyUsage || []
    for (var i = days.length - 1; i >= 0; i--)
      if (costForUsage((days[i] || {}).modelUsage).pricedModels > 0) return true
    return false
  }

  function dayCost(day) { return costForUsage(day ? day.modelUsage : null).total }

  function dayMetric(day) {
    return analyticsMode === "cost" ? dayCost(day) : Number(day ? day.messageCount || 0 : 0)
  }

  function dayMetricText(day) {
    return analyticsMode === "cost" ? formatMoney(dayCost(day), "USD")
      : usage.formatTokenCount(Number(day ? day.messageCount || 0 : 0))
  }

  function analyticsPeak(p) {
    var days = root.analyticsDays
    var peak = 0
    for (var i = 0; i < days.length; i++) peak = Math.max(peak, dayMetric(days[i]))
    return peak
  }

  function analyticsTotalText() {
    return analyticsMode === "cost" ? formatMoney(costEstimate.total, "USD")
      : usage.formatTokenCount(tokenTotal({ modelUsage: analyticsUsage }))
  }

  function modelMetric(row) {
    return analyticsMode === "cost" ? Number(row && row.priced ? row.cost : 0)
      : Number(row ? row.total : 0)
  }

  function modelMetricText(row) {
    if (analyticsMode !== "cost") return usage.formatTokenCount(Number(row ? row.total : 0))
    return row && row.priced ? formatMoney(row.cost, "USD") : "—"
  }

  function modelMetricPeak() {
    var peak = 0
    for (var i = 0; i < models.length; i++) peak = Math.max(peak, modelMetric(models[i]))
    return peak
  }

  // ------------------------------------------------------------- insights

  // The four token kinds, in the order the mix bar draws them. Cache reads
  // come first among the cheap ones so the costly slices sit together.
  readonly property var mixKinds: [
    { key: "inputTokens", label: "Input", rate: "input" },
    { key: "outputTokens", label: "Output", rate: "output" },
    { key: "cacheCreationInputTokens", label: "Cache write", rate: "cacheWrite" },
    { key: "cacheReadInputTokens", label: "Cache read", rate: "cached" }
  ]

  readonly property var analysis: analysisFor(analyticsUsage, analyticsDays)

  function analysisFor(byModel, days) {
    var tokens = { inputTokens: 0, outputTokens: 0, cacheReadInputTokens: 0, cacheCreationInputTokens: 0 }
    var cost = { inputTokens: 0, outputTokens: 0, cacheReadInputTokens: 0, cacheCreationInputTokens: 0 }
    var savings = 0
    byModel = byModel || {}
    for (var id in byModel) {
      var bucket = byModel[id] || {}
      for (var k in tokens) tokens[k] += Number(bucket[k] || 0)
      var rates = apiPricing(id)
      if (!rates) continue
      var write = Number(bucket.cacheCreationInputTokens || 0)
      var longWrite = Math.min(write, Number(bucket.cacheCreation1hInputTokens || 0))
      var longRate = isFinite(rates.cacheWrite1h) ? rates.cacheWrite1h : rates.cacheWrite
      cost.inputTokens += Number(bucket.inputTokens || 0) * rates.input / 1000000
      cost.outputTokens += Number(bucket.outputTokens || 0) * rates.output / 1000000
      cost.cacheReadInputTokens += Number(bucket.cacheReadInputTokens || 0) * rates.cached / 1000000
      cost.cacheCreationInputTokens += ((write - longWrite) * rates.cacheWrite + longWrite * longRate) / 1000000
      // What those cache hits would have cost as fresh input.
      savings += Number(bucket.cacheReadInputTokens || 0) * (rates.input - rates.cached) / 1000000
    }
    var totalTokens = 0, totalCost = 0
    for (var t in tokens) { totalTokens += tokens[t]; totalCost += cost[t] }
    var prompt = tokens.inputTokens + tokens.cacheReadInputTokens + tokens.cacheCreationInputTokens

    var active = 0, peak = null
    days = days || []
    for (var i = 0; i < days.length; i++) {
      if (Number(days[i].messageCount || 0) <= 0) continue
      active++
      if (!peak || dayMetric(days[i]) > dayMetric(peak)) peak = days[i]
    }

    // Projection only means something for a period that is still running.
    var bounds = periodBounds(), projection = -1, elapsed = 0, span = 0
    var today = parsedDay(todayDate()), start = parsedDay(bounds.start), end = parsedDay(bounds.end)
    if (today && start && end && today >= start && today <= end) {
      elapsed = Math.round((today - start) / 86400000) + 1
      span = Math.round((end - start) / 86400000) + 1
      if (span > elapsed) projection = (analyticsMode === "cost" ? totalCost : totalTokens) * span / elapsed
    }

    return {
      tokens: tokens, cost: cost, totalTokens: totalTokens, totalCost: totalCost,
      hitRate: prompt > 0 ? tokens.cacheReadInputTokens / prompt : -1,
      savings: savings, activeDays: active, peak: peak,
      projection: projection, elapsedDays: elapsed, spanDays: span
    }
  }

  function metricText(value) {
    return analyticsMode === "cost" ? formatMoney(value, "USD") : usage.formatTokenCount(value)
  }

  // One entry per token kind, largest first, so the biggest driver leads.
  function mixRows(a) {
    var rows = []
    var total = analyticsMode === "cost" ? a.totalCost : a.totalTokens
    for (var i = 0; i < mixKinds.length; i++) {
      var kind = mixKinds[i]
      var value = analyticsMode === "cost" ? a.cost[kind.key] : a.tokens[kind.key]
      rows.push({ label: kind.label, value: value, share: total > 0 ? value / total : 0,
        tokens: a.tokens[kind.key], shade: 0.92 - i * 0.22 })
    }
    rows.sort(function(x, y) { return y.value - x.value })
    return rows
  }

  function insightTiles(a) {
    var total = analyticsMode === "cost" ? a.totalCost : a.totalTokens
    var tiles = [{
      label: "Daily average",
      value: a.activeDays > 0 ? metricText(total / a.activeDays) : "—",
      detail: a.activeDays + (a.activeDays === 1 ? " active day" : " active days")
    }]
    if (a.projection >= 0)
      tiles.push({ label: "Projected", value: metricText(a.projection),
        detail: "day " + a.elapsedDays + " of " + a.spanDays })
    else
      tiles.push({ label: "Peak day", value: a.peak ? metricText(dayMetric(a.peak)) : "—",
        detail: a.peak ? parsedDay(a.peak.date).toLocaleDateString(Qt.locale(), "ddd MMM d") : "no usage" })
    tiles.push({ label: "Cache hit rate",
      value: a.hitRate >= 0 ? Math.round(a.hitRate * 100) + "%" : "—",
      detail: "of prompt tokens" })
    if (costAvailable)
      tiles.push({ label: "Cache saved", value: formatMoney(a.savings, "USD"),
        detail: a.totalCost + a.savings > 0
          ? Math.round(a.savings / (a.totalCost + a.savings) * 100) + "% vs no cache" : "vs no cache" })
    else
      tiles.push({ label: "Output share",
        value: a.totalTokens > 0 ? Math.round(a.tokens.outputTokens / a.totalTokens * 100) + "%" : "—",
        detail: "of all tokens" })
    return tiles
  }

  function sessionRows(p) {
    var source = p && Array.isArray(p.recentSessions) ? p.recentSessions : []
    var bounds = periodBounds()
    var rows = []
    for (var i = 0; i < source.length; i++) {
      var session = source[i] || {}
      var updated = new Date(String(session.updatedAt || ""))
      var sessionDate = isNaN(updated.getTime()) ? "" : isoDate(updated)
      if (bounds.start !== "" && (sessionDate === "" || sessionDate < bounds.start)) continue
      if (bounds.end !== "" && (sessionDate === "" || sessionDate > bounds.end)) continue
      var cost = costForUsage(session.modelUsage || {})
      rows.push({
        id: String(session.id || i),
        name: String(session.title || "Session"),
        updatedAt: String(session.updatedAt || ""),
        updatedAtMs: Number(session.updatedAtMs || 0),
        total: Number(session.totalTokens || 0),
        cost: cost.total,
        priced: cost.pricedModels > 0,
        unpricedModels: cost.unpricedModels,
        modelUsage: session.modelUsage || {},
        modelReasoning: session.modelReasoning || {}
      })
    }
    rows.sort(function(a, b) { return b.updatedAtMs - a.updatedAtMs })
    return rows.slice(0, 5)
  }

  function sessionMetricPeak() {
    var peak = 0
    for (var i = 0; i < sessions.length; i++) peak = Math.max(peak, modelMetric(sessions[i]))
    return peak
  }

  function sessionTooltip(row) {
    if (!row) return ""
    var updated = new Date(row.updatedAt)
    return isNaN(updated.getTime()) ? "" : "Last active · " + updated.toLocaleString(Qt.locale(), "MMM d · h:mm AP")
  }

  function sessionModelDetails(row) {
    if (!row) return []
    var details = []
    var reasoning = row.modelReasoning || {}
    var ids = Object.keys(row.modelUsage || {})
    Object.keys(reasoning).forEach(function(id) { if (ids.indexOf(id) < 0) ids.push(id) })
    ids.sort()
    for (var i = 0; i < ids.length; i++) {
      var levels = reasoning[ids[i]] || []
      details.push({ name: usage.friendlyModelName(ids[i]),
        levels: levels.length ? levels.join(" · ") : "Not recorded" })
    }
    return details
  }

  function modelRows(p) {
    var usageByModel = p ? (p.modelUsage || {}) : {}
    var rows = []
    for (var id in usageByModel) {
      var bucket = usageByModel[id] || {}
      var input = Number(bucket.inputTokens || 0)
      var output = Number(bucket.outputTokens || 0)
      var cacheRead = Number(bucket.cacheReadInputTokens || 0)
      var cacheWrite = Number(bucket.cacheCreationInputTokens || 0)
      var rates = apiPricing(id)
      rows.push({
        id: id,
        name: usage.friendlyModelName(id),
        total: input + output + cacheRead + cacheWrite,
        input: input,
        output: output,
        cacheRead: cacheRead,
        cacheWrite: cacheWrite,
        priced: !!rates,
        cost: rates ? bucketCost(bucket, rates) : 0
      })
    }
    rows.sort(function(a, b) { return b.total - a.total })
    return rows.slice(0, 4)
  }

  function modelRowsFromUsage(byModel) { return modelRows({ modelUsage: byModel || {} }) }

  function modelTooltip(row) {
    if (!row) return ""
    var text = "In " + usage.formatTokenCount(row.input)
      + " · out " + usage.formatTokenCount(row.output)
      + " · cache read " + usage.formatTokenCount(row.cacheRead)
      + " · cache write " + usage.formatTokenCount(row.cacheWrite)
    if (row.priced) text += " · " + formatMoney(row.cost, "USD") + " API equivalent"
    else text += " · API price unavailable"
    return text
  }

  // Official standard API rates in USD per million text tokens. Subscription
  // usage is not billed this way, so this is an API-cost equivalent rather
  // than an account charge. OpenAI's table refreshes daily; these published
  // rates cover offline use and remain the fallback if it fails.
  function apiPricing(modelId) {
    var id = String(modelId || "").toLowerCase()
      .replace(/-\d{4}-\d{2}-\d{2}$/, "").replace(/-\d{8}$/, "").replace(/\[1m\]$/, "")
    var published = publishedPricing[id]
    if (published && isFinite(published.input) && isFinite(published.cached)
        && isFinite(published.cacheWrite) && isFinite(published.output)) return published
    var claude = claudePricing(id)
    if (claude) return claude
    if (id === "gpt-6-astra")
      return { input: 10.00, cached: 1.00, output: 50.00, cacheWrite: 12.50 }
    if (id === "gpt-6.1-sol")
      return { input: 2.00, cached: 0.10, output: 10.00, cacheWrite: 2.50 }
    if (id === "gpt-6-sol")
      return { input: 2.00, cached: 0.20, output: 10.00, cacheWrite: 2.50 }
    if (id === "gpt-6-luna")
      return { input: 0.10, cached: 0.01, output: 0.50, cacheWrite: 0.125 }
    if (id === "gpt-5.6" || id === "gpt-5.6-sol")
      return { input: 4.00, cached: 0.40, output: 20.00, cacheWrite: 5.00 }
    if (id === "gpt-5.6-terra")
      return { input: 2.00, cached: 0.20, output: 12.00, cacheWrite: 2.50 }
    if (id === "gpt-5.6-luna")
      return { input: 0.20, cached: 0.02, output: 1.20, cacheWrite: 0.25 }
    return null
  }

  // Anthropic's standard API rates: 5-minute cache writes at 1.25x input,
  // 1-hour writes at 2x, cache reads at each model's published rate.
  function claudePricing(id) {
    var table = {
      "claude-fable-5-1": [10.00, 0.25, 50.00],
      "claude-mythos-5-1": [10.00, 0.25, 50.00],
      "claude-fable-5": [10.00, 1.00, 50.00],
      "claude-mythos-5": [10.00, 1.00, 50.00],
      "claude-opus-5-5": [4.00, 0.20, 20.00],
      "claude-opus-5": [5.00, 0.50, 25.00],
      "claude-opus-4-8": [5.00, 0.50, 25.00],
      "claude-opus-4-7": [5.00, 0.50, 25.00],
      "claude-opus-4-6": [5.00, 0.50, 25.00],
      "claude-opus-4-5": [5.00, 0.50, 25.00],
      "claude-sonnet-5-5": [2.00, 0.20, 10.00],
      "claude-sonnet-5": [2.00, 0.20, 10.00],
      "claude-sonnet-4-6": [3.00, 0.30, 15.00],
      "claude-sonnet-4-5": [3.00, 0.30, 15.00],
      "claude-haiku-5-5": [0.10, 0.01, 0.50],
      "claude-haiku-4-5": [1.00, 0.10, 5.00]
    }
    var rates = table[id]
    if (!rates) return null
    return { input: rates[0], cached: rates[1], output: rates[2],
      cacheWrite: rates[0] * 1.25, cacheWrite1h: rates[0] * 2 }
  }

  function apiCostEstimate(p) {
    return costForUsage(p ? p.modelUsage : null)
  }

  // Only speaks up when the numbers cover more than this machine.
  function footerText() {
    if (usage.syncStatusText !== "") return usage.syncStatusText
    if (provider && provider.syncEnabled && provider.syncDeviceCount > 0)
      return "Merged from " + provider.syncDeviceCount + " device" + (provider.syncDeviceCount === 1 ? "" : "s")
    return ""
  }

  // Agents that ship a white mark carry an `assets/<id>-light.svg` twin for
  // light surfaces; marks that work on both (Claude's brand-orange) ship one
  // file. The luminance check decides which candidate to try first.
  function colorChannelLuminance(value) {
    var channel = Number(value)
    if (!isFinite(channel)) return 0
    return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  function colorLuminance(color) {
    return 0.2126 * colorChannelLuminance(color.r)
      + 0.7152 * colorChannelLuminance(color.g)
      + 0.0722 * colorChannelLuminance(color.b)
  }

  // Marks resolve by convention, so a new agent's data file needs nothing
  // from this panel: assets/<id>.svg if it ships one, the module's bar glyph
  // if it doesn't.
  function iconCandidatesForProvider(p, surfaceColor) {
    if (!p) return []
    var candidates = []
    if (colorLuminance(surfaceColor || Color.background) >= 0.5)
      candidates.push(Qt.resolvedUrl("assets/" + p.providerId + "-light.svg"))
    candidates.push(Qt.resolvedUrl("assets/" + p.providerId + ".svg"))
    return candidates
  }

  // Nothing to report, nothing in the bar: Bar.qml collapses a slot whose item
  // is invisible, so the icon appears the moment the first scan finds usage and
  // stays away entirely on a machine that has never run either CLI.
  visible: providers.length > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onProviderIndexChanged: if (panelFlick) panelFlick.contentY = 0
  onOpenedChanged: if (opened) {
    cursorActive = false
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    usage.refreshLimits()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Main {
    id: usage
    settings: root.settings
  }

  // Cheap enough to keep running: it only re-evaluates text bindings, and a
  // stale "resets in 2h" on a panel that is open is worse than a timer.
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
      Item {
        id: barMark
        width: Style.bar.iconCanvas
        height: button.fontSize
        anchors.verticalCenter: parent.verticalCenter
        property var candidates: root.iconCandidatesForProvider(root.provider, Color.bar.background)
        property string candidatesKey: candidates.join("\n")
        property int candidateIndex: 0
        onCandidatesKeyChanged: candidateIndex = 0
        Image {
          id: barMarkImage
          anchors.centerIn: parent
          width: Style.bar.iconCanvas
          height: width
          source: barMark.candidateIndex < barMark.candidates.length ? barMark.candidates[barMark.candidateIndex] : ""
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          fillMode: Image.PreserveAspectFit
          onStatusChanged: if (status === Image.Error && barMark.candidateIndex < barMark.candidates.length)
            Qt.callLater(function() { barMark.candidateIndex++ })
        }
        Text {
          anchors.centerIn: parent
          visible: barMarkImage.status !== Image.Ready
          text: button.text
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.bar.iconFont
        }
      }
      Repeater {
        model: root.barLimits.length ? root.barLimits : [{percent: -1}]
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
    // Taller than the control panels on purpose: this one is a dashboard, and
    // the whole point is reading limits and history without scrolling.
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dx !== 0) {
          root.cursorActive = true
          root.selectProvider(root.providerIndex + dx)
        }
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshNow()
        else if (t === "t" || t === "T") root.analyticsMode = "tokens"
        else if ((t === "c" || t === "C") && root.costAvailable)
          root.analyticsMode = "cost"
        else if (t === "1") root.analyticsView = "day"
        else if (t === "2") root.analyticsView = "model"
        else if (t === "3" && root.sessions.length > 0) root.analyticsView = "sessions"
        else if (t === "4") root.analyticsView = "insights"
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ---------- Hero: provider mark · name · plan ----------
          PanelHero {
            id: hero
            visible: !!root.provider
            width: parent.width
            title: root.provider ? root.provider.providerName : ""
            meta: root.heroMeta(root.provider)
            foreground: root.foreground
            fontFamily: root.fontFamily

            trailingControl: Component {
              CursorSurface {
                id: refreshControl
                width: Style.space(32)
                height: Style.space(28)
                enabled: !usage.refreshing
                opacity: enabled ? 1.0 : 0.65
                bordered: true
                foreground: hero.foreground
                hasCursor: refreshArea.containsMouse

                Canvas {
                  id: refreshMark
                  width: Style.space(18)
                  height: Style.space(18)
                  anchors.centerIn: parent
                  antialiasing: true

                  property color strokeColor: refreshControl.foreground
                  onStrokeColorChanged: requestPaint()

                  onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = strokeColor
                    ctx.lineWidth = 1.7
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"

                    var cx = width / 2
                    var cy = height / 2
                    var radius = Math.min(width, height) * 0.29
                    var start = -Math.PI * 0.78
                    var end = Math.PI * 0.58
                    ctx.beginPath()
                    ctx.arc(cx, cy, radius, start, end, false)
                    ctx.stroke()

                    var tipX = cx + radius * Math.cos(end)
                    var tipY = cy + radius * Math.sin(end)
                    var tangent = end + Math.PI / 2
                    var wing = 3.1
                    ctx.beginPath()
                    ctx.moveTo(tipX, tipY)
                    ctx.lineTo(tipX - wing * Math.cos(tangent - 0.62),
                               tipY - wing * Math.sin(tangent - 0.62))
                    ctx.moveTo(tipX, tipY)
                    ctx.lineTo(tipX - wing * Math.cos(tangent + 0.62),
                               tipY - wing * Math.sin(tangent + 0.62))
                    ctx.stroke()
                  }

                  RotationAnimator on rotation {
                    running: usage.refreshing
                    from: 0
                    to: 360
                    duration: 850
                    loops: Animation.Infinite
                  }
                }

                MouseArea {
                  id: refreshArea
                  anchors.fill: parent
                  enabled: !usage.refreshing
                  hoverEnabled: true
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: root.refreshNow()
                }

                PanelToolTip {
                  visible: refreshArea.containsMouse
                  text: usage.refreshing ? "Refreshing usage…" : "Refresh usage"
                  fontFamily: hero.fontFamily
                }
              }
            }

            iconComponent: Component {
              Item {
                id: heroMark
                property var candidates: root.iconCandidatesForProvider(root.provider, root.surface)
                // Provider objects are rebuilt on every refresh, which churns the
                // array's identity without changing its content. Restart the fallback
                // walk only when the URLs change: re-pointing source at a URL whose
                // load already failed emits no statusChanged, so an identity-only
                // reset would strand the walker on a missing -light twin.
                property string candidatesKey: candidates.join("\n")
                property int candidateIndex: 0
                onCandidatesKeyChanged: candidateIndex = 0

                width: Style.font.display
                height: Style.font.display

                Image {
                  id: heroMarkImage
                  anchors.fill: parent
                  source: heroMark.candidateIndex < heroMark.candidates.length ? heroMark.candidates[heroMark.candidateIndex] : ""
                  sourceSize.width: Style.font.display * 2
                  sourceSize.height: Style.font.display * 2
                  fillMode: Image.PreserveAspectFit
                  // Advancing source from inside its own status change trips the
                  // binding-loop detector; defer the step one tick.
                  onStatusChanged: if (status === Image.Error && heroMark.candidateIndex < heroMark.candidates.length)
                    Qt.callLater(function() { heroMark.candidateIndex++ })
                }

                Text {
                  anchors.centerIn: parent
                  visible: heroMarkImage.status !== Image.Ready
                  text: button.text
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
            }
          }

          Text {
            visible: root.providers.length === 0
            width: parent.width
            topPadding: Style.space(24)
            text: "No AI coding subscriptions found.\nAgents show up here once you've used them."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          // ---------- Provider switch ----------
          Row {
            id: providerSwitch
            visible: root.providers.length > 1
            width: parent.width
            spacing: Style.spacing.md

            readonly property real cellWidth: root.providers.length > 0
              ? (width - spacing * (root.providers.length - 1)) / root.providers.length
              : 0

            Repeater {
              model: root.providers

              Button {
                required property var modelData
                required property int index

                width: providerSwitch.cellWidth
                text: modelData.providerName
                selected: index === root.providerIndex
                hasCursor: root.cursorActive && index === root.providerIndex
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: {
                  root.cursorActive = true
                  root.selectProvider(index)
                }
                onHovered: function(isHovered) { if (isHovered) root.cursorActive = true }
              }
            }
          }

          // ---------- Status ----------
          BorderSurface {
            visible: !!root.provider && String(root.provider.usageStatusText || "") !== ""
            width: parent.width
            implicitHeight: statusText.implicitHeight + Style.spacing.xl * 2
            color: root.alpha(root.urgent, 0.10)
            borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: statusText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: root.provider ? String(root.provider.authHelpText || "") : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---------- Balance / limits ----------
          PanelSeparator {
            visible: balanceSection.visible || limitsSection.visible
            foreground: root.foreground
          }

          Column {
            id: balanceSection
            visible: !!root.balance
            width: parent.width
            spacing: Style.space(10)

            // The meter shows what is left, not what is used: a prepaid
            // account drains toward empty rather than filling toward a cap.
            readonly property real ratio: root.balance && root.balance.funded > 0
              ? root.clamp(root.balance.remaining / root.balance.funded, 0, 1)
              : -1

            PanelSectionHeader {
              width: parent.width
              text: "BALANCE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(balanceLabel.implicitHeight, balanceValue.implicitHeight)

              Text {
                id: balanceLabel
                text: "Prepaid credits"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: balanceValue
                text: root.balance ? root.formatMoney(root.balance.remaining, root.balance.currency) : ""
                color: root.balanceAlarming ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Meter {
              visible: balanceSection.ratio >= 0
              width: parent.width
              value: balanceSection.ratio
              alarming: root.balanceAlarming
            }

            Text {
              visible: text !== ""
              width: parent.width
              text: root.balanceDetailText(root.balance)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            id: limitsSection
            visible: root.limits.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "LIMITS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.limits

              LimitRow {
                required property var modelData
                width: limitsSection.width
                window: modelData
              }
            }
          }

          // ---------- Analytics ----------
          PanelSeparator {
            visible: analyticsSection.visible
            foreground: root.foreground
          }

          Column {
            id: analyticsSection
            visible: !!root.provider && root.provider.recentDays && root.provider.recentDays.length > 0
            width: parent.width
            spacing: Style.spacing.md

            readonly property var days: root.analyticsDays
            readonly property real peak: Math.max(0.000001, root.analyticsPeak(root.provider))

            PanelSectionHeader {
              text: "USAGE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              id: analyticsTabs
              width: parent.width
              spacing: Style.spacing.md

              readonly property real cellWidth: (width - spacing) / 2

              Button {
                width: analyticsTabs.cellWidth
                text: "TOKENS"
                selected: root.analyticsMode === "tokens"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.analyticsMode = "tokens"
              }

              Button {
                width: analyticsTabs.cellWidth
                text: "COST"
                selected: root.analyticsMode === "cost"
                enabled: root.costAvailable
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.analyticsMode = "cost"
              }
            }

            Row {
              id: periodControl
              width: parent.width
              spacing: Style.spacing.md

              Button {
                width: Style.space(38)
                text: "‹"
                enabled: root.timeScope === "day" || root.timeScope === "week"
                  || root.timeScope === "month" || root.timeScope === "year"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.shiftPeriod(-1)
              }

              Button {
                width: periodControl.width - Style.space(76) - periodControl.spacing * 2
                text: root.scopeLabel()
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.cycleScope(1)
                MouseArea {
                  anchors.fill: parent
                  acceptedButtons: Qt.RightButton
                  onClicked: root.cycleScope(-1)
                }
              }

              Button {
                width: Style.space(38)
                text: "›"
                enabled: (root.timeScope === "day" || root.timeScope === "week"
                  || root.timeScope === "month" || root.timeScope === "year") && root.periodOffset < 0
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.shiftPeriod(1)
              }
            }

            Row {
              visible: root.timeScope === "custom"
              width: parent.width
              spacing: Style.spacing.md

              Repeater {
                model: [root.customStart, root.customEnd]
                Rectangle {
                  required property string modelData
                  required property int index
                  width: (parent.width - parent.spacing) / 2
                  height: Style.space(30)
                  color: root.alpha(root.foreground, 0.04)
                  border.color: root.alpha(root.foreground, 0.28)
                  radius: Style.cornerRadius
                  TextInput {
                    anchors.fill: parent
                    anchors.margins: Style.space(7)
                    text: modelData
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    selectByMouse: true
                    onEditingFinished: {
                      if (index === 0) root.customStart = text.trim()
                      else root.customEnd = text.trim()
                    }
                  }
                }
              }
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(analyticsTotalLabel.implicitHeight, analyticsTotalValue.implicitHeight)

              Text {
                id: analyticsTotalLabel
                text: "Total"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: analyticsTotalSecondary
                // The other metric rides along, so neither needs a toggle to read.
                visible: root.costAvailable
                text: root.analyticsMode === "cost"
                  ? usage.formatTokenCount(root.analysis.totalTokens) + " tokens"
                  : root.formatMoney(root.costEstimate.total, "USD")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: analyticsTotalValue.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: analyticsTotalValue
                text: root.analyticsTotalText()
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Row {
              id: analyticsViewTabs
              width: parent.width
              spacing: Style.spacing.md

              readonly property real cellWidth: (width - spacing * 3) / 4

              Button {
                width: analyticsViewTabs.cellWidth
                text: "DAY"
                selected: root.analyticsView === "day"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                verticalPadding: Style.space(5)
                onClicked: root.analyticsView = "day"
              }

              Button {
                width: analyticsViewTabs.cellWidth
                text: "MODEL"
                selected: root.analyticsView === "model"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                verticalPadding: Style.space(5)
                onClicked: root.analyticsView = "model"
              }

              Button {
                width: analyticsViewTabs.cellWidth
                text: "SESSIONS"
                selected: root.analyticsView === "sessions"
                enabled: root.sessions.length > 0
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                verticalPadding: Style.space(5)
                onClicked: root.analyticsView = "sessions"
              }

              Button {
                width: analyticsViewTabs.cellWidth
                text: "INSIGHT"
                selected: root.analyticsView === "insights"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                verticalPadding: Style.space(5)
                onClicked: root.analyticsView = "insights"
              }
            }

            Column {
              id: dayView
              visible: root.analyticsView === "day"
              width: parent.width
              spacing: Style.spacing.md

              Repeater {
                model: analyticsSection.days

                DayRow {
                  required property var modelData
                  required property int index

                  width: dayView.width
                  day: modelData
                  ratio: root.dayMetric(modelData) / analyticsSection.peak
                  // By date, not by position: the Claude stats-cache fallback can
                  // hand us a window that stops short of today.
                  today: String(modelData.date || "") === root.todayDate()
                }
              }
            }

            Column {
              id: modelView
              visible: root.analyticsView === "model"
              width: parent.width
              spacing: Style.spacing.md

              Repeater {
                model: root.models

                ModelRow {
                  required property var modelData
                  width: modelView.width
                  row: modelData
                  share: root.modelMetric(modelData) / Math.max(0.000001, root.modelMetricPeak())
                }
              }
            }

            Column {
              id: sessionView
              visible: root.analyticsView === "sessions"
              width: parent.width
              spacing: Style.spacing.md

              Repeater {
                model: root.sessions

                ModelRow {
                  required property var modelData
                  width: sessionView.width
                  row: modelData
                  share: root.modelMetric(modelData) / Math.max(0.000001, root.sessionMetricPeak())
                  tooltipText: root.sessionTooltip(modelData)
                  sessionDetails: true
                }
              }
            }

            Column {
              id: insightView
              visible: root.analyticsView === "insights"
              width: parent.width
              spacing: Style.spacing.md

              Grid {
                id: tileGrid
                width: parent.width
                columns: 2
                columnSpacing: Style.spacing.md
                rowSpacing: Style.spacing.md

                Repeater {
                  model: root.insightTiles(root.analysis)

                  StatTile {
                    required property var modelData
                    width: (tileGrid.width - tileGrid.columnSpacing) / 2
                    label: modelData.label
                    value: modelData.value
                    detail: modelData.detail
                  }
                }
              }

              Text {
                text: root.analyticsMode === "cost" ? "Cost mix" : "Token mix"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MixBar {
                width: parent.width
                rows: root.mixRows(root.analysis)
              }

              Grid {
                id: mixLegend
                width: parent.width
                columns: 2
                columnSpacing: Style.spacing.lg
                rowSpacing: Style.space(4)

                Repeater {
                  model: root.mixRows(root.analysis)

                  MixRow {
                    required property var modelData
                    width: (mixLegend.width - mixLegend.columnSpacing) / 2
                    row: modelData
                  }
                }
              }
            }

            Text {
              visible: (root.analyticsView === "model" || root.analyticsView === "insights")
                && root.analyticsMode === "cost" && root.costEstimate.unpricedModels > 0
              width: parent.width
              text: "API equivalent · " + root.costEstimate.unpricedModels + " unpriced model"
                + (root.costEstimate.unpricedModels === 1 ? " excluded" : "s excluded")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
            }
          }

          Text {
            visible: text !== ""
            width: parent.width
            topPadding: Style.space(2)
            text: root.footerText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // A limit window: label and percentage, meter, and reset countdown.
  component LimitRow: Column {
    id: limitRow
    property var window: null

    readonly property bool alarming: window && window.percent >= 0.9

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(limitLabel.implicitHeight, limitValue.implicitHeight)

      Text {
        id: limitLabel
        // A model-scoped window is titled after its model, and those names run
        // long enough to reach the percentage, so the title gives way first.
        text: limitRow.window ? limitRow.window.title : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: limitValue.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: limitValue
        text: limitRow.window && limitRow.window.percent >= 0
          ? Math.round(limitRow.window.percent * 100) + "%"
          : "—"
        color: root.usageColor(limitRow.window ? limitRow.window.percent : -1)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Meter {
      width: parent.width
      value: limitRow.window ? limitRow.window.percent : -1
      pace: root.paceFor(limitRow.window)
      alarming: limitRow.alarming
      graded: true
    }

    Text {
      id: resetText
      width: parent.width
      text: {
        var remainingMs = root.resetMsFor(limitRow.window)
        if (!(remainingMs > 0)) return ""
        var pace = root.paceText(limitRow.window)
        return "Resets in " + root.formatDuration(remainingMs) + (pace !== "" ? " · " + pace : "")
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Rounded track showing the percentage of the allowance used.
  component Meter: Item {
    id: meter
    property real value: -1
    // Where usage would sit if spread evenly over the window; -1 hides it.
    property real pace: -1
    property bool alarming: false
    property bool graded: false
    property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(meter.value, 0, 1)
      color: meter.graded ? root.usageColor(meter.value) : (meter.alarming ? root.urgent : root.foreground)

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

    Rectangle {
      visible: meter.pace >= 0
      width: Math.max(2, Math.round(meter.thickness * 0.45))
      height: meter.thickness + Style.space(6)
      radius: width / 2
      anchors.verticalCenter: meterTrack.verticalCenter
      x: root.clamp(meterTrack.width * meter.pace - width / 2, 0, meterTrack.width - width)
      color: root.alpha(root.foreground, 0.8)
    }
  }

  // One row per day: label, bar, tokens. Today is picked out in full
  // foreground so the week reads as a run-up to right now.
  component DayRow: Item {
    id: dayRow
    property var day: null
    property real ratio: 0
    property bool today: false

    implicitHeight: Math.max(dayLabel.implicitHeight, dayValue.implicitHeight) + Style.spacing.sm

    Text {
      id: dayLabel
      text: root.dayLabel(dayRow.day ? dayRow.day.date : "", dayRow.today)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: dayRow.today
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    Rectangle {
      id: dayTrack
      anchors.left: dayLabel.right
      anchors.right: dayValue.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
      radius: height / 2
      color: root.track

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        radius: parent.radius
        width: parent.width * root.clamp(dayRow.ratio, 0, 1)
        color: dayRow.today ? root.foreground : root.alpha(root.foreground, 0.55)

        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      id: dayValue
      text: root.dayMetricText(dayRow.day)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    MouseArea {
      id: dayHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: dayHover.containsMouse
      text: root.dayTooltip(dayRow.day, dayRow.today)
      fontFamily: root.fontFamily
    }
  }

  // Model rows read as a table: the share bar fills the row behind the label
  // instead of stacking under it, which keeps the whole dashboard on one screen.
  component ModelRow: Item {
    id: modelRow
    property var row: null
    property real share: 0
    property string tooltipText: root.modelTooltip(row)
    property bool sessionDetails: false

    implicitHeight: modelName.implicitHeight + Style.spacing.lg

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.05)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * root.clamp(modelRow.share, 0, 1)
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.14)

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

    Text {
      id: modelName
      text: modelRow.row ? modelRow.row.name : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: modelTokens.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: modelTokens
      text: root.modelMetricText(modelRow.row)
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: modelHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: modelHover.containsMouse && !modelRow.sessionDetails
      text: modelRow.tooltipText
      fontFamily: root.fontFamily
    }

    PanelToolTip {
      id: sessionTip
      visible: modelHover.containsMouse && modelRow.sessionDetails
      fontFamily: root.fontFamily
      contentItem: Column {
        width: Style.space(340)
        padding: Style.space(14)
        spacing: Style.space(8)
        Text {
          width: parent.width - 2 * parent.padding
          text: modelRow.row ? modelRow.row.name : "Session"
          wrapMode: Text.Wrap
          color: sessionTip.panelForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
        Text {
          text: modelRow.tooltipText
          color: root.alpha(sessionTip.panelForeground, 0.65)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          text: modelRow.row ? usage.formatTokenCount(modelRow.row.total) + " tokens"
            + (modelRow.row.priced ? "  ·  " + root.formatMoney(modelRow.row.cost, "USD") + " API equivalent" : "") : ""
          color: sessionTip.panelForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Rectangle {
          width: parent.width - 2 * parent.padding
          height: 1
          color: root.alpha(sessionTip.panelForeground, 0.15)
        }
        Repeater {
          model: root.sessionModelDetails(modelRow.row)
          delegate: Column {
            required property var modelData
            width: Style.space(312)
            spacing: Style.space(3)
            Text {
              width: parent.width
              text: modelData.name
              wrapMode: Text.Wrap
              color: sessionTip.panelForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
            Text {
              width: parent.width
              text: "Reasoning · " + modelData.levels
              wrapMode: Text.Wrap
              color: root.alpha(sessionTip.panelForeground, 0.65)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }

  }

  // A labelled figure for the insights grid: what it is, the number, and
  // the context that makes the number mean something.
  component StatTile: Rectangle {
    id: tile
    property string label: ""
    property string value: ""
    property string detail: ""

    implicitHeight: tileColumn.implicitHeight + Style.space(10)
    radius: Style.cornerRadius
    color: root.alpha(root.foreground, 0.05)
    border.color: root.alpha(root.foreground, 0.10)

    Column {
      id: tileColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: 0

      Text {
        width: parent.width
        text: tile.label
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: tile.value
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: tile.detail
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }

  // A 100% stacked bar: one slice per token kind, shaded by rank. The legend
  // rows below carry the names and numbers, so shade is never the only cue.
  component MixBar: Item {
    id: mixBar
    property var rows: []
    implicitHeight: Style.space(10)

    Rectangle {
      anchors.fill: parent
      radius: Style.space(3)
      color: root.track
    }

    Row {
      anchors.fill: parent
      spacing: 1
      Repeater {
        model: mixBar.rows
        Rectangle {
          required property var modelData
          required property int index
          visible: modelData.share > 0
          width: Math.max(0, (mixBar.width - (mixBar.rows.length - 1)) * modelData.share)
          height: mixBar.height
          radius: Style.space(3)
          color: root.alpha(root.foreground, modelData.shade)
        }
      }
    }
  }

  component MixRow: Item {
    id: mixRow
    property var row: null
    implicitHeight: mixLabel.implicitHeight + Style.space(4)

    Rectangle {
      id: mixSwatch
      width: Style.space(8)
      height: Style.space(8)
      radius: Style.space(2)
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      color: root.alpha(root.foreground, mixRow.row ? mixRow.row.shade : 0)
    }

    Text {
      id: mixLabel
      text: mixRow.row ? mixRow.row.label.replace("Cache ", "C. ") : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      anchors.left: mixSwatch.right
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: mixShare
      text: mixRow.row ? Math.round(mixRow.row.share * 100) + "%" : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignRight
      width: Style.space(30)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      text: mixRow.row ? root.metricText(mixRow.row.value) : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      anchors.right: mixShare.left
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: mixHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: mixHover.containsMouse && root.analyticsMode === "cost"
      text: mixRow.row ? usage.formatTokenCount(mixRow.row.tokens) + " " + mixRow.row.label.toLowerCase() + " tokens" : ""
      fontFamily: root.fontFamily
    }
  }
}
