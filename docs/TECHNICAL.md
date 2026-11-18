# Technical notes

## How it works

One process, the login service (`hushpen --daemon`, started by
`~/Library/LaunchAgents/io.github.yerstev.hushpen.agent.plist`), does everything:

1. It registers the shortcut and loads the model at startup. The model stays
   loaded so dictations start immediately; see the ASR results for measured RSS.
2. A shortcut press opens the microphone. Audio is kept in memory and resampled
   to 16 kHz mono. Recording stops after 300 seconds at the latest.
3. While you speak, the audio after the last settled word is transcribed about
   every 0.7 seconds and shown in the box. Words more than 4 seconds old are
   settled, so each pass stays short while the box shows the whole text.
4. The second press closes the microphone. The whole recording, followed by
   0.6 seconds of silence so the last word is not cut off, is transcribed once
   more; that result is pasted, not the preview.
5. Optional cleanup (`--cleanup on`) by Gemma 4 E4B through llama.cpp, before
   pasting; see below.
6. Pasting: the text goes to the clipboard (marked transient), ⌘V is sent, and
   the previous clipboard is restored after 0.6 seconds. Before and after, the
   focused element's role and character count are read through Accessibility
   (never its text). If the count is readable and has not changed, the paste
   did not arrive: the text stays in the clipboard, the box shows "press ⌘V"
   and the log notes the app and element.

### Text cleanup

`TextCleanup.swift` runs the steps measured in `eval/cleanup` (see its README
for results):

1. The transcript is sent as numbered sentences with `Prompts/cleanup.txt`.
   The model returns the sentences that remain, edited where needed.
2. If the result contains a word that is not in the transcript, it is not
   used.
3. Text that starts with a greeting and ends with a sign-off and a name gets a
   second request with `Prompts/layout.txt`. Its result is used only if it has
   exactly the same words, letter for letter.

`LlamaRunner.swift` wraps the llama.cpp C API (pinned xcframework, release
b11429, the version the evaluation used). Decoding is greedy, so it matches
`llama-server` at temperature 0 exactly; `eval/cleanup/run.py --hushpen`
compares both. Each prompt keeps its own sequence in the context, so its
instructions are processed once. Tokens are drafted from the dictation itself
and checked in one step (prompt lookup decoding), which does not change the
output. Gemma's sliding-window layers use the full-size cache (`swa_full`) so
tokens can be removed from a sequence.

`CleanupService` loads the model when a recording starts, processes both
prompts while the user speaks, and unloads it after 10 minutes without a
dictation. A cleanup that fails or takes more than 10 seconds leaves the
transcript as it is. The log records the outcome and the time, never text.

The model file is registered with `--cleanup-model download|PATH` and checked
by SHA-256; its size and modification date are recorded and a changed file is
hashed again before loading. `--clean-text` cleans each line of standard input
and prints JSON, for the evaluation.

### The dictation box

A long-lived panel can stop appearing after Space, full-screen or Stage
Manager changes, while a new panel appears normally. Half a second after each
start the box checks that it is on the current screen; if not, it moves its
content to a new panel and logs what it found. `DictationBoxTests` cover this
and show the box briefly when `check.sh` runs.

There is no socket or other inter-process interface. A lock file prevents a
second service. Before each recording, the model folder is hashed and compared
with the hash saved when the model was registered; a changed model is rejected.

## Source map

| File | Purpose |
| --- | --- |
| `main.swift` | Command-line commands |
| `Daemon.swift` | Login service: shortcut, startup, shutdown |
| `Dictation.swift` | One recording: start, live preview, stop, paste |
| `TextCleanup.swift`, `LlamaRunner.swift`, `CleanupService.swift`, `CleanupModel.swift` | Optional text cleanup with llama.cpp |
| `Prompts/` | Cleanup and layout prompts, shared with `eval/cleanup` |
| `DictationBox.swift` | On-screen glass box with the live text and voice edge |
| `ModelHost.swift` | Keeps the verified model loaded |
| `ModelImport.swift`, `ModelDigest.swift`, `Config.swift` | Model download, checks, registration |
| `Recorder.swift` | Microphone capture and resampling |
| `Output.swift`, `Paste.swift` | Clipboard and ⌘V |
| `Hotkey.swift` | Key combination and Fn shortcuts |
| `Setup.swift` | Setup window shown when the app is opened |
| `Telemetry.swift` | Awaits SDK license requests before the service exits |

## Commands

The binary is `~/Applications/hushpen.app/Contents/MacOS/hushpen`.

| Command | Purpose |
| --- | --- |
| `--download-model` | Download, check and register the model |
| `--set-model PATH` | Register a model folder you already have |
| `--verify` | Show model, settings and service state |
| `--hotkey SPEC` | Set the shortcut: `cmd+shift+d`, `f18`, `fn`, … |
| `--paste-mode on\|off` | Paste automatically, or only copy |
| `--cleanup on\|off` | Text cleanup before pasting (off by default) |
| `--cleanup-model download\|PATH` | Download or register the cleanup model (5.2 GB) |
| `--clean-text` | Clean each line of standard input (diagnostic) |
| `--install-agent` / `--uninstall-agent` | Start or remove the login service |
| `--transcribe-file FILE` | Transcribe an audio file to stdout |
| `--daemon` | Run the service in the foreground (for debugging) |
| `--setup` | Open the setup window |

After changing the shortcut, paste mode or cleanup, restart the service:
`launchctl kickstart -k gui/$(id -u)/io.github.yerstev.hushpen.agent`

The default shortcut is `fn`: a tap of Fn/🌐 on its own (Fn combinations with
other keys are ignored). It needs System Settings → Keyboard → "Press 🌐 key to"
→ Do Nothing. Other shortcuts: modifiers `cmd`, `shift`, `alt`, `ctrl`; keys
a–z, 0–9, space, return, tab, escape, f1–f20. Letters need a modifier.

## Building

```sh
./scripts/install.sh      # build, install, download model, start service
./scripts/check.sh        # build, tests and policy checks; no microphone, no changes to your setup
```

Without a certificate the app is signed ad hoc. macOS then ties the
Accessibility permission to that exact build: after each rebuild, remove hushpen
from Accessibility, add it again, and restart the service. With an Apple
Development certificate the permission survives rebuilds:

```sh
security find-identity -v -p codesigning
HUSHPEN_SIGN_IDENTITY="<SHA-1 from above>" ./scripts/install.sh
```

## SDK licensing and source audit (2026-11-10)

The app pins desert-ant-core 4.3.0 and Voz v0.5.0 (Hugging Face tag commit
81940d2b41329e1e157acbac8af95e23aa4e224b). The SDK catalog confirms Parakeet
TDT 0.6B v3; the Apple initializer defaults to CPU and Neural Engine.
The public download, synchronous model-directory initializer and transcription
APIs remain compatible. Model assets live in a separate versioned directory;
the old v0.1.0 assets are retained. The install script explicitly migrates the
old model registration instead of accepting any matching old checksum.

Reviewed the 4.3.0 Sources/Usage implementation (Licensing, Wire, Identity,
AppIdentity, Storage, LicenseToken, LicenseVerifier, DesertAnt and
TelemetryDebug), PlatformSupport/HTTPClient, and ModelStore transport,
distribution, manifests and Hub authorization code before changing the baseline.
The old ingest transport and transcription counters are gone. Model load queues
POST /api/v1/license and /api/v1/activate on https://events.desertant.com.
The grant's fields are installId, model, modelVersion, sdk (name/version),
platform (server on macOS), app (id), and an optional key. Activation carries a
signed license token and optional key. Native API keys use Authorization Bearer;
hushpen supplies none. There are no audio, text, transcription-count or device
context fields. A random installation ID and signed license state are persisted
in UserDefaults. Verified, activated grants are cached to their period end;
network failures retry after five minutes, other failures back off (one minute
to six hours), terminal grant errors wait one day. Flush awaits in-flight work,
not delayed retries. Model registration also awaits pending license requests
before its short-lived validation instance is released or the CLI exits.
No endpoint override, blocking or licensing changes are
introduced by hushpen.

ModelStore downloads manifests/files from Hugging Face, follows CDN redirects,
and checks size and SHA-256. HF_TOKEN is attached only to huggingface.co URLs;
redirect handling clears Authorization when the destination host changes. The optional Xet
transport is guarded by canImport(Xet); this dependency graph does not enable
that trait. PlatformSupport implements generic platform HTTP; Apple uses
URLSession. No audio upload path was found in the reviewed call sites. This is
a source review, not a packet-capture or OS isolation guarantee.

Expanded HTTP-call detection also finds HostBridge/JNI.swift (Android host
method lookup) and CoreAndroidTests/CoreBridge.swift (an Android-only test
request). Reviewed these call sites; neither executes in the Apple product.
Their source hashes are included in the gate.

The audit retains the network-file inventory and now hashes every Swift file
in Usage, ModelStore and PlatformSupport, plus the Voz catalog and load hooks.
It checks exact grant/activation fields and endpoints, so edits that preserve a
field count also require review. Update the baseline only after documenting a
new source review here. Never disable or redirect SDK license requests.

## Troubleshooting

- Log: `~/Library/Logs/hushpen.log`
- "Accessibility access is missing" in the log: re-add hushpen under
  Accessibility, then restart the service.
- The first load after a fresh download can take a minute while Core ML
  prepares the model for your Mac.
