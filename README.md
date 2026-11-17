# JSON Formatter

A native macOS app for validating, fixing, formatting, and reshaping JSON.

## Features

- **Validate** — strict JSON check that reports the exact line/column of the first problem and a plain-English suggestion for what to change. Handles Windows-style CRLF line endings correctly, and catches invisible Unicode whitespace left over from copy-pasting (zero-width spaces, BOM, non-breaking spaces, ...) and `//`/`/* */` comments with a specific, clear message instead of a confusing unrelated error.
- **Lint** — flags things that are *valid* JSON but are almost always a bug: duplicate keys in the same object (most parsers silently keep only the last one and discard the rest) and integers with more digits than a standard JSON number can represent exactly (large IDs that some JSON consumers, notably JavaScript, will silently round).
- **Auto-Fix** — tolerates and repairs common mistakes: trailing commas, single-quoted strings, unquoted object keys, Python-style `True`/`False`/`None`, `//` and `/* */` comments, invisible whitespace from pasting. Lists every fix it made.
- **Format** — pretty-prints with 2-space, 4-space, or compact indentation.
- **Flatten / Unflatten** — converts `{"user":{"name":"x"}}` ⇄ `{"user.name":"x"}`, fully reversible.
- **Merge With…** — paste a second JSON (e.g. `appsecrets.json`) and deep-merge it into Input (e.g. `appsettings.json`): matching keys recurse, the pasted JSON wins on conflicts, everything else on either side is kept.
- Line-numbered, syntax-highlighted editor (light/dark mode aware).
- Clear button on both the Input and Output panes.
- Open/Save files (⌘O, ⌘S, ⇧⌘S). The last session's input and indent setting persist across launches.

## Just want to use the app?

Don't build from source — download the prebuilt app from **[Releases](https://github.com/Meruem03/json-formatter-mac/releases/latest)**. No Xcode required, works on any Mac (Apple Silicon or Intel):

1. Download `JSON Formatter.zip` from the latest release and unzip it.
2. Move `JSON Formatter.app` to Applications (or anywhere).
3. **Right-click the app → Open → confirm Open.** (First launch only — it's ad-hoc signed, not notarized with a paid Apple Developer ID, so Gatekeeper warns once. If it's already been blocked: **System Settings → Privacy & Security → scroll down → Open Anyway**.)

Building from source is only needed if you want to modify the code.

## Building from source

Requires the full **Xcode app** (not just the Command Line Tools) — if Xcode isn't installed, use the Release download above instead; building won't work without it.

```bash
git clone https://github.com/Meruem03/json-formatter-mac.git
cd json-formatter-mac
./build_app.sh
```

This builds a universal binary (Apple Silicon + Intel), assembles `build/JSON Formatter.app` with its icon and `Info.plist`, and ad-hoc signs it. Drag it into `/Applications` or `~/Applications` to install it properly, or run it straight out of `build/`.

If `xcode-select -p` doesn't already point at Xcode (`/Applications/Xcode.app/Contents/Developer`), do this first:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license
```

### While developing

```bash
swift run JSONFormatterApp   # run directly, no .app bundle needed
swift run SelfTest           # run the regression test suite
```

A GitHub Actions workflow (`.github/workflows/ci.yml`) runs `SelfTest` automatically on every push and pull request.

## Project layout

```
Sources/JSONCore/          Parser, auto-fixer, serializer, flatten/unflatten — no UI dependencies
Sources/JSONFormatterApp/  SwiftUI app: editor, buttons, menu commands
Sources/SelfTest/          Regression test suite (also run in CI)
build_app.sh               Packages the signed .app bundle
```

## Known limitations

Tracked as [open issues](https://github.com/Meruem03/json-formatter-mac/issues) — currently just notarization for distributing beyond your own Macs ([#6](https://github.com/Meruem03/json-formatter-mac/issues/6)).
