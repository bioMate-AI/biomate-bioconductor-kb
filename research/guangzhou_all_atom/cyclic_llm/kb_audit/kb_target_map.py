"""UniProt keys for the 16 target_kb targets and a STRICT match to the benchmark's target_key/genes (retro_recovery/data/targets.csv).
Rule: a KB target maps to a benchmark target only if the benchmark gene set contains ALL chains of the KB target (heterodimers) or a chain that
pairs only with that partner (ITGB6 pairs only with ITGAV; ITGB7 mainly with ITGA4/ITGAE — treated as specific for a4b7 only when ITGA4 also present).
This fixes the over-count of a loose gene-token match (e.g. genes ITGAV,ITGB3 = alpha-v beta-3 must NOT map to avb6)."""
import os, sys
import pandas as pd
KB = {  # kb target -> (UniProt accessions of the complex, required gene set, single-chain-specific genes that suffice)
 "avb6": (["P06756", "P18564"], {"itgav", "itgb6"}, {"itgb6"}),
 "a4b1": (["P13612", "P05556"], {"itga4", "itgb1"}, set()),
 "a4b7": (["P13612", "P26010"], {"itga4", "itgb7"}, set()),
 "lfa1": (["P20701", "P05107"], {"itgal", "itgb2"}, {"itgal"}),   # alpha-L pairs only with beta-2
 "pdl1": (["Q9NZQ7"], {"cd274"}, set()), "baff": (["Q9Y275"], {"tnfsf13b"}, set()), "c5": (["P01031"], {"c5"}, set()),
 "cd20": (["P11836"], {"ms4a1"}, set()), "cd40": (["P25942"], {"cd40"}, set()), "fcrn": (["P55899"], {"fcgrt"}, set()),
 "il17a": (["Q16552"], {"il17a"}, set()), "il17f": (["Q96PD4"], {"il17f"}, set()), "il23": (["Q9NPF7", "P29460"], {"il23a"}, set()),
 "il2ra": (["P01589"], {"il2ra"}, set()), "il6r": (["P08887"], {"il6r"}, set()), "tnfa": (["P01375"], {"tnf"}, set())}

def genes_of(s): return {g for g in str(s).lower().replace(";", " ").replace(",", " ").split() if g and g != "nan"}

def map_kb(genes):
    g = genes_of(genes); hits = []
    for k, (_acc, need, spec) in KB.items():
        if need <= g or (spec and spec <= g): hits.append(k)
    return hits

if __name__ == "__main__":
    t = pd.read_csv(os.path.join(os.path.dirname(__file__), "..", "..", "multitarget", "integrin_chembl", "retro_recovery", "data", "targets.csv"))
    t["kb"] = t.genes.map(map_kb); cov = t[t.kb.map(len) > 0]
    cov.assign(kb=cov.kb.map(",".join))[["target_key", "genes", "kb", "n_pos", "eligible_M", "eligible_I"]].to_csv(os.path.join(os.path.dirname(__file__), "kb_target_coverage.csv"), index=False)
    print("strict mapping: targets", len(cov), "| eligible_M", int(cov.eligible_M.sum()), "of", int(t.eligible_M.sum()), "| eligible_I", int(cov.eligible_I.sum()), "of", int(t.eligible_I.sum()),
          "| positives", int(cov.n_pos.sum()), "of", int(t.n_pos.sum()))
    print(cov[["target_key", "genes", "kb", "n_pos", "eligible_M", "eligible_I"]].to_string(index=False))
