# Agents

One bar icon and one panel for every AI coding subscription on the machine.
The panel is strictly a display: it watches the usage records that
`bin/usage-update` writes to `~/.local/state/omarchy/agents/usage/` and draws
whatever appears there. `Panel.qml` owns the bar button, the popup, keyboard
and IPC; `GlanceView.qml` and `DetailsView.qml` are its two pages, built from
`components/`; `Analytics.js` holds every calculation (pricing, periods,
summaries, charts) as plain functions tested in `tests/`; `Main.qml` discovers
and watches the records (and handles the optional cross-device aggregation);
`Agent.qml` is the per-record file watcher.

## Panel

The popup has two pages. The first answers "how am I doing" without a click;
everything deeper is one step away.

**Glance**

- **Header** — the agent's mark and name, the signed-in account email, and
  the plan with its renewal countdown ("PRO · RENEWS IN 30 DAYS"). Auth and
  endpoint problems replace the plan line and repeat in a card. On the right,
  one small chip per enabled agent and the refresh button. With synced
  numbers the email line adds "· N devices".
- **Limits** — each allowance's percentage used, a meter with a pace tick
  (where usage would sit if spread evenly over the window), and "Resets in …
  · on pace / N% under / ahead of pace". Prepaid agents show their credit
  balance instead.
- **Today** — tokens and API-equivalent cost for the glance period (setting,
  default Today) over a 7-day column chart; hover a column for its numbers.
- **Details ›** — opens the report (Enter does too).

**Details**

- **Period** — one row: `Today · 7D · 30D · Cycle · All · …`. The line below
  shows the range with `‹ ›` to step back and forward by the period's own
  length (a day, 7 or 30 days, or a billing cycle). `…` is a custom range: the
  range line turns into two date fields. Cycle appears when a renewal date is
  known.
- **Four figures** — cost, tokens (with active days), daily average per active
  day (with a projection to renewal for the current cycle, otherwise the peak
  day), and cache hit rate with the money the cache saved.
- **By day / week / month** — columns stacked by the period's top models; the
  unit coarsens for long periods. Hover for per-model numbers.
- **Models** — cost and tokens per model with a share bar; hover for the
  input/output/cache split.
- **Mix** — a 100% bar of cost (or tokens when unpriced) by input, output,
  cache write and cache read, labelled with values and shares.
- **Sessions** — the five latest in the period; click one to expand its
  models, tokens, cost, reasoning effort, cache hit rate and last activity.

Cost rates input, output, cache-read and cache-write tokens at standard API
prices — OpenAI's for Codex, Anthropic's for Claude — as an equivalent, not a
charge. Claude's cache writes are split by TTL: 5-minute writes at 1.25x
input, 1-hour writes (Claude Code's default) at 2x. Models without a
published price show an em dash and are excluded from totals. OpenAI's
Standard rates refresh daily into
`~/.local/state/omarchy/agents/api-pricing.json` (the last good copy is kept);
bundled rates for both providers live in `Analytics.js` for offline use. The
estimate uses short-context Standard rates; the records cannot identify
long-context requests or other processing tiers.

**Account and renewal.** Claude's email and subscription start come from
`~/.claude.json`; the renewal assumes monthly billing anchored on the start
date. Codex's email is the `email` claim of the locally stored ChatGPT id
token (decoded on the machine, never sent anywhere); its renewal comes from
the account's live entitlement.

A subscription appears only when it is enabled in settings and has actually
recorded usage — on this machine or on a synced one. With one such agent
there is no switch row at all; with none, the module leaves the bar entirely
rather than sitting there with nothing to say. A CLI installed mid-session
shows up at the next refresh, so nothing polls the disk waiting for it.

That self-hiding is why the widget ships in the default bar layout: a machine
that has never run an AI coding agent draws nothing, and the icon arrives on
its own the first time a scan finds usage. Drop it with
`omarchy plugin disable sherry.agents`.

## Data

Each agent is one JSON record in `~/.local/state/omarchy/agents/usage/`,
written by the plugin's `bin/usage-update`. That command runs one
`omarchy-agent-usage-<agent>` collector per agent — wrapped by
`bin/codex-collector` and `bin/claude-collector` for those two; the widget invokes it
on separate local, limits, and full refresh timers, and picks up any
record that lands in the directory regardless of who wrote it.

Codex local usage refreshes every 5 seconds by default. Its local pass reuses
the last account limits and only rereads session files whose size or mtime
changed. The per-file token cache lives in SQLite under
`~/.cache/omarchy/agent-usage/`; the session index uses the same change
detection. Claude refreshes every 30 seconds; `bin/claude-session-enricher`
adds full per-day, per-model history and the session index from the same
transcripts, caching each file's parsed messages by size and mtime in
`~/.cache/omarchy/agent-usage/claude-session-index-v1.json`. Session titles
come from Claude Code's own titles, falling back to the first prompt, and
subagent transcripts count toward their parent session. Codex account limits refresh
every 15 seconds while local usage is changing and every 60 seconds while
idle. All providers, including Fireworks billing, refresh every 5 minutes.
Busy refreshes do not overlap. The manual refresh button updates the selected
subscription; Codex local changes appear first, followed by fresh account
limits. A full forced scan remains available through `bin/usage-update --force`.

Adding an agent therefore never touches this plugin: ship a collector that
prints the record contract (see the `claude` and `codex` collectors in
`bin/`), and the panel gains a tab. An `assets/<id>.svg` mark is optional —
with an `assets/<id>-light.svg` twin if the mark needs a dark variant for
light surfaces — and the bar glyph stands in when there is none.

| Collector | Limits | Local stats |
|---|---|---|
| `claude` | Anthropic's OAuth usage endpoint (5-hour session + 7-day weekly) | `~/.claude/projects` transcripts, opencode sessions on an Anthropic provider, plus `stats-cache.json` and `history.jsonl` as fallback |
| `codex` | The Codex app-server RPC | native Codex CLI session files (plus pi and opencode sessions) |
| `fireworks` | Estimated prepaid balance: configured funding minus rated account costs | Fireworks billing API, grouped by day and model for the last 30 days |

Claude limits need a signed-in CLI; without credentials the panel says so and
falls back to local stats only. A non-default Claude directory is honored via
`CLAUDE_CONFIG_DIR`, Codex via `CODEX_HOME`. Fireworks reads
`FIREWORKS_API_KEY` and `FIREWORKS_ACCOUNT_ID` first, then
`~/.fireworks/auth.ini` (which `firectl set-api-key` creates), then the key
opencode stores in `~/.local/share/opencode/auth.json` when Fireworks is
signed in there.

### Fireworks balance

The collector first asks the account's `:getBalance` endpoint for the real
prepaid ledger. That endpoint exists but is permission-gated, and as of
August 2026 no console-issued API key passes it — Fireworks appears to
reserve it for the dashboard session. The probe stays because it is cheap
and the live figure lights up automatically if Fireworks ever opens it to
keys. Until then the collector falls back to estimating the balance from
configuration in `~/.config/omarchy/agents/fireworks.json`:

```json
{
  "accountId": "",
  "fundedAmount": 20,
  "fundedAt": "2026-07-01"
}
```

Set `fundedAmount` to the credits purchased and optionally `fundedAt` to the
purchase date; with no date, the collector uses the account creation time. It
subtracts rated account costs and the panel labels the result as estimated.
For a later top-up, increase `fundedAmount` by the new credit while keeping
the original `fundedAt`, so both the funding and spend still cover the same
period. `accountId` only matters when one API key can access several
accounts. Without a configured `fundedAmount` the tab still shows token
usage, just no balance. With a live ledger, `fundedAmount` is optional and
only adds the meter and the spent-of-funded line under the real figure.

## Interactions

- Bar: provider logo followed by session and weekly percentages used (`5% | 10%`).
  A missing window is omitted; no limits shows `—`. Left-click opens the panel,
  right-click immediately refreshes usage; middle-click has no action.
- Bar figures and popup limit meters share colors at 25%, 50%, 75%, 90%,
  and 95% used: green, teal, lime, amber, orange, then red.
- Failed refreshes retain last known limits in memory and mark them stale in
  the bar tooltip. Automatic refresh continues at the configured interval.
- Refresh button: refresh the selected subscription immediately; Codex
  local usage appears first, then its account limits. The button spins while
  the selected provider check is running.
- Glance: `h`/`l` or the header chips switch agent, `r` refreshes, Enter opens
  Details, Esc closes.
- Details: `←`/`→` step the period, `1`–`5` pick Today/7D/30D/Cycle/All,
  `j`/`k` scroll, Esc or Backspace go back. Closing the popup returns to the
  glance.
- Tab moves to the neighbouring bar panel, as everywhere in the shell.
- IPC: `omarchy-shell omarchy.agents <open|close|toggle|refresh|next|details>`.

## Settings

Settings live in the widget's entry in `~/.config/omarchy/shell.json`. The
top-level keys can be set with
`omarchy bar set sherry.agents <key> <value>`:

| Key | Default | What it does |
|---|---|---|
| `glancePeriod` | `"Today"` | Period on the glance: `Today`, `7D`, `30D` or `Cycle` |
| `showAccount` | `true` | Show the account email (turn off for screen sharing) |
| `refreshIntervalSec` | `300` | Full refresh of all providers, including billing |
| `fastIntervalSec` | `5` | Codex local usage refresh interval |
| `syncMode` | `"Off"` | `"On"` writes this machine's snapshot and merges the others |
| `syncDir` | `""` | A folder synced by Syncthing, Dropbox, rsync, … |
| `syncFileName` | `<hostname>.json` | This machine's snapshot file |
| `syncDeviceId` | hostname | Stable device name inside the snapshot |

Numbers need `--json`, or they land in `shell.json` as strings:

```bash
omarchy bar set sherry.agents fastIntervalSec 5 --json
omarchy bar set sherry.agents syncDir '~/Sync/agent-usage'
```

Per-agent enablement is nested, and `set` writes its key literally rather
than walking a dotted path — so pass the whole `providers` object as JSON (or
edit `shell.json` directly):

```bash
omarchy bar set sherry.agents providers '{
  "claude": { "enabled": true },
  "codex": { "enabled": false },
  "fireworks": { "enabled": true }
}' --json
```

`enabled` defaults to `true` for every discovered agent; set it to `false` to
hide a subscription that is installed. Disabled agents are also skipped when
the records regenerate.

With `syncMode` on, every `*.json` snapshot in `syncDir` is merged, so today,
the last 7 days, and the all-time totals cover every machine you code on —
active days are unioned by date rather than summed. Rate limits stay
per-account and are never merged. A record may declare `"scope": "account"`
when its stats are account-global rather than machine-local (Fireworks'
billing API); those merge by taking the widest value instead of summing, so
the same account synced from two machines is not counted twice.

One caveat on "all-time": the Codex collector only reads native session files
touched in the last 30 days, and Fireworks requests the last 30 days from its
billing API, so their totals and day counts cover that window. Claude's cover
every transcript still on disk.

Subscription countdowns use the selected Codex account's live ChatGPT
entitlement, fetched during account and manual refreshes. The next renewal
(or access end for a cancelled subscription) is cached per account; local
usage passes reuse that date without making network requests. The panel
recalculates every second while open and immediately on manual refresh,
showing full days, then hours below one day, then minutes below one hour.
Offline refreshes retain a valid cached date. Past login-token dates never
produce an expiry message or an invented future billing period.
