# Dev Stats

A contribution-activity grid for the Omarchy bar, in the style of the GitHub profile graph. One widget, several platforms:

![Dev-stats preview](preview.png?v=2=1.1.0)

| Platform | Login (once, in a terminal) | Source of the numbers |
| --- | --- | --- |
| GitHub / GitHub Enterprise | `gh auth login` | GraphQL contribution calendar |
| GitLab / self-hosted GitLab | `glab auth login` | your activity events, counted per day |
| Forgejo / Gitea / Codeberg | `tea login add` or `fj auth login` | the instance's public heatmap endpoint |

The bar shows the last 7 days of the selected account as coloured squares. Click it for the full grid, streaks and per-day hover details. Middle-click refreshes. Data refreshes every 30 minutes.

In the panel, the chips under the account tabs switch between the rolling last year and individual calendar years. Past years are fetched when you pick them.

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
| `gridColor` | `#rrggbb` hex color | `#39d353` |

Pick the grid color in the panel: click a swatch, type a `#rrggbb` value and press Enter, or Reset. `gridColor` in the table is the color of the busiest days. The quieter levels are darker shades of the same color. An invalid value falls back to the default green.

## Security and privacy

* The QML code makes no network requests. Fetching happens in `bin/dev-stats.sh`, which runs your own `gh`, `glab` and `curl` as your user.
* The plugin never reads, prints or stores access tokens. It reads only the host and account names from the CLI config.
* Host and account names are validated before they reach any command line, and may not start with `-`.
* The only file written is `~/.config/dev-stats/color`, which holds the grid color you pick. Results are held in memory only.

## Limitations

* Year selection: GitHub offers every year your account has activity. GitLab offers the last three calendar years (its events API keeps about three years). Forgejo/Gitea only expose the last year, so no year chips appear for them.
* GitLab has no public calendar API, so Dev-stats counts your activity events per day. Numbers can differ slightly from GitLab's own graph.
* Forgejo/Gitea use the public heatmap endpoint over HTTPS. Private profiles and plain-HTTP instances are not supported.
* Account discovery for `tea` and `fj` depends on their config formats. If an account is not found automatically, use `accounts.json`.
* Month and weekday labels are English.

## Adding another platform

Add a `detect_<name>` and `fetch_<name>` function to `bin/dev-stats.sh` (each prints JSON), add the name to the `provider` checks, and add a label and glyph in `Stats.js`.

## Remove

```sh
omarchy plugin remove io.github.qempexe.dev-stats
```
