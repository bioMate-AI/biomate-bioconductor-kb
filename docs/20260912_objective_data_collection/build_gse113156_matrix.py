"""Build the GSE113156 count matrix from per-sample supplementary files.

Genuine RNA-seq gene counts (Gene, Count) for 6 RA subjects x {CD8,CD4} x {w0,w24}.
This is a real paired-longitudinal design (unlike GSE35455's noisy dye-swap arrays).
Small n, so role = external-test only, but with real expression now joined to labels.
Matrix -> raw/ (gitignored). Training-eligible stays False pending the admission gate.
"""
import gzip, json, re, statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parent
FILES = ROOT / "raw" / "gse113156_files"

samples = {}   # gsm -> {gene: count}
meta = {}      # gsm -> dict(cell, week, subject)
for p in sorted(FILES.glob("*.txt.gz")):
    m = re.match(r"(GSM\d+)_(CD\d)_(w\d+)_(R\d+)_", p.name)
    if not m:
        continue
    gsm, cell, week, subj = m.groups()
    meta[gsm] = dict(cell=cell, week=week, subject=subj)
    counts = {}
    with gzip.open(p, "rt") as f:
        for line in f:
            g, _, v = line.partition("\t")
            if g == "Gene" or not v.strip():
                continue
            try: counts[g] = int(v)
            except ValueError: pass
    samples[gsm] = counts

genes = sorted({g for c in samples.values() for g in c})
gsms = sorted(samples)
out = ROOT / "raw" / "GSE113156_counts_matrix.tsv"
with out.open("w") as f:
    f.write("gene\t" + "\t".join(gsms) + "\n")
    for g in genes:
        f.write(g + "\t" + "\t".join(str(samples[s].get(g, 0)) for s in gsms) + "\n")

# QC: library sizes + paired w0/w24 structure per (subject, cell)
libsizes = {s: sum(samples[s].values()) for s in gsms}
pairs = {}
for gsm, mt in meta.items():
    pairs.setdefault((mt["subject"], mt["cell"]), {})[mt["week"]] = gsm
complete_pairs = {k: v for k, v in pairs.items() if "w0" in v and "w24" in v}

summary = {
    "GSE113156": {
        "assay": "RNA-seq gene counts (real longitudinal, paired w0/w24)",
        "n_genes": len(genes),
        "n_samples": len(gsms),
        "n_subjects": len({m["subject"] for m in meta.values()}),
        "cell_types": sorted({m["cell"] for m in meta.values()}),
        "complete_w0_w24_pairs": len(complete_pairs),
        "pairs_detail": [f"{subj}/{cell}" for (subj, cell) in sorted(complete_pairs)],
        "median_library_size": int(statistics.median(libsizes.values())),
        "min_library_size": int(min(libsizes.values())),
        "matrix": str(out.relative_to(ROOT)),
        "role": "external-test only (n small but real paired design); do not train on it",
        "training_eligible": False,
    }
}
(ROOT / "gse113156_matrix_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
