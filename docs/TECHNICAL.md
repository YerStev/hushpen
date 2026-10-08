# Technical notes

## How it works

One process, the login service (`hushpen --daemon`, started by
`~/Library/LaunchAgents/io.github.yerstev.hushpen.agent.plist`), does everything:

1. It registers the shortcut and loads the model at startup. The model stays
   in memory (about 80 MB) so dictations start immediately.
2. A shortcut press opens the microphone. Audio is kept in memory and resampled
   to 16 kHz mono. Recording stops after 300 seconds at the latest.
3. While you speak, the audio after the last settled word is transcribed about
   every 0.7 seconds and shown in the box. Words more than 4 seconds old are
   settled, so each pass stays short while the box shows the whole text.
4. The second press closes the microphone. The whole recording is transcribed
   once more; that result is pasted, not the preview.
5. Pasting: the text goes to the clipboard (marked transient), ⌘V is sent, and
   the previous clipboard is restored after 0.6 seconds.

There is no socket or other inter-process interface. A lock file prevents a
second service. Before each recording, the model folder is hashed and compared
with the hash saved when the model was registered; a changed model is rejected.

## Source map

| File | Purpose |
| --- | --- |
| `main.swift` | Command-line commands |
| `Daemon.swift` | Login service: shortcut, startup, shutdown |
| `Dictation.swift` | One recording: start, live preview, stop, paste |
| `DictationBox.swift` | On-screen glass box with the live text and voice edge |
| `ModelHost.swift` | Keeps the verified model loaded |
| `ModelImport.swift`, `ModelDigest.swift`, `Config.swift` | Model download, checks, registration |
| `Recorder.swift` | Microphone capture and resampling |
| `Output.swift`, `Paste.swift` | Clipboard and ⌘V |
| `Hotkey.swift` | Key combination and Fn shortcuts |
| `Setup.swift` | Setup window shown when the app is opened |
| `Telemetry.swift` | Flushes SDK usage before the service exits |

## Commands

The binary is `~/Applications/hushpen.app/Contents/MacOS/hushpen`.

| Command | Purpose |
| --- | --- |
| `--download-model` | Download, check and register the model |
| `--set-model PATH` | Register a model folder you already have |
| `--verify` | Show model, settings and service state |
| `--hotkey SPEC` | Set the shortcut: `cmd+shift+d`, `f18`, `fn`, … |
| `--paste-mode on\|off` | Paste automatically, or only copy |
| `--install-agent` / `--uninstall-agent` | Start or remove the login service |
| `--transcribe-file FILE` | Transcribe an audio file to stdout |
| `--daemon` | Run the service in the foreground (for debugging) |
| `--setup` | Open the setup window |

After changing the shortcut or paste mode, restart the service:
`launchctl kickstart -k gui/$(id -u)/io.github.yerstev.hushpen.agent`

The default shortcut is `fn`: a tap of Fn/🌐 on its own (Fn combinations with
other keys are ignored). It needs System Settings → Keyboard → "Press 🌐 key to"
→ Do Nothing. Other shortcuts: modifiers `cmd`, `shift`, `alt`, `ctrl`; keys
a–z, 0–9, space, return, tab, escape, f1–f20. Letters need a modifier.

## Building

```sh
./scripts/install.sh      # build, install, download model, start service
./scripts/check.sh        # build and policy checks; no microphone, no changes to your setup
```

Without a certificate the app is signed ad hoc. macOS then ties the
Accessibility permission to that exact build: after each rebuild, remove hushpen
from Accessibility, add it again, and restart the service. With an Apple
Development certificate the permission survives rebuilds:

```sh
security find-identity -v -p codesigning
HUSHPEN_SIGN_IDENTITY="<SHA-1 from above>" ./scripts/install.sh
```

## SDK and usage reporting

The app pins `desert-ant-core` 3.5.0 (`Package.resolved`).
`scripts/audit-sdk-network.sh` fails when the SDK's network-capable files or the
report fields change, so an SDK update needs a review first. The app uses the
SDK's public `Voz.download` for the model and never disables usage reporting:
the model license does not allow it.

macOS cannot restrict a single process to one host without a Network Extension
(`sandbox-exec` only accepts `*` or `localhost` as hosts), so hushpen does not
try. Do not block `events.desertant.com`; that breaks the license terms.

## Troubleshooting

- Log: `~/Library/Logs/hushpen.log`
- "Accessibility access is missing" in the log: re-add hushpen under
  Accessibility, then restart the service.
- The first load after a fresh download can take a minute while Core ML
  prepares the model for your Mac.
