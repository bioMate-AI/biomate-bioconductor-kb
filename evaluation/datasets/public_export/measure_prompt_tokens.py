#!/usr/bin/env python3
"""Deterministically measure RealBio prompt (input) + prediction (output-floor) sizes.
NO API calls. Reconstructs the EXACT prompt each item sent, using run_baseline.py's TASKS/GEN
spec, and measures chars -> est tokens (chars/4). Output floor = saved prediction length.
Key fact this exposes: the INPUT prompt is identical across models for a given task+mode
(prompt doesn't depend on the model), so token counts are model-independent; cost differences
are driven by per-token PRICE, not token count."""
import os, json, re, sys
BASE = "/Users/kky/biomate/evaluation/datasets/public_export"
sys.path.insert(0, BASE)

# import the exact specs (module import triggers only argparse in main(), guarded by __main__)
import importlib.util
spec = importlib.util.spec_from_file_location("rb", os.path.join(BASE, "run_baseline.py"))
rb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rb)
TASKS, GEN = rb.TASKS, rb.GEN

def toks(s):  # chars/4 heuristic
    return len(s) / 4.0

def labels_for(task, rows):
    g = TASKS[task]["gt"]
    return sorted({str(r[g]) for r in rows if g in r})

def build_prompt(task, r, rows, mode):
    if task in GEN:
        s = GEN[task]
        return f"{s['instr']}\n\nINPUT:\n{s['inp'](r)}"
    s = TASKS[task]
    if task == "cross_domain_routing" and mode == "bare":
        return (f"{s['instr']}\nRespond with ONLY the single canonical workflow name "
                f"(e.g. 'nf-core/rnaseq') and nothing else.\n\nINPUT:\n{s['inp'](r)}")
    labs = labels_for(task, rows)
    return (f"{s['instr']}\nRespond with EXACTLY ONE option from this list and nothing else:\n"
            f"{', '.join(labs)}\n\nINPUT:\n{s['inp'](r)}")

# task -> (mode label, mode) pairs we actually scored
PLAN = [
    ("cross_domain_routing", "routing_bare", "bare"),
    ("cross_domain_routing", "routing_catalog", "catalog"),
    ("autofix_benchmark", "autofix", "catalog"),
    ("protocol_thresholds", "protocol", "catalog"),
    ("param_prefill", "param_prefill", "catalog"),
    ("workflow_generation", "workflow_gen", "catalog"),
]

print(f"{'task/mode':<22}{'n':>5}{'in_tok/item':>13}{'in_tok_total':>14}")
grand_in = 0
per = {}
for task, lab, mode in PLAN:
    dp = os.path.join(BASE, task, "data.jsonl")
    if not os.path.exists(dp):
        print(f"{lab:<22}  (no data.jsonl)"); continue
    rows = [json.loads(l) for l in open(dp)]
    ins = [toks(build_prompt(task, r, rows, mode)) for r in rows]
    tot = sum(ins); grand_in += tot
    per[lab] = dict(n=len(rows), in_per=tot/len(rows), in_tot=tot)
    print(f"{lab:<22}{len(rows):>5}{tot/len(rows):>13.0f}{tot:>14.0f}")
print(f"{'—'*54}")
print(f"{'TOTAL input tokens (one pass, one model)':<40}{grand_in:>14.0f}")

# output floor from a representative model's predictions
print("\n=== output-floor (chars/4 of saved predictions), gpt-5.6 as representative ===")
RES = os.path.join(BASE, "results", "gpt-5.6")
out_tot = 0
for task, lab, mode in PLAN:
    suffix = {"bare": "_bare", "catalog": "_catalog"}.get(mode, "") if task == "cross_domain_routing" else ""
    fn = os.path.join(RES, f"{task}{suffix}.jsonl")
    if not os.path.exists(fn):
        # try common alt names
        alt = os.path.join(RES, f"{task}.jsonl")
        fn = alt if os.path.exists(alt) else fn
    if not os.path.exists(fn):
        print(f"{lab:<22}  (no prediction file)"); continue
    preds = [json.loads(l) for l in open(fn)]
    o = sum(toks(json.dumps(p.get("prediction", ""))) for p in preds)
    out_tot += o
    print(f"{lab:<22}{len(preds):>5}{o/max(len(preds),1):>13.1f}{o:>14.0f}")
print(f"{'—'*54}")
print(f"{'TOTAL output-floor tokens (one pass)':<40}{out_tot:>14.0f}")
print(f"\nRATIO input:output = {grand_in/max(out_tot,1):.0f} : 1  (input-dominated workload)")

json.dump({"per_taskmode": per, "grand_input_tokens": grand_in, "output_floor_tokens": out_tot},
          open("/tmp/token_measure.json", "w"), indent=2)
