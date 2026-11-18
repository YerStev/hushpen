# Cleanup review, 2026-11-18

## Findings

The installed app had cleanup enabled and the registered Gemma 4 E4B model.
The log contained cold loads around 9–12 seconds, timeouts at the previous
10-second limit, and whole-result rejections for new words. No transcript text
was read from or written to logs.

The current system is primarily an editor for fillers and spoken corrections.
Its prompt explicitly preserves grammar and its vocabulary guard disallows
new words. It cannot reliably fix misrecognized names or general grammar.
Removing that guard would also admit invented names, numbers and content.
Even a result containing only source words can delete the wrong sentence or
negation, so the guard is not a semantic correctness guarantee.

## Changes

- An orange, nonactivating, click-through screen border replaces the transcript
  panel. The border stays still and brightens with microphone level, fading gently
  during pauses. Its geometry and width do not move.
  The redundant live-preview ASR work was removed.
- Every final dictation stays in the clipboard, replacing previous contents.
  Clearly non-text controls, secure input or missing Accessibility permission
  mean copy-only. Unknown browser/Electron editor roles receive Command-V too;
  a strict three-role allowlist prevented pasting into some actual editors and
  was removed after user feedback.
  An app-specific paste failure cannot erase the clipboard fallback.
- The separate email layout pass is removed.
- The cleanup prompt clarifies reformulation. Broader retraction-prompt changes
  were tried and rejected after they caused additional deletion errors.
  If new vocabulary appears, valid numbered responses can preserve just the
  uncertain sentences rather than discarding all successful edits.
- A generation that reaches its token limit is rejected instead of pasting a
  potentially incomplete result.
- Cleanup preloads at service startup. Idle unloading remains at 10 minutes,
  including after canceled recordings. The total cleanup wait is now capped at
  20 seconds to allow typical cold loads. This reduces, but cannot eliminate,
  cold-load fallback under memory pressure.

## Measurement

All 137 existing synthetic cases were run against the installed binary before
changes and the updated release binary. The primary comparison excludes the
11 email-layout cases, whose line-break expectations are intentionally no longer
part of the product. Tests were not rewritten to match the new output.

These fixtures were already used in earlier experiments. They test cleanup of
written German examples, not end-to-end recognition from audio. The historical
holdouts were inspected during this review and are not a fresh blind test.
Real spontaneous dictation, ASR mistakes, names and grammar remain under-covered.

| Measure | Installed baseline | Selected update |
| --- | --- | --- |
| Non-email cleanup cases | 119/126 | 121/126 |
| Training cases, excluding email | 74/80 | 75/80 |
| Historical holdout 1, excluding email | 28/28 | 28/28 |
| Historical holdout 2, excluding email | 17/18 | 18/18 |
| Changed text that should remain unchanged | 0/58 | 0/58 |
| Outputs with new words | 0 | 0 |
| Median generation time, all 137 cases | 0.36 s | 0.36 s |
| p90 generation time, all 137 cases | 0.71 s | 0.51 s |

Only two non-email outputs changed, both from incorrect to expected:
`rephrase-04` and `h2-reph-01`. The five remaining failures are
`correction-13`, `retract-01`, `retract-04`, `restart-05`, and `rephrase-01`.
These include incomplete retractions and retained correction markers.

The old full score was 128/137; the new historical full score is 121/137 because
all 11 email-layout cases now fail the intentionally removed formatting
requirement. Excluding them is an explicit scope change, not a general quality
improvement claim. Email content can still expose the same retraction weaknesses.

Two broader prompt variants scored 122/126 and 119/126, but introduced worse or
additional deletion errors. Neither was selected. The chosen smaller change
preserves all other non-email outputs exactly.

Cold-load measurements varied from 3.0 to 15.9 seconds across runs and cache
states; they are not a controlled speed comparison. The median is generation
latency only, not end-to-end audio-to-paste time. Raw results use synthetic
fixtures only and remain in local temporary evaluation folders.

## Handy comparison

Reviewed upstream Handy at commit
`aca8985190c3ad7f361d8a80cb30f179513ed690`.

- Its [custom word matcher](https://github.com/cjpais/Handy/blob/aca8985190c3ad7f361d8a80cb30f179513ed690/src-tauri/src/audio_toolkit/text.rs)
  uses edit distance, Soundex and up to three-word candidates. Soundex is
  explicitly English/ASCII-oriented; copying it unchanged would be a poor fit
  for German names and umlauts. Vocabulary-capable models can receive words
  directly; other models use post-recognition matching.
- [Learning from corrections](https://github.com/cjpais/Handy/discussions/2310)
  is documented as an idea and a contributor's opt-in Windows branch. The author
  reports observing edits for up to 60 seconds and adding similar replacement
  words, excluding common words and general rephrasing. This is not evidence of
  an established macOS feature or a model retraining itself.

For hushpen, the useful next feature is a small, reviewable local vocabulary of
names, products and specialist terms, with explicit recognition aliases. Learning
suggestions should require confirmation and remain reversible. General edits
such as changing a date, negation or sentence structure must not become global
replacement rules. A context-aware cleanup model remains separate from this
vocabulary. No edit monitoring or automatic dictionary storage was added here.

## Verification and remaining manual check

`./scripts/check.sh` covers the build, 16 Swift tests, the unchanged SDK network
policy and app packaging. The tests exercise the real border lifecycle and an
isolated pasteboard, without recording microphone audio or changing the user's
clipboard. Automated checks do not establish that every target application's
Accessibility implementation supports automatic paste. A real Fn dictation with
and without a focused field remains the final usability check on this Mac.
