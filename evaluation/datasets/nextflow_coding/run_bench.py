#!/usr/bin/env python3
"""Generate a .nf per task from a model, then execution-grade it with grade.py.

Baseline path is OpenRouter (the local 9B is training / not served yet — see "Local model"
below to point this at a served endpoint later). Reuses the bioc_method_selection runner
conventions (urllib, OPENROUTER_API_KEY, markdown stripping, temperature 0).

Usage:
  export OPENROUTER_API_KEY=$(cat ~/.config/biomate/openrouter.key)
  python3 run_bench.py openai/gpt-5-mini [more/models ...]
  # outputs: gen/<model>/<task_id>.nf  and  results/<model>.json

Local model (later): set OPENROUTER_BASE and MODEL to a served OpenAI-compatible endpoint,
e.g. a vLLM server for the 9B:
  export OPENROUTER_BASE=http://localhost:8000/v1/chat/completions
  export OPENROUTER_API_KEY=dummy
  python3 run_bench.py biomate-9b
grade.py still executes the real `nextflow` binary regardless of which model produced the .nf.
"""
import json, os, re, sys, time, urllib.request
from pathlib import Path
import grade  # local grade.py

HERE = Path(__file__).resolve().parent
KEY = os.environ.get("OPENROUTER_API_KEY", "")
BASE = os.environ.get("OPENROUTER_BASE", "https://openrouter.ai/api/v1/chat/completions")

SYSTEM = ("You are an expert Nextflow (DSL2) engineer. You output ONLY the content of a single "
          "`.nf` file — no explanation, no markdown code fences. The file must be complete and runnable.")

def build_prompt(t):
    p = t["prompt"]
    if t["kind"] == "convert":
        return (f"TASK: convert the following {t['source_lang']} script to Nextflow DSL2.\n\n"
                f"--- SOURCE ({t['source_lang']}) ---\n{t['source']}\n--- END SOURCE ---\n\n{p}")
    if t["kind"] == "fix":
        return (f"TASK: fix the bug in the following Nextflow file.\n\n"
                f"--- BROKEN .nf ---\n{t['broken_nf']}\n--- END ---\n\n{p}")
    return f"TASK: write a Nextflow DSL2 pipeline.\n\n{p}"

def strip_nf(text):
    """Pull the .nf out of a model reply: prefer a fenced block, else raw text."""
    if not text:
        return ""
    m = re.search(r"```(?:groovy|nextflow|nf|bash)?\s*\n(.*?)```", text, re.S)
    body = m.group(1) if m else text
    # drop any leading prose line before the shebang / nextflow directive if present
    return body.strip() + "\n"

def call(model, prompt):
    body = json.dumps({"model": model,
                       "messages": [{"role": "system", "content": SYSTEM},
                                    {"role": "user", "content": prompt}],
                       "temperature": 0, "max_tokens": 1500}).encode()
    hdr = {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json",
           "HTTP-Referer": "https://biomate.ai", "X-Title": "biomate-nextflow-coding"}
    for a in range(3):
        try:
            r = urllib.request.urlopen(urllib.request.Request(BASE, body, hdr), timeout=120)
            j = json.load(r)
            usage = j.get("usage", {}) or {}
            return j["choices"][0]["message"]["content"] or "", usage
        except Exception as e:
            if a == 2:
                print(f"  FAIL {model}: {e}", flush=True)
                return "", {}
            time.sleep(4)

def main():
    models = sys.argv[1:]
    if not models:
        sys.exit("usage: python3 run_bench.py <model> [<model> ...]")
    if not KEY:
        sys.exit("ERROR: set OPENROUTER_API_KEY (export OPENROUTER_API_KEY=$(cat ~/.config/biomate/openrouter.key))")
    if not grade._have_nextflow():
        sys.exit("ERROR: nextflow not on PATH — grading cannot run.")

    tasks = [json.loads(l) for l in open(HERE / "tasks.jsonl")]
    (HERE / "results").mkdir(exist_ok=True)

    for model in models:
        gen_dir = HERE / "gen" / model.replace("/", "_")
        gen_dir.mkdir(parents=True, exist_ok=True)
        results, tok_in, tok_out = [], 0, 0
        for t in tasks:
            text, usage = call(model, build_prompt(t))
            nf = strip_nf(text)
            (gen_dir / f"{t['id']}.nf").write_text(nf)
            tok_in += usage.get("prompt_tokens", 0)
            tok_out += usage.get("completion_tokens", 0)
            r = grade.grade_one(nf, t)
            r.pop("logs", None)
            results.append(r)
            print(f"  {t['id']:28s} A={r['tierA_pass']} B={r['tierB_pass']} "
                  f"C={r['tierC_pass']} score={r['score']}", flush=True)
        agg = grade.aggregate(results)
        agg["tokens"] = {"prompt": tok_in, "completion": tok_out}
        out = HERE / "results" / f"{model.replace('/', '_')}.json"
        out.write_text(json.dumps({"model": model, "aggregate": agg, "results": results}, indent=2))
        print(json.dumps(agg, indent=2))
        print(f"wrote {out}\n")

if __name__ == "__main__":
    main()
