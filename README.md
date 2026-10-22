# Agents

One bar icon and one panel for every AI coding subscription on the machine.
The panel is strictly a display: it watches the usage records that
`omarchy-agent-usage-update` writes to `~/.local/state/omarchy/agents/usage/`
and draws whatever appears there. `Panel.qml` owns the bar button and the
popup; `Main.qml` discovers and watches the records (and handles the optional
cross-device aggregation); `Agent.qml` is the per-record file watcher.

## Panel

- **Hero** — the mark, the tool, and the plan it runs on ("Max 20x", "Pro").
  Auth and endpoint problems replace the plan line and repeat in a card.
- **Subscription switch** — one chip per enabled agent (`h`/`l` or click).
- **Subscription countdown** — the days remaining beside the plan in the
  panel header. Codex reads it from the signed account token; Claude derives
  the next renewal from the subscription start date Claude Code caches in
  `~/.claude.json`, assuming monthly billing (an annual plan would show the
  next monthly anniversary instead).
- **Limits** — the percentage of each allowance used, a matching meter with a
  pace tick (where usage would sit if spread evenly over the window, with
  "ahead of"/"under pace" beside the reset time), and
  the time until the session or weekly window resets.
- **Balance** — prepaid agents report a credit ledger instead of limits:
  remaining credit, a fuel-gauge meter that drains toward empty, and
  funded-versus-spent detail.
- **Insight** — a fourth analytics view for the selected period: daily
  average per active day, projection to the period's end (or the peak day
  once a period is over), cache hit rate, the API cost the cache saved, and a
  100% stacked mix of input, output, cache-write, and cache-read tokens (or
  their cost), largest first with values and shares. The Subscription period
  covers the current billing cycle when a renewal date is known.
- **Usage analytics** — a compact Tokens/Cost switch and period navigator
  control the total, timeline, per-model, and session views. Sessions are
  filtered to the selected period before the five latest matches are shown. The
  period cycles through Today, Week, Month, Year, Subscription, All time, and
  Custom; arrows browse a specific day/week/month/year, while Custom exposes
  ISO start/end fields only while it is active. Sessions sort by their
  latest interaction rather than creation time. Cost mode rates each day's,
  model's, and session's uncached input, output, cache-read, and cache-write tokens against
  the official standard API prices — OpenAI's for Codex, Anthropic's for
  Claude. Claude's cache writes are split by TTL: 5-minute writes at 1.25x
  input and 1-hour writes (Claude Code's default) at 2x. Internal model IDs
  without a published price display an em dash and are excluded from cost
  totals. The Cost switch is available for any agent with a priced model.
  The plugin refreshes OpenAI's published Standard text-token rates once a day
  and caches them in `~/.local/state/omarchy/agents/api-pricing.json`, so newly
  listed models can be priced without editing the widget. It keeps the last
  good cache if the page cannot be read. Bundled rates for GPT-6.1 Sol, GPT-6 Astra, Sol,
  Luna, and GPT-5.6 remain available offline; Claude rates (Fable, Opus,
  Sonnet, and Haiku, 4.5 onward) are bundled in `Panel.qml`. The estimate uses short-context
  Standard rates; the usage records do not contain enough detail to identify
  long-context requests or other API processing tiers.

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
- Hero refresh button: refresh the selected subscription immediately; Codex
  local usage appears first, then its account limits. The button spins while
  the selected provider check is running.
- Panel: click the period label to move forward through scopes and right-click
  it to move backward; period arrows browse historical calendar periods.
  `h`/`l` switch subscription, `j`/`k` scroll, `r` or Enter refresh,
  `t`/`c` switch metric, `1`/`2`/`3`/`4` select day/model/sessions/insight, Tab moves to
  the neighboring bar panel, Esc closes.
- IPC: `omarchy-shell omarchy.agents <open|close|toggle|refresh|next>`.

## Settings

Settings live in the widget's entry in `~/.config/omarchy/shell.json`. The
top-level keys can be set with
`omarchy bar set sherry.agents <key> <value>`:

| Key | Default | What it does |
|---|---|---|
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
