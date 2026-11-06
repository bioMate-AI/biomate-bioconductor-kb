#!/usr/bin/env python3
"""Clean DPO preference pairs: an LLM validates that `rejected` is GENUINELY a worse routing answer
than `chosen` for the query (not also-correct, not arbitrary). Keeps only validated pairs. Fixes the
committee's one remaining soft spot (negative_valid 0.28-0.68). Incremental/resumable.

Run:  OPENROUTER_API_KEY=... python3 validate_dpo_negatives.py --in dpo_pairs_combined.jsonl \
          --out dpo_pairs_validated.jsonl --model openai/gpt-6.1-sol
"""
from __future__ import annotations
import argparse, json, os, re, urllib.request
from pathlib import Path

KEY = os.environ.get("OPENROUTER_API_KEY") or open(os.path.expanduser("~/.config/biomate/openrouter.key")).read().strip()
POOL = Path(__file__).resolve().parents[1].parent / "docs" / "20260912_onprem_llm" / "data_pool_v2"
PROMPT = (
    "You validate preference pairs for training a bioinformatics workflow-router. For EACH item: the "
    "user `query`, a `chosen` workflow and a `rejected` workflow. Mark keep=1 ONLY if `rejected` is a "
    "GENUINELY WORSE answer to the query than `chosen` AND still plausibly confusable (same area) — i.e. "
    "a good hard-negative. Mark keep=0 if `rejected` could ALSO be correct for the query, OR is "
    "obviously unrelated (too easy), OR chosen itself is wrong. Return ONLY JSON [{\"idx\":int,\"keep\":0|1}]."
)


def _call(model, prompt):
    body = {"model": model, "messages": [{"role": "user", "content": prompt}], "max_tokens": 4000, "temperature": 0}
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions",
                                 data=json.dumps(body).encode(),
                                 headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=180))["choices"][0]["message"]["content"] or ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", default=str(POOL / "dpo_pairs_combined.jsonl"))
    ap.add_argument("--out", default=str(POOL / "dpo_pairs_validated.jsonl"))
    ap.add_argument("--model", default="openai/gpt-6.1-sol")
    ap.add_argument("--batch", type=int, default=20)
    a = ap.parse_args()
    pairs = [json.loads(l) for l in open(a.inp) if l.strip()]
    outp = Path(a.out)
    done = 0
    if outp.exists():
        done = sum(1 for l in outp.read_text().splitlines() if l.strip())
    print(f"pairs: {len(pairs)} | already validated-written: {done} (resuming after)")
    # resume by index: we processed the first `done_batches*batch`; track via a sidecar count file
    side = outp.with_suffix(".progress")
    start = int(side.read_text()) if side.exists() else 0
    kept = done
    with outp.open("a") as fout:
        for i in range(start, len(pairs), a.batch):
            chunk = pairs[i:i + a.batch]
            items = [{"idx": j, "query": p["prompt"].split("\n\n", 1)[-1], "chosen": p["chosen"], "rejected": p["rejected"]}
                     for j, p in enumerate(chunk)]
            try:
                txt = _call(a.model, PROMPT + "\n\nITEMS:\n" + json.dumps(items))
                m = re.search(r"\[.*\]", txt, re.S)
                verd = {d["idx"]: d.get("keep", 0) for d in (json.loads(m.group()) if m else []) if isinstance(d, dict)}
            except Exception as e:
                print(f"  batch {i} failed: {str(e)[:90]}"); verd = {}
            for j, p in enumerate(chunk):
                if verd.get(j) == 1:
                    fout.write(json.dumps(p) + "\n"); fout.flush(); kept += 1
            side.write_text(str(i + a.batch))
            print(f"  {min(i+a.batch,len(pairs))}/{len(pairs)} | kept {kept}")
    print(f"VALIDATED DPO PAIRS kept: {kept} / {len(pairs)} -> {a.out}")


if __name__ == "__main__":
    main()
