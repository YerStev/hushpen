#!/usr/bin/env python3
"""Measures how well local models clean up dictated text.

Each model is served by llama-server (llama.cpp) and gets every case in
cases.jsonl with the instruction in prompt.txt. The model may rewrite: it
should drop fillers, self-corrections, retracted sentences and restarts, keep
the better of two phrasings, and lay out emails.

Usage:
    python3 eval/cleanup/run.py --model path/to/model.gguf [--model ...] [--hushpen .build/release/hushpen]

Results go to measurements/local/cleanup/ (not committed).
"""

import argparse
import json
import re
import shutil
import signal
import statistics
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
UNCHANGED = ("keep", "lookalike")
# The app's prompts; the evaluation uses the same files.
PROMPTS = ROOT / "Sources/hushpen/Prompts"


def words(text):
    return re.findall(r"\w+(?:'\w+)?", text.lower())


def lines(text):
    return [words(line) for line in text.split("\n") if line.strip()]


def matches(output, expected):
    """Same words. For emails also the greeting, the sign-off and the name on
    their own lines; how the body between them breaks does not matter."""
    for option in expected:
        if words(output) != words(option):
            continue
        if "\n" not in option:
            return True
        want, got = lines(option), lines(output)
        if len(got) >= 4 and got[0] == want[0] and got[-2:] == want[-2:]:
            return True
    return False


def novel_words(source, output):
    """Words in the output that the speaker never said."""
    said = set(words(source))
    return [word for word in words(output) if word not in said]


def numbered(text):
    """One sentence per line, each with its number in brackets."""
    sentences = [part for part in re.split(r"(?<=[.!?])\s+", text.strip()) if part]
    return "\n".join(f"[{index}] {sentence}" for index, sentence in enumerate(sentences, 1))


def unnumbered(reply):
    """The kept sentences; the "Remove:" line is the model's working step."""
    kept = [re.sub(r"^\[\d+\]\s*", "", line).strip() for line in reply.splitlines()
            if not line.lower().startswith("remove:")]
    return " ".join(line for line in kept if line)


def same_words_and_case(before, after):
    """The layout pass may only insert line breaks."""
    original = re.findall(r"\w+(?:'\w+)?", before)
    laid_out = re.findall(r"\w+(?:'\w+)?", after)
    return original == laid_out


# Only text that starts with a greeting and ends with a sign-off gets the
# layout pass.
GREETING = re.compile(r"^(hallo|hi|hey|moin|servus|liebe|lieber|sehr geehrte[rn]?|guten (morgen|tag|abend))\b", re.IGNORECASE)
SIGN_OFF = re.compile(r"\b(grüße|gruß|grüßen|bis dann|bis bald|bis später|ciao|tschüss|cheers)\b\W*(\w+\W*){1,3}$", re.IGNORECASE)


def looks_like_email(text):
    return bool(GREETING.search(text) and SIGN_OFF.search(text))


def clean_reply(text):
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL).strip()
    text = re.sub(r"^(output|ausgabe)\s*:\s*", "", text, flags=re.IGNORECASE)
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'":
        text = text[1:-1]
    return text.strip()


def request(port, payload, timeout=180):
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return json.load(response)


def wait_for_server(port, process, timeout=300):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if process.poll() is not None:
            raise RuntimeError("llama-server exited during start-up")
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=2) as response:
                if response.status == 200:
                    return
        except (urllib.error.URLError, ConnectionError):
            pass
        time.sleep(0.5)
    raise RuntimeError("llama-server did not become ready")


def run_model(model, cases, prompt, server, port, log_file, numbered_input=False, server_args=(), layout=None):
    command = [
        server, "-m", str(model), "--port", str(port), "--host", "127.0.0.1",
        "-ngl", "99", "-c", "8192", "-np", "1", "--jinja", "--no-webui", *server_args,
    ]
    started = time.perf_counter()
    process = subprocess.Popen(command, stdout=log_file, stderr=subprocess.STDOUT)
    try:
        wait_for_server(port, process)
        load_seconds = time.perf_counter() - started

        def ask(system, text):
            payload = {
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": text},
                ],
                "temperature": 0,
                "max_tokens": max(96, len(text)),
                "chat_template_kwargs": {"enable_thinking": False},
                "cache_prompt": True,
            }
            return clean_reply(request(port, payload)["choices"][0]["message"]["content"] or "")

        def clean(text):
            begin = time.perf_counter()
            output = ask(prompt, numbered(text) if numbered_input else text)
            if numbered_input:
                output = unnumbered(output)
            # Guard: words the speaker never said mean the model made
            # something up; the dictation is kept as it was.
            if novel_words(text, output):
                output = text
            if layout and looks_like_email(output):
                laid_out = ask(layout, output)
                if same_words_and_case(output, laid_out):
                    output = laid_out
            return output, time.perf_counter() - begin

        clean("Ich bin, äh, gleich da.")  # warm-up, fills the prompt cache

        results = []
        for case in cases:
            output, seconds = clean(case["input"])
            results.append({
                "id": case["id"],
                "category": case["category"],
                "long": case.get("long", False),
                "input": case["input"],
                "expected": case["expected"],
                "output": output,
                "correct": matches(output, case["expected"]),
                "novel": novel_words(case["input"], output),
                "seconds": round(seconds, 3),
            })
        return {"load_seconds": round(load_seconds, 1), "results": results}
    finally:
        process.send_signal(signal.SIGINT)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()


def run_hushpen(binary, cases):
    """The app's own pipeline, through `hushpen --clean-text`."""
    started = time.perf_counter()
    process = subprocess.Popen([binary, "--clean-text"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    results = []
    for case in cases:
        process.stdin.write(case["input"] + "\n")
        process.stdin.flush()
        reply = json.loads(process.stdout.readline())
        results.append({
            "id": case["id"],
            "category": case["category"],
            "long": case.get("long", False),
            "input": case["input"],
            "expected": case["expected"],
            "output": reply["output"],
            "correct": matches(reply["output"], case["expected"]),
            "novel": novel_words(case["input"], reply["output"]),
            "seconds": round(reply["seconds"], 3),
        })
    process.stdin.close()
    process.wait()
    return {"load_seconds": round(time.perf_counter() - started - sum(r["seconds"] for r in results), 1),
            "results": results}


def percentile(values, fraction):
    values = sorted(values)
    return values[min(len(values) - 1, int(round(fraction * (len(values) - 1))))]


def report(all_runs, cases):
    categories = list(dict.fromkeys(c["category"] for c in cases))
    unchanged = sum(c["category"] in UNCHANGED for c in cases)
    out = [
        "# Cleanup evaluation", "",
        f"{datetime.now():%Y-%m-%d %H:%M}, {len(cases)} cases. Correct means the same words as expected "
        "(for emails also greeting, sign-off and name on their own lines); a valid rewording counts as wrong, so read the failures.", "",
        "| Model | Correct | Changed text that should stay | Outputs with new words | Median s | p90 s | Long text s | Load s |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for model, run in all_runs.items():
        results = run["results"]
        for r in results:
            r["correct"] = matches(r["output"], r["expected"])
        correct = sum(r["correct"] for r in results)
        harmful = sum(1 for r in results if r["category"] in UNCHANGED and not r["correct"])
        novel = sum(1 for r in results if r["novel"])
        seconds = [r["seconds"] for r in results]
        long_seconds = [r["seconds"] for r in results if r["long"]] or [0]
        out.append(
            f"| {model} | {correct}/{len(results)} | {harmful}/{unchanged} | {novel} "
            f"| {statistics.median(seconds):.2f} | {percentile(seconds, 0.9):.2f} | {max(long_seconds):.2f} "
            f"| {run['load_seconds']} |"
        )

    out += ["", "## By category", "", "| Model | " + " | ".join(categories) + " |",
            "|---|" + "---|" * len(categories)]
    for model, run in all_runs.items():
        cells = []
        for category in categories:
            subset = [r for r in run["results"] if r["category"] == category]
            cells.append(f"{sum(r['correct'] for r in subset)}/{len(subset)}")
        out.append(f"| {model} | " + " | ".join(cells) + " |")

    for model, run in all_runs.items():
        failures = [r for r in run["results"] if not r["correct"]]
        out += ["", f"## Failures: {model}", ""]
        for r in failures:
            novel = f" (new words: {', '.join(r['novel'])})" if r["novel"] else ""
            out += [
                f"- `{r['id']}`{novel}",
                f"  - in:   {r['input']!r}",
                f"  - out:  {r['output']!r}",
                f"  - want: {r['expected'][0]!r}",
            ]
    return "\n".join(out) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--model", action="append", default=[], help="GGUF file; repeat for several")
    parser.add_argument("--hushpen", type=Path,
                        help="Also run the app's pipeline with this hushpen binary (--clean-text)")
    parser.add_argument("--cases", default=HERE / "cases.jsonl", type=Path)
    parser.add_argument("--prompt", default=PROMPTS / "cleanup.txt", type=Path)
    parser.add_argument("--out", default=ROOT / "measurements/local/cleanup", type=Path)
    parser.add_argument("--server", default=shutil.which("llama-server") or "llama-server")
    parser.add_argument("--port", default=8077, type=int)
    parser.add_argument("--only", help="Run only cases whose id starts with this prefix")
    parser.add_argument("--plain", dest="numbered", action="store_false",
                        help="Send the text as it is instead of as numbered sentences")
    parser.add_argument("--server-args", default="",
                        help='Extra llama-server flags, e.g. "--spec-type ngram-simple"')
    parser.add_argument("--layout", type=Path, default=PROMPTS / "layout.txt",
                        help="Second pass for emails; pass an empty string to skip it")
    parser.add_argument("--rescore", type=Path, help="Rebuild the report from a saved results.json")
    args = parser.parse_args()

    cases = [json.loads(line) for line in args.cases.read_text().splitlines() if line.strip()]
    if args.only:
        cases = [c for c in cases if c["id"].startswith(args.only)]
    if args.rescore:
        print(report(json.loads(args.rescore.read_text()), cases))
        return
    prompt = args.prompt.read_text()
    args.out.mkdir(parents=True, exist_ok=True)
    stamp = f"{datetime.now():%Y%m%d-%H%M%S}"

    all_runs = {}
    with open(args.out / f"{stamp}-server.log", "w") as log_file:
        for model in map(Path, args.model):
            print(f"Running {model.name} on {len(cases)} cases ...", file=sys.stderr)
            all_runs[model.name] = run_model(model, cases, prompt, args.server, args.port, log_file, args.numbered, args.server_args.split(),
                                             args.layout.read_text() if str(args.layout) not in ("", ".") else None)

    if args.hushpen:
        print("Running hushpen --clean-text ...", file=sys.stderr)
        all_runs["hushpen"] = run_hushpen(str(args.hushpen), cases)

    (args.out / f"{stamp}-results.json").write_text(json.dumps(all_runs, ensure_ascii=False, indent=1))
    text = report(all_runs, cases)
    (args.out / f"{stamp}-report.md").write_text(text)
    print(text)
    print(f"Saved to {args.out}/{stamp}-*", file=sys.stderr)


if __name__ == "__main__":
    main()
