#!/usr/bin/env python3
"""Build DEPLOYMENT-CONDITION routing SFT: prompt = request + the retrieved CANDIDATE catalog
(gold + distractors, each with its description), completion = the gold filename. This matches how
the harness feeds the model at inference (base+harness routes at 0.885 this way), unlike the earlier
bare query->filename SFT that mismatched deployment and REGRESSED routing (0.885->0.53). Grounded in
the DB; candidates are real workflows; leak guard inherited (clean routing SFT only).

Run:  python3 build_deployment_condition_sft.py --out clean_sft_depcond_routing.jsonl
"""
from __future__ import annotations
import argparse, json, random, re, sqlite3
from collections import defaultdict
from pathlib import Path

_HERE = Path(__file__).resolve().parent
DB = _HERE.parents[1] / "backend" / "database" / "galaxy_ai_tools.db"
POOL = _HERE.parents[1] / "docs" / "20260912_onprem_llm" / "data_pool_v2"
SYS = ("You are BioMate's workflow router. Given a user request and a list of candidate workflows "
       "(each with a short description), respond with the single candidate filename that best fits.")


def _lit(x):
    if isinstance(x, (list, dict)):
        return x
    try:
        return json.loads(x)
    except Exception:
        return []


_PARAM_DUMP = re.compile(r"key_parameters|::|;;|object=|classVar|\w+=[A-Z]|=The |=A |=List of", re.I)


def _first(txt):
    return (re.split(r"(?<=[.!?])\s", (txt or "").strip())[0] or "")[:160]


def _is_prose(d):
    return bool(d) and len(d) >= 12 and not _PARAM_DUMP.search(d) and (d.count("=") + d.count(";")) <= 1 and " " in d.strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--routing", default=str(POOL / "db_generated_routing_sft.jsonl"))
    ap.add_argument("--out", default=str(POOL / "clean_sft_depcond_routing.jsonl"))
    ap.add_argument("--n-cand", type=int, default=8, help="candidates shown per example (incl gold)")
    a = ap.parse_args()
    conn = sqlite3.connect(str(DB)); conn.row_factory = sqlite3.Row
    # filename -> (domain, desc); and domain -> [filenames] for distractor sampling
    meta, by_dom = {}, defaultdict(list)
    gen = {}
    gp = POOL / "generated_workflow_descriptions.jsonl"
    if gp.exists():
        for l in gp.read_text().splitlines():
            if l.strip():
                r = json.loads(l); gen[r["filename"]] = r["generated_description"]
    for r in conn.execute("SELECT filename,domain,description,annotation_v2 FROM workflows"):
        fn = r["filename"]
        if not fn:
            continue
        f1 = _first(r["annotation_v2"] or r["description"])
        # prefer a prose DB description; else the committee-validated generated one; else the domain
        d = f1 if _is_prose(f1) else (gen.get(fn) or (r["domain"] or "workflow"))
        meta[fn] = {"domain": r["domain"], "desc": d[:120]}
        if r["domain"]:
            by_dom[r["domain"]].append(fn)

    rows = [json.loads(l) for l in open(a.routing) if l.strip()]
    out = []
    for r in rows:
        msgs = r.get("messages", [])
        if len(msgs) < 3:
            continue
        query = msgs[1]["content"]
        gold = msgs[2]["content"]  # bare gold filename
        gmeta = meta.get(gold) or meta.get(gold.replace("nf-core", "nfcore")) or {}
        dom = gmeta.get("domain")
        rng = random.Random(hash(gold) & 0xffffffff)
        # candidates = gold + same-domain distractors + a few cross-domain, each with description
        sib = [f for f in by_dom.get(dom, []) if f != gold]
        rng.shuffle(sib)
        cross = [f for d2, fs in by_dom.items() if d2 != dom for f in fs]
        rng.shuffle(cross)
        cands = [gold] + sib[:max(0, a.n_cand - 3)] + cross[:3]
        cands = list(dict.fromkeys(cands))[:a.n_cand]
        if gold not in cands:
            cands[0] = gold
        rng.shuffle(cands)
        cat = "\n".join(f"- {c}: {meta.get(c, {}).get('desc', '')}" for c in cands)
        user = f"Request: {query}\n\nCandidate workflows:\n{cat}"
        out.append({"messages": [{"role": "system", "content": SYS},
                                 {"role": "user", "content": user},
                                 {"role": "assistant", "content": gold}],
                    "task": "routing_depcond"})
    Path(a.out).write_text("\n".join(json.dumps(r) for r in out) + "\n")
    print(f"DEPLOYMENT-CONDITION routing SFT: {len(out)} rows -> {a.out}")
    ex = out[0]["messages"][1]["content"]
    print("sample prompt (first 220 chars):\n ", ex[:220].replace("\n", " ⏎ "))


if __name__ == "__main__":
    main()
