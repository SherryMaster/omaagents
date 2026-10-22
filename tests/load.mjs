// Loads the QML JS library into Node: drop the .pragma line and expose its
// top-level functions.
import { readFileSync } from "node:fs"

const NAMES = ["pricing", "bucketCost", "periodRange", "daysInRange", "sumUsage", "summary",
  "chartBuckets", "modelRows", "sessionRows", "formatTokens", "formatMoney"]

export function loadAnalytics() {
  const source = readFileSync(new URL("../Analytics.js", import.meta.url), "utf8")
    .replace(/^\.pragma library\s*$/m, "")
  return new Function(source + "\nreturn {" + NAMES.join(",") + "}")()
}
