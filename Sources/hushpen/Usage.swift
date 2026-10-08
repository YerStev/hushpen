let usageText = """
hushpen — on-device dictation with the Voz model

Press the shortcut (default Fn), speak, press it again. The text is pasted
at your cursor. The menu-bar microphone can stop or discard a recording.

SETUP
  --download-model         Download, check and register the model (~470 MB)
  --set-model PATH         Register a model folder you already have
  --install-agent          Start the service now and at login
  --uninstall-agent        Stop and remove the service
  --hotkey SPEC            Shortcut: cmd+shift+d, f18, fn, ...
  --paste-mode on|off      Paste automatically, or only copy
  --verify                 Show model, settings and service state
  --setup                  Open the setup window

OTHER
  --transcribe-file FILE   Transcribe an audio file to stdout
  --daemon                 Run the service in the foreground
  --version, --help

Restart the service after changing settings:
  launchctl kickstart -k gui/$(id -u)/io.github.yerstev.hushpen.agent

Speech is processed on this Mac. The Voz SDK sends a usage report to
Desert Ant Labs (installation ID, counts, versions; no audio, no text).

EXIT CODES
  0 Success   1 Error   2 Usage   3 Missing model   4 Model checksum mismatch
  5 Service state   6 Transcription   7 Microphone
"""
