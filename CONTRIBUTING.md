# Contributing

Dev Stats is small: one list of settings, one file of pure logic, one fetch helper,
and the QML that shows them. Most changes touch one or two files.

```
qml/BarWidget.qml        the bar squares and clicks, fetching and holding the results, docking
                         and popping out, and what the window asks of it (`ui.service`)
qml/core/UiState.qml     colors, spacing and the open tab, shared by both windows (`ui.*`)
qml/panel/StatsView.qml  the window: header, tabs, Grid, Settings, footer
qml/panel/GridPage.qml   the accounts, the years, the grid and its numbers
qml/panel/SettingRow.qml one setting, drawn from its Schema.js entry
qml/js/Schema.js         every setting, in the tabs and order the Settings tab shows
qml/js/Stats.js          pure logic: the grid, streaks, colors, and cleaning what comes in
bin/dev-stats.sh         account discovery and fetching (gh, glab, tea, fj, curl)
```

## A new setting

1. Add it to a group in `qml/js/Schema.js`: a `key` that never changes once released, a
   `kind` (`bool`, `int`, `enum`, `string`, `color` or `palette`), a `label`, a `fallback`
   and a one-sentence `hint`. An `int` takes `min`, `max` and `step`; an `enum` takes
   `options` and `labels`, and `control: "tiles"` to draw it as tiles (add its picture
   to `qml/panel/TileArt.qml`); a `color` takes `presets`. `section` puts it under a
   heading, `when` dims it unless another setting has one of the given values.
2. Read it as `cfg.<key>` in `qml/BarWidget.qml` or `ui.cfgSafe.<key>` in the window. The
   value is already clean (`Schema.resolve`).
3. Write the manifest again: `node tools/gen-manifest.js`.

The Settings tab builds its row, its search entry and its reset by itself.

## Another platform

Add a `detect_<name>` and a `fetch_<name>` function to `bin/dev-stats.sh` (each prints
JSON), add the name to the `provider` checks there, and add a label and a glyph to
`PROVIDERS` in `qml/js/Stats.js`.

## Rules

- `qml/js/Stats.js` and `qml/js/Schema.js` stay pure: no Qt, so the tests run in node.
- Anything from outside is checked before it's used: accounts through
  `Stats.parseAccounts()`, results through `Stats.parseResult()`, settings through
  `Schema.resolve()`, theme files through `Theme.parseBorder()`.
- Tokens are never read, printed or stored. `bin/dev-stats.sh` reads only host and
  account names from the CLI configs, checks them before they reach a command line, and
  prints only fixed error codes, never a remote error text.
- Text goes through `controls/Txt.qml`, which is plain text only. A text field is
  `controls/PasteInput.qml`, never a `TextInput`, so the clipboard is only read on
  Ctrl+V, capped.
- Helper commands are argument arrays, never strings put together for a shell.
- ES6 JavaScript: `const` and `let`, and arrow functions for callbacks.

## Tests

```bash
node tests/test_model.js
```

They need nothing but node and bash: the grid and streaks, the colors, the cleaning of
accounts and results, the settings and their 1.2 names, the border colors, the fetch
helper refusing odd accounts, plain text everywhere, and that `manifest.json` matches
`Schema.js`.

Everyone taking part is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).
