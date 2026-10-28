"""Tables generated from committed artifacts (markdown + CSV in out/tables/):
 T1  data profile (CycPeptMPDB loader set; annotations)         T5  L5 loop results
 T6  model comparison (auto-fills from l7_aggregate.json; PENDING rows otherwise)
 T7  benchmark results (analysis I/M2/M: arms, AUROC/EF5 CIs, coverage)
 T_loops  earlier loops: retrospective evidence vs integration tests (docstrings verified)
No number is typed by hand; PENDING cells are explicit.
"""
import ast
import json

import pandas as pd

from common import OUT, check, log, reread, sources_of, src

TAB = OUT / "tables"
TAB.mkdir(exist_ok=True)
MAN = []


def write(name: str, df: pd.DataFrame, title: str, note: str, rels: list[str]) -> None:
    df.to_csv(TAB / f"{name}.csv", index=False)
    md = f"**{title}**\n\n" + df.to_markdown(index=False) + f"\n\n{note}\n\nSources: " + "; ".join(f"{s['path']}@{s['commit']}" for s in sources_of(*rels)) + "\n"
    (TAB / f"{name}.md").write_text(md)
    with open(OUT / "figure_sources.jsonl", "a") as f:
        f.write(json.dumps(dict(figure=name, title=title, caption=note, sources=sources_of(*rels), status="rendered")) + "\n")
    log(f"WROTE table {name} ({len(df)} rows)")


# ---------------- T1 data profile
ANN = "research/guangzhou_all_atom/cyclic_llm/stratification/data/annotations.csv.gz"
FS = "research/guangzhou_all_atom/cyclic_llm/stratification/data/feat_summary.json"
a = pd.read_csv(src(ANN)); fs = json.load(open(src(FS)))
b = a[a.y_loader.notna()]
fl = b.groupby("flat_smiles").size()
rows = [("unique structures in CycPeptMPDB (annotated)", len(a)), ("peptides with a PAMPA label (loader set)", len(b)), ("sources contributing to the loader set", int(fs["n_sources"])),
        ("sources with ≥30 peptides", int(fs["n_sources_ge30"])), ("flat structures (stereo-free)", len(fl)), ("peptides in stereoisomer groups (≥2)", int(fl[fl > 1].sum())),
        ("largest stereoisomer group", int(fl.max())), ("peptides with Caco-2 label", int(b.caco2.notna().sum())), ("peptides with RRCK label", int(b.rrck.notna().sum())),
        ("peptides with MDCK label", int(b.mdck.notna().sum()))]
topo = b.helm_topology.value_counts().to_dict() if "helm_topology" in b else {}
rows += [(f"topology (HELM-derived): {k}", int(v)) for k, v in topo.items()]
check("T1 n sources == feat_summary", b.Source.nunique(), int(fs["n_sources"]))
write("T1_data_profile", pd.DataFrame(rows, columns=["quantity", "value"]), "T1. CycPeptMPDB profile used by the loop", "Binding table, stability, conformational and renal datasets: are PENDING here (no machine-readable profile artifact committed). Solubility: no cyclic-peptide data (gap).", [ANN, FS])

# ---------------- T5 L5
L5 = "research/guangzhou_all_atom/cyclic_llm/loop_retro/results/l5_aggregate.json"
d = json.load(open(src(L5)))
rows = []
for r, name in (("A", "A in-distribution"), ("B", "B scaffold-shifted"), ("C", "C near-duplicate-aware")):
    fp = d[f"fp_{r}"]; rnd = d[f"fp_minus_random_{r}"]
    rows.append((name, fp["n_seeds"], fp["total"], rnd["random"], f"{rnd['mean']:+.1f} [{rnd['ci95'][0]:+.1f}, {rnd['ci95'][1]:+.1f}]",
                 d[f"fp_minus_rule_z_{r}"]["rule_total"], f"{d[f'fp_minus_rule_z_{r}']['mean']:+.1f} [{d[f'fp_minus_rule_z_{r}']['ci95'][0]:+.1f}, {d[f'fp_minus_rule_z_{r}']['ci95'][1]:+.1f}]",
                 "yes" if rnd["lower_gt0"] else "no"))
    check(f"T5 {r} loop total", fp["total"], float(reread(L5, f"fp_{r}", "total")))
write("T5_L5_loop", pd.DataFrame(rows, columns=["regime", "seeds", "loop hits/500", "random hits/500", "loop − random (95% CI)", "rule K_z hits/500", "loop − rule K_z (95% CI)", "95% CI of loop − random excludes 0"]),
      "T5. Controlled retrospective loop (L5; hits among 500 picks, within-source top-decile definition)",
      f"Pre-registered claim C1 (loop beats random in A and B): {'met' if d['CLAIM_loop_beats_random_both_regimes'] else 'NOT met'}. All 15 knowledge-arm contrasts: 99% intervals include 0.", [L5])

# ---------------- T7 benchmark results
RR = "research/guangzhou_all_atom/multitarget/integrin_chembl/retro_recovery/results/"
rows, rels = [], []
for an in ("I", "M2", "M"):
    rel = RR + f"results_V2_{an}.json"; rels.append(rel)
    res = json.load(open(src(rel)))
    allr = res["all"]
    for arm, v in allr["arms"].items():
        verdict = allr["vs_strongest_auc"].get(arm, {}).get("verdict", "(baseline)")
        cov = res["coverage"].get(arm, {})
        rows.append((an, arm, f"{v['auc']['point']:.3f} [{v['auc']['lo']:.3f}, {v['auc']['hi']:.3f}]", f"{v['ef5']['point']:.2f} [{v['ef5']['lo']:.2f}, {v['ef5']['hi']:.2f}]",
                     v["auc"]["n_families"], f"{cov.get('targets_nonconstant', '')}/{cov.get('targets_total', '')}", verdict))
write("T7_benchmark_results", pd.DataFrame(rows, columns=["analysis", "arm", "AUROC [95% CI]", "EF5 [95% CI]", "families", "targets non-constant", "verdict vs strongest baseline"]),
      "T7. Benchmark results (V2; all targets)", "Analyses I, M, M2 failed the validity gate in whole or in part (see F3); verdicts apply only under the control-adjusted rule. Strongest baseline per analysis is listed in F3.", rels)

# ---------------- loops classification
GA = "research/guangzhou_all_atom/"
loops = [("c2_retro_loop.py", GA + "c2_retro_loop.py", "retrospective closed-loop evidence (measured affinity)", ["retrospective closed-loop"], "numbers PENDING reproduction (workstream 7)"),
         ("replay_permeability.py", GA + "replay_permeability.py", "retrospective closed-loop evidence (measured PAMPA)", ["Retrospective"], None),
         ("L3/L5/L7 loop (this study)", GA + "cyclic_llm/loop_retro/run_loop_prior.py", "retrospective closed-loop evidence (measured PAMPA, within-source)", ["Knowledge-as-prior"], "L5: see T5"),
         ("simulate_closed_loop.py", GA + "simulate_closed_loop.py", "integration test only (SIMULATED assay values)", ["SIMULATED", "not full UniMoMo or evidence of biological improvement"], None),
         ("cyclic_llm/loop.py", GA + "cyclic_llm/loop.py", "built verifier-ladder system (not a replay on measured labels)", [], None)]
rows = []
for name, rel, klass, must, note in loops:
    p = src(rel)
    doc = ast.get_docstring(ast.parse(p.read_text())) or ""
    for kw in must:
        check(f"loops: docstring of {name} contains '{kw}'", kw.lower() in doc.lower(), True)
    first = " ".join(doc.split())[:200]
    extra = ""
    if name == "replay_permeability.py":
        pr = json.load(open(src(GA + "results/permeability_replay.json")))
        pp = pr["protocol"]
        extra = f"{len(pr['campaigns'])} campaigns ({', '.join(pr['campaigns'])}); {pp['initial_labels']} initial labels; {pp['rounds']} rounds × {pp['batch_size']}; {len(pp['seeds'])} seeds; {pp['split']}"
    rows.append((name, klass, first, extra or (note or "")))
write("T_loops_classification", pd.DataFrame(rows, columns=["loop", "classification", "own docstring (first 200 chars)", "protocol / status"]),
      "Earlier closed loops: which count as retrospective validation", "Classification per docs/20261028_CYCLIC_PROGRAM_MANUSCRIPT_INVENTORY.md §G; docstring keywords asserted in the log.",
      [GA + "c2_retro_loop.py", GA + "replay_permeability.py", GA + "cyclic_llm/loop_retro/run_loop_prior.py", GA + "simulate_closed_loop.py", GA + "cyclic_llm/loop.py", GA + "results/permeability_replay.json"])

# ---------------- T6 model comparison (auto-fill; PENDING otherwise)
L7 = "research/guangzhou_all_atom/cyclic_llm/loop_retro/results/l7_aggregate.json"
l7 = json.load(open(src(L7)))
planned = ["gbm_aware", "gbm_blind", "gbm_physchem", "knn", "gp_tanimoto", "atom_lm_P0", "chemberta", "ihlm_R0", "ihlm_R1", "ihlm_R2", "ihlm_R3", "ihlm_R4",
           "peptideclm2_base", "peptideclm2_large", "chemfm_1b", "smi_ted", "esm2_650m"]
def cell(entry, arm):
    try:
        v = entry["yield_total"][arm]
        return f"{v['mean']:.1f} [{v['ci'][0]:.1f}, {v['ci'][1]:.1f}] (n={v['n']})"
    except (KeyError, TypeError):
        return "PENDING"
rows = []
for m in planned:
    for reg in ("A", "B", "L"):
        e = l7["small"].get(f"{m}|{reg}") or l7.get("large", {}).get(f"{m}|{reg}")
        if e is None:
            rows.append((m, reg, "PENDING", "PENDING", "PENDING", "PENDING", "no result yet"))
        else:
            rows.append((m, reg, cell(e, "loop_sub"), cell(e, "loop_kphys_sub"), cell(e, "frozen_sub"), cell(e, "shuffled_sub"), e.get("status", "")))
write("T6_model_comparison", pd.DataFrame(rows, columns=["model", "regime", "loop yield (sub protocol)", "loop + K_phys", "frozen", "shuffled-label control", "status"]),
      "T6. Model comparison in the loop replay (yield over the sub protocol; mean [95% seed-bootstrap CI]; paired seeds)",
      "Only models with entries in l7_aggregate.json are filled; all others are PENDING. Regimes A in-distribution, B scaffold-shifted, L leave-labs-out. A result needs ≥ 8 paired seeds (n shown) before any claim. "
      "Exploratory general-purpose-LLM arms (Haiku 5.5, Gemini 3.1 Flash-Lite; cheap tier, 4 seeds) are in the supplement, not here.", [L7])
