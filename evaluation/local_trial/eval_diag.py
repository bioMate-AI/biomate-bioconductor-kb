"""Diagnostic: is the LOW score the MODEL or the EVAL HARNESS? Dumps sft_v4's actual outputs on a few
items, CURRENT harness (user-only, thinking-default, 300 tok, judge raw) vs FIXED (system+user,
enable_thinking=False, 512 tok, strip </think>), with judge scores for both. Ground truth, not theory.
Usage: python eval_diag.py --base <p> --adapter <p> --evalfile corpus_eval.jsonl
"""
import argparse, json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eval_removal import direct_load, judge, _DIRECT


def gen(msgs, mx, think):
    import torch
    m, tok = _DIRECT["model"], _DIRECT["tok"]
    try:
        s = tok.apply_chat_template(msgs, add_generation_prompt=True, tokenize=False, enable_thinking=think)
    except TypeError:
        s = tok.apply_chat_template(msgs, add_generation_prompt=True, tokenize=False)
    enc = tok(s, return_tensors="pt", add_special_tokens=False).to(m.device)
    n = enc["input_ids"].shape[1]
    with torch.no_grad():
        out = m.generate(**enc, max_new_tokens=mx, do_sample=False, pad_token_id=tok.pad_token_id)
    return tok.decode(out[0][n:], skip_special_tokens=True)


def strip_think(o): return o.rsplit("</think>", 1)[1].strip() if "</think>" in o else o.strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True); ap.add_argument("--adapter", required=True)
    ap.add_argument("--evalfile", required=True); ap.add_argument("--per", type=int, default=2)
    a = ap.parse_args()
    os.environ["EVAL_DTYPE"] = "bf16"
    direct_load(a.base, a.adapter)
    rows = [json.loads(l) for l in open(a.evalfile)]
    import collections
    seen = collections.Counter(); pick = []
    for r in rows:
        t = r.get("task", "?")
        if seen[t] < a.per: pick.append(r); seen[t] += 1
    SYS = "You are BioMate, an agentic bioinformatics assistant."
    for r in pick:
        um = [m for m in r["messages"] if m["role"] == "user"]
        am = [m for m in r["messages"] if m["role"] == "assistant"]
        if not (um and am): continue
        user, gold, task = um[-1]["content"], am[-1]["content"], r.get("task", "?")
        cur = gen([{"role": "user", "content": user}], 300, True)                 # current harness
        fix = strip_think(gen([{"role": "system", "content": SYS}, {"role": "user", "content": user}], 512, False))  # fixed
        sc_cur = judge([{"step": gold}], cur); sc_fix = judge([{"step": gold}], fix)
        print("="*80, flush=True)
        print(f"TASK {task}", flush=True)
        print(f"USER: {user[:160]}", flush=True)
        print(f"GOLD: {gold[:160]}", flush=True)
        print(f"CUR out (thinktoks?={'<think>' in cur or 'think' in cur[:20].lower()}, len={len(cur)}): {cur[:240]!r}", flush=True)
        print(f"FIX out (len={len(fix)}): {fix[:240]!r}", flush=True)
        print(f"JUDGE cur={sc_cur}  fix={sc_fix}", flush=True)
    print("DIAG_DONE", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
