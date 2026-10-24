# OmaAgents

AI coding agent usage for the [Omarchy](https://omarchy.org) bar. One icon
shows your Claude Code / Codex session and weekly limits; click it for a calm
glance at limits with pace, today's tokens and API-equivalent cost, and one
step further for a details report: any period, models, sessions, cache hit
rate and cost mix.

Supports **Claude Code**, **Codex** and **Fireworks** (prepaid balance), and
pools of accounts behind [CPAMC](#account-pools-cpamc): pooled limits, every
account's own windows, and one-click kicks for idle ones.

## Install

```bash
omarchy plugin add https://github.com/SherryMaster/omaagents --enable
```

Then put it in your bar with `omarchy plugin enable io.github.sherrymaster.omaagents`
(or pick it in the bar settings). Update later with
`omarchy plugin update io.github.sherrymaster.omaagents`.

**Requires** an Omarchy release that ships the agent usage collectors
(`/usr/share/omarchy/bin/omarchy-agent-usage-*`), Python 3, and `jq`. Claude
limits need a signed-in Claude Code CLI; Codex limits need a signed-in Codex
CLI. Usage never leaves your machine except the providers' own limit
endpoints that the Omarchy collectors already call.

## How it works

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
  one small chip per enabled agent. With synced numbers the email line adds
  "· N devices".
- **Limits** — each allowance's percentage used, a meter with a pace tick
  (where usage would sit if spread evenly over the window), and "Resets in …
  · on pace / N% under / ahead of pace". Prepaid agents show their credit
  balance instead. Under the meters, how old the limits are ("Updated 40s
  ago"), and when the provider refused the last check, why and when the next
  one happens ("· rate-limited, retrying in 45s").
- **Today** — tokens and API-equivalent cost for the glance period (setting,
  default Today) over a 7-day column chart; hover a column for its numbers.
- **Details ›** — opens the report (Enter does too).

**Details**

- **Period** — one row: `Today · 7D · 30D · Cycle · All · …`. The line below
  shows the range with `‹ ›` to step back and forward by the period's own
  length (a day, 7 or 30 days, or a billing cycle). `…` is a custom range: it opens a
  calendar — click the first day, then the last (the range previews as you
  hover), or use This month / Last month / This year. Days with usage carry a
  dot, and the scroll wheel flips months. Click the range summary to reopen it. Cycle appears when a renewal date is
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
`omarchy plugin disable io.github.sherrymaster.omaagents`.

## Account pools (CPAMC)

[CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) (CPAMC) can hold
many accounts per provider and spread an agent's traffic across them. When
it holds accounts for Codex or Claude, `bin/account-pool` reads each one's
own limits — in parallel, read-only, with the access token CPAMC already
stores — and attaches them to the agent's record as `pool`. It never
refreshes or rewrites a credential: refresh tokens rotate, and a second
writer would break CPAMC's copy.

CPAMC is found through `$CPAMC_CONFIG`, `~/.config/cliproxyapi/config.yaml`
or `~/.cli-proxy-api/config.yaml` (its `auth-dir` and port). The agent counts
as **routed** when its own config sends traffic to that port on localhost —
Codex's `model_provider` base URL in `~/.codex/config.toml`, Claude's
`ANTHROPIC_BASE_URL` in the environment or `~/.claude/settings.json`.

**Routed**, the pool replaces the signed-in account everywhere: the bar's
`session | weekly` figures, the header ("7 accounts via CPAMC", "POOL · 3
PLUS + 4 FREE") and the limit meters are the serving tier's averages
("3 Plus pooled"), with "2/3 have room · frees up in 1h 10m · on pace" under
each. **Not routed**, the accounts still list, flagged "not routed", and the
meters stay the signed-in account's.

**One account.** With a single account to work with (disabled ones don't
count), the pool vocabulary goes away: the header shows that account's email
"via CPAMC" and "PRO · VIA CPAMC", the meters are its own windows with the
usual reset and pace line, and the section is one row without a tier header
or checkbox — the kick can only mean it. Likewise, a serving tier left with a
single account that has capacity shows that account's windows, not an
average.

**Accounts.** Accounts group into tiers by CPAMC `priority` — the highest
tier serves while any of it has room, lower tiers are overflow and fold into
a one-line summary until clicked. Each row shows the account, a mini meter
per window with its reset, and its state as glyph and word: `● in use`
(it served tokens within `inUseMinutes`, default 3), `○ idle` (no recent use;
accent-colored with a checkbox when its window hasn't started, so a kick
would start it), `■ full · 1h 10m`, `▲ sign in again`, `– disabled`.

Use is literal tokens. Codex logs every turn's tokens together with the
serving account's rate limits, and each account's reset instants are unique,
so `account-pool` matches the last 15 minutes of turns in
`~/.codex/sessions` to their accounts (tooltip: "In use — 18.2K tokens in the
last 3m"). That read is local and runs on every pass, fast ones included.
Clients that don't write Codex session logs still register through the
account's usage percent rising. A kick only starts a window, so it never
counts as use. The account Codex itself is signed in to carries `SIGN-IN`.
Hover a row for every window's numbers. With `showAccount` off, emails read
"Account 1…N".

**Kick.** Idle accounts carry a checkbox; click rows to select them. The
action button kicks the selection, or every idle account when none is
selected ("Kick (2)" / "Kick 2 selected"; Shift+K does the same). A
kick is one tiny request through
[`codex-kick`](#codex-kick) that starts the account's window so it resets
sooner; the button spins while it runs, the line under the list reports
what happened, and the pool is re-read at once. The button is dimmed with
the reason — in its tooltip and in plain text under the list — when
`codex-kick` is missing, when its `--probe` fails (with the error), when
nothing is idle, or for Claude, which it doesn't support.

**Claude accounts** go through the same pool, with three differences.
CPAMC's Claude files carry no plan, so it is read from the account's OAuth
profile once a day ("Pro", "Max 5x", "Max 20x"). The account Claude Code
itself is signed in to is never asked twice: the pool reuses the limits the
Claude collector just fetched (stale marker included), since Anthropic's
endpoint allows about one check per account every two minutes. And Claude
Code transcripts don't record which account served a reply, so token-based
"in use" works when one Claude account serves a routed Claude Code; with
several, an account reads as in use when its usage percent rises. Kicking
is Codex-only.

Account checks reuse a per-account cache in
`~/.cache/omarchy/agent-usage/pool-<agent>-v1.json`: Codex accounts are
re-read at most every 30 seconds, Claude accounts every 150 (Anthropic's
endpoint is strict), with a backoff after refusals. Local-only passes never
touch the network.

### codex-kick

`codex-kick` is a separate command (not shipped with the plugin) that the
panel finds on `PATH` or in `~/.local/bin`. The panel needs two modes from
it: `codex-kick --probe` prints `{"ok": true, …}` when it works, and
`codex-kick --json <email…>` kicks exactly those accounts and prints one
JSON object with a per-account `action` (`kicked`, `already_running`,
`limit`, `error`, `would_kick` with `-n`).

## Data

Each agent is one JSON record in `~/.local/state/omarchy/agents/usage/`,
written by the plugin's `bin/usage-update`. That command runs one
`omarchy-agent-usage-<agent>` collector per agent — wrapped by
`bin/codex-collector` and `bin/claude-collector` for those two — and the
widget picks up any record that lands in the directory regardless of who
wrote it.

Refreshing is automatic; there is no button. Each agent with a record gets
its own queue (`UpdateLane.qml`): runs within a queue never overlap, so a
record has one writer at a time, while queues run side by side, so Codex's
few-second RPC never holds Claude back. Requests that arrive while a run is
busy merge into one follow-up instead of being dropped. One clock drives
every queue:

| | Panel open | Panel closed |
|---|---|---|
| Opening the panel | every agent refreshes on the spot | — |
| Claude and Codex local usage | every `fastIntervalSec` (5 s) | with the limits pass |
| Claude limits | every 30 s | every 2 min |
| Codex limits | every 15 s | 15 s while Codex is in use, else 60 s |
| Other agents (Fireworks billing) | `refreshIntervalSec` (5 min), and on open if older than a minute | `refreshIntervalSec` |

Local passes never touch the network: they reuse the last account limits
and only reread session files whose size or mtime changed. Codex's per-file
token cache lives in SQLite under `~/.cache/omarchy/agent-usage/`; its
session index uses the same change detection. `bin/claude-session-enricher`
adds Claude's full per-day, per-model history and the session index from the
same transcripts, caching each file's parsed messages by size and mtime in
`~/.cache/omarchy/agent-usage/claude-session-index-v1.json`. Session titles
come from Claude Code's own titles, falling back to the first prompt, and
subagent transcripts count toward their parent session.

Anthropic's usage endpoint rate-limits hard — roughly one answer every two
minutes, with 429s (carrying `Retry-After: 0`) for the rest — so Claude's
cadence is paced to that budget and `bin/claude-limits.pyfrag` backs off
after a refusal (1, 2, 4, then 5 minutes), never probing inside the backoff.
A probe under 15 seconds old is reused. The last good limits stay on screen
marked with their age. Agents without a record yet are found by a discovery
pass every `refreshIntervalSec`. A full forced scan remains available through
`bin/usage-update --force`.

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
  A missing window is omitted; no limits shows `—`. Left-click opens the panel
  (which refreshes it), right-click refreshes the selected agent without
  opening; middle-click has no action.
- Bar figures and popup limit meters share colors at 25%, 50%, 75%, 90%,
  and 95% used: green, teal, lime, amber, orange, then red.
- Failed refreshes retain last known limits and mark them stale, with their
  age, in the bar tooltip and under the meters. Automatic refresh continues.
- Glance: `h`/`l` or the header chips switch agent, `r` refreshes, Shift+K
  kicks the selected (or every idle) pooled account, Enter opens Details, Esc
  closes.
- Details: `←`/`→` step the period, `1`–`5` pick Today/7D/30D/Cycle/All,
  `j`/`k` scroll, Esc or Backspace go back. Closing the popup returns to the
  glance.
- Tab moves to the neighbouring bar panel, as everywhere in the shell.
- IPC: `omarchy-shell omaagents <open|close|toggle|refresh|next|details|kick>`.

## Settings

Settings live in the widget's entry in `~/.config/omarchy/shell.json`. The
top-level keys can be set with
`omarchy bar set io.github.sherrymaster.omaagents <key> <value>`:

| Key | Default | What it does |
|---|---|---|
| `glancePeriod` | `"Today"` | Period on the glance: `Today`, `7D`, `30D` or `Cycle` |
| `showAccount` | `true` | Show the account email (turn off for screen sharing) |
| `inUseMinutes` | `3` | A pooled account reads "in use" while it served tokens within this many minutes |
| `refreshIntervalSec` | `300` | Refresh of agents without a faster cadence (Fireworks billing), and discovery of new ones |
| `fastIntervalSec` | `5` | Claude and Codex local usage refresh while the panel is open |
| `syncMode` | `"Off"` | `"On"` writes this machine's snapshot and merges the others |
| `syncDir` | `""` | A folder synced by Syncthing, Dropbox, rsync, … |
| `syncFileName` | `<hostname>.json` | This machine's snapshot file |
| `syncDeviceId` | hostname | Stable device name inside the snapshot |

Numbers need `--json`, or they land in `shell.json` as strings:

```bash
omarchy bar set io.github.sherrymaster.omaagents fastIntervalSec 5 --json
omarchy bar set io.github.sherrymaster.omaagents syncDir '~/Sync/agent-usage'
```

Per-agent enablement is nested, and `set` writes its key literally rather
than walking a dotted path — so pass the whole `providers` object as JSON (or
edit `shell.json` directly):

```bash
omarchy bar set io.github.sherrymaster.omaagents providers '{
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
entitlement, fetched during account refreshes. The next renewal
(or access end for a cancelled subscription) is cached per account; local
usage passes reuse that date without making network requests. The panel
recalculates every second while open,
showing full days, then hours below one day, then minutes below one hour.
Offline refreshes retain a valid cached date. Past login-token dates never
produce an expiry message or an invented future billing period.

## Credits

Started as a clone of Omarchy's built-in `omarchy.agents` bar plugin and its
usage collectors ([basecamp/omarchy](https://github.com/basecamp/omarchy),
MIT). Rebuilt with a two-page panel, Claude daily history, sessions and cost,
account display, and the analytics library.
