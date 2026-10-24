.pragma library

// Everything the panel computes from usage records, kept free of QML so it
// can be tested on its own. Dates travel as local ISO days ("2026-10-22");
// money is USD at standard API rates, an equivalent rather than a charge.

var FIELDS = ["inputTokens", "outputTokens", "cacheReadInputTokens", "cacheCreationInputTokens"]
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MIX = [
  { key: "inputTokens", label: "Input", rate: "input" },
  { key: "outputTokens", label: "Output", rate: "output" },
  { key: "cacheCreationInputTokens", label: "Cache write", rate: "cacheWrite" },
  { key: "cacheReadInputTokens", label: "Cache read", rate: "cached" }
]

// ------------------------------------------------------------------ pricing

// Anthropic: [input, cache read, output]; writes are 1.25x input for the
// 5-minute TTL and 2x for the 1-hour TTL Claude Code uses.
var CLAUDE = {
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

// OpenAI's published Standard rates, used until the daily download lands.
var OPENAI = {
  "gpt-6-astra": { input: 10.00, cached: 1.00, output: 50.00, cacheWrite: 12.50 },
  "gpt-6.1-sol": { input: 2.00, cached: 0.10, output: 10.00, cacheWrite: 2.50 },
  "gpt-6-sol": { input: 2.00, cached: 0.20, output: 10.00, cacheWrite: 2.50 },
  "gpt-6-luna": { input: 0.10, cached: 0.01, output: 0.50, cacheWrite: 0.125 },
  "gpt-5.6": { input: 4.00, cached: 0.40, output: 20.00, cacheWrite: 5.00 },
  "gpt-5.6-sol": { input: 4.00, cached: 0.40, output: 20.00, cacheWrite: 5.00 },
  "gpt-5.6-terra": { input: 2.00, cached: 0.20, output: 12.00, cacheWrite: 2.50 },
  "gpt-5.6-luna": { input: 0.20, cached: 0.02, output: 1.20, cacheWrite: 0.25 }
}

function pricing(modelId, published) {
  var id = String(modelId || "").toLowerCase()
    .replace(/-\d{4}-\d{2}-\d{2}$/, "").replace(/-\d{8}$/, "").replace(/\[1m\]$/, "")
  var listed = (published || {})[id]
  if (listed && isFinite(listed.input) && isFinite(listed.cached)
      && isFinite(listed.cacheWrite) && isFinite(listed.output)) return listed
  var claude = CLAUDE[id]
  if (claude) return { input: claude[0], cached: claude[1], output: claude[2],
    cacheWrite: claude[0] * 1.25, cacheWrite1h: claude[0] * 2 }
  return OPENAI[id] || null
}

function num(value) {
  var n = Number(value)
  return isFinite(n) ? n : 0
}

function bucketTokens(bucket) {
  var total = 0
  for (var i = 0; i < FIELDS.length; i++) total += num((bucket || {})[FIELDS[i]])
  return total
}

function bucketCost(bucket, rates) {
  bucket = bucket || {}
  var write = num(bucket.cacheCreationInputTokens)
  var longWrite = Math.min(write, num(bucket.cacheCreation1hInputTokens))
  var longRate = isFinite(rates.cacheWrite1h) ? rates.cacheWrite1h : rates.cacheWrite
  return (num(bucket.inputTokens) * rates.input
    + num(bucket.outputTokens) * rates.output
    + num(bucket.cacheReadInputTokens) * rates.cached
    + (write - longWrite) * rates.cacheWrite
    + longWrite * longRate) / 1000000
}

// Cost of a {model: bucket} map; priced is false when no used model has a rate.
function usageCost(byModel, published) {
  var total = 0, priced = false, unpriced = 0
  for (var id in byModel || {}) {
    var rates = pricing(id, published)
    if (!rates) {
      if (bucketTokens(byModel[id]) > 0) unpriced++
      continue
    }
    priced = true
    total += bucketCost(byModel[id], rates)
  }
  return { total: total, priced: priced, unpriced: unpriced }
}

// -------------------------------------------------------------------- dates

function dayNumber(iso) {
  var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso || ""))
  return m ? Math.round(Date.UTC(+m[1], +m[2] - 1, +m[3]) / 86400000) : NaN
}

function isoFromNumber(n) {
  var d = new Date(n * 86400000)
  return d.getUTCFullYear() + "-" + String(d.getUTCMonth() + 1).padStart(2, "0")
    + "-" + String(d.getUTCDate()).padStart(2, "0")
}

function addDays(iso, days) { return isoFromNumber(dayNumber(iso) + days) }

// The local calendar day of a timestamp; a bare date is taken as-is.
function localIso(value) {
  var text = String(value || "")
  if (/^\d{4}-\d{2}-\d{2}$/.test(text)) return text
  var d = new Date(text)
  if (isNaN(d.getTime())) return ""
  return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0")
    + "-" + String(d.getDate()).padStart(2, "0")
}

// Same day-of-month `months` away, pinned to the month's last day the way
// billing anchors are.
function addMonths(iso, months) {
  var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso)
  var index = +m[1] * 12 + (+m[2] - 1) + months
  var year = Math.floor(index / 12), month = index % 12
  var last = new Date(Date.UTC(year, month + 1, 0)).getUTCDate()
  return isoFromNumber(Math.round(Date.UTC(year, month, Math.min(+m[3], last)) / 86400000))
}

function shortDate(iso) {
  var n = dayNumber(iso)
  var d = new Date(n * 86400000)
  return MONTHS[d.getUTCMonth()] + " " + d.getUTCDate()
}

function weekday(iso) { return WEEKDAYS[new Date(dayNumber(iso) * 86400000).getUTCDay()] }

function spanLabel(start, end) {
  if (start === end) return weekday(start) + " " + shortDate(start)
  var sameMonth = start.slice(0, 7) === end.slice(0, 7)
  return shortDate(start) + " – " + (sameMonth ? String(+end.slice(8, 10)) : shortDate(end))
}

// ------------------------------------------------------------------ periods

function periodRange(kind, offset, todayIso, renewalIso, customStart, customEnd) {
  offset = Math.min(0, Math.round(num(offset)))
  var out = { kind: kind, start: "", end: "", label: "", canStepBack: true,
    canStepForward: false, available: true }
  if (kind === "today") {
    out.start = out.end = addDays(todayIso, offset)
    out.label = offset === 0 ? "Today" : spanLabel(out.start, out.end)
  } else if (kind === "7d" || kind === "30d") {
    var length = kind === "7d" ? 7 : 30
    out.end = addDays(todayIso, offset * length)
    out.start = addDays(out.end, 1 - length)
    out.label = spanLabel(out.start, out.end)
  } else if (kind === "cycle") {
    var renewal = localIso(renewalIso)
    if (renewal === "") {
      out.available = false
      out.canStepBack = false
      return out
    }
    out.start = addMonths(renewal, offset - 1)
    out.end = addDays(addMonths(renewal, offset), -1)
    out.label = "Cycle · " + shortDate(out.start) + " – " + shortDate(out.end)
  } else if (kind === "custom") {
    var a = localIso(customStart), b = localIso(customEnd)
    out.canStepBack = false
    if (a === "" || b === "") { out.label = "Custom"; return out }
    if (a > b) { var swap = a; a = b; b = swap }
    out.start = a; out.end = b
    out.label = spanLabel(a, b)
    return out
  } else {
    out.kind = "all"
    out.label = "All time"
    out.canStepBack = false
    return out
  }
  out.canStepForward = out.end < todayIso
  return out
}

// The period to show: a Cycle without a renewal date has no bounds, so it
// becomes 7D rather than silently reporting all-time numbers.
function resolvePeriod(kind, offset, todayIso, renewalIso, customStart, customEnd) {
  var range = periodRange(kind, offset, todayIso, renewalIso, customStart, customEnd)
  return range.available ? range : periodRange("7d", 0, todayIso, renewalIso, customStart, customEnd)
}

// Whether any model this provider has used has a price, judged on its whole
// history so a quiet period still reads "$0.00" instead of "—".
function providerPriced(p, published) {
  if (!p) return false
  if (usageCost(p.modelUsage || {}, published).priced) return true
  var days = p.dailyUsage || []
  for (var i = days.length - 1; i >= 0; i--)
    if (usageCost((days[i] || {}).modelUsage || {}, published).priced) return true
  return false
}

function inRange(date, range) {
  return date !== "" && (range.start === "" || date >= range.start) && (range.end === "" || date <= range.end)
}

function daysInRange(dailyUsage, range) {
  var out = []
  var source = dailyUsage || []
  for (var i = 0; i < source.length; i++) {
    var day = source[i] || {}
    if (inRange(String(day.date || ""), range)) out.push(day)
  }
  out.sort(function(x, y) { return String(x.date).localeCompare(String(y.date)) })
  return out
}

// -------------------------------------------------------------- aggregation

function emptyBucket() {
  return { inputTokens: 0, outputTokens: 0, cacheReadInputTokens: 0,
    cacheCreationInputTokens: 0, cacheCreation1hInputTokens: 0 }
}

function addBucket(target, source) {
  for (var key in target) target[key] += num((source || {})[key])
}

function sumUsage(days) {
  var out = {}
  for (var i = 0; i < (days || []).length; i++) {
    var byModel = days[i].modelUsage || {}
    for (var id in byModel) {
      if (!out[id]) out[id] = emptyBucket()
      addBucket(out[id], byModel[id])
    }
  }
  return out
}

// A day's token total. messageCount carries tokens from sources without a
// model breakdown too, so it is the total of record.
function dayTokens(day) {
  var count = num(day.messageCount)
  if (count > 0) return count
  var usage = day.modelUsage || {}, total = 0
  for (var id in usage) total += bucketTokens(usage[id])
  return total
}

function summary(days, range, todayIso, published, pricedProvider) {
  days = days || []
  var byModel = sumUsage(days)
  var cost = usageCost(byModel, published)
  // Nothing used in the period: a priced provider spent $0.
  if (!cost.priced && cost.unpriced === 0 && pricedProvider === true) cost.priced = true
  var kinds = emptyBucket(), kindCost = emptyBucket(), savings = 0
  for (var id in byModel) {
    var bucket = byModel[id]
    addBucket(kinds, bucket)
    var rates = pricing(id, published)
    if (!rates) continue
    kindCost.inputTokens += num(bucket.inputTokens) * rates.input / 1000000
    kindCost.outputTokens += num(bucket.outputTokens) * rates.output / 1000000
    kindCost.cacheReadInputTokens += num(bucket.cacheReadInputTokens) * rates.cached / 1000000
    kindCost.cacheCreationInputTokens += bucketCost({ cacheCreationInputTokens: bucket.cacheCreationInputTokens,
      cacheCreation1hInputTokens: bucket.cacheCreation1hInputTokens }, rates)
    savings += num(bucket.cacheReadInputTokens) * (rates.input - rates.cached) / 1000000
  }

  var tokens = 0, active = 0, peak = null
  for (var i = 0; i < days.length; i++) {
    var t = dayTokens(days[i])
    tokens += t
    if (t <= 0) continue
    active++
    var c = usageCost(days[i].modelUsage || {}, published).total
    var metric = cost.priced ? c : t
    if (!peak || metric > peak.metric) peak = { date: String(days[i].date), tokens: t, cost: cost.priced ? c : -1, metric: metric }
  }
  if (peak) delete peak.metric

  var prompt = kinds.inputTokens + kinds.cacheReadInputTokens + kinds.cacheCreationInputTokens
  var mixTotal = 0
  var mix = MIX.map(function(kind) {
    var value = cost.priced ? kindCost[kind.key] : kinds[kind.key]
    mixTotal += value
    return { key: kind.key, label: kind.label, tokens: kinds[kind.key],
      cost: cost.priced ? kindCost[kind.key] : -1, value: value, share: 0 }
  })
  mix.forEach(function(row) { row.share = mixTotal > 0 ? row.value / mixTotal : 0 })
  mix.sort(function(x, y) { return y.value - x.value })

  // Only a billing cycle that is still running has an end worth projecting to.
  var projection = -1, projectionTokens = -1, projectionDate = ""
  if (range && range.kind === "cycle" && range.start !== "" && todayIso >= range.start && todayIso <= range.end) {
    var elapsed = dayNumber(todayIso) - dayNumber(range.start) + 1
    var span = dayNumber(range.end) - dayNumber(range.start) + 1
    projectionTokens = tokens / elapsed * span
    projection = cost.priced ? cost.total / elapsed * span : -1
    projectionDate = range.end
  }

  return {
    tokens: tokens,
    cost: cost.priced ? cost.total : -1,
    priced: cost.priced,
    unpricedModels: cost.unpriced,
    activeDays: active,
    avgTokens: active > 0 ? tokens / active : 0,
    avgCost: cost.priced ? (active > 0 ? cost.total / active : 0) : -1,
    projection: projection,
    projectionTokens: projectionTokens,
    projectionDate: projectionDate,
    peak: peak,
    hitRate: prompt > 0 ? kinds.cacheReadInputTokens / prompt : -1,
    savings: cost.priced ? savings : -1,
    mix: mix
  }
}

// ------------------------------------------------------------------- charts

// Columns for the period: days up to a month, ISO weeks up to half a year,
// then months. Segments stack the top models of the whole period plus the
// rest as "other", in the same order in every column.
function chartBuckets(days, range, todayIso, published, topN) {
  days = days || []
  topN = topN || 3
  var start = range.start !== "" ? range.start : (days.length ? String(days[0].date) : todayIso)
  var end = range.end !== "" ? range.end : todayIso
  if (end > todayIso && range.kind !== "cycle" && range.kind !== "custom") end = todayIso
  var span = dayNumber(end) - dayNumber(start) + 1
  var unit = span <= 31 ? "day" : (span <= 182 ? "week" : "month")

  var totals = sumUsage(days)
  var top = Object.keys(totals).sort(function(a, b) { return bucketTokens(totals[b]) - bucketTokens(totals[a]) }).slice(0, topN)

  function keyFor(iso) {
    if (unit === "day") return iso
    if (unit === "month") return iso.slice(0, 7)
    var n = dayNumber(iso)
    var dow = (new Date(n * 86400000).getUTCDay() + 6) % 7
    return isoFromNumber(n - dow)
  }

  var order = [], buckets = {}
  function ensure(key, first) {
    if (buckets[key]) return buckets[key]
    var label = unit === "day" ? weekday(first) : (unit === "week" ? shortDate(first) : MONTHS[+key.slice(5, 7) - 1])
    buckets[key] = { key: key, unit: unit, label: label, first: first, last: first, isToday: false, tokens: 0, cost: 0, usage: {} }
    order.push(key)
    return buckets[key]
  }
  for (var n = dayNumber(start); n <= dayNumber(end); n++) {
    var iso = isoFromNumber(n)
    var b = ensure(keyFor(iso), iso)
    b.last = iso
    if (iso === todayIso) b.isToday = true
  }
  for (var i = 0; i < days.length; i++) {
    var date = String(days[i].date)
    if (dayNumber(date) < dayNumber(start) || dayNumber(date) > dayNumber(end)) continue
    var target = ensure(keyFor(date), date)
    target.tokens += dayTokens(days[i])
    var usage = days[i].modelUsage || {}
    for (var id in usage) {
      var name = top.indexOf(id) >= 0 ? id : "other"
      if (!target.usage[name]) target.usage[name] = { tokens: 0, cost: 0 }
      target.usage[name].tokens += bucketTokens(usage[id])
      var rates = pricing(id, published)
      var c = rates ? bucketCost(usage[id], rates) : 0
      target.usage[name].cost += c
      target.cost += c
    }
  }
  var names = top.concat(["other"])
  return order.map(function(key) {
    var bucket = buckets[key]
    bucket.segments = names.map(function(model) {
      var u = bucket.usage[model] || { tokens: 0, cost: 0 }
      return { model: model, tokens: u.tokens, cost: u.cost }
    }).filter(function(seg) { return seg.tokens > 0 })
    delete bucket.usage
    return bucket
  })
}

// ------------------------------------------------------------------- tables

function modelRows(byModel, published) {
  var rows = []
  var anyPriced = false
  for (var id in byModel || {}) {
    var bucket = byModel[id]
    var rates = pricing(id, published)
    if (rates) anyPriced = true
    rows.push({
      id: id, tokens: bucketTokens(bucket), priced: !!rates,
      cost: rates ? bucketCost(bucket, rates) : -1,
      input: num(bucket.inputTokens), output: num(bucket.outputTokens),
      cacheRead: num(bucket.cacheReadInputTokens), cacheWrite: num(bucket.cacheCreationInputTokens),
      share: 0
    })
  }
  var metric = function(row) { return anyPriced ? Math.max(0, row.cost) : row.tokens }
  rows = rows.filter(function(row) { return row.tokens > 0 })
  rows.sort(function(a, b) { return metric(b) - metric(a) || b.tokens - a.tokens })
  var peak = rows.length ? metric(rows[0]) : 0
  rows.forEach(function(row) { row.share = peak > 0 ? metric(row) / peak : 0 })
  return rows
}

function sessionRows(sessions, range, published, limit) {
  var rows = []
  for (var i = 0; i < (sessions || []).length; i++) {
    var session = sessions[i] || {}
    if (!inRange(localIso(session.updatedAt), range)) continue
    var usage = session.modelUsage || {}
    var reasoning = session.modelReasoning || {}
    var cost = usageCost(usage, published)
    var read = 0, prompt = 0
    var models = Object.keys(usage).map(function(id) {
      var bucket = usage[id]
      read += num(bucket.cacheReadInputTokens)
      prompt += num(bucket.inputTokens) + num(bucket.cacheReadInputTokens) + num(bucket.cacheCreationInputTokens)
      var rates = pricing(id, published)
      return { id: id, tokens: bucketTokens(bucket), cost: rates ? bucketCost(bucket, rates) : -1,
        effort: (reasoning[id] || []).filter(function(level) { return level !== "Not recorded" }) }
    }).sort(function(a, b) { return b.tokens - a.tokens })
    rows.push({
      id: String(session.id || i), title: String(session.title || "Session"),
      updatedAt: String(session.updatedAt || ""), updatedAtMs: num(session.updatedAtMs),
      tokens: num(session.totalTokens) || models.reduce(function(sum, m) { return sum + m.tokens }, 0),
      cost: cost.priced ? cost.total : -1, priced: cost.priced,
      hitRate: prompt > 0 ? read / prompt : -1, models: models
    })
  }
  rows.sort(function(a, b) { return b.updatedAtMs - a.updatedAtMs })
  return rows.slice(0, limit || 5)
}

// --------------------------------------------------------------- formatting

function formatTokens(n) {
  n = num(n)
  var abs = Math.abs(n)
  function short(value, suffix) {
    var text = value >= 10 || Math.round(value * 10) % 10 === 0 ? String(Math.round(value * 10) / 10) : value.toFixed(1)
    return text.replace(/\.0$/, "") + suffix
  }
  if (abs >= 1e9) return short(n / 1e9, "B")
  if (abs >= 1e6) return short(n / 1e6, "M")
  if (abs >= 1e4) return Math.round(n / 1e3) + "K"
  if (abs >= 1e3) return short(n / 1e3, "K")
  return String(Math.round(n))
}

function formatMoney(n) {
  n = Number(n)
  if (!isFinite(n) || n < 0) return "—"
  if (n >= 1000) return "$" + Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  return "$" + n.toFixed(2)
}

// ------------------------------------------------------------------- limits
//
// Collectors spell windows differently ("Session (5-hour)", "5h window",
// "Weekly (7-day)"); everything lands on {title, percent, resetAt, spanMs}.

function windowIsLong(text) {
  return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0
    || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0
}

function windowSpanMs(label) {
  var text = String(label || "").toLowerCase()
  if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0) return 30 * 86400000
  if (windowIsLong(text)) return 7 * 86400000
  var hours = text.match(/(\d+)\s*-?\s*h(?:our)?\b/)
  if (hours) return Number(hours[1]) * 3600000
  var minutes = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/)
  if (minutes) return Number(minutes[1]) * 60000
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

function limitWindows(p) {
  var out = []
  var list = (p && p.limits) || []
  for (var i = 0; i < list.length; i++) {
    var entry = list[i] || {}
    if (entry.percent === null || entry.percent === undefined) continue
    var percent = Number(entry.percent)
    if (!isFinite(percent) || percent < 0) continue
    // A collector that names the window (a model-scoped limit) beats parsing.
    var w = { title: String(entry.title || "") !== "" ? String(entry.title) : windowTitle(entry.label),
      percent: percent, resetAt: String(entry.resetsAt || ""), spanMs: windowSpanMs(entry.label) }
    // Pooled windows bring their own pace (the accounts' average) and
    // open/total counts; a single reset date cannot describe them.
    if (entry.pool) { w.pool = entry.pool; w.pace = Number(entry.pace); w.subtitle = String(entry.subtitle || "") }
    out.push(w)
  }
  return out
}

function resetMs(w, nowMs) {
  if (!w || w.resetAt === "") return -1
  var at = new Date(w.resetAt).getTime()
  return isFinite(at) ? at - nowMs : -1
}

function paceFor(w, nowMs) {
  if (w && w.pool) return isFinite(w.pace) ? w.pace : -1
  var remaining = resetMs(w, nowMs)
  if (!w || !(w.spanMs > 0) || remaining < 0) return -1
  return Math.max(0, Math.min(1, 1 - remaining / w.spanMs))
}

function formatDuration(ms) {
  if (!(ms > 0)) return "now"
  var minutes = Math.floor(ms / 60000), hours = Math.floor(minutes / 60), days = Math.floor(hours / 24)
  if (days > 0) return days + "d " + (hours % 24) + "h"
  if (hours > 0) return hours + "h " + (minutes % 60) + "m"
  return Math.max(1, minutes) + "m"
}

function limitDetail(w, nowMs) {
  if (w && w.pool) return poolDetail(w, nowMs)
  var remaining = resetMs(w, nowMs)
  if (!(remaining > 0)) return ""
  var text = "Resets in " + formatDuration(remaining)
  var pace = paceFor(w, nowMs)
  if (pace < 0) return text
  var delta = Math.round((w.percent - pace) * 100)
  if (Math.abs(delta) < 3) return text + " · on pace"
  return text + " · " + Math.abs(delta) + "% " + (delta > 0 ? "ahead of pace" : "under pace")
}

// "Updated 40s ago" under the limits, plus why and until when once the
// provider refused the check and the numbers are the last good ones.
function limitsFreshness(p, nowMs) {
  var at = num(p && p.limitsFetchedAtMs)
  if (!(at > 0)) return ""
  var age = Math.max(0, nowMs - at)
  var text = age < 5000 ? "Updated just now"
    : "Updated " + (age < 60000 ? Math.floor(age / 1000) + "s" : formatDuration(age)) + " ago"
  if (p.limitsStale !== true) return text
  text += " · " + (String(p.limitsNote || "") || "stale")
  var retry = num(p.limitsRetryAtMs) - nowMs
  if (retry > 0) text += ", retrying in " + (retry < 60000 ? Math.ceil(retry / 1000) + "s" : formatDuration(retry))
  return text
}

// "Pro · renews in 30 days", or the collector's status when something is wrong.
function planLine(p, nowMs) {
  if (!p) return ""
  if (String(p.usageStatusText || "") !== "") return String(p.usageStatusText)
  var tier = String(p.tierLabel || "")
  var label = tier === "" ? "Subscription" : tier.charAt(0).toUpperCase() + tier.slice(1)
  var end = new Date(String(p.subscriptionEndsAt || "")).getTime()
  if (!isFinite(end) || end <= nowMs) return label
  var left = end - nowMs
  var days = Math.floor(left / 86400000)
  if (days >= 1) return label + " · renews in " + days + (days === 1 ? " day" : " days")
  var hours = Math.floor(left / 3600000)
  if (hours >= 1) return label + " · renews in " + hours + "h"
  return label + " · renews in " + Math.max(1, Math.floor(left / 60000)) + "m"
}

// ----------------------------------------------------------------- calendar

// Six weeks of cells for a month (0-based month), starting on weekStart
// (0 or 7 = Sunday, 1 = Monday, …), so the grid keeps one height.
function monthGrid(year, month, weekStart, todayIso) {
  var first = Math.round(Date.UTC(year, month, 1) / 86400000)
  var dow = new Date(first * 86400000).getUTCDay()
  var lead = (dow - (num(weekStart) % 7) + 7) % 7
  var cells = []
  for (var i = 0; i < 42; i++) {
    var n = first - lead + i
    var iso = isoFromNumber(n)
    cells.push({ iso: iso, day: +iso.slice(8, 10), inMonth: +iso.slice(5, 7) === month + 1,
      isToday: iso === todayIso, future: iso > todayIso })
  }
  return cells
}

// Calendar presets for the custom range, never reaching past today.
function monthPreset(kind, todayIso) {
  var monthStart = todayIso.slice(0, 8) + "01"
  if (kind === "lastMonth") {
    var start = addMonths(monthStart, -1)
    return { start: start, end: addDays(monthStart, -1) }
  }
  if (kind === "thisYear") return { start: todayIso.slice(0, 5) + "01-01", end: todayIso }
  return { start: monthStart, end: todayIso }
}

// ----------------------------------------------------------- account pool
//
// A record's `pool` lists every account CPAMC holds for the agent, each with
// its own windows. Accounts route by CPAMC priority: the highest tier serves
// everything while any of it has room, lower tiers are overflow. A pooled
// window is the tier's average, since the tier's capacity is the sum.

var PLAN_RANK = { max: 0, pro: 1, plus: 2, team: 3, business: 4, enterprise: 5, free: 9 }

// "max 20x" ranks as max.
function planRank(plan) {
  var rank = PLAN_RANK[String(plan || "").split(" ")[0]]
  return rank === undefined ? 8 : rank
}

function planLabel(plan) {
  var text = String(plan || "")
  return text === "" ? "Account" : text.charAt(0).toUpperCase() + text.slice(1)
}

function poolWindowTitle(lengthSec) {
  if (lengthSec <= 6 * 3600) return "Session"
  if (lengthSec <= 8 * 86400) return "Weekly"
  return "Monthly"
}

function poolWindowShort(lengthSec) {
  if (lengthSec <= 6 * 3600) return Math.max(1, Math.round(lengthSec / 3600)) + "h"
  if (lengthSec <= 8 * 86400) return "wk"
  return Math.round(lengthSec / 86400) + "d"
}

// A window whose reset passed since the fetch has reset: nothing used, not
// started, whatever the stale numbers say.
function liveWindow(w, nowMs) {
  var length = num(w && w.lengthSec)
  var at = new Date(String(w && w.resetsAt || "")).getTime()
  var left = isFinite(at) ? at - nowMs : -1
  if (left <= 0) return { lengthSec: length, short: poolWindowShort(length), percent: 0, started: false, resetMs: -1 }
  var percent = Math.max(0, num(w.percent))
  return { lengthSec: length, short: poolWindowShort(length), percent: percent, started: w.started === true,
    resetMs: left, pace: w.started === true && length > 0 ? Math.max(0, Math.min(1, 1 - left / (length * 1000))) : 0 }
}

var IN_USE_MS = 3 * 60000

// idle: nothing counting down yet, so a kick starts its clock.
// quiet: counting down, but no use for a while; it reads as idle too.
// running: served tokens within the last inUseMs. limited: a window is full.
function accountView(a, nowMs, inUseMs) {
  var windows = ((a && a.windows) || []).map(function(w) { return liveWindow(w, nowMs) })
  var view = { id: String(a.id || a.email || ""), email: String(a.email || ""), plan: String(a.plan || ""),
    planLabel: planLabel(a.plan), priority: num(a.priority), windows: windows, note: String(a.note || ""),
    stale: a.stale === true, freeInMs: -1, kickable: false,
    lastActiveMs: num(a.lastActiveMs), quietMs: num(a.lastActiveMs) > 0 ? nowMs - num(a.lastActiveMs) : -1,
    recentTokens: 0 }
  var span = inUseMs > 0 ? inUseMs : IN_USE_MS
  var minutes = Array.isArray(a.recentTokens) ? a.recentTokens : []
  for (var m = 0; m < minutes.length; m++)
    // A minute bucket counts while any of it falls inside the span.
    if (num(minutes[m][0]) + 60000 > nowMs - span) view.recentTokens += num(minutes[m][1])
  var full = windows.filter(function(w) { return w.percent >= 1 && w.resetMs > 0 })
  if (a.status === "disabled") view.status = "disabled"
  else if (a.status === "expired") view.status = "expired"
  else if (a.status === "unknown" || windows.length === 0 && a.status !== "limited") view.status = "unknown"
  else if (full.length > 0 || a.status === "limited"
           && (windows.length === 0 || windows.some(function(w) { return w.started }))) {
    view.status = "limited"
    view.freeInMs = full.length ? Math.max.apply(null, full.map(function(w) { return w.resetMs })) : -1
  } else if (!windows[0].started) {
    view.status = "idle"
    view.kickable = true
  } else {
    var recent = view.lastActiveMs > 0 && nowMs - view.lastActiveMs < span
    view.status = recent ? "running" : "quiet"
  }
  view.usable = view.status === "idle" || view.status === "quiet" || view.status === "running"
  return view
}

function poolSummary(pool, nowMs, inUseMs) {
  var accounts = ((pool && pool.accounts) || []).map(function(a) { return accountView(a, nowMs, inUseMs) })
  accounts.sort(function(x, y) {
    return y.priority - x.priority || planRank(x.plan) - planRank(y.plan)
      || (x.email < y.email ? -1 : x.email > y.email ? 1 : 0)
  })
  var tiers = []
  for (var i = 0; i < accounts.length; i++) {
    var a = accounts[i]
    var tier = tiers.length && tiers[tiers.length - 1].priority === a.priority ? tiers[tiers.length - 1] : null
    if (!tier) tiers.push(tier = { priority: a.priority, accounts: [], plans: [] })
    tier.accounts.push(a)
    if (tier.plans.indexOf(a.planLabel) < 0) tier.plans.push(a.planLabel)
  }
  for (var t = 0; t < tiers.length; t++) {
    var tr = tiers[t]
    tr.label = tr.plans.join(" · ")
    tr.counted = tr.accounts.filter(function(x) { return x.usable || x.status === "limited" })
    tr.open = tr.accounts.filter(function(x) { return x.usable }).length
    tr.total = tr.accounts.filter(function(x) { return x.status !== "disabled" }).length
    tr.windows = poolWindows(tr.counted)
  }
  var active = accounts.filter(function(x) { return x.status !== "disabled" })
  return {
    routed: !!(pool && pool.routed), endpoint: String(pool && pool.endpoint || ""),
    accounts: accounts, tiers: tiers,
    // One account to work with: the panel drops the pool vocabulary and
    // reads like any single account that happens to go through CPAMC.
    single: active.length === 1, only: active.length === 1 ? active[0] : null,
    open: accounts.filter(function(x) { return x.usable }).length,
    total: accounts.filter(function(x) { return x.status !== "disabled" }).length,
    kickable: accounts.filter(function(x) { return x.kickable })
  }
}

// The tier's windows grouped by length: average use and pace over the
// accounts that have it, and the soonest moment any of it frees up.
function poolWindows(accounts) {
  var byLength = {}, order = []
  for (var i = 0; i < accounts.length; i++) {
    for (var j = 0; j < accounts[i].windows.length; j++) {
      var w = accounts[i].windows[j]
      if (!byLength[w.lengthSec]) { byLength[w.lengthSec] = []; order.push(w.lengthSec) }
      byLength[w.lengthSec].push({ w: w, account: accounts[i] })
    }
  }
  order.sort(function(x, y) { return x - y })
  return order.map(function(length) {
    var list = byLength[length], used = 0, pace = 0, next = -1, freeing = -1
    for (var k = 0; k < list.length; k++) {
      var w = list[k].w
      used += Math.min(1, w.percent)
      pace += w.pace || 0
      if (w.started && w.resetMs > 0 && (next < 0 || w.resetMs < next)) next = w.resetMs
      if (w.percent >= 1 && w.resetMs > 0 && (freeing < 0 || w.resetMs < freeing)) freeing = w.resetMs
    }
    return { lengthSec: length, title: poolWindowTitle(length), short: poolWindowShort(length),
      percent: list.length ? used / list.length : 0, pace: list.length ? pace / list.length : -1,
      accounts: list.length, full: list.filter(function(x) { return x.w.percent >= 1 }).length,
      nextResetMs: next, freeInMs: freeing }
  })
}

// The primary tier's windows in the shape of a record's `limits`, so the bar
// and the limit meters draw a pool the way they draw one account. A tier
// with one account holding capacity is that account: its own windows, reset
// dates and pace, with nothing averaged.
function poolLimits(pool, nowMs) {
  var summary = poolSummary(pool, nowMs)
  var tier = summary.tiers[0]
  if (!tier) return []
  if (tier.counted.length <= 1) {
    var one = tier.counted[0] || summary.only
    if (!one) return []
    return one.windows.map(function(w) {
      var label = w.lengthSec <= 6 * 3600 ? w.short + " window" : w.lengthSec <= 8 * 86400 ? "Weekly (7-day)"
        : "Monthly (" + Math.round(w.lengthSec / 86400) + "-day)"
      return { label: label, title: poolWindowTitle(w.lengthSec), percent: Math.min(1, w.percent),
        resetsAt: w.started && w.resetMs > 0 ? new Date(nowMs + w.resetMs).toISOString() : "" }
    })
  }
  return tier.windows.map(function(w) {
    var reset = w.freeInMs > 0 ? w.freeInMs : w.nextResetMs
    return { label: w.title, title: w.title, percent: w.percent, pace: w.pace,
      resetsAt: reset > 0 ? new Date(nowMs + reset).toISOString() : "",
      subtitle: tier.counted.length + " " + tier.label + " pooled",
      pool: { open: tier.open, total: tier.total, full: w.full, accounts: w.accounts,
        nextResetAt: w.nextResetMs > 0 ? nowMs + w.nextResetMs : 0,
        freeAt: w.freeInMs > 0 ? nowMs + w.freeInMs : 0 } }
  })
}

function poolDetail(w, nowMs) {
  var p = w.pool || {}
  var parts = []
  if (p.full > 0) parts.push((p.accounts - p.full) + "/" + p.accounts + " have room")
  else parts.push(p.open + "/" + p.total + " open")
  if (p.freeAt > nowMs) parts.push("frees up in " + formatDuration(p.freeAt - nowMs))
  else if (p.nextResetAt > nowMs) parts.push("next reset " + formatDuration(p.nextResetAt - nowMs))
  var pace = isFinite(w.pace) ? w.pace : -1
  if (pace >= 0) {
    var delta = Math.round((w.percent - pace) * 100)
    parts.push(Math.abs(delta) < 3 ? "on pace" : Math.abs(delta) + "% " + (delta > 0 ? "ahead of pace" : "under pace"))
  }
  return parts.join(" · ")
}

// "Pool · 3 Plus + 4 Free" for the header's plan line.
function poolPlanLine(pool, nowMs) {
  var summary = poolSummary(pool, nowMs)
  if (summary.single) return summary.only.planLabel + " · via CPAMC"
  var parts = summary.tiers.map(function(t) { return t.total + " " + t.label })
  return (summary.routed ? "Pool · " : "CPAMC · ") + parts.join(" + ")
}
