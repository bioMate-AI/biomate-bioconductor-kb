"""ADMET-CPT test data builder. Uses Therapeutics Data Commons (PyTDC) ADMET group — real, standard, with
SCAFFOLD splits (anti-memorization: train/test share no scaffolds). Emits:
 (1) SFT: SMILES -> property/class, conversation format (per task, scaffold-split train).
 (2) CPT priors: ADMET structure-activity knowledge the task NEEDS in weights (the "clock-formula" analog):
     descriptor/rule definitions (Lipinski/Veber/Ghose), assay descriptions, SAR patterns. Deterministic text.
 (3) eval: scaffold-split test, with the TDC metric per task (AUROC class / MAE|Spearman reg).
Run on a box: pip install PyTDC rdkit. Usage: python build_admet_data.py --out-dir admet_data
"""
import argparse, json, os
# Representative ADMET tasks (mix of classification + regression; TDC names + metric)
TASKS = {
 "herg": ("hERG", "classification", "AUROC"),          # cardiotoxicity (hERG block)
 "ames": ("AMES", "classification", "AUROC"),           # mutagenicity
 "cyp3a4": ("CYP3A4_Veith", "classification", "AUROC"), # CYP inhibition
 "bbb": ("BBB_Martins", "classification", "AUROC"),     # blood-brain barrier
 "caco2": ("Caco2_Wang", "regression", "MAE"),          # permeability
 "lipophilicity": ("Lipophilicity_AstraZeneca", "regression", "MAE"),
 "ld50": ("LD50_Zhu", "regression", "MAE"),             # acute toxicity
}
PRIORS = [  # the stable, task-needed ADMET knowledge (CPT corpus) — the 'clock formula' analog
 "Lipinski's Rule of Five: oral bioavailability is favored when MW<=500, logP<=5, H-bond donors<=5, acceptors<=10.",
 "Veber rules: good oral bioavailability correlates with <=10 rotatable bonds and polar surface area <=140 A^2.",
 "hERG blockade (cardiotoxicity) is associated with lipophilic basic amines, high logP, and a positively charged nitrogen ~5-7 A from an aromatic ring.",
 "CYP3A4 inhibition is common for large lipophilic molecules with aromatic nitrogen heterocycles that coordinate heme iron.",
 "Blood-brain-barrier penetration is favored by low polar surface area (<90 A^2), MW<450, and moderate logP (2-4).",
 "AMES mutagenicity is associated with structural alerts: aromatic nitro groups, aromatic amines, epoxides, Michael acceptors, N-nitroso groups.",
 "Caco-2 permeability (gut absorption) decreases with high polar surface area and many H-bond donors.",
 "Lipophilicity (logD7.4) rises with aromatic rings and halogenation, falls with ionizable/polar groups.",
]


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--out-dir", default="admet_data"); a = ap.parse_args()
    os.makedirs(a.out_dir, exist_ok=True)
    from tdc.benchmark_group import admet_group
    grp = admet_group(path=os.path.join(a.out_dir, "tdc"))
    sft, evals = [], []
    for key, (tdc_name, kind, metric) in TASKS.items():
        try:
            bench = grp.get(tdc_name)
        except Exception as e:
            print(f"skip {tdc_name}: {str(e)[:80]}", flush=True); continue
        tr, te = bench["train_val"], bench["test"]   # TDC scaffold split
        q = (f"For the molecule SMILES below, predict {tdc_name} "
             + ("(answer 0 or 1)." if kind == "classification" else "(answer a numeric value).")
             + "\nSMILES: {smi}\nAnswer:")
        for _, r in tr.iterrows():
            sft.append({"messages": [{"role": "user", "content": q.format(smi=r["Drug"])},
                        {"role": "assistant", "content": str(r["Y"])}], "task": f"admet_{key}", "source": "tdc"})
        for _, r in te.iterrows():
            evals.append({"task": f"admet_{key}", "grader": kind, "metric": metric,
                          "prompt": q.format(smi=r["Drug"]), "gold": r["Y"]})
        print(f"{tdc_name}: train {len(tr)}, test {len(te)} ({kind}/{metric})", flush=True)
    with open(os.path.join(a.out_dir, "admet_sft.jsonl"), "w") as f:
        for r in sft: f.write(json.dumps(r) + "\n")
    with open(os.path.join(a.out_dir, "admet_eval.jsonl"), "w") as f:
        for r in evals: f.write(json.dumps(r) + "\n")
    with open(os.path.join(a.out_dir, "admet_cpt_priors.jsonl"), "w") as f:
        for _ in range(50):  # repeat the small stable prior set to upweight (memorization of the rules)
            for p in PRIORS: f.write(json.dumps({"text": p}) + "\n")
    print(f"ADMET DATA: sft={len(sft)} eval={len(evals)} priors={len(PRIORS)}x50 -> {a.out_dir}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
