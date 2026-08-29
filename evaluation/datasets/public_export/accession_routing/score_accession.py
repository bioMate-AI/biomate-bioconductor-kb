#!/usr/bin/env python3
"""Score accession_routing predictions vs published gold modality. Objective, no LLM judge.
Usage: python3 score_accession.py results/<model>/accession_routing_<mode>.jsonl [more.jsonl ...]
Prints per-file: modality accuracy + 95% Wilson CI + per-modality breakdown + abstain rate.
"""
import json, os, sys, math
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
_GOLDF = os.environ.get("ACC_GOLD", "data.jsonl")
GOLD = {r["id"]: r for r in (json.loads(l) for l in open(os.path.join(HERE, _GOLDF)) if l.strip())}

def wilson(k, n, z=1.96):
    if n == 0: return [None, None]
    p = k / n; d = 1 + z*z/n
    c = p + z*z/(2*n); h = z*math.sqrt(p*(1-p)/n + z*z/(4*n*n))
    return [round((c-h)/d, 3), round((c+h)/d, 3)]

def score(path):
    preds = {p["id"]: p.get("prediction") for p in (json.loads(l) for l in open(path))}
    n = hit = abstain = 0
    per = defaultdict(lambda: [0, 0])  # modality -> [hit, total]
    for gid, g in GOLD.items():
        if gid not in preds: continue
        n += 1; gm = g["modality"]; pm = str(preds[gid] or "").strip().lower()
        per[gm][1] += 1
        if pm in ("abstain", ""): abstain += 1; continue
        if pm == gm: hit += 1; per[gm][0] += 1
    acc = round(hit / n, 4) if n else None
    return dict(n=n, correct=hit, accuracy=acc, ci95=wilson(hit, n), abstain=abstain,
                per_modality={k: f"{v[0]}/{v[1]}" for k, v in sorted(per.items())})

if __name__ == "__main__":
    for path in sys.argv[1:]:
        r = score(path)
        tag = os.path.basename(os.path.dirname(path)) + "/" + os.path.basename(path)
        print(f"\n== {tag} ==")
        print(f"  modality accuracy: {r['accuracy']}  (n={r['n']}, correct={r['correct']}, "
              f"abstain={r['abstain']})  95% CI {r['ci95']}")
        print(f"  per-modality: {r['per_modality']}")
