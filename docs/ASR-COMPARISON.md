# Local ASR comparison, 2026-11-10

Completed measurements and recommendation: [ASR-RESULTS-2026-11-10.md](ASR-RESULTS-2026-11-10.md).

## Machine and preserved baseline

Apple M1 Pro (8 CPU cores), 16 GiB unified memory, macOS 26.6.2, Apple Swift 6.4.
About 30 GiB free before setup. The installed app reported hushpen 0.3.0,
desert-ant-core 3.5.0 and Voz v0.1.0, with a matching model digest. Fn,
automatic paste and Gemma 4 E4B cleanup were already enabled.

Before changing the dependency, preserved the HEAD source archive
`f2d5032fd31236a64470240f63b1c1a65cc7bc9a`, Package manifests, SDK 3.5.0 checkout,
installed signed app, complete hushpen state including old model assets, login
agent and app preferences outside the repository, under
`~/Library/Application Support/hushpen-comparison/baseline-2026-11-10`.
`sha256.json` inventories retained files. The Gemma registration still points to
the existing unchanged local file. No private content is included in this report.

SDK [4.3.0](https://github.com/Desert-Ant-Labs/desert-ant-core/releases/tag/v4.3.0)
(November 5, not a prerelease) and Voz v0.5.0 are the latest stable releases
checked through the release API and Hugging Face tags. Voz v0.5.0 resolves to
`81940d2b41329e1e157acbac8af95e23aa4e224b`; v0.1.0 resolves to
`8e7ab8ca342c6bb00f9347a25e53fe44543b2a40`. The SDK catalog confirms its Parakeet
TDT 0.6B v3 origin. Model conversion/runtime changes are not automatically a
newly trained recognizer. The SDK source/network review is in TECHNICAL.md.

## Concrete app catalogs

Neither Superwhisper nor Handy was installed in /Applications or
~/Applications. No app benchmark has therefore been performed. Model tests use
independent local workers and cannot establish the apps' final latency, VAD,
live preview, vocabulary handling, formatting or paste behavior.

[Superwhisper's current model page](https://superwhisper.com/models) lists:

| Local model label | Underlying family | German | Published download |
| --- | --- | --- | --- |
| Fast / Nano / Standard / Pro | Whisper tiny / likely base / small / medium; Nano mapping unconfirmed | Yes | 75 MB / 150 MB / 500 MB / 1.5 GB |
| Ultra V3 | Whisper large-v3 | Yes | 3.0 GB |
| Ultra V3 Turbo | Whisper large-v3-turbo | Yes | 1.6 GB |
| Parakeet V2 | Parakeet English | No | 476 MB |
| Parakeet V3 | Multilingual Parakeet | Yes | 494 MB |
| Cohere Transcribe | Cohere 2B | Yes | 1.3 GB |

Superwhisper does not expose exact export commits or quantizations on that
page. Its page says 100+ languages for Cohere while its
[Cohere announcement](https://superwhisper.com/blog/cohere) and the
[upstream card](https://huggingface.co/CohereLabs/cohere-transcribe-03-2026)
specify 14; use the upstream list. Its advertised WER/speed figures are not
measurements on this Mac or this German corpus. "Ultra V3" (Whisper) must not
be confused with the separate "Parakeet Ultra" fine-tune.

[Handy stable 0.10.0](https://github.com/cjpais/Handy/releases/tag/v0.10.0)
was published November 2 and pins transcribe.cpp 0.4.0 in its bundled catalog.
The public catalog includes 76 entries, including VAD/language-ID entries rather
than only recognizers. Relevant exact repository revisions, language lists,
quantizations and file hashes are retained in `eval/asr/handy-catalog.json`.
These models are already in stable, not just a development branch. The main
branch checked at `73cc8579cff74e97e08de9d86035a92e4335ff7f` has an identical
bundled catalog and transcribe.cpp catalog version.

| Candidate | Stable Handy export | Treatment |
| --- | --- | --- |
| Parakeet V3 | `handy-computer/parakeet-tdt-0.6b-v3-gguf`, Q8_0 | Primary direct-family comparison; independent MLX export tested separately |
| Whisper large-v3 / turbo | `handy-computer/whisper-large-v3[-turbo]-gguf`, Q8_0 | Primary alternatives, MLX exports for this run |
| Cohere Transcribe | `handy-computer/cohere-transcribe-03-2026-gguf`, Q8_0 | Primary alternative; independent MLX conversion |
| Parakeet Ultra | `handy-computer/parakeet-ultra-gguf`, Q8_0, engine >=0.4.0 | Available; separate fine-tune, not Superwhisper Ultra V3 |
| Nemotron Streaming 3.5 | `handy-computer/nemotron-3.5-asr-streaming-0.6b-gguf`, Q8_0 | German available; streaming requires a separate chunk/latency protocol |
| Canary 180M Flash / 1B v2 | `handy-computer/canary-180m-flash-gguf` / `canary-1b-v2-gguf` | German available; secondary alternatives |
| Qwen3-ASR 0.6B / 1.7B | `handy-computer/Qwen3-ASR-0.6B-gguf` / `Qwen3-ASR-1.7B-gguf` | German available; secondary alternatives |
| Voxtral Mini 4B Realtime / 3B | `handy-computer/Voxtral-Mini-4B-Realtime-2602-gguf` / `Voxtral-Mini-3B-2507-gguf` | German available; heavier or streaming-specific comparison |
| Parakeet Primeline | `handy-computer/parakeet-primeline-gguf`, Q8_0 | German-focused candidate; catalog still declares multilingual coverage |
| Parakeet V2 / Unified EN, English Nemotron, Canary-Qwen | English-only entries | Excluded from German comparison |
| Voxtral Small 24B | 24B | Excluded from first round on 16 GiB shared memory |

The secondary candidates are not classified as unavailable or poor quality.
First-round priority is the requested old/new Voz, direct Parakeet V3, large
Whisper variants, Cohere, and a German fine-tune. Further models require their
own pinned conversion/runtime runs; a catalog listing is not a measurement.

### Explicit limits of this experiment

Parakeet Ultra and Qwen3-ASR are available German-capable candidates, but are
excluded from this measured round. The current 20-clip public set and unverified
personal prompts are too small to justify an exhaustive family ranking; reviewed
personal names/number/term targets should precede expansion beyond the requested
core comparisons. This is an experiment-design limit, not a claim that these
models are incompatible with the Mac or less accurate.

Nemotron Streaming 3.5 and Voxtral Mini Realtime are excluded from streaming
claims: their intended benefit needs fixed chunk sizes, incremental output,
first-token and finalization latency measurements. An offline full-file timer
would not assess that benefit. Canary and non-realtime Voxtral remain available
secondary families; their Handy GGUF exports require a separately validated
transcribe.cpp worker/conversion control rather than assuming equivalence to
these MLX workers. They were not run. The English-only entries are excluded by
language, and Voxtral Small 24B by this machine's 16 GiB memory budget.

## Corpus and validity

Existing material was found in the neighboring voxa project's
`_tools/voz-benchmark/data`: 30 synthetic clean/noisy cases and six human
recordings under Sprachtest, with a manifest and read prompts. The human audio
totals 89.53 seconds. Every human reference is marked
`read_prompt_unverified`. They cannot be described as manually checked
transcripts. Corpus copies/converted PCM, references, hashes and hypotheses are
kept outside the repository. No new microphone permission is required for file
inference. An offline review form is retained beside the local comparison
state as `reference-review.html`; its confirmations require actual listening.

Until references are independently checked against the recordings, human WER
is provisional. Synthetic prompt WER is a separate smoke/stress metric and not
representative human dictation accuracy. Repeated clean/noisy versions do not
increase the number of independent utterances. An additional public corpus uses the first 20 German FLEURS test rows at
revision `0b98f0538af50329c9b336824d7d697c594b9c26`, selected before inference.
Its parquet SHA-256 matches the official Hugging Face LFS hash. These are
published benchmark references, not references manually re-audited in this run.
All 20 reference sentences are distinct. Attribution: Google FLEURS, CC BY 4.0;
[dataset card](https://huggingface.co/datasets/google/fleurs).

Name/number/technical-term
accuracy needs locally reviewed span annotations; German capitalization alone
is not a reliable name detector.

Method and worker protocol: `eval/asr/README.md`. Fresh-process load and first
inference are separated from inference with a resident model. Each worker gets
identical converted PCM; no cleanup, hints or app-specific silence padding.
Process RSS and MLX allocation are incomplete views of unified memory. All
models execute sequentially on this Mac; no cross-machine leaderboard numbers
are used as results.

## German specialization

[Primeline Whisper large-v3-turbo German](https://huggingface.co/primeline/whisper-large-v3-turbo-german)
is a German speech fine-tune (809M parameters), not a smaller architecture
created by dropping other languages. It may improve German errors, but does
not inherently load faster or consume less RAM. A quantized MLX conversion is
included as a separate candidate. Compare it against multilingual turbo with
German explicitly selected before attributing an improvement to fine-tuning.
A matched multilingual turbo control is quantized locally with MLX to 4-bit,
group size 64, from the same cached FP16 base snapshot. This separates the
German fine-tuning comparison from the additional FP16-versus-Q4 comparison.
Other runtime/conversion differences remain confounds and are reported.

A switch should be based on verified German references, including short
commands, spontaneous corrections, names, technical terms and mixed English.
Do not replace the production recognizer solely because a model is labeled
German or has a favorable Common Voice result.

## Cleanup is a separate decision

Existing `eval/cleanup` uses hand-written synthetic text, not ASR audio. Its
reported Gemma 4 E4B results (77/86 development, 29/31 first holdout) are prior
measurements and have not been rerun here. They include false changes on text
that should stay unchanged (2/36 and 1/13). Cleanup cannot be credited with
improving raw ASR WER. The word-preservation guard prevents novel words but
cannot prevent incorrect deletions or choosing the wrong correction.

Keep the existing optional cleanup setting for production during this upgrade;
exclude it entirely from model timing/accuracy. A later end-to-end evaluation
should score raw speech against verbatim references and final cleaned text
against separately reviewed intended outputs, including numeric/name retention,
rejected outputs and added latency. A roughly 4 GiB loaded cleanup model also
competes with ASR and other applications on this 16 GiB Mac.
