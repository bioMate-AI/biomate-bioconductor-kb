"""Build analysis-ready matrices from local GEO SOFT and correct the GSE35455 design label.

GSE35455 reality (verified from the SOFT, not the series description):
  - Two-color dye-swap array. #VALUE = "normalized log2 ratio after/before treatment".
  - 112 RA patients, each with exactly 2 peripheral-blood arrays that are DYE-SWAP
    TECHNICAL REPLICATES of one after/before Tocilizumab contrast (both normalized to
    the same after/before orientation; median replicate r reported below).
  - This is a per-patient TREATMENT-RESPONSE contrast, NOT a pre/post durability
    time-series. The earlier "n_paired_pre_post" framing was wrong and is retracted.

Output: a probes x 112-patients matrix of averaged after/before log2 ratios.
GSE113156's expression matrix is NOT embedded in its SOFT (0 sample tables) — it
needs a separate series-matrix download; recorded as a gap, not silently skipped.
Matrix written to raw/ (gitignored). Nothing here is training-eligible.
"""
import json, statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw"

def load_all_tables(path):
    """Return {gsm: {probe: value}} for every embedded sample table."""
    cur = None; intbl = False; data = {}
    for line in path.open(encoding="utf-8", errors="replace"):
        if line.startswith("^SAMPLE ="):
            cur = line.split(" = ", 1)[1].strip()
        elif line.startswith("!sample_table_begin"):
            intbl = True; data.setdefault(cur, {})
        elif line.startswith("!sample_table_end"):
            intbl = False
        elif intbl:
            p = line.rstrip("\n").split("\t")
            if len(p) > 1 and p[0] not in ("ID_REF", ""):
                try: data[cur][p[0]] = float(p[1])
                except ValueError: pass
    return data

# Map GSM -> patient using the extracted labels
labels = {r["gsm"]: r for r in json.loads((ROOT / "geo_sample_labels.json").read_text()) if r["gse"] == "GSE35455"}
by_patient = {}
for gsm, r in labels.items():
    by_patient.setdefault(r["patient_id"], []).append(gsm)

tables = load_all_tables(RAW / "GSE35455.soft.txt")

# collapse dye-swap replicates per patient (average shared probes), record replicate r
patient_vec = {}
rep_corrs = []
for pat, gsms in by_patient.items():
    if len(gsms) == 2 and all(g in tables for g in gsms):
        a, b = tables[gsms[0]], tables[gsms[1]]
        common = [k for k in a if k in b]
        if len(common) > 100:
            xa = [a[k] for k in common]; xb = [b[k] for k in common]
            sa, sb = statistics.pstdev(xa), statistics.pstdev(xb)
            if sa and sb:
                ma, mb = sum(xa)/len(xa), sum(xb)/len(xb)
                r = sum((xa[i]-ma)*(xb[i]-mb) for i in range(len(common)))/len(common)/(sa*sb)
                rep_corrs.append(r)
        # union of probes, mean where both present
        vec = {}
        for k in set(a) | set(b):
            vals = [v for v in (a.get(k), b.get(k)) if v is not None]
            vec[k] = sum(vals)/len(vals)
        patient_vec[pat] = vec

# assemble matrix
all_probes = sorted({p for v in patient_vec.values() for p in v})
patients = sorted(patient_vec)
out = RAW / "GSE35455_afterbefore_matrix.tsv"
with out.open("w") as f:
    f.write("probe\t" + "\t".join(patients) + "\n")
    for pr in all_probes:
        f.write(pr + "\t" + "\t".join(f"{patient_vec[p].get(pr, ''):}" if pr in patient_vec[p] else "" for p in patients) + "\n")

summary = {
    "GSE35455": {
        "design": "two-color dye-swap microarray; VALUE = log2(after/before) Tocilizumab",
        "unit": "per-patient after/before treatment-response contrast",
        "retraction": "NOT pre/post durability; the 2 arrays/patient are dye-swap technical replicates",
        "n_patients": len(patients),
        "n_probes": len(all_probes),
        "median_dye_swap_replicate_r": round(statistics.median(rep_corrs), 3) if rep_corrs else None,
        "replicate_r_note": "low median r => single-patient contrasts are noisy; treat as weak per-patient labels",
        "matrix": str(out.relative_to(ROOT)),
        "tissue": "peripheral blood (no synovium present)",
    },
    "GSE113156": {
        "design": "expression matrix NOT embedded in SOFT (0 sample tables)",
        "gap": "needs series-matrix / supplementary download before it can be joined",
        "labels_ready": "yes (6 subjects, CD8+CD4, w0/w24) — only the expression values are missing",
    },
}
(ROOT / "geo_matrix_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
