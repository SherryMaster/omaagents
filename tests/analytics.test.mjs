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
