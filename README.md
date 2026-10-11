# Dev Stats

A contribution-activity grid for the Omarchy bar, in the style of the GitHub profile graph. One widget, several platforms:

![Dev-stats preview](preview.png?v=2=1.1.0)

| Platform | Login (once, in a terminal) | Source of the numbers |
| --- | --- | --- |
| GitHub / GitHub Enterprise | `gh auth login` | GraphQL contribution calendar |
| GitLab / self-hosted GitLab | `glab auth login` | your activity events, counted per day |
| Forgejo / Gitea / Codeberg | `tea login add` or `fj auth login` | the instance's public heatmap endpoint |

## On the bar

```text
[ logo ] ▪▪▪▪▪▪▪
```

The bar shows the last 7 days of the selected account as coloured squares (3 to 14 days, and the logo can be hidden).

- **Left click**: opens the panel (configurable).
- **Middle click**: refreshes (configurable).
- **Right click**: opens the panel on the Bar tab.

## The panel

A floating panel anchored to the bar, closed with `Esc` or a click outside. Changes apply instantly.

| Tab | What is in it |
| --- | --- |
| **Grid** | Account tabs, the chips for the rolling last year and each calendar year, the contribution grid with streaks, per-day hover details, Refresh |
| **Bar** | Show the platform icon, days on the bar (3 to 14), left and middle click actions |
| **Data** | Refresh automatically, refresh interval (5 to 240 minutes) |
| **Look** | Grid color (6 presets or any hex), panel colors: Follow theme, Custom (8 presets or a hex), Monochrome |

Every setting has a plain-language hint and a reset arrow once it differs from the default. The switch in the header turns automatic refreshing on and off, and **Reset all** (asks twice) puts every setting back to its default.

## Install

```sh
omarchy plugin add https://github.com/qempexe/omarchy-dev-stats.git --enable --yes
```

## Requirements

`bash`, `jq` and `curl`, plus the CLI for each platform you use (`gh`, `glab`, and `tea` or `fj`). Only the CLIs for platforms you actually use are needed.

## Accounts

Accounts are found automatically from your existing CLI logins. To add one by hand (or to follow a public profile), create `~/.config/dev-stats/accounts.json`:

```json
[
  { "provider": "forgejo", "host": "codeberg.org", "user": "yourname" },
  { "provider": "gitlab",  "host": "gitlab.example.com", "user": "yourname" }
]
```

`provider` is `github`, `gitlab` or `forgejo` (`gitea` is accepted as an alias).

## Settings

| Setting | Values | Default |
| --- | --- | --- |
| `showIcon` | `true`, `false` | `true` |
| `days` | 3 to 14 | `7` |
| `clickAction` | `panel`, `refresh`, `none` | `panel` |
| `middleAction` | `refresh`, `panel`, `none` | `refresh` |
| `autoRefresh` | `true`, `false` | `true` |
| `refreshMinutes` | 5 to 240 | `30` |
| `gridColor` | `#rrggbb` hex color | `#39d353` |
| `panelColor` | `theme`, `custom`, `monochrome` | `theme` |
| `panelCustomColor` | `#rrggbb` hex color | `#7aa2f7` |

`gridColor` is the color of the busiest days. The quieter levels are darker shades of the same color. An invalid value falls back to the default green. Settings are saved in `~/.local/state/omarchy-dev-stats/settings.json`; edits made there by hand are picked up while the shell runs.

If you used 1.1.x, the grid color you picked is moved over from `~/.config/dev-stats/color` the first time 1.2.0 runs.

## Security and privacy

* The QML code makes no network requests. Fetching happens in `bin/dev-stats.sh`, which runs your own `gh`, `glab` and `curl` as your user.
* The plugin never reads, prints or stores access tokens. It reads only the host and account names from the CLI config.
* Host and account names are validated before they reach any command line, and may not start with `-`.
* The only file written is `~/.local/state/omarchy-dev-stats/settings.json`, which holds the settings shown in the panel. Results are held in memory only.
* Text fields in the panel are drawn by `SettingRow` (never a native `TextInput`), so nothing watches the clipboard on its own. Pasting uses `wl-paste` (`wl-clipboard`), read at most 1 KB for at most 2 seconds, only when you press Ctrl+V.

## Limitations

* Year selection: GitHub offers every year your account has activity. GitLab offers the last three calendar years (its events API keeps about three years). Forgejo/Gitea only expose the last year, so no year chips appear for them.
* GitLab has no public calendar API, so Dev-stats counts your activity events per day. Numbers can differ slightly from GitLab's own graph.
* Forgejo/Gitea use the public heatmap endpoint over HTTPS. Private profiles and plain-HTTP instances are not supported.
* Account discovery for `tea` and `fj` depends on their config formats. If an account is not found automatically, use `accounts.json`.
* Month and weekday labels are English.

## How it works

```text
BarWidget.qml      the bar squares and clicks; fetches and holds the data; reads settings
SettingsPopup.qml  the panel (tabs, account and year chips, the grid, theme colors)
SettingRow.qml     one setting: segments, chips, tiles, slider, switch, text field, colors
SettingsStore.qml  settings.json: instant, merged on load, watched, echo-safe
Stats.js           grid, streak and color maths; cleans everything that comes from outside
Foreground.qml     only supplies the bar's foreground color
bin/dev-stats.sh   account discovery and fetching (gh, glab, tea, fj, curl)
```

## Tests

```bash
python3 tests/test_manifest.py   # SettingsPopup.qml schema == manifest.json == BarWidget.qml; no native text inputs
python3 tests/test_stats.py      # Stats.js under node: grid, streaks, colors, input cleaning
```

## Status

The model (`Stats.js`) and the manifest are tested. If something looks off, check `qs log` for `dev-stats` lines.

## Adding another platform

Add a `detect_<name>` and `fetch_<name>` function to `bin/dev-stats.sh` (each prints JSON), add the name to the `provider` checks, and add a label and glyph in `Stats.js`.

## Remove

```sh
omarchy plugin remove io.github.qempexe.dev-stats
```

## Changelog

### 1.2.0

- The panel is now a tabbed settings popup (Grid, Bar, Data, Look) anchored to the bar.
- New settings: platform icon, days on the bar, left and middle click actions, automatic refresh and its interval, panel colors (Follow theme / Custom / Monochrome).
- Right click opens the panel on the Bar tab.
- Settings are stored in `~/.local/state/omarchy-dev-stats/settings.json`; the old `~/.config/dev-stats/color` is migrated once.

### 1.1.0

- Calendar-year chips, grid color, GitLab and Forgejo support.


### 1.0.0

- First release.

### License

MIT