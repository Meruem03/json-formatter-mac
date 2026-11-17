# JSON Formatter

A native macOS app for validating, fixing, formatting, and reshaping JSON.

## Features

- **Validate** — strict JSON check that reports the exact line/column of the first problem and a plain-English suggestion for what to change.
- **Auto-Fix** — tolerates and repairs common mistakes: trailing commas, single-quoted strings, unquoted object keys, Python-style `True`/`False`/`None`, `//` and `/* */` comments. Lists every fix it made.
- **Format** — pretty-prints with 2-space, 4-space, or compact indentation.
- **Flatten / Unflatten** — converts `{"user":{"name":"x"}}` ⇄ `{"user.name":"x"}`, fully reversible.
- Line-numbered, syntax-highlighted editor (light/dark mode aware).
- Open/Save files (⌘O, ⌘S, ⇧⌘S). The last session's input and indent setting persist across launches.

## Using a prebuilt `.app`

If you already have `JSON Formatter.app` (copied from another Mac, a zip, etc.), just double-click it.

It's only ad-hoc signed — there's no paid Apple Developer ID behind it — so the first time you open it, macOS will likely say it "cannot verify the developer." That's expected:

- Right-click (or Control-click) the app → **Open** → confirm **Open**, or
- If it's already been blocked once: **System Settings → Privacy & Security → scroll down → Open Anyway**

You only need to do this once per Mac.

## Building from source

Requires the full **Xcode** app (not just the Command Line Tools) — needed to build, not to run an already-built `.app`.

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
