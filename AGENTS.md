# Instructions for coding agents

## Setting hushpen up for a user

1. Check the machine: `uname -m` must be `arm64`, `sw_vers -productVersion` 14 or
   newer, `xcrun swift --version` 6.2 or newer. If Swift is missing or old, ask
   the user to install or update Xcode or the Command Line Tools
   (`xcode-select --install`); you cannot do this for them.
2. Run `./scripts/install.sh` from the repository root. It builds the app into
   `~/Applications/hushpen.app`, downloads the model (about 340 MB from
   huggingface.co, a few minutes), and starts the login service. It is safe to
   run again.
   - If the user has an Apple Development certificate
     (`security find-identity -v -p codesigning`), set
     `HUSHPEN_SIGN_IDENTITY="<SHA-1>"` for this command, so permissions
     survive later rebuilds.
   - Text cleanup is optional: a local model (Gemma 4 E4B, 5.2 GB download,
     about 4 GB of memory while loaded) removes fillers and self-corrections
     before pasting. Ask only for a new installation; preserve the existing
     choice when updating.
     It needs 16 GB of memory (`sysctl -n hw.memsize`) and about 8 GB free
     disk space (`df -g ~`). If yes, set `HUSHPEN_CLEANUP=1` for the install
     command; the download takes several minutes and starts over if it is
     interrupted. To add it later, rerun the installer with `HUSHPEN_CLEANUP=1`.
3. Ask the user to grant the two permissions; macOS does not let you do it:
   - Microphone: they press the shortcut (default Fn) once and click Allow.
   - Accessibility, for pasting: open the settings page with
     `open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"`
     and have them turn on hushpen. Then run
     `launchctl kickstart -k gui/$(id -u)/io.github.yerstev.hushpen.agent`.
4. Verify: `~/Applications/hushpen.app/Contents/MacOS/hushpen --verify` shows
   the checksum as "(matches)" and the service as "running", and with cleanup
   "Cleanup: on" and a registered cleanup model. After a test
   dictation, check recent entries in `~/Library/Logs/hushpen.log` for missing
   Accessibility access. Old errors from previous builds are not current failures.

The default shortcut is Fn. It needs System Settings → Keyboard → "Press 🌐 key
to" → Do Nothing (`defaults read com.apple.HIToolbox AppleFnUsageType` prints 0);
the install script warns otherwise. Ask the user to change that setting rather
than changing it yourself. For keyboards without Fn, set another shortcut with
`hushpen --hotkey cmd+shift+d` (or `f18`) and restart the service.

## Updating an existing installation

1. Check `git status --short`; preserve local changes. In a clean clone, run
   `git switch main` and `git pull --ff-only origin main`. Stop on a conflict;
   do not reset or discard changes.
2. Run the install steps above with this Mac's signing certificate, if present.
   Existing settings and cleanup registration are kept; old speech models are
   upgraded automatically. Do not download or enable cleanup again unless asked.
3. Run `--verify` using the full installed binary path. Confirm `(matches)` and
   `Service: running`. Have the user test automatic paste in a text field and
   manual paste with no field focused. Every dictation stays in the clipboard.
   Inspect only recent log entries for permission errors. With ad-hoc signing,
   the user must remove and re-add hushpen under Accessibility after rebuilding.

## Working on the code

- Read `docs/TECHNICAL.md` first.
- Run `./scripts/check.sh` before committing. It must pass.
- After changing code, `./scripts/install.sh` reinstalls and restarts the service.
  With ad-hoc signing the user has to re-add hushpen under Accessibility.
- Interface text, code comments and docs are in English.

## Rules

- Do not disable, alter or block the SDK's usage reporting (`DesertAnt.usageDisabled`,
  `DAL_USAGE_DISABLED`, blocking `events.desertant.com`). The model license
  forbids it.
- Do not commit model files, recordings or transcripts. Do not log transcript text.
- Keep the Desert Ant Labs attribution in the app and README.
- Do not update `scripts/sdk-network-baseline.txt` without reviewing the SDK's
  network code and noting the result in `docs/TECHNICAL.md`.
