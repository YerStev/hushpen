# Privacy

hushpen 0.3.0

## On your Mac

- The microphone is open only between the two presses of your shortcut.
- Speech is recognized on your Mac by the Voz model. Audio and text are kept in
  memory only while a dictation is processed; no recordings or transcripts are
  written to disk. macOS may still swap memory to disk.
- The recognized text is shown in a box on your screen while you speak. Screen
  sharing or recording would capture it.
- Pasting uses the clipboard: hushpen puts the text there, marked as transient
  so clipboard managers skip it, sends ⌘V and restores your previous clipboard
  0.6 seconds later. If pasting is off or fails, the text stays in the clipboard,
  where other apps can read it.
- The log (`~/Library/Logs/hushpen.log`) records states and errors, never text.
- `~/Library/Application Support/hushpen` holds settings, the model and a lock file.

## Network

hushpen's own code makes no network requests. The Voz SDK does two things:

1. **Model download** from huggingface.co when you install or choose
   *Download model*. A Hugging Face token is sent only if you have set `HF_TOKEN`.
2. **Usage report** to `https://events.desertant.com/api/v1/ingest`, required by
   the model license. It contains:
   - a random installation ID, created by the SDK and stored in the app's
     preferences (`defaults read io.github.yerstev.hushpen`),
   - the number of transcriptions since the last report (live preview passes
     count as transcriptions),
   - the app ID (`io.github.yerstev.hushpen`) and version, the SDK name and version,
   - "macOS" and the major macOS version,
   - the time it was sent.

   It contains no audio and no text. It is sent on the first dictation of each
   day (UTC) and when the service stops or the model is replaced; counts in
   between are carried to the next report. Your IP address is visible to the
   server, as with any request. Desert Ant Labs is responsible for this data
   under its [license](https://license.desertant.com/1.0).

hushpen does not disable or alter the report. Because the service that records
audio also has network access, the guarantee that no audio or text is sent rests
on the code, not on an operating-system block. `scripts/audit-sdk-network.sh`
checks the pinned SDK's network code and report fields before each build.

## Permissions

- **Microphone**: to record.
- **Accessibility**: to paste with ⌘V. It allows broad control of other apps;
  hushpen uses it only to send ⌘V. Without it, paste yourself.
- The ⌘⇧D shortcut registers that one key combination. The Fn shortcut watches
  modifier keys only, not typed text.

Powered by Desert Ant Labs — [desertant.com](https://desertant.com)
