# Clip

Select text anywhere on your Mac and a small popup appears with quick actions — copy it, send it to Obsidian, or turn it into an Asana task.

Clip lives quietly in the menu bar and does nothing until you drag-select or double-click some text in any app.

## Install

1. Download the latest `Clip.dmg` from [Releases](../../releases).
2. Open the DMG and drag **Clip** into your Applications folder.
3. Launch Clip. Since it isn't notarized by Apple, macOS will warn it's from an unidentified developer the first time — right-click (or Control-click) the app and choose **Open**, or go to **System Settings → Privacy & Security** and click **Open Anyway**.
4. Clip needs Accessibility access to detect selections in other apps. Grant it in **System Settings → Privacy & Security → Accessibility**, then relaunch Clip.

## Using it

Drag-select or double-click text in any app. A small popup appears near your cursor:

- **Copy** — copies the selection to your clipboard.
- **Capture to Obsidian** — sends the text to a note in an Obsidian vault.
- **Add Asana Task** — creates a task in Asana with the selection as the title.

Click the wand icon in the menu bar → **Preferences…** to configure each extension (Obsidian vault name, Asana access token, etc.) or turn one off.

### Obsidian

Requires the free **Advanced URI** community plugin, installed and enabled in Obsidian's Community Plugins settings. In Clip's Preferences, enter your vault's exact name (case-sensitive). You can optionally set a target note, a heading to insert under, and whether to include a timestamp or the source app.

### Asana

In Clip's Preferences, add a Personal Access Token (Asana → your profile photo → Settings → Apps → Manage Developer Apps → Personal Access Tokens) and your workspace's number (the digits after `/0/` in an Asana URL).

## Extensions

Clip's actions live as plain folders in `~/Library/Application Support/Clip/Extensions/` (menu bar icon → **Open Extensions Folder**). Each one is a `<Name>.extension` folder containing:

- `manifest.json` — name, icon, which selection types it applies to, and a schema for its settings.
- `action.js` — runs via `osascript -l JavaScript` (JXA) when the action is clicked, receiving the selection and your saved settings as JSON.

Add a new folder in that format and relaunch Clip to pick it up.

## Building from source

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
open Clip.xcodeproj
```

Build and run the `Clip` scheme (macOS 13+).

## License

MIT — see [LICENSE](LICENSE).
