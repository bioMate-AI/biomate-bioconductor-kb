#!/usr/bin/env python3
"""Regenerate leaderboard.csv from the committed predictions using the shared score.py.

Every cell traces to a predictions file under results/ scored by score.py — no hand
values, no carry-forward. This mirrors the manuscript Table 1 (§5.2 of
docs/20260817_REALBIO_BENCHMARK_PAPER_DRAFT.md):

  * LLM rows: each task scored from that model's committed predictions file
    (routing from cross_domain_routing_bare; boin over the 18 scorable items —
    score.py excludes the 2 null-true_MTD_mg items).
  * BioMate: reported ONLY where a committed SAME-ITEM RealBio prediction exists —
    routing (biomate_dev/cross_domain_routing_c2ir.jsonl) and pbpk
    (biomate_product/pbpk_benchmark_sameitem.jsonl). All other BioMate cells have
    no committed same-item predictions and are left blank (not-yet-reported), never
    carried over from non-RealBio harnesses.
  * Biomni: agent scaffold; routing from its catalog file (no bare file committed);
    dd is a small partial cell (n=4) and is annotated.

Usage: python3 regen_leaderboard_csv.py            # writes leaderboard.csv
       python3 regen_leaderboard_csv.py --stdout    # print, do not write
"""
import os, sys, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("score", os.path.join(HERE, "score.py"))
S = importlib.util.module_from_spec(spec); spec.loader.exec_module(S)

# CSV column -> (benchmark dir, scorer, headline key)
TASKS = {
    "routing":          ("cross_domain_routing", S.score_routing,      "accuracy"),
    # +harness (catalog) routing — same scorer, reads each model's cross_domain_routing_catalog
    # file (the RAG-fair candidate list = the production retrieval harness). Bare vs this column
    # = the LLM+harness dividend. Blank where a model has no committed catalog file.
    "routing_harness":  ("cross_domain_routing", S.score_routing,      "accuracy"),
    "autofix":          ("autofix_benchmark",    S.score_autofix,      "fix_category_accuracy"),
    "param_prefill_F1": ("param_prefill",        S.score_param_prefill,"param_f1"),
    "workflow_gen":     ("workflow_generation",  S.score_workflow_gen, "accuracy"),
    "protocol_QC":      ("protocol_thresholds",  S.score_protocol,     "accuracy"),
    "pbpk_2fold":       ("pbpk_benchmark",       S.score_pbpk,         "within_2fold"),
    "boin_mtd":         ("boin_benchmark",       S.score_boin,         "accuracy"),
    "dd_spearman":      ("drug_discovery_e2e",   S.score_drug_disc,    "mean_spearman_rank"),
}
COLS = list(TASKS.keys())

def score(col, relpath):
    """Score one cell from a predictions file; return the rounded headline value."""
    bench, scorer, key = TASKS[col]
    path = os.path.join(HERE, "results", relpath)
    res = scorer(S.load(bench), S.load_preds(path))
    v = res.get(key)
    return None if v is None else round(v, 3)

# model display name -> {col: predictions relpath}. Only listed cells are scored;
# any col omitted is left blank (not-yet-reported).
MODELS = [
    ("Claude Opus 5", "anthropic_claude-opus-5", {}),
    ("Gemini 3.1 Pro", "google_gemini-3.1-pro-preview", {}),
    # GPT-5.6 predictions are split across two committed dirs:
    ("GPT-5.6", "gpt-5.6", {"pbpk_2fold": "openai_gpt-5.6/pbpk_benchmark.jsonl",
                            "boin_mtd": "openai_gpt-5.6/boin_benchmark.jsonl",
                            "dd_spearman": "openai_gpt-5.6/drug_discovery_e2e.jsonl"}),
    ("Qwen3.8-Max", "qwen_qwen3.8-max", {}),
    ("GLM-5.2", "z-ai_glm-5.2", {}),
    # GLM-5.3-prime = latest GLM flagship (roster-verified). Only the 5 RealBio-native tasks are
    # committed; boin/pbpk/dd (DrugDev) left blank until the gated sweep runs them.
    ("GLM-5.3-prime", "z-ai_glm-5.3-prime", {}),
    ("GPT-5.6-luna", "openai_gpt-5.6-luna", {}),
    ("Kimi K3", "moonshotai_kimi-k3", {}),
    ("DeepSeek V4-pro", "deepseek_deepseek-v4-pro", {}),
    # --- small / open LLMs (results committed; were missing from the leaderboard) ---
    ("Qwen3.8-27B", "qwen_qwen3.8-27b", {}),
    ("Qwen3.5-27B", "qwen_qwen3.5-27b", {}),
    ("Qwen3.5-9B", "qwen_qwen3.5-9b", {}),
    ("Qwen2.5-7B", "qwen_qwen-2.5-7b-instruct", {}),
    # on-prem 9B (the small open model BioMate serves): base vs gold-SFT
    ("BioMate 9B (base)", "base", {}),
    ("BioMate 9B (SFT)", "sft", {}),
    # BioMate: ONLY same-item committed cells (routing + pbpk). Everything else blank.
    ("BioMate (engine-free, C2)", None, {
        "routing": "biomate_dev/cross_domain_routing_c2ir.jsonl",
        "pbpk_2fold": "biomate_product/pbpk_benchmark_sameitem.jsonl",
    }),
    # Biomni: routing from catalog file (no bare committed); dd is partial (n=4).
    ("Biomni (A1 scaffold)", "biomni_ec2", {
        "routing": "biomni_ec2/cross_domain_routing_catalog.jsonl",
    }),
]

def default_file(col, base):
    fbase = {
        "routing": "cross_domain_routing_bare",
        # described = production-faithful catalog (UnifiedWorkflowSearch view); prefer it,
        # fall back to the legacy names-only `catalog` in build().
        "routing_harness": "cross_domain_routing_catalog_described",
        "autofix": "autofix_benchmark",
        "param_prefill_F1": "param_prefill", "workflow_gen": "workflow_generation",
        "protocol_QC": "protocol_thresholds", "pbpk_2fold": "pbpk_benchmark",
        "boin_mtd": "boin_benchmark", "dd_spearman": "drug_discovery_e2e",
    }[col]
    return f"{base}/{fbase}.jsonl"

def fmt(v):
    return "" if v is None else f"{v:.3f}"

def build():
    rows = ["model," + ",".join(COLS)]
    for name, base, overrides in MODELS:
        cells = []
        for col in COLS:
            if base is None and col not in overrides:
                cells.append("")                 # BioMate not-yet-reported cell
                continue
            relpath = overrides.get(col) or default_file(col, base)
            full = os.path.join(HERE, "results", relpath)
            # +harness routing: some models committed the described-catalog variant filename —
            # both are catalog (harness) mode, so fall back to it.
            if not os.path.exists(full) and col == "routing_harness" and base:
                alt = f"{base}/cross_domain_routing_catalog.jsonl"
                if os.path.exists(os.path.join(HERE, "results", alt)):
                    relpath, full = alt, os.path.join(HERE, "results", alt)
            if not os.path.exists(full):
                cells.append(""); continue
            v = score(col, relpath)
            # Biomni dd is a small partial cell (only 4/15 items completed) — annotate.
            if name.startswith("Biomni") and col == "dd_spearman" and v is not None:
                cells.append(f"{v:.1f} (n=4)")
            else:
                cells.append(fmt(v))
        qname = f'"{name}"' if "," in name else name
        rows.append(qname + "," + ",".join(cells))
    return "\n".join(rows) + "\n"

if __name__ == "__main__":
    csv = build()
    if "--stdout" in sys.argv:
        sys.stdout.write(csv)
    else:
        with open(os.path.join(HERE, "leaderboard.csv"), "w") as f:
            f.write(csv)
        sys.stderr.write("wrote leaderboard.csv\n")
