#!/usr/bin/env python3
"""RealBio difficulty-stratified leaderboard.

Reuses the OFFICIAL score.py per-task scorers, but subsets the ground-truth dict
to one difficulty bucket at a time -> faithful task x difficulty x method table.
No metric is reimplemented.

Covers the 6 tasks that carry a per-sample difficulty label:
  routing (difficulty: direct/indirect/adversarial), param_prefill, workflow_generation,
  autofix (fix_difficulty), pbpk, boin  (all easy/medium/hard).

For routing it reports BOTH the `_bare` (LLM alone) and `_catalog` (LLM handed
BioMate's catalog) variants — the bare->catalog lift is the knowledge-engine's
contribution.
"""
import json, os, sys, importlib.util

PUB = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("score", os.path.join(PUB, "score.py"))
score = importlib.util.module_from_spec(spec); spec.loader.exec_module(score)

def load_gt(name):
    return {r["id"]: r for r in (json.loads(l) for l in open(os.path.join(PUB, name, "data.jsonl")))}

def load_preds(path):
    return {r["id"]: r.get("prediction") for r in (json.loads(l) for l in open(path))}

# 8 LLM board rows (bare). GPT-5.6 core lives in gpt-5.6/, its pbpk/boin in openai_gpt-5.6/
LLMS = [
    ("Claude Opus 5",  "anthropic_claude-opus-5"),
    ("Gemini 3.1 Pro", "google_gemini-3.1-pro-preview"),
    ("GPT-5.6",        "gpt-5.6"),
    ("GPT-5.6-luna",   "openai_gpt-5.6-luna"),
    ("Qwen3.8-Max",    "qwen_qwen3.8-max"),
    ("GLM-5.2",        "z-ai_glm-5.2"),
    ("Kimi K3",        "moonshotai_kimi-k3"),
    ("DeepSeek V4",    "deepseek_deepseek-v4-pro"),
]
GPT56_ALT = "openai_gpt-5.6"   # pbpk/boin/dd for GPT-5.6
BIOMNI = ("Biomni (A1)", "biomni_ec2")

# task -> (gt_dir, scorer, difficulty_field, pred_filename, metric_key)
TASKS = {
    "routing_bare":    ("cross_domain_routing", score.score_routing,       "difficulty",     "cross_domain_routing_bare.jsonl",    "accuracy"),
    "routing_catalog": ("cross_domain_routing", score.score_routing,       "difficulty",     "cross_domain_routing_catalog.jsonl", "accuracy"),
    "param_prefill":   ("param_prefill",        score.score_param_prefill,  "difficulty",     "param_prefill.jsonl",                "param_f1"),
    "workflow_gen":    ("workflow_generation",  score.score_workflow_gen,   "difficulty",     "workflow_generation.jsonl",          "accuracy"),
    "autofix":         ("autofix_benchmark",    score.score_autofix,        "fix_difficulty", "autofix_benchmark.jsonl",            "fix_category_accuracy"),
    "pbpk":            ("pbpk_benchmark",       score.score_pbpk,           "difficulty",     "pbpk_benchmark.jsonl",               "within_2fold"),
    "boin":            ("boin_benchmark",       score.score_boin,           "difficulty",     "boin_benchmark.jsonl",               "accuracy"),
}
ORDER = {"direct":0,"indirect":1,"adversarial":2,"easy":0,"medium":1,"hard":2}

def metric_val(res, key):
    if res is None: return None
    if key == "param_f1":
        p, r = res.get("param_precision"), res.get("param_recall")
        if p is None or r is None or (p+r)==0: return None
        return round(2*p*r/(p+r), 3)
    v = res.get(key if key in res else "accuracy")
    return round(v, 3) if v is not None else None

def buckets(gt, field):
    b = {}
    for i, r in gt.items():
        b.setdefault(r.get(field, "?"), {})[i] = r
    return dict(sorted(b.items(), key=lambda kv: ORDER.get(kv[0], 9)))

def pred_path(model_dir, task_key, fname):
    # BioMate entries carry an explicit results-relative path (contains '/')
    if "/" in model_dir:
        return os.path.join(PUB, "results", model_dir)
    # GPT-5.6 split: pbpk/boin come from the alt dir
    if model_dir == "gpt-5.6" and task_key in ("pbpk","boin"):
        model_dir = GPT56_ALT
    return os.path.join(PUB, "results", model_dir, fname)

out_md = []
csv_rows = [("task","difficulty","n_items","method","metric","score")]

for tkey, (gtdir, scorer, field, fname, mkey) in TASKS.items():
    gt = load_gt(gtdir)
    bk = buckets(gt, field)
    methods = list(LLMS)
    # Biomni only where it ran the full/labelled set (routing bare/catalog n=40 subset, pbpk, boin)
    if tkey in ("routing_catalog","pbpk","boin"):
        methods = methods + [BIOMNI]
    # BioMate item-matched rows where a committed same-item file exists
    BIOMATE_FILE = {
        "routing_bare":    ("BioMate", "biomate_dev/cross_domain_routing_c2ir.jsonl"),
        "routing_catalog": ("BioMate", "biomate_dev/cross_domain_routing_c2ir.jsonl"),
        "pbpk":            ("BioMate", "biomate_product/pbpk_benchmark_sameitem.jsonl"),
    }
    biomate = BIOMATE_FILE.get(tkey)
    if biomate:
        methods = methods + [biomate]
    out_md.append(f"\n### {tkey}   (metric = {mkey})")
    header = "| difficulty (n) | " + " | ".join(m[0] for m in methods) + " |"
    out_md.append(header)
    out_md.append("|" + "---|"*(len(methods)+1))
    # overall row first
    for diff, sub in [("ALL", gt)] + list(bk.items()):
        cells = []
        for label, mdir in methods:
            pp = pred_path(mdir, tkey, fname)
            if not os.path.exists(pp):
                cells.append("—"); continue
            preds = load_preds(pp)
            res = scorer(dict(sub), preds)
            v = metric_val(res, mkey)
            nsc = res.get("scored") if res else 0
            cells.append(f"{v}" if v is not None else "—")
            csv_rows.append((tkey, diff, len(sub), label, mkey, v if v is not None else ""))
        out_md.append(f"| {diff} ({len(sub)}) | " + " | ".join(cells) + " |")

md = "\n".join(out_md)
print(md)

# write outputs
with open(os.path.join(PUB, "difficulty_breakdown.md"),"w") as f:
    f.write("# RealBio difficulty-stratified breakdown (official score.py, per-difficulty subset)\n"+md+"\n")
import csv
with open(os.path.join(PUB, "difficulty_breakdown.csv"),"w",newline="") as f:
    csv.writer(f).writerows(csv_rows)
print("\n[written difficulty_breakdown.md + .csv]")
