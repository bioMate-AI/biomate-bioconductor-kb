#!/bin/bash -ue
if [ "true" = "true" ]; then
        python3 << 'EOF'
import json
import random
from datetime import datetime

random.seed(77)

drug_name   = "Imatinib"
target_gene = "BCR-ABL1"

# ---------------------------------------------------------------------------
# Mock CMap hits: 5 similar drug signatures with biologically coherent
# annotations for a kinase-inhibitor query (e.g. Imatinib / BCR-ABL1).
# ---------------------------------------------------------------------------
CMAP_DRUGS = [
    {
        "drug_name":      "Dasatinib",
        "target":         "BCR-ABL1 / Src",
        "moa_annotation": "ABL/Src kinase inhibitor (2nd gen TKI)",
        "cell_line":      "K562",
    },
    {
        "drug_name":      "Nilotinib",
        "target":         "BCR-ABL1",
        "moa_annotation": "Selective BCR-ABL1 inhibitor (2nd gen TKI)",
        "cell_line":      "K562",
    },
    {
        "drug_name":      "Bosutinib",
        "target":         "BCR-ABL1 / Src",
        "moa_annotation": "Dual ABL/Src kinase inhibitor",
        "cell_line":      "K562",
    },
    {
        "drug_name":      "Ponatinib",
        "target":         "BCR-ABL1 T315I",
        "moa_annotation": "Pan-BCR-ABL1 inhibitor (3rd gen TKI)",
        "cell_line":      "K562",
    },
    {
        "drug_name":      "Gleevec_analogue_1",
        "target":         "BCR-ABL1 / c-KIT",
        "moa_annotation": "Imatinib-class RTK inhibitor",
        "cell_line":      "HL60",
    },
]

similarity_scores = [0.92, 0.88, 0.81, 0.74, 0.63]
random.shuffle(similarity_scores)

matches = []
for drug, sim in zip(CMAP_DRUGS, similarity_scores):
    matches.append({
        "drug_name":           drug["drug_name"],
        "target":              drug["target"],
        "similarity_score":    round(sim, 3),
        "moa_annotation":      drug["moa_annotation"],
        "cell_line":           drug["cell_line"],
        "cmap_perturbagen_id": f"BRD-K{random.randint(10000000, 99999999):08d}",
    })

matches.sort(key=lambda m: m["similarity_score"], reverse=True)

# Write TSV
header = "drug_name\ttarget\tsimilarity_score\tmoa_annotation\tcell_line\tcmap_perturbagen_id"
with open("cmap_matches.tsv", "w") as f:
    f.write(header + "\n")
    for m in matches:
        f.write(
            f"{m['drug_name']}\t{m['target']}\t{m['similarity_score']}\t"
            f"{m['moa_annotation']}\t{m['cell_line']}\t{m['cmap_perturbagen_id']}\n"
        )

# Write JSON
payload = {
    "query_drug":  drug_name,
    "target_gene": target_gene,
    "n_matches":   len(matches),
    "mock_mode":   True,
    "timestamp":   datetime.utcnow().isoformat() + "Z",
    "matches":     matches,
}
with open("cmap_matches.json", "w") as f:
    json.dump(payload, f, indent=2)

print(f"CMap lookup (mock): {len(matches)} similar drugs found for {drug_name}")
for m in matches:
    print(f"  [{m['similarity_score']:.3f}] {m['drug_name']} — {m['moa_annotation']}")
EOF

    else
        # ---------------------------------------------------------------------------
        # Live: derive top up/down gene signature from DE results and query the
        # LINCS CMap API (clue.io).  Set env var LINCS_API_KEY before running.
        # ---------------------------------------------------------------------------
        python3 << 'PYEOF'
import json
import os
import sys
import csv
import urllib.request
from datetime import datetime

drug_name   = "Imatinib"
target_gene = "BCR-ABL1"

# Build top up/down gene lists from significant DE genes
sig_up   = []
sig_down = []
with open("de_results.tsv") as fh:
    reader = csv.DictReader(fh, delimiter="\t")
    for row in reader:
        try:
            padj   = float(row["padj"])
            log2fc = float(row["log2FoldChange"])
        except (ValueError, KeyError):
            continue
        if padj < 0.05 and abs(log2fc) > 1:
            if log2fc > 0:
                sig_up.append((row["gene_name"], log2fc))
            else:
                sig_down.append((row["gene_name"], log2fc))

sig_up.sort(key=lambda x: -x[1])
sig_down.sort(key=lambda x: x[1])
top_up   = [g for g, _ in sig_up[:50]]
top_down = [g for g, _ in sig_down[:50]]

api_key = os.environ.get("LINCS_API_KEY", "")
if not api_key:
    print("WARNING: LINCS_API_KEY not set — CMap query may fail", file=sys.stderr)

query_payload = json.dumps({
    "up_genes":  top_up,
    "dn_genes":  top_down,
    "n_results": 10,
}).encode()

matches = []
try:
    req = urllib.request.Request(
        "https://api.clue.io/api/query",
        data=query_payload,
        headers={"user_key": api_key, "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        cmap_data = json.loads(resp.read())
    matches_raw = cmap_data.get("result", [])
    for hit in matches_raw[:5]:
        matches.append({
            "drug_name":           hit.get("pert_iname", "unknown"),
            "target":              hit.get("target", "unknown"),
            "similarity_score":    round(float(hit.get("score", 0.0)), 3),
            "moa_annotation":      hit.get("moa", "unknown"),
            "cell_line":           hit.get("cell_id", "unknown"),
            "cmap_perturbagen_id": hit.get("pert_id", "unknown"),
        })
except Exception as exc:
    print(f"WARNING: CMap API call failed: {exc}", file=sys.stderr)

matches.sort(key=lambda m: m["similarity_score"], reverse=True)

header = "drug_name\ttarget\tsimilarity_score\tmoa_annotation\tcell_line\tcmap_perturbagen_id"
with open("cmap_matches.tsv", "w") as f:
    f.write(header + "\n")
    for m in matches:
        f.write(
            f"{m['drug_name']}\t{m['target']}\t{m['similarity_score']}\t"
            f"{m['moa_annotation']}\t{m['cell_line']}\t{m['cmap_perturbagen_id']}\n"
        )

payload = {
    "query_drug":  drug_name,
    "target_gene": target_gene,
    "n_matches":   len(matches),
    "mock_mode":   False,
    "timestamp":   datetime.utcnow().isoformat() + "Z",
    "matches":     matches,
}
with open("cmap_matches.json", "w") as f:
    json.dump(payload, f, indent=2)

print(f"CMap lookup (live): {len(matches)} similar drugs found for {drug_name}")
PYEOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "DRUG_MOA_RNASEQ:LINCS_CMAP_LOOKUP":
        python: $(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "true"
    END_VERSIONS
