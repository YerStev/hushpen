# Cleanup evaluation

Measures whether a local model can clean up dictated German text the way a
person would after dictating: drop filler sounds, keep only the corrected
version of a self-correction, remove sentences the speaker takes back, start
over after "nochmal von vorne", keep the better of two phrasings, and lay out
emails. Nothing here is part of the app.

- `cases.jsonl`: 86 hand-written test sentences with the expected result,
  including text that must stay unchanged ("Er wollte nicht nein sagen").
  The prompts were tuned on these.
- `cases-holdout.jsonl`: 31 further sentences, written before the final
  pipeline was run and not used for tuning.
- `prompt-numbered.txt`: cleanup; the text is sent as numbered sentences and
  the model returns the sentences that remain.
- `prompt-layout.txt`: second pass, only for text that starts with a greeting
  and ends with a sign-off.
- `run.py`: serves each model with `llama-server` and scores it.

No real dictations are used. The pipeline rejects an output that contains
words the speaker never said and keeps the dictation as it was.

```sh
brew install llama.cpp
python3 eval/cleanup/run.py --numbered --prompt eval/cleanup/prompt-numbered.txt \
    --layout eval/cleanup/prompt-layout.txt \
    --server-args "--spec-type ngram-simple --spec-draft-n-max 32" \
    --model ~/.cache/hushpen-eval/gemma-4-E4B_q4_0-it.gguf
```

Reports are written to `measurements/local/cleanup/` and are not committed.

## Results (M1 Pro, 16 GB, llama.cpp b11429, 2026-10-18)

Single prompt, before the numbered pipeline (prompt v3, `ngram-simple` speculation):

| Model | Size | Correct (86) | Changed text that should stay (36) | Median / long text |
| --- | --- | --- | --- | --- |
| Qwen3.5 2B Q4_K_M | 1.3 GB | 48 | 4 | 0.25 s / 1.9 s (prompt v1, no speculation) |
| Gemma 4 E2B Q4_K_M | 3.1 GB | 65 | 4 | 0.4 s / 1.4 s |
| Qwen3.5 4B Q4_K_M | 2.7 GB | 68 | 2 | 0.7 s / 2.4 s |
| Gemma 4 E4B QAT Q4_0 | 5.2 GB | 76 | 1 | 0.5 s / 1.9 s |
| Qwen3.5 9B Q4_K_M | 5.7 GB | 76 | 4 | 0.9 s / 3.9 s |

Chosen pipeline with Gemma 4 E4B (numbered cleanup, layout pass, guard):

| Set | Correct | Changed text that should stay | Median / long text |
| --- | --- | --- | --- |
| cases.jsonl | 77/86 | 2/36 | 0.5 s / 1.5 s |
| cases-holdout.jsonl | 29/31 | 1/13 | 0.5 s |

Findings:

- Taking a sentence back ("vergiss den letzten Satz") is the hardest case.
  Numbered sentences raised it from 5/10 to 7–8/10 for Gemma 4 E4B; Qwen 4B
  could not use the numbering (0/10).
- Smaller models sometimes keep the wrong half of a self-correction
  ("zwei Pizzen" instead of "drei"); Gemma 4 E4B and Qwen 9B got all 16 right.
- Speculative decoding from the input (`ngram-simple`) halves the time for
  long text, because the output mostly repeats the input. Output is unchanged.
- Asking to keep du/Sie and verb forms stopped "Fasse" -> "Fassen Sie".
