# Agent Burn for macOS

Native SwiftUI dashboard and menu-bar app, backed by the Rust Agent Burn CLI.
macOS 14 or newer. Public releases contain Apple Silicon and Intel binaries.

The Codex and Claude menu-bar tabs focus on remaining quota, its reset time, and
a compact usage forecast. Expand **Usage details** for spend, plan pricing, and
top models. Saved readings and update failures remain visible beside the quota.

## Install

[Download Agent Burn](https://agent-burn.melvynx.dev/download), unzip it, move
Agent Burn.app to Applications, and open it. No Node.js installation is needed.
Enable **Settings → Startup → Launch at login** to start automatically when you
sign in. Registration uses macOS Login Items; any required approval is shown in
Settings. Disable the option to remove the login item. Menu-bar-only mode is
respected at startup.

Use Settings to configure sources. The menu-bar percentage can show Codex, Claude, or Cursor remaining
quota; change it from the percentage menu or **Settings → Menu bar quota**. Enable **Settings → Appearance → Menu bar only** to hide the app from
the Dock and Command-Tab. The preference survives restarts; the dashboard and
Settings remain accessible from the menu-bar icon. Disable it to restore Dock
visibility.

The official full-color logo is shared by Finder, the Dock, Command-Tab, window
icons, and the menu bar, including when running through Swift Package Manager.

## Build and test

From this directory:

```sh
./build.sh
open 'dist/Agent Burn.app'
swift test --disable-keychain --disable-xctest
```

Xcode 16 or newer and Rust are required. The repository Nix dev shell provides
CLI tooling; Xcode provides Apple SDKs. `just macos::build` and
`just macos::test` are equivalent root tasks. Swift dependencies are pinned in
Package.resolved. The default build is ad-hoc signed for local development.

## Data

Period changes immediately filter saved daily totals. Missing model detail loads
in the background without disabling the selector. Recent reports are reused, and
rapid changes load the latest selected period. Harness tabs read only their own
source; General reads all sources. Automatic refresh maintains history and recovery
files without dashboard controls. If a refresh fails, saved data stays visible.

Codex, Claude, and Cursor promotional-credit quotas are collected every minute by a macOS background agent,
even after the app quits. Enable or disable this in **Settings → Background quota
history**; allow background activity in macOS Settings if requested. The agent
reads live provider counters independently of full spend reports and cached mode.
Collection resumes after sleep or login. During outages, the last valid reading
and its timestamp remain visible; missed measurements are not fabricated.

`quota-archive.json` keeps collected quota readings without expiration, with a
previous valid `.bak` copy. Existing `quota-history.json` is preserved as a saved
reading fallback. `quota-collector.json` contains source paths, never credentials.

`usage-journal.json` keeps changed report snapshots per source. If both
`report-cache.json` and its `.bak` are unreadable, the journal rebuilds daily graphs
and model totals. Quota screens count scheduled and possible resets from remaining
jumps, and show Codex banked rate-limit resets when the live meter
reports them. **Reset to date** filters spend from the current cycle start.
The Claude dashboard shows the same live account meters Claude Code reports:
session remaining, weekly remaining, scoped model weeks, and extra-usage
credits when Claude returns them. The Codex and Claude dashboard quota card
shows when the current weekly limit started and how much of it has been used,
next to the reset time. Cursor uses that same remaining chart while promotional
credits are burning, then the daily spend chart with All models and Cursor models
filters once those credits are gone. It also
crosses live used percent with API-equivalent spend for an average $ / %,
and logged tokens with spend for tokens / $. The cycle
chart starts the recorded line at that limit and can show the current cycle
until reset, reset to today, today, the last 7 days, or the last 30 days. That
picker does not change the spend period. Claude always charts the current week,
next to a 5-hour session chart recorded by the same background collector.

Metrics are stored under `~/Library/Application Support/Agent Burn/`.
`metrics-history.json` keeps days providers stop returning. Days still present
in an all-time snapshot follow that latest report, so a stale `today` or
`month` cache cannot double the same day's spend. Filtered period snapshots
only fill missing dates. There is no expiration. Its `.bak` is the previous valid copy. No prompts or
conversations are archived. Back up this directory to protect against disk loss.
Old data absent from every source cannot be reconstructed. Model breakdowns
reflect available source data, rather than invented historical precision.

The app does not send usage to an Agent Burn service. Live CLI mode can contact
provider endpoints and pricing sources. The app never checks for updates on its
own: new versions ship as DMG files on this fork's GitHub releases.

## Release process

1. Increase `Config/version` using `major.minor.patch`. Never reuse a version.
2. Commit and push the exact source to the `origin` repository.
3. Run `./release.sh` (needs `rustup`, `create-dmg` and an authenticated `gh`).

The script builds universal binaries, packs `dist/Agent-Burn-<version>.dmg`
and publishes it as the `macos-v<version>` release of `origin`. Without
`AGENT_BURN_SIGN_IDENTITY` the app is signed ad-hoc and not notarized, so the
first launch needs **System Settings → Privacy & Security → Open Anyway**.

Agent Burn is MIT licensed. Provider logos belong to their respective owners and identify
supported integrations; no endorsement is implied.
