# ASR results on this Mac, 2026-11-10

Two sequential rounds per model; no cleanup, vocabulary hints or app UI. The hushpen service was stopped during timing and restored afterward. Setup/downloads finished before timed runs. An earlier preparation run overlapped setup and is excluded. The native Cohere export was tested in a separate follow-up, with identical PCM hashes and the same two-round protocol.

M1 Pro, 8 CPU cores, 16 GiB RAM, macOS 26.6.2, Swift 6.4; AC power. SDKs 3.5.0 / 4.3.0; MLX 0.32.4, MLX-Audio 0.6.5, mlx-whisper 0.4.3. Core ML was configured for CPU + Neural Engine; MLX used Metal. Layer utilization was not profiled.

## Published German references

First 20 German FLEURS test rows, selected before inference: 450 reference words, 20 distinct texts. These are published benchmark references, not manually re-audited here. Each clip ran twice; repetitions do not double the accuracy sample size. WER is strict NFC/casefold/tokenized edit distance with no number equivalence. Higher RTFx is faster.

| Model / tested export | WER | Warm median | Warm p95 | RTFx | Model load | Sampled peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Voz 0.1.0 / SDK 3.5.0 | 3.56% | 254 ms | 352 ms | 54.4× | 357 ms | 125 MiB |
| Voz 0.5.0 / SDK 4.3.0 | 4.44% | 98 ms | 181 ms | 121.4× | 422 ms | 166 MiB |
| Direct Parakeet V3 Q4 | 5.11% | 253 ms | 910 ms | 38.0× | 2285 ms | 764 MiB |
| Whisper turbo FP16 | 3.78% | 833 ms | 966 ms | 15.5× | 376 ms | 1819 MiB |
| Whisper large-v3 Q4 | 2.89% | 1370 ms | 1784 ms | 9.3× | 847 ms | 1541 MiB |
| Whisper turbo German, encoder Q4 | 4.22% | 876 ms | 990 ms | 15.0× | 456 ms | 1259 MiB |
| Whisper turbo control, matched encoder Q4 | 3.78% | 865 ms | 978 ms | 15.0× | 195 ms | 978 MiB |
| Cohere native MLX-Audio Q4 | 3.78% | 526 ms | 774 ms | 24.4× | 1990 ms | 1770 MiB |

Load is a fresh-process model initialization after preparation of Core ML caches, not a cold-filesystem or first-install compilation measurement. Python imports outside the model loader are recorded separately locally. RSS is sampled every 50 ms and excludes some driver/accelerator allocations; it is not total unified-memory use. Do not add RSS and MLX allocation figures together.

## Personal and synthetic material

The six personal clips have 169 reference words; all references were marked read_prompt_unverified. Their WER is provisional. The 30 synthetic clips have 1,150 reference words and only 15 distinct texts (clean/noisy pairs); they are a separate stress test, not human dictation accuracy.

| Model | Personal WER, unverified references | Synthetic WER |
| --- | ---: | ---: |
| Voz 0.1.0 / SDK 3.5.0 | 9.47% | 2.43% |
| Voz 0.5.0 / SDK 4.3.0 | 8.88% | 2.78% |
| Direct Parakeet V3 Q4 | 11.24% | 0.87% |
| Whisper turbo FP16 | 10.06% | 0.96% |
| Whisper large-v3 Q4 | 10.65% | 1.30% |
| Whisper turbo German, encoder Q4 | 10.65% | 0.87% |
| Whisper turbo control, matched encoder Q4 | 11.83% | 1.74% |
| Cohere native MLX-Audio Q4 | 11.24% | 0.87% |

## First inference and resident memory

First inference uses the same first personal clip for every engine; the timed warm pass follows it. Peak MLX allocation is an allocator diagnostic, not total process or machine memory.

| Model | First inference, median | Warm RSS, median on FLEURS | Peak MLX allocation |
| --- | ---: | ---: | ---: |
| Voz 0.1.0 / SDK 3.5.0 | 159 ms | 124 MiB | not measured |
| Voz 0.5.0 / SDK 4.3.0 | 113 ms | 164 MiB | not measured |
| Direct Parakeet V3 Q4 | 107 ms | 673 MiB | 1515 MiB |
| Whisper turbo FP16 | 888 ms | 1814 MiB | 2373 MiB |
| Whisper large-v3 Q4 | 1235 ms | 1536 MiB | 1774 MiB |
| Whisper turbo German, encoder Q4 | 927 ms | 1254 MiB | 1532 MiB |
| Whisper turbo control, matched encoder Q4 | 926 ms | 974 MiB | 1532 MiB |
| Cohere native MLX-Audio Q4 | 949 ms | 1712 MiB | 2012 MiB |

## German specialization and uncertainty

The German fine-tune and multilingual turbo control have identical architecture and the same 160-layer quantization mask (4-bit, group 64); neither has an architectural size advantage. The full-FP16 multilingual turbo is an additional control. Different file formats can affect load-time and sampled peak RSS.

| Paired comparison | WER difference | Exploratory 95% paired-clip bootstrap interval |
| --- | ---: | ---: |
| voz-new minus voz-old | +0.89 pp | [-0.26, +2.40] pp |
| whisper-german minus whisper-turbo-q4 | +0.44 pp | [+0.00, +1.01] pp |
| whisper-large minus whisper-turbo | -0.89 pp | [-2.35, +0.24] pp |

Intervals use 10,000 resamples of the 20 clips (seed 0), not repeated latency runs as new observations. They describe this small read-speech sample; training overlap, spontaneous dictation, dialects and personal vocabulary were not controlled. There is no demonstrated reason here to switch solely because a model is German-focused.

## Export validation

The first Cohere checkpoint targeted another MLX layout. Reversing its published key map and splitting QKV preserved all 2,621 source tensors bit-for-bit; a deterministic sinusoidal position buffer was regenerated, and strict loading passed. That establishes storage reconstruction, not full upstream forward-pass parity. It produced 41.78% strict FLEURS WER with many omissions and is retained only as an exploratory implementation result. It is not used to judge the Cohere model family or Superwhisper. A native MLX-Audio BF16/Q4 export was therefore downloaded and measured separately.

Voz compiled MIL inspection found uint6 LUT operations in the old encoder/decoder, int4 blockwise dequantization in the new encoder and int8 in the new decoder. Both expose FP16 I/O and contain mixed-precision data. Metadata saying float16 does not imply all weights are FP16. See `eval/asr/voz-quantization.json`. SDK and export changed together, so the timing/error changes cannot be assigned to quantization alone.

## Model revisions

| Label | Repository | Immutable revision |
| --- | --- | --- |
| parakeet-v3 | beshkenadze/parakeet-tdt-0.6b-v3-mlx-4bit | `beffc63002c6fd5c5477c8c560bc8956c4878eb5` |
| whisper-turbo | mlx-community/whisper-large-v3-turbo | `a4aaeec0636e6fef84abdcbe3544cb2bf7e9f6fb` |
| whisper-large | mlx-community/whisper-large-v3-mlx-4bit | `d12b5d0043a6fe0c59af321617fba041d4e8e0c8` |
| cohere | beshkenadze/cohere-transcribe-03-2026-mlx-4bit | `104bc4391b5b1a12b040859793d7148525e1a08c` |
| whisper-german | mlx-community/whisper-large-v3-turbo-german-f16-q4 | `124e7ec35728c6a28499c577f96b5c228a8b1e52` |
| whisper-turbo-q4 | mlx-community/whisper-large-v3-turbo | `a4aaeec0636e6fef84abdcbe3544cb2bf7e9f6fb` |
| cohere-native | lyzgeorge/cohere-transcribe-03-2026-mlx-4bit | `f2f6d89b1a300c51f48ae1ecb8523dbb58636cb0` |

Voz revisions: v0.1.0 = `8e7ab8ca342c6bb00f9347a25e53fe44543b2a40`; v0.5.0 = `81940d2b41329e1e157acbac8af95e23aa4e224b`. SDK 4.3.0 = `baf4e6e3b4655c8e54aa8d5a25215b5f35f899a7`. Exact local file hashes, commands, inputs, reference statuses and raw hypotheses are retained outside Git under `~/Library/Application Support/hushpen-comparison`.

These are independent model/runtime tests. No Superwhisper or Handy app latency, VAD, vocabulary wrapper, cleanup or paste result has been measured. Availability and exclusions are documented in ASR-COMPARISON.md.

Full quantization dictionaries, scope counts, public weight-file hashes and
aggregate diagnostics are in [the results JSON](../eval/asr/results-2026-11-10.json).
The optional reference-span annotator used Gemma 4 E4B Q4_0, llama.cpp b11429
(commit d81235049), greedy decoding and thinking disabled. Its server was local,
its output was not logged, and it ended before native Cohere timing.

Validation: scripts/check.sh passed (13 tests plus packaging/policy checks),
the SDK audit passed, installed and archived app signatures verify, and the
installed app successfully transcribed one existing audio file to a private
pipe. Microphone capture and actual paste were not exercised by this file test.
Settings and cleanup registration are byte-identical to the saved baseline.
