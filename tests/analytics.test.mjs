import { test } from "node:test"
import assert from "node:assert/strict"
import { loadAnalytics } from "./load.mjs"

const A = loadAnalytics()
const close = (actual, expected) => assert.ok(Math.abs(actual - expected) < 1e-9, `${actual} ≈ ${expected}`)

const bucket = (input, output, read, write, write1h) => ({
  inputTokens: input, outputTokens: output, cacheReadInputTokens: read,
  cacheCreationInputTokens: write, cacheCreation1hInputTokens: write1h,
})
const DAYS = [
  { date: "2026-10-21", messageCount: 10 + 1000 + 1e6 + 1e5,
    modelUsage: { "claude-opus-5-5": bucket(10, 1000, 1e6, 1e5, 1e5) } },
  { date: "2026-10-22", messageCount: 500,
    modelUsage: { "claude-sonnet-5-5": bucket(0, 500, 0, 0, 0) } },
]

test("pricing", () => {
  assert.deepEqual(A.pricing("claude-opus-5-5", {}),
    { input: 4, cached: 0.2, output: 20, cacheWrite: 5, cacheWrite1h: 8 })
  assert.equal(A.pricing("claude-haiku-4-5-20251001", {}).input, 1)
  assert.equal(A.pricing("nope", {}), null)
  assert.equal(A.pricing("gpt-6-sol", { "gpt-6-sol": { input: 9, cached: 1, cacheWrite: 2, output: 3 } }).input, 9)
})

test("bucketCost prices 1h writes at their own rate", () => {
  const cost = A.bucketCost({ inputTokens: 1e6, cacheCreationInputTokens: 1e6, cacheCreation1hInputTokens: 5e5 },
    A.pricing("claude-opus-5-5", {}))
  close(cost, 4 + 2.5 + 4)
})

test("periodRange 7d rolls and steps", () => {
  const now = A.periodRange("7d", 0, "2026-10-22", "", "", "")
  assert.equal(now.start, "2026-10-16")
  assert.equal(now.end, "2026-10-22")
  assert.equal(now.canStepForward, false)
  const back = A.periodRange("7d", -1, "2026-10-22", "", "", "")
  assert.equal(back.start, "2026-10-09")
  assert.equal(back.end, "2026-10-15")
  assert.equal(back.canStepForward, true)
})

test("periodRange cycle without renewal", () => {
  assert.equal(A.periodRange("cycle", 0, "2026-10-22", "", "", "").available, false)
  const cycle = A.periodRange("cycle", 0, "2026-10-22", "2026-11-22T16:33:12+00:00", "", "")
  assert.equal(cycle.available, true)
  assert.equal(cycle.start, "2026-10-22")
  assert.equal(cycle.end, "2026-11-21")
  const previous = A.periodRange("cycle", -1, "2026-10-22", "2026-11-22T16:33:12+00:00", "", "")
  assert.equal(previous.start, "2026-09-22")
  assert.equal(previous.end, "2026-10-21")
})

test("periodRange custom swaps reversed ends and all is open", () => {
  const custom = A.periodRange("custom", 0, "2026-10-22", "", "2026-10-20", "2026-10-01")
  assert.equal(custom.start, "2026-10-01")
  assert.equal(custom.end, "2026-10-20")
  const all = A.periodRange("all", 0, "2026-10-22", "", "", "")
  assert.equal(all.start, "")
  assert.equal(all.label, "All time")
})

test("summary over a running cycle projects to renewal", () => {
  const range = A.periodRange("cycle", 0, "2026-10-22", "2026-11-22", "", "")
  const days = A.daysInRange(DAYS, range)
  const s = A.summary(days, range, "2026-10-22", {})
  assert.equal(s.activeDays, 1)  // only 2026-10-22 falls inside the cycle
  const all = A.periodRange("all", 0, "2026-10-22", "", "", "")
  const t = A.summary(A.daysInRange(DAYS, all), all, "2026-10-22", {})
  assert.equal(t.activeDays, 2)
  close(t.hitRate, 1e6 / (10 + 1e6 + 1e5))
  assert.equal(t.projection, -1)
  close(s.projection, s.cost / 1 * 31)
  assert.equal(s.projectionDate, "2026-11-21")
  assert.ok(t.savings > 0)
  assert.equal(t.peak.date, "2026-10-21")
})

test("summary unpriced", () => {
  const days = [{ date: "2026-10-22", messageCount: 300, modelUsage: { "fireworks/x": bucket(100, 200, 0, 0, 0) } }]
  const all = A.periodRange("all", 0, "2026-10-22", "", "", "")
  const s = A.summary(days, all, "2026-10-22", {})
  assert.equal(s.cost, -1)
  assert.equal(s.avgCost, -1)
  assert.equal(s.priced, false)
  assert.equal(s.mix[0].key, "outputTokens")
  assert.ok(!JSON.stringify(s).includes("null") || s.peak !== null)
  for (const v of [s.tokens, s.avgTokens, s.hitRate]) assert.ok(Number.isFinite(v))
})

test("summary empty", () => {
  const s = A.summary([], A.periodRange("7d", 0, "2026-10-22", "", "", ""), "2026-10-22", {})
  assert.equal(s.tokens, 0)
  assert.equal(s.activeDays, 0)
  assert.equal(s.avgTokens, 0)
  assert.equal(s.peak, null)
  assert.equal(s.hitRate, -1)
})

test("chartBuckets fills days and coarsens long spans", () => {
  const week = A.periodRange("7d", 0, "2026-10-22", "", "", "")
  const buckets = A.chartBuckets(A.daysInRange(DAYS, week), week, "2026-10-22", {}, 3)
  assert.equal(buckets.length, 7)
  assert.equal(buckets[6].isToday, true)
  assert.equal(buckets[5].tokens, DAYS[0].messageCount)
  assert.ok(buckets[5].segments.some(seg => seg.model === "claude-opus-5-5"))
  const long = [{ date: "2025-09-01", messageCount: 5, modelUsage: { m: bucket(5, 0, 0, 0, 0) } }, ...DAYS]
  const all = A.periodRange("all", 0, "2026-10-22", "", "", "")
  const months = A.chartBuckets(A.daysInRange(long, all), all, "2026-10-22", {}, 3)
  assert.equal(months.length, 14)
})

test("modelRows sorts by cost and sessionRows filters by range", () => {
  const rows = A.modelRows(A.sumUsage(DAYS), {})
  assert.equal(rows[0].id, "claude-opus-5-5")
  assert.equal(rows[0].share, 1)
  const sessions = [
    { id: "a", title: "old", updatedAt: "2026-09-01T10:00:00Z", updatedAtMs: 1, totalTokens: 5,
      modelUsage: { "claude-opus-5-5": bucket(5, 0, 0, 0, 0) }, modelReasoning: {} },
    { id: "b", title: "new", updatedAt: "2026-10-22T10:00:00Z", updatedAtMs: 2, totalTokens: 9,
      modelUsage: { "claude-opus-5-5": bucket(1, 8, 0, 0, 0) }, modelReasoning: { "claude-opus-5-5": ["medium"] } },
  ]
  const out = A.sessionRows(sessions, A.periodRange("7d", 0, "2026-10-22", "", "", ""), {}, 5)
  assert.equal(out.length, 1)
  assert.equal(out[0].id, "b")
  assert.deepEqual(out[0].models[0].effort, ["medium"])
})

test("formatting", () => {
  assert.equal(A.formatMoney(-1), "—")
  assert.equal(A.formatMoney(1711.54), "$1,712")
  assert.equal(A.formatMoney(5.364), "$5.36")
  assert.equal(A.formatTokens(12_400_000), "12.4M")
  assert.equal(A.formatTokens(40_000), "40K")
  assert.equal(A.formatTokens(980), "980")
})

test("limit windows, pace and header line", () => {
  const now = Date.parse("2026-10-22T12:00:00Z")
  const windows = A.limitWindows({ limits: [
    { label: "Session (5-hour)", percent: 0.3, resetsAt: "2026-10-22T14:30:00Z" },
    { label: "Weekly (7-day)", percent: 0.02, resetsAt: "2026-10-29T00:00:00Z" },
    { label: "Broken", percent: null },
  ] })
  assert.equal(windows.length, 2)
  assert.equal(windows[0].title, "Session")
  assert.equal(windows[1].title, "Weekly")
  close(A.paceFor(windows[0], now), 0.5)
  assert.equal(A.limitDetail(windows[0], now), "Resets in 2h 30m · 20% under pace")
  assert.equal(A.formatDuration(3 * 86400000 + 3600000), "3d 1h")
  assert.equal(A.planLine({ tierLabel: "pro", subscriptionEndsAt: "2026-11-22T00:00:00Z" }, now), "Pro · renews in 30 days")
  assert.equal(A.planLine({ tierLabel: "", usageStatusText: "Sign-in expired" }, now), "Sign-in expired")
})

test("resolvePeriod falls back when cycle has no renewal", () => {
  assert.equal(A.resolvePeriod("cycle", 0, "2026-10-22", "", "", "").kind, "7d")
  assert.equal(A.resolvePeriod("cycle", 0, "2026-10-22", "2026-11-22", "", "").kind, "cycle")
  assert.equal(A.resolvePeriod("30d", -1, "2026-10-22", "", "", "").start, "2026-08-24")
})

test("an empty period on a priced provider costs $0, not —", () => {
  const range = A.periodRange("today", 0, "2026-10-22", "", "", "")
  const s = A.summary([], range, "2026-10-22", {}, true)
  assert.equal(s.cost, 0)
  assert.equal(s.priced, true)
  assert.equal(s.avgCost, 0)
  assert.equal(A.summary([], range, "2026-10-22", {}, false).cost, -1)
  assert.equal(A.providerPriced({ modelUsage: { "claude-opus-5-5": bucket(1, 1, 0, 0, 0) } }, {}), true)
  assert.equal(A.providerPriced({ modelUsage: { "fireworks/x": bucket(1, 1, 0, 0, 0) } }, {}), false)
})

test("chartBuckets reports its unit even when the first bucket is one day", () => {
  const custom = A.periodRange("custom", 0, "2026-10-22", "", "2026-08-02", "2026-10-22")
  const weeks = A.chartBuckets([], custom, "2026-10-22", {}, 3)
  assert.equal(weeks[0].unit, "week")
  assert.equal(weeks[0].first, "2026-08-02")
  const days = A.chartBuckets([], A.periodRange("7d", 0, "2026-10-22", "", "", ""), "2026-10-22", {}, 3)
  assert.equal(days[0].unit, "day")
})

test("monthGrid lays out six weeks from the week start", () => {
  const cells = A.monthGrid(2026, 9, 1, "2026-10-22")  // October 2026, Monday first
  assert.equal(cells.length, 42)
  assert.equal(cells[0].iso, "2026-09-28")  // Oct 1 2026 is a Thursday
  assert.equal(cells[0].inMonth, false)
  assert.equal(cells[3].iso, "2026-10-01")
  assert.equal(cells[3].inMonth, true)
  const today = cells.find(c => c.iso === "2026-10-22")
  assert.equal(today.isToday, true)
  assert.equal(cells.find(c => c.iso === "2026-10-23").future, true)
  assert.equal(A.monthGrid(2026, 9, 0, "2026-10-22")[0].iso, "2026-09-27")  // Sunday first
  assert.equal(A.monthGrid(2026, 9, 7, "2026-10-22")[0].iso, "2026-09-27")  // Qt's Sunday = 7
})

test("monthPreset gives calendar ranges clipped to today", () => {
  assert.deepEqual(A.monthPreset("thisMonth", "2026-10-22"), { start: "2026-10-01", end: "2026-10-22" })
  assert.deepEqual(A.monthPreset("lastMonth", "2026-10-22"), { start: "2026-09-01", end: "2026-09-30" })
  assert.deepEqual(A.monthPreset("thisYear", "2026-10-22"), { start: "2026-01-01", end: "2026-10-22" })
  assert.deepEqual(A.monthPreset("lastMonth", "2026-01-15"), { start: "2025-12-01", end: "2025-12-31" })
})

test("limitsFreshness says how old the limits are and why they are stale", () => {
  const now = 1_800_000_000_000
  assert.equal(A.limitsFreshness({}, now), "")
  assert.equal(A.limitsFreshness({ limitsFetchedAtMs: now - 2000 }, now), "Updated just now")
  assert.equal(A.limitsFreshness({ limitsFetchedAtMs: now - 42000 }, now), "Updated 42s ago")
  assert.equal(A.limitsFreshness({ limitsFetchedAtMs: now - 185000 }, now), "Updated 3m ago")
  assert.equal(A.limitsFreshness({
    limitsFetchedAtMs: now - 185000, limitsStale: true, limitsNote: "rate-limited", limitsRetryAtMs: now + 30500,
  }, now), "Updated 3m ago · rate-limited, retrying in 31s")
  assert.equal(A.limitsFreshness({ limitsFetchedAtMs: now - 185000, limitsStale: true }, now), "Updated 3m ago · stale")
})

// ---------------------------------------------------------------- pool
const NOW = Date.parse("2026-10-24T08:00:00Z")
const inH = (h) => new Date(NOW + h * 3600000).toISOString()
const win = (lengthSec, percent, resetH, started = true) => ({ lengthSec, percent, resetsAt: inH(resetH), started })
const POOL = {
  routed: true, endpoint: "127.0.0.1:8317",
  accounts: [
    { id: "f1", email: "free1@x", plan: "free", priority: 0, status: "ok", windows: [win(2592000, 0.25, 600)] },
    { id: "p2", email: "b@x", plan: "plus", priority: 100, status: "ok", lastActiveMs: NOW - 60000,
      windows: [win(18000, 0.5, 2.5), win(604800, 0.4, 84)] },
    { id: "p1", email: "a@x", plan: "plus", priority: 100, status: "ok",
      windows: [win(18000, 0, 5, false), win(604800, 0.2, 100)] },
    { id: "p3", email: "c@x", plan: "plus", priority: 100, status: "limited",
      windows: [win(18000, 1, 1), win(604800, 0.6, 50)] },
    { id: "x", email: "dead@x", plan: "plus", priority: 100, status: "expired", windows: [] },
    { id: "d", email: "off@x", plan: "free", priority: 0, status: "disabled", windows: [] },
  ],
}

test("accountView classifies idle, running, limited, expired", () => {
  const s = A.poolSummary(POOL, NOW)
  const by = Object.fromEntries(s.accounts.map((a) => [a.id, a]))
  assert.equal(by.p1.status, "idle"); assert.equal(by.p1.kickable, true)
  assert.equal(by.p2.status, "running"); assert.equal(by.p2.kickable, false)
  assert.equal(by.p3.status, "limited"); close(by.p3.freeInMs, 3600000)
  assert.equal(by.x.status, "expired")
  assert.equal(by.d.status, "disabled")
  assert.deepEqual(s.kickable.map((a) => a.id), ["p1"])
})

test("a window whose reset passed reads as reset", () => {
  const a = A.accountView({ id: "z", status: "limited", windows: [win(18000, 1, -1)] }, NOW)
  assert.equal(a.status, "idle")
  assert.equal(a.windows[0].percent, 0)
  assert.equal(A.accountView({ id: "y", status: "limited", windows: [] }, NOW).status, "limited")
})

test("poolSummary tiers by priority, plans first, emails next", () => {
  const s = A.poolSummary(POOL, NOW)
  assert.deepEqual(s.tiers.map((t) => [t.priority, t.label, t.open, t.total]), [[100, "Plus", 2, 4], [0, "Free", 1, 1]])
  assert.deepEqual(s.tiers[0].accounts.map((a) => a.id), ["p1", "p2", "p3", "x"])
  // The expired account holds no capacity, so the averages skip it.
  const [session, weekly] = s.tiers[0].windows
  close(session.percent, 0.5)
  assert.equal(session.full, 1)
  close(session.freeInMs, 3600000)
  close(weekly.percent, 0.4)
})

test("poolLimits feeds the bar and meters", () => {
  const limits = A.poolLimits(POOL, NOW)
  assert.deepEqual(limits.map((l) => l.title), ["Session", "Weekly"])
  assert.equal(limits[0].subtitle, "3 Plus pooled")
  const windows = A.limitWindows({ limits })
  close(A.paceFor(windows[0], NOW), limits[0].pace)
  assert.match(A.limitDetail(windows[0], NOW), /^2\/3 have room · frees up in 1h 0m · /)
  assert.match(A.limitDetail(windows[1], NOW), /^2\/4 open · next reset 2d 2h · /)
  assert.deepEqual(A.poolLimits({ accounts: [] }, NOW), [])
})

test("one account reads as one account", () => {
  const solo = { routed: true, accounts: [
    { id: "s", email: "solo@x", plan: "pro", priority: 0, status: "ok", windows: [win(18000, 0.3, 2), win(604800, 0.1, 100)] },
    { id: "off", email: "off@x", plan: "plus", priority: 0, status: "disabled", windows: [] },
  ] }
  const s = A.poolSummary(solo, NOW)
  assert.equal(s.single, true)
  assert.equal(s.only.id, "s")
  assert.equal(A.poolPlanLine(solo, NOW), "Pro · via CPAMC")
  const limits = A.poolLimits(solo, NOW)
  assert.deepEqual(limits.map((l) => [l.title, l.label, l.pool]), [["Session", "5h window", undefined], ["Weekly", "Weekly (7-day)", undefined]])
  const windows = A.limitWindows({ limits })
  assert.match(A.limitDetail(windows[0], NOW), /^Resets in 2h 0m · /)
  // A pool whose serving tier has one account left with capacity shows that account, not an average.
  const leftover = { routed: true, accounts: [POOL.accounts[1], { ...POOL.accounts[2], status: "expired" }] }
  assert.equal(A.poolSummary(leftover, NOW).single, false)
  assert.equal(A.poolLimits(leftover, NOW)[0].pool, undefined)
  close(A.poolLimits(leftover, NOW)[0].percent, 0.5)
})

test("poolPlanLine", () => {
  assert.equal(A.poolPlanLine(POOL, NOW), "Pool · 4 Plus + 1 Free")
  assert.equal(A.poolPlanLine({ ...POOL, routed: false }, NOW), "CPAMC · 4 Plus + 1 Free")
})

test("in use only while usage keeps rising", () => {
  const running = (last) => ({ id: "r", status: "ok", lastActiveMs: last, windows: [win(18000, 0.3, 3)] })
  assert.equal(A.accountView(running(NOW - 60000), NOW).status, "running")
  assert.equal(A.accountView(running(NOW - 4 * 60000), NOW).status, "quiet")
  assert.equal(A.accountView(running(NOW - 11 * 60000), NOW).status, "quiet")
  assert.equal(A.accountView(running(0), NOW).status, "quiet")
  assert.equal(A.accountView(running(NOW - 11 * 60000), NOW, 20 * 60000).status, "running")
  const busy = A.accountView({ ...running(NOW - 30000),
    recentTokens: [[NOW - 10 * 60000, 999], [NOW - 120000, 4000], [NOW - 60000, 1500]] }, NOW)
  assert.equal(busy.recentTokens, 5500)
  const quiet = A.accountView(running(0), NOW)
  assert.equal(quiet.usable, true)
  assert.equal(quiet.kickable, false)
})
