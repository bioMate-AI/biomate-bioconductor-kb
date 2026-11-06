"""Run the drug novelty/FTO gate on the 22 CRO candidates (structure axis + same-target subset)."""
import csv, json, time
from dataclasses import asdict
from pathlib import Path
import drug_novelty_fto as nf

ROOT = Path(__file__).resolve().parent
LIB_CSV = ROOT / "data/raw/binding_affinity/binding_affinity_v1.csv"
CACHE = ROOT / "data/_registry_cache/novelty_lib_binding_affinity_v1.pkl"
PANELS = [
    ("results/CRO_SEND_pdl1_panelA.csv", "PD-L1", ("is_pdl1", "True")),
    ("results/CRO_SEND_avb6_panelB.csv", "avb6", ("is_avb6", "True")),
]
CHECK_PATENTS = bool(int(__import__("os").environ.get("FTO_CHECK_PATENTS", "0")))

t0 = time.time()
lib = nf.build_library(str(LIB_CSV), smiles_col="smiles", id_col="id",
                       tag_cols=["is_pdl1", "is_avb6", "target_name", "cyclic_bool"],
                       cache_path=str(CACHE))
print(f"library: {len(lib)} fingerprinted known actives  ({time.time()-t0:.0f}s)")

verdicts = []
for panel, tgt, restrict in PANELS:
    with open(ROOT / panel, newline="") as f:
        for row in csv.DictReader(f):
            cid = row["Item"]; seq = row["Sequence_N_to_C"]
            v = nf.score_candidate(cid, seq=seq, modality="peptide", cyclic=True,
                                   library=lib, restrict_tag=restrict,
                                   check_patents=CHECK_PATENTS)
            d = asdict(v); d["target"] = tgt
            verdicts.append(d)
            same = v.nearest_known_tag.get("same_target_max_tanimoto")
            print(f"{cid:11s} {tgt:6s} {seq:16s} occ={str(v.occupied):5s} {v.verdict:12s} "
                  f"maxT={v.max_tanimoto}  near={v.nearest_known_id}  sameT={same}")

summary = {
    "n": len(verdicts),
    "library_size": len(lib),
    "tanimoto_cutoff": nf.DEFAULT_TANIMOTO_CUTOFF,
    "occupied": sum(1 for v in verdicts if v["occupied"] is True),
    "novel": sum(1 for v in verdicts if v["verdict"] == "novel"),
    "unknown": sum(1 for v in verdicts if v["verdict"] == "unknown"),
    "patents_checked": CHECK_PATENTS,
    "max_tanimoto_overall": max((v["max_tanimoto"] for v in verdicts if v["max_tanimoto"] is not None), default=None),
}
out = {"summary": summary, "verdicts": verdicts}
outp = ROOT / "results/fto_novelty_22.json"
outp.parent.mkdir(parents=True, exist_ok=True)
with open(outp, "w") as f:
    json.dump(out, f, indent=2)
print("\nSUMMARY:", json.dumps(summary, indent=2))
print("wrote", outp)
