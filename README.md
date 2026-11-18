# hushpen

Dictation for macOS that runs on your Mac. Press a shortcut, speak, press it
again: the text is pasted where your cursor is. While you speak, an orange glow
frames the active screen and responds to your voice. No transcript overlay is shown.

Speech recognition uses the [Voz](https://huggingface.co/desert-ant-labs/voz)
model by [Desert Ant Labs](https://desertant.com). Audio and text stay on your Mac.

## Requirements

- Mac with Apple silicon, macOS 14 or newer
- Xcode or the Command Line Tools with Swift 6.2 or newer (`xcode-select --install`)
- About 1 GB of disk space (about 340 MB for the speech model)

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

The dictation always remains in the clipboard. Without Accessibility or a
focused text control, paste it yourself with ⌘V.

## Update an existing installation

From your existing clone, with no uncommitted changes:

```sh
git switch main
git pull --ff-only origin main
./scripts/install.sh
```

Settings and registered models are kept. An older speech model is upgraded when
needed. Use your Apple Development certificate on this Mac to preserve permissions:
`HUSHPEN_SIGN_IDENTITY="<SHA-1>" ./scripts/install.sh` (find it with
`security find-identity -v -p codesigning`). Without a certificate, remove and
re-add hushpen under Accessibility after rebuilding.

Verify: `~/Applications/hushpen.app/Contents/MacOS/hushpen --verify` should show
`(matches)` and `Service: running`. Test one dictation in a text field and one
with no text field focused; both should remain available with ⌘V.

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

### Text cleanup (optional)

A second local model can tidy up what you said before it is pasted. Just
speak naturally:

- filler sounds ("äh", "ähm") are removed,
- "am Dienstag, nein, am Mittwoch" becomes "am Mittwoch",
- spoken deletion commands such as "vergiss den letzten Satz" are supported,
  but can remove the wrong sentence,
- "Okay, nochmal von vorne" keeps only what follows,
- "besser gesagt …" keeps the better phrasing.

Enable cleanup during installation or update:

```sh
HUSHPEN_CLEANUP=1 ./scripts/install.sh
```

It needs 16 GB RAM, about 8 GB free disk space and a 5.2 GB model download
(Gemma 4 E4B, Apache 2.0). Existing cleanup settings are preserved on updates.
Cleanup is tuned for German and usually adds about 0.3–2 seconds once loaded;
cold loading can take longer. After 20 seconds, the original transcript is used.
Names, grammar and spoken deletion commands can still be wrong. There is no
separate email formatting or automatic vocabulary learning.

## What leaves your Mac

The SDK fetches Voz v0.5.0 from huggingface.co and checks file sizes and
SHA-256. Optional cleanup downloads the pinned Gemma model from Hugging Face;
cleanup inference runs on this Mac.

SDK 4.3.0 replaces usage reports with license grant and activation requests to
`https://events.desertant.com/api/v1/license` and `/api/v1/activate` on model
load. These carry a persistent random installation ID, app ID, model and SDK
versions, platform and the signed activation token. They contain no audio,
text or transcription counts. Activated licenses are cached for their period;
failed requests are retried. Requests reveal your IP address to the server.
hushpen leaves SDK licensing unchanged. See the source review in
[docs/TECHNICAL.md](docs/TECHNICAL.md).

On your Mac, hushpen saves no recordings and no transcripts. The text passes
into the clipboard and stays there for manual pasting, replacing its previous
contents. Automatic paste is attempted unless focus is clearly non-text or secure. Details: [docs/PRIVACY.md](docs/PRIVACY.md).

Recognition comparison methodology and model availability: [docs/ASR-COMPARISON.md](docs/ASR-COMPARISON.md). Private evaluation data stays outside this repository.

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

Text cleanup uses [llama.cpp](https://github.com/ggml-org/llama.cpp) (MIT,
[license](docs/licenses/LICENSE-llama.cpp.txt), included in the app) and the
Gemma 4 E4B model by Google (Apache 2.0), which you download separately.

Technical notes: [docs/TECHNICAL.md](docs/TECHNICAL.md).
