# Local ASR comparison

This is separate from `eval/cleanup`: it compares recognition without cleanup,
app capture, live preview, vocabulary hints, clipboard or paste. Private audio,
references and hypotheses must live outside the repository. Do not print them,
redirect them to logs, or commit them.

`run.py CONFIG --repetitions 3` runs persistent workers sequentially, rotates
engine order between rounds, converts each source once to identical mono 16 kHz
float32 PCM, records its SHA-256, separates first inference from warm inference,
and records fresh-process load time, sampled process RSS (50 ms) and MLX peak
allocation where available. It retains private responses in a local JSON result
file, discards worker stderr and unstructured stdout, and prints status only.
Downloads, compilation and the hushpen service must finish/stop before timing.
Restart the service even after an interrupted benchmark.

The source recordings, hashes, reference status, model revisions, commands and
runtime versions belong in the local run manifest. A new process does not imply
cold filesystem/Core ML caches. Process RSS excludes some accelerator/driver
allocations; MLX peak allocation is also not total unified memory. No GPU/ANE
utilization is inferred from timing. Report configured acceleration explicitly.
No trailing silence is appended: each engine receives exactly the same PCM.
This differs from hushpen's final dictation path, which adds 0.6 s of silence.

`voz-worker.swift` is built twice, linked to the retained 3.5.0 and pinned 4.3.0
SDKs respectively. It keeps the model loaded and awaits the unmodified SDK's
pending usage/license requests before exit. `mlx-worker.py` uses local snapshots,
MLX/Metal, German decoding for supported models, and greedy Whisper decoding.
A Whisper German fine-tune is a separate candidate from merely forcing the
multilingual base model's language to German. Exact quantization is read from
the downloaded config/weights, not guessed from the app's marketing name.

WER: Unicode NFC, casefold and Unicode letter/digit tokens; punctuation ignored,
no conversion between spelled-out numbers and digits. Corpus WER is the sum of
word edit distances divided by reference words. Repetitions are latency samples,
not independent accuracy samples. Keep human/synthetic results separate.
Unverified read prompts do not become verified transcripts through agreement
between recognizers. Label their WER provisional until independently checked
against the recording. A small read-speech set cannot establish a general winner.

For names, numbers and specialist terminology, annotate reference spans locally
before inspecting hypotheses. Score exact normalized span matches and report
errors with denominators. Do not infer proper names from capitalization in
German. Preserve a strict number score and, if needed, a separately documented
semantic-equivalence score. Missing annotations are missing results, not zero
errors. Keep error examples private.

Config structure (all paths absolute; actual manifests stay local):

```json
{
  "output": "/private/local/results/run-01",
  "corpora": ["/private/local/corpus/manifest.json"],
  "engines": [{"name": "voz-old", "command": ["/private/local/VozBench", "/private/local/model"]}]
}
```

A corpus is a JSON list with `audio` (relative to manifest), `reference`,
`source_kind` (`human`, `synthetic`, or `public_fleurs`) and `reference_status`. Workers read
`{"pcm":"/absolute/audio.f32"}` lines and return private JSON responses.

`handy-catalog.json` is public model metadata extracted from the stable Handy
0.10.0 catalog, not an app benchmark. Its revision pins and quantizations describe
Handy's exports; MLX runs may use a different conversion, and must be labeled
accordingly. Superwhisper's actual export revision/quantization is not fully
published on its model page. An independent MLX model result must not be reported
as a measured Superwhisper or Handy app result.

`quantize-whisper.py` creates a matched Q4/group-64 multilingual control from
an existing MLX Whisper snapshot. Preserve the source revision and generated
weight hash in the local model manifest. It runs before, never during, timing.

`make-review.py MANIFEST /private/local/reference-review.html` creates an offline
form with local audio playback, editable verbatim references and target-span
annotations. Export is enabled only after each recording is confirmed. It does
not certify existing read prompts automatically or send anything over a network.
Use the exported reviewed manifest for a separate run; retain the original
unverified manifest and results for provenance.

The automatic digit-token diagnostic counts normalized tokens containing a
digit, using multiset overlap for precision/recall. It is sensitive to number
formatting (e.g. spelled words versus digits), is not semantic numeric accuracy,
and does not substitute for reviewed name/number/term spans.

Completed aggregate results are in `docs/ASR-RESULTS-2026-11-10.md` and
`results-2026-11-10.json`. These contain no reference text, audio or hypotheses.
The local run directory retains the exact commands and file hashes.

`annotate-local.py` optionally proposes reference-only target spans using the
already installed Gemma file and a temporary llama-server bound to 127.0.0.1.
It suppresses server output, disables thinking, never gives ASR hypotheses to
the annotator, validates exact reference substrings and closes the server before
further ASR timing. Proposals are not human-verified labels. `entity-diagnostic.py`
scores normalized exact span retention on the first repetition only. Neither
script edits ASR output or forms part of the app's cleanup path.

`number-diagnostic.py` is a restricted formatting sensitivity check using
num2words 0.5.14, not a general semantic number scorer. `aggregate.py STATE REPORT
AGGREGATE_JSON` exports only metrics, public model metadata and clip-level paired
bootstrap intervals. It checks that the native Cohere follow-up used identical
PCM hashes and that both runs completed without worker failures.

The exploratory Cohere layout adapter is retained only in local provenance,
not shipped as a supported loader. The main Cohere result uses a native
MLX-Audio export; storage reconstruction alone was insufficient to validate
the exploratory export's forward behavior.
