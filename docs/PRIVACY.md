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
- Text cleanup, if you turn it on, runs on your Mac with llama.cpp and the
  Gemma model. The text goes to no other process or server.
- `~/Library/Application Support/hushpen` holds settings, the models and a lock file.

## Network

hushpen's own code makes one network request, and only when you ask for it:
`hushpen --cleanup-model download` fetches the Gemma 4 E4B model file
(`gemma-4-E4B_q4_0-it.gguf`, pinned revision) from huggingface.co and checks
its SHA-256. The llama.cpp library contains no network code. The Voz SDK does
two things:

1. **Model download** from huggingface.co when you install or choose
   *Download model*. A Hugging Face token is sent only if you have set `HF_TOKEN`.
2. **License requests** to `https://events.desertant.com/api/v1/license` and
   `/api/v1/activate`, managed by the unmodified SDK 4.3.0 on model load.
   The grant contains a random persistent installation ID, app identifier,
   model name/version, SDK name/version and platform (`server` on macOS).
   Activation sends the signed license token. If an external SDK API key is
   configured, native requests include it in an Authorization header.
   There is no audio, transcript, transcription count, app version or OS version
   in these requests. Your IP address is visible to the receiving server.
   The SDK stores installation identity and license state in preferences,
   caches an activated license until its period ends and retries failed requests.

hushpen does not disable or alter licensing. The source review is documented in
[TECHNICAL.md](TECHNICAL.md). The audit checks the reviewed source hashes,
network file inventory and license payloads. This is a code-level guarantee,
not an operating-system network block or packet-capture verification.

## Permissions

- **Microphone**: to record.
- **Accessibility**: to paste with ⌘V. It allows broad control of other apps;
  hushpen uses it only to send ⌘V. Without it, paste yourself.
- The default Fn shortcut watches modifier keys only, not typed text. A key
  combination such as ⌘⇧D registers only that combination.

Powered by Desert Ant Labs — [desertant.com](https://desertant.com)
