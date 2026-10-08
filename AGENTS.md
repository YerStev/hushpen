# Instructions for coding agents

## Setting hushpen up for a user

1. Check the machine: `uname -m` must be `arm64`, `sw_vers -productVersion` 14 or
   newer, `xcrun swift --version` 6.2 or newer. If Swift is missing or old, ask
   the user to install or update Xcode or the Command Line Tools
   (`xcode-select --install`); you cannot do this for them.
2. Run `./scripts/install.sh` from the repository root. It builds the app into
   `~/Applications/hushpen.app`, downloads the model (about 470 MB from
   huggingface.co, a few minutes), and starts the login service. It is safe to
   run again.
   - If the user has an Apple Development certificate
     (`security find-identity -v -p codesigning`), set
     `HUSHPEN_SIGN_IDENTITY="<SHA-1>"` for this command, so permissions
     survive later rebuilds.
3. Ask the user to grant the two permissions; macOS does not let you do it:
   - Microphone: they press the shortcut (default ⌘⇧D) once and click Allow.
   - Accessibility, for pasting: open the settings page with
     `open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"`
     and have them turn on hushpen. Then run
     `launchctl kickstart -k gui/$(id -u)/io.github.yerstev.hushpen.agent`.
4. Verify: `~/Applications/hushpen.app/Contents/MacOS/hushpen --verify` shows
   the checksum as "(matches)" and the service as "running". After a test
   dictation, `~/Library/Logs/hushpen.log` must not contain "Accessibility
   access is missing".

To change the shortcut: `hushpen --hotkey fn` (or `f18`, `cmd+shift+d`), then
restart the service as above. For `fn`, the user sets System Settings →
Keyboard → "Press 🌐 key to" → Do Nothing.

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
