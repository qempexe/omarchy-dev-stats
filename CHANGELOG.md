# Changelog

All notable changes to Dev Stats. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [1.3.1] - 2026-10-28

### Fixed

- Your own text color stays readable: when it is too close to the background (a light
  text color on a light custom background, say), it is made darker or lighter, keeping
  its tint, only as much as needed. A color that already reads is used as it is.

## [1.3.0] - 2026-10-28

### Added

- **Pop out**: Dev Stats can leave the bar and become a window you can move, resize
  and tile, and **Dock** puts it back. **Open as** picks which one the bar button opens.
- Many new settings, in tabs with a search box: color schemes (Follow theme, Window
  borders, Custom, Monochrome) and the text color; card style, spacing, roundness and
  text size; window size, outline, tint and opacity; the size and roundness of the
  squares on the bar; whether the grid shows its streaks, legend and numbers. Each has
  its own reset, and **Reset all** puts everything back.
- Number cards under the grid: contributions, active days, the longest streak and the
  busiest day.
- A logo, and an **About** tab with the version and a link to more plugins.
- A **Refresh** button in the header, next to the automatic refresh switch.
- Tests for the grid, the settings, the border colors, the fetch helper's input checks
  and the manifest: `node tests/test_model.js`.
- A changelog, a contributing guide and a code of conduct.

### Changed

- A new window: header card, underlined Grid and Settings tabs, one content card,
  and a footer with the shortcuts. **Alt+←/→** switches tabs.
- The grid's squares grow with the window, and month and weekday names that would
  overlap are left out.
- The colors follow the bar and the theme straight from the shell.
- The files live in `qml/` folders: `core/`, `panel/`, `controls/` and `js/`.
- The JavaScript is written in ES6: `const` and `let`, and arrow functions.
- The README follows a new layout, with screenshots and a new preview.
- Settings saved by 1.2 keep working: **Settings panel colors** becomes **Colors**, and
  a custom panel accent becomes the accent of **Custom colors**.

### Security

- The settings folder is made private (0700) at every start.
- The grid color left by 1.1 is read straight from its file, without a shell.

## [1.2.0] - 2026-10-12

### Changed

- The panel is a tabbed settings popup (Grid, Bar, Data, Look) anchored to the bar.
- Right click opens the panel on the Bar tab.
- Settings are stored in `~/.local/state/omarchy-dev-stats/settings.json`; the old
  `~/.config/dev-stats/color` is moved over once.

### Added

- Settings for the platform icon, the days on the bar, the left and middle click,
  automatic refresh and its interval, and the panel colors (Follow theme, Custom,
  Monochrome).

## [1.1.0] - 2026-10-07

### Added

- A grid color picker in the panel, and the color you pick is kept.

### Fixed

- The squares on the bar are centered vertically.

## [1.0.0] - 2026-10-05

### Added

- First release: a contribution grid for GitHub, GitLab and Forgejo/Gitea/Codeberg in
  the Omarchy bar, with the last year and each calendar year, from your existing
  `gh`, `glab`, `tea` or `fj` logins.

[1.3.1]: https://github.com/qempexe/omarchy-dev-stats/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/qempexe/omarchy-dev-stats/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/qempexe/omarchy-dev-stats/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/qempexe/omarchy-dev-stats/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/qempexe/omarchy-dev-stats/releases/tag/v1.0.0
