# hushpen

Dictation for macOS that runs on your Mac. Press a shortcut, speak, press it
again: the text is pasted where your cursor is. While you speak, a small box at
the bottom of the screen shows the recognized text.

Speech recognition uses the [Voz](https://huggingface.co/desert-ant-labs/voz)
model by [Desert Ant Labs](https://desertant.com). Audio and text stay on your Mac.

## Requirements

- Mac with Apple silicon, macOS 14 or newer
- Xcode or the Command Line Tools with Swift 6.2 or newer (`xcode-select --install`)
- About 1 GB of disk space (470 MB for the model)

## Install

```sh
git clone https://github.com/YerStev/hushpen.git
cd hushpen
./scripts/install.sh
```

Or double-click `Setup.command`, or ask your coding agent to set it up
(instructions for agents are in [AGENTS.md](AGENTS.md)).

The script builds the app into `~/Applications/hushpen.app`, downloads the model,
and starts a background service that runs at login. Then grant two permissions,
which macOS only lets you do yourself:

1. **Microphone**: press Fn once and allow access.
2. **Accessibility** (for pasting): System Settings → Privacy & Security →
   Accessibility → turn on hushpen. Then restart the service:
   `launchctl kickstart -k gui/$(id -u)/io.github.yerstev.hushpen.agent`

Without Accessibility, the text is copied to the clipboard and the box shakes;
paste it with ⌘V.

## Use

- Press **Fn** (🌐) to start, speak, press **Fn** to stop.
- For this, set System Settings → Keyboard → "Press 🌐 key to" → **Do Nothing**;
  otherwise macOS opens its own emoji picker or dictation on Fn.
- A microphone icon in the menu bar lets you stop or discard a recording.
- Another shortcut, e.g. for keyboards without Fn:
  `~/Applications/hushpen.app/Contents/MacOS/hushpen --hotkey cmd+shift+d`
  (or `f18`, …), then restart the service.
- Open the app in Finder for settings: model, paste mode, service on/off.

Recognition can mishear names and numbers. Read the text before you send it.

## What leaves your Mac

hushpen itself makes no network requests. Two things do:

**Model download** (once): the SDK fetches Voz v0.1.0 from huggingface.co and
checks every file against its SHA-256.

**Usage report**: the Voz SDK reports usage to Desert Ant Labs. This is a
condition of the model license, so hushpen does not turn it off. A real report:

```json
POST https://events.desertant.com/api/v1/ingest
{
  "app": { "id": "io.github.yerstev.hushpen" },
  "events": [{
    "name": "load",
    "deviceId": "<random ID created on first use>",
    "callCount": 1,
    "context": { "appVersion": "0.3.0", "osName": "macOS", "osVersion": "26" }
  }],
  "platform": "server",
  "sdk": { "name": "Voz", "version": "3.5.0" },
  "sentAt": "2026-10-08T18:42:10.160Z"
}
```

`callCount` is the number of transcriptions since the last report; the live text
preview counts too. A report is sent on the first dictation of each day (UTC)
and when the service stops. It contains no audio and no text. Like any request,
it reveals your IP address to the receiving server.

On your Mac, hushpen saves no recordings and no transcripts. The text passes
through the clipboard while it is pasted, and your previous clipboard is
restored afterwards. Details: [docs/PRIVACY.md](docs/PRIVACY.md).

## Uninstall

```sh
~/Applications/hushpen.app/Contents/MacOS/hushpen --uninstall-agent
rm -rf ~/Applications/hushpen.app "$HOME/Library/Application Support/hushpen"
rm -f ~/Library/Logs/hushpen.log
defaults delete io.github.yerstev.hushpen
```

Then remove hushpen from Microphone and Accessibility in System Settings.

## License

The hushpen code is MIT-licensed ([LICENSE](LICENSE)).

Voz and its SDK (`desert-ant-core`) are **not** open source. They are available
under the [Desert Ant Labs Source-Available License 1.0](https://license.desertant.com/1.0):
free below 100,000 monthly active devices per platform and model, outputs may not
be used to train a competing model, and apps must credit Desert Ant Labs. The
model is downloaded from its publisher and is not part of this repository.

Technical notes: [docs/TECHNICAL.md](docs/TECHNICAL.md).
