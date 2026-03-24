#!/bin/bash -ue
if [ "false" = "true" ]; then
        python3 << 'EOF'
import json
import csv
import random
from datetime import datetime

random.seed(42)

meta_id     = "test_actives"
max_cands   = int("20")
lip_filter  = str("true").lower() in ("true", "1", "yes")

# ---------------------------------------------------------------------------
# Mock top-10 scaffold hop candidates
#
# Ranking criteria:
#   1. MMP frequency (how often the scaffold appears across pairs)
#   2. QED score      (Bickerton et al., quantitative drug-likeness 0-1)
#   3. Lipinski pass  (MW ≤ 500, HBA ≤ 10, HBD ≤ 5, logP ≤ 5)
#   4. SA score       (Ertl & Schuffenhauer synthetic accessibility, 1=easy, 10=hard)
#
# Compounds ordered by composite rank score = 0.4*QED + 0.3*norm_freq + 0.3*(1-norm_SA)
# ---------------------------------------------------------------------------
candidates = [
    {
        "rank":           1,
        "scaffold_smiles": "[*]Nc1ccc(O)cc1",
        "hop_smiles":     "CC(=O)Nc1ccc(O)cc1",
        "scaffold_id":    "SCAF_001",
        "mmp_frequency":  9,
        "qed_score":      0.82,
        "sa_score":       1.83,
        "mw_da":          151.16,
        "logP":           0.91,
        "hba":            2,
        "hbd":            2,
        "lipinski_pass":  True,
        "rank_score":     0.791,
        "origin_pairs":   "MMP_001,MMP_009,MMP_010,MMP_011,MMP_013,MMP_014",
        "novelty_flag":   "reference_scaffold",
    },
    {
        "rank":           2,
        "scaffold_smiles": "Fc1ccc([*])cc1",
        "hop_smiles":     "CC(=O)Nc1ccc(F)cc1",
        "scaffold_id":    "SCAF_002",
        "mmp_frequency":  5,
        "qed_score":      0.79,
        "sa_score":       1.91,
        "mw_da":          153.15,
        "logP":           1.77,
        "hba":            1,
        "hbd":            1,
        "lipinski_pass":  True,
        "rank_score":     0.753,
        "origin_pairs":   "MMP_002,MMP_006,MMP_008",
        "novelty_flag":   "novel_hop",
    },
    {
        "rank":           3,
        "scaffold_smiles": "COc1ccc([*])cc1",
        "hop_smiles":     "CC(=O)Nc1ccc(OC)cc1",
        "scaffold_id":    "SCAF_003",
        "mmp_frequency":  7,
        "qed_score":      0.77,
        "sa_score":       2.01,
        "mw_da":          165.19,
        "logP":           1.35,
        "hba":            2,
        "hbd":            1,
        "lipinski_pass":  True,
        "rank_score":     0.741,
        "origin_pairs":   "MMP_001,MMP_006,MMP_007,MMP_015",
        "novelty_flag":   "novel_hop",
    },
    {
        "rank":           4,
        "scaffold_smiles": "Clc1ccc([*])cc1",
        "hop_smiles":     "CC(=O)Nc1ccc(Cl)cc1",
        "scaffold_id":    "SCAF_004",
        "mmp_frequency":  5,
        "qed_score":      0.74,
        "sa_score":       1.95,
        "mw_da":          169.61,
        "logP":           2.39,
        "hba":            1,
        "hbd":            1,
        "lipinski_pass":  True,
        "rank_score":     0.718,
        "origin_pairs":   "MMP_003,MMP_007,MMP_008",
        "novelty_flag":   "novel_hop",
    },
    {
        "rank":           5,
        "scaffold_smiles": "Cc1cc([*])ccc1O",
        "hop_smiles":     "CC(=O)Nc1ccc(O)cc1C",
        "scaffold_id":    "SCAF_005",
        "mmp_frequency":  4,
        "qed_score":      0.72,
        "sa_score":       2.14,
        "mw_da":          165.19,
        "logP":           1.35,
        "hba":            2,
        "hbd":            2,
        "lipinski_pass":  True,
        "rank_score":     0.694,
        "origin_pairs":   "MMP_013,MMP_014",
        "novelty_flag":   "novel_hop",
    },
    {
        "rank":           6,
        "scaffold_smiles": "[*]Nc1cc(O)ccc1",
        "hop_smiles":     "CC(=O)Nc1cc(O)ccc1",
        "scaffold_id":    "SCAF_006",
        "mmp_frequency":  3,
        "qed_score":      0.70,
        "sa_score":       2.02,
        "mw_da":          151.16,
        "logP":           0.88,
        "hba":            2,
        "hbd":            2,
        "lipinski_pass":  True,
        "rank_score":     0.681,
        "origin_pairs":   "MMP_009",
        "novelty_flag":   "novel_hop",
    },
    {
        "rank":           7,
        "scaffold_smiles": "O=C([*])c1ccccc1",
        "hop_smiles":     "O=C(Nc1ccc(O)cc1)c1ccccc1",
        "scaffold_id":    "SCAF_007",
        "mmp_frequency":  4,
        "qed_score":      0.68,
        "sa_score":       1.78,
        "mw_da":          213.23,
        "logP":           2.12,
        "hba":            2,
        "hbd":            2,
        "lipinski_pass":  True,
        "rank_score":     0.671,
        "origin_pairs":   "MMP_005,MMP_012",
        "novelty_flag":   "novel_hop",
    },
    {
        "rank":           8,
        "scaffold_smiles": "Fc1cc([*])ccc1O",
        "hop_smiles":     "CC(=O)Nc1ccc(O)c(F)c1",
        "scaffold_id":    "SCAF_008",
        "mmp_frequency":  3,
        "qed_score":      0.66,
        "sa_score":       2.21,
        "mw_da":          169.15,
        "logP":           1.47,
        "hba":            2,
        "hbd":            2,
        "lipinski_pass":  True,
        "rank_score":     0.649,
        "origin_pairs":   "MMP_010",
        "novelty_flag":   "novel_hop",
    },
    {
        "rank":           9,
        "scaffold_smiles": "[*]Nc1ccc([*])cc1",
        "hop_smiles":     "CCC(=O)Nc1ccc(O)cc1",
        "scaffold_id":    "SCAF_009",
        "mmp_frequency":  3,
        "qed_score":      0.63,
        "sa_score":       2.05,
        "mw_da":          165.19,
        "logP":           1.14,
        "hba":            2,
        "hbd":            2,
        "lipinski_pass":  True,
        "rank_score":     0.621,
        "origin_pairs":   "MMP_004,MMP_012",
        "novelty_flag":   "novel_hop",
    },
    {
        "rank":           10,
        "scaffold_smiles": "Cc1ccc([*])cc1O",
        "hop_smiles":     "CC(=O)Nc1ccc(O)c(C)c1",
        "scaffold_id":    "SCAF_010",
        "mmp_frequency":  2,
        "qed_score":      0.60,
        "sa_score":       2.18,
        "mw_da":          165.19,
        "logP":           1.22,
        "hba":            2,
        "hbd":            2,
        "lipinski_pass":  True,
        "rank_score":     0.598,
        "origin_pairs":   "MMP_011",
        "novelty_flag":   "novel_hop",
    },
]

# Apply Lipinski filter if requested
if lip_filter:
    candidates = [c for c in candidates if c["lipinski_pass"]]

# Cap at max_candidates
candidates = candidates[:max_cands]

# Re-rank after filter
for i, c in enumerate(candidates, 1):
    c["rank"] = i

with open(f"{meta_id}_scaffold_candidates.csv", "w", newline="") as csvf:
    writer = csv.DictWriter(csvf, fieldnames=list(candidates[0].keys()))
    writer.writeheader()
    writer.writerows(candidates)

# ---- HTML Report ----
def qed_color(q):
    if q >= 0.75: return "#2ecc71"    # green
    if q >= 0.60: return "#f39c12"    # amber
    return "#e74c3c"                  # red

def sa_color(sa):
    if sa <= 2.0: return "#2ecc71"
    if sa <= 3.5: return "#f39c12"
    return "#e74c3c"

rows_html = ""
for c in candidates:
    lip_badge = (
        '<span style="background:#2ecc71;color:#fff;padding:2px 6px;border-radius:3px;">PASS</span>'
        if c["lipinski_pass"] else
        '<span style="background:#e74c3c;color:#fff;padding:2px 6px;border-radius:3px;">FAIL</span>'
    )
    qc = qed_color(c["qed_score"])
    sc = sa_color(c["sa_score"])
    rows_html += (
        "        <tr>\n"
        "          <td style='text-align:center'><b>" + str(c["rank"]) + "</b></td>\n"
        "          <td><code style='font-size:11px'>" + str(c["hop_smiles"]) + "</code></td>\n"
        "          <td><code style='font-size:10px;color:#555'>" + str(c["scaffold_smiles"]) + "</code></td>\n"
        "          <td style='text-align:center'>" + str(c["mmp_frequency"]) + "</td>\n"
        "          <td style='text-align:center;color:" + qc + "'><b>" + "{:.2f}".format(c["qed_score"]) + "</b></td>\n"
        "          <td style='text-align:center;color:" + sc + "'>" + "{:.2f}".format(c["sa_score"]) + "</td>\n"
        "          <td style='text-align:center'>" + "{:.1f}".format(c["mw_da"]) + "</td>\n"
        "          <td style='text-align:center'>" + "{:.2f}".format(c["logP"]) + "</td>\n"
        "          <td style='text-align:center'>" + lip_badge + "</td>\n"
        "          <td style='text-align:center;font-weight:bold'>" + "{:.3f}".format(c["rank_score"]) + "</td>\n"
        "        </tr>\n"
    )

n_cands   = len(candidates)
lip_label = "ON" if lip_filter else "OFF"
generated = datetime.utcnow().isoformat() + "Z"
html = (
    "<!DOCTYPE html>\n"
    "<html lang='en'>\n"
    "<head>\n"
    "  <meta charset='UTF-8'>\n"
    "  <title>BioMate Scaffold Hopping Report - " + meta_id + "</title>\n"
    "  <style>\n"
    "    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;"
    "           margin: 0; padding: 24px; background: #f9f9f9; color: #222; }\n"
    "    h1   { font-size: 22px; color: #2c3e50; border-bottom: 2px solid #3498db;"
    "           padding-bottom: 8px; }\n"
    "    .meta { background: #eaf2fb; border-left: 4px solid #3498db;"
    "            padding: 10px 16px; margin: 16px 0; border-radius: 4px; font-size: 14px; }\n"
    "    .badge { display:inline-block; background:#3498db; color:#fff;"
    "             padding:2px 8px; border-radius:10px; font-size:12px; margin:2px; }\n"
    "    table { border-collapse: collapse; width: 100%; background: #fff;"
    "            box-shadow: 0 1px 4px rgba(0,0,0,.08); border-radius: 6px;"
    "            overflow: hidden; margin-top: 16px; }\n"
    "    th    { background: #2c3e50; color: #fff; padding: 10px 8px;"
    "            font-size: 12px; text-align: center; }\n"
    "    td    { padding: 8px 8px; font-size: 12px; border-bottom: 1px solid #eee; }\n"
    "    tr:hover td { background: #f0f7ff; }\n"
    "    .footer { font-size: 11px; color: #999; margin-top: 20px; text-align: right; }\n"
    "  </style>\n"
    "</head>\n"
    "<body>\n"
    "  <h1>BioMate Scaffold Hopping Report</h1>\n"
    "  <div class='meta'>\n"
    "    <b>Run ID:</b> " + meta_id + " &nbsp;|&nbsp;\n"
    "    <b>Reference SMILES:</b> <code>CC(=O)Nc1ccc(O)cc1</code> (acetaminophen) &nbsp;|&nbsp;\n"
    "    <b>Candidates shown:</b> " + str(n_cands) + " &nbsp;|&nbsp;\n"
    "    <b>Lipinski filter:</b> " + lip_label + " &nbsp;|&nbsp;\n"
    "    <b>Mode:</b> <span class='badge'>MOCK</span>\n"
    "    <br><b>Generated:</b> " + generated + "\n"
    "  </div>\n"
    "  <h2 style='font-size:16px;margin-top:24px'>Top Scaffold Hop Candidates</h2>\n"
    "  <p style='font-size:13px;color:#555'>\n"
    "    Rank score = 0.4 x QED + 0.3 x norm_frequency + 0.3 x (1 - norm_SA_score).\n"
    "    Lipinski pass: MW &le; 500, HBA &le; 10, HBD &le; 5, logP &le; 5.\n"
    "  </p>\n"
    "  <table>\n"
    "    <thead>\n"
    "      <tr>\n"
    "        <th>Rank</th><th>Hop SMILES</th><th>Core Scaffold</th>\n"
    "        <th>MMP Freq</th><th>QED</th><th>SA Score</th>\n"
    "        <th>MW (Da)</th><th>logP</th><th>Lipinski</th><th>Rank Score</th>\n"
    "      </tr>\n"
    "    </thead>\n"
    "    <tbody>\n"
    + rows_html +
    "    </tbody>\n"
    "  </table>\n"
    "  <div class='footer'>\n"
    "    Generated by BioMate scaffold_hopping pipeline &bull;\n"
    "    RECAP (Lewell 1998) + mmpdb (Dalke 2018) + RDKit &bull;\n"
    "    Mock mode - no real chemistry tools were executed\n"
    "  </div>\n"
    "</body>\n"
    "</html>\n"
)
with open(f"{meta_id}_scaffold_report.html", "w") as hf:
    hf.write(html)

# Ranking summary JSON
ranking_summary = {
    "meta_id":              meta_id,
    "total_candidates":     len(candidates),
    "lipinski_filter_applied": lip_filter,
    "max_candidates":       max_cands,
    "top_candidate": {
        "smiles":      candidates[0]["hop_smiles"],
        "scaffold":    candidates[0]["scaffold_smiles"],
        "qed":         candidates[0]["qed_score"],
        "sa_score":    candidates[0]["sa_score"],
        "rank_score":  candidates[0]["rank_score"],
    },
    "qed_range":   [min(c["qed_score"] for c in candidates),
                    max(c["qed_score"] for c in candidates)],
    "sa_score_range": [min(c["sa_score"] for c in candidates),
                       max(c["sa_score"] for c in candidates)],
    "all_lipinski_pass": all(c["lipinski_pass"] for c in candidates),
    "tool":      "RDKit (QED + SA score, mock)",
    "timestamp": datetime.utcnow().isoformat() + "Z",
    "mock_mode": True,
}

with open(f"{meta_id}_ranking_summary.json", "w") as jf:
    json.dump(ranking_summary, jf, indent=2)

print(f"Scaffold hopping mock complete: {len(candidates)} candidates ranked")
print(f"  Top hit: {candidates[0]['hop_smiles']}")
print(f"  Top QED: {candidates[0]['qed_score']:.2f}  SA: {candidates[0]['sa_score']:.2f}")
EOF

    else
        # ---------------------------------------------------------------------------
        # Live: RDKit QED + SA score ranking
        # ---------------------------------------------------------------------------
        python3 << 'PYEOF'
import json
import csv
import sys
from datetime import datetime

try:
    from rdkit import Chem
    from rdkit.Chem import Descriptors, QED, rdMolDescriptors
    from rdkit.Contrib.SA_Score import sascorer
    RDKIT_OK = True
except ImportError:
    RDKIT_OK = False
    print("WARNING: RDKit or SA_Score contrib not found.", file=sys.stderr)

meta_id      = "test_actives"
frags_file   = "test_actives_recap_fragments.csv"
mmp_file     = "test_actives_mmp_pairs.csv"
max_cands    = int("20")
lip_filter   = str("true").lower() in ("true", "1", "yes")

# ---- 1. Collect candidate SMILES from MMP pairs ----
candidates_raw = {}
with open(mmp_file, newline="") as csvf:
    reader = csv.DictReader(csvf)
    for row in reader:
        for smi_key in ("match_smiles", "query_smiles"):
            smi = row.get(smi_key, "").strip()
            if smi:
                candidates_raw[smi] = candidates_raw.get(smi, 0) + 1

# Also add RECAP scaffold smiles as hopping candidates
with open(frags_file, newline="") as csvf:
    reader = csv.DictReader(csvf)
    for row in reader:
        sc = row.get("scaffold_smiles", "").strip()
        if sc:
            candidates_raw[sc] = candidates_raw.get(sc, 0) + int(row.get("fragment_frequency", 1))

# ---- 2. Score each candidate ----
scored = []
for smi, freq in candidates_raw.items():
    mol = Chem.MolFromSmiles(smi) if RDKIT_OK else None
    if mol is None:
        continue

    mw    = round(Descriptors.MolWt(mol), 3)
    logp  = round(Descriptors.MolLogP(mol), 3)
    hba   = rdMolDescriptors.CalcNumHBA(mol)
    hbd   = rdMolDescriptors.CalcNumHBD(mol)
    qed   = round(QED.qed(mol), 4)
    try:
        sa  = round(sascorer.calculateScore(mol), 3)
    except Exception:
        sa  = 5.0

    lip   = (mw <= 500 and hba <= 10 and hbd <= 5 and logp <= 5)

    if lip_filter and not lip:
        continue

    scored.append({
        "smiles":          smi,
        "mmp_frequency":   freq,
        "qed_score":       qed,
        "sa_score":        sa,
        "mw_da":           mw,
        "logP":            logp,
        "hba":             hba,
        "hbd":             hbd,
        "lipinski_pass":   lip,
    })

# ---- 3. Normalise + composite rank ----
if scored:
    max_freq = max(c["mmp_frequency"] for c in scored) or 1
    max_sa   = max(c["sa_score"]      for c in scored) or 1
    for c in scored:
        norm_freq = c["mmp_frequency"] / max_freq
        norm_sa   = c["sa_score"] / max_sa
        c["rank_score"] = round(0.4 * c["qed_score"] + 0.3 * norm_freq + 0.3 * (1 - norm_sa), 4)

scored.sort(key=lambda x: -x["rank_score"])
scored = scored[:max_cands]

for i, c in enumerate(scored, 1):
    c["rank"]       = i
    c["scaffold_id"] = f"SCAF_{i:03d}"
    c["hop_smiles"]  = c.pop("smiles")

with open(f"{meta_id}_scaffold_candidates.csv", "w", newline="") as csvf:
    if scored:
        writer = csv.DictWriter(csvf, fieldnames=list(scored[0].keys()))
        writer.writeheader()
        writer.writerows(scored)
    else:
        csvf.write("rank,scaffold_id,hop_smiles,qed_score,sa_score\n")

# Minimal HTML report (build rows without nested f-strings)
table_rows = ""
for c in scored:
    table_rows += (
        "<tr><td>" + str(c["rank"]) + "</td>"
        "<td><code>" + str(c["hop_smiles"]) + "</code></td>"
        "<td>" + str(c["qed_score"]) + "</td>"
        "<td>" + str(c["sa_score"]) + "</td>"
        "<td>" + str(c["mw_da"]) + "</td>"
        "<td>" + str(c["logP"]) + "</td>"
        "<td>" + str(c["rank_score"]) + "</td></tr>"
    )
n_cands    = len(scored)
lip_label  = "ON" if lip_filter else "OFF"
generated  = datetime.utcnow().isoformat() + "Z"
html = (
    "<!DOCTYPE html>\n<html><head><meta charset='UTF-8'>\n"
    "<title>BioMate Scaffold Hopping — " + meta_id + "</title></head>\n"
    "<body><h1>Scaffold Hopping Candidates — " + meta_id + "</h1>\n"
    "<p>" + str(n_cands) + " candidates (Lipinski filter: " + lip_label + ")</p>\n"
    "<table border='1' cellpadding='4'>\n"
    "<tr><th>Rank</th><th>SMILES</th><th>QED</th><th>SA</th>"
    "<th>MW</th><th>logP</th><th>Score</th></tr>\n"
    + table_rows +
    "\n</table>\n"
    "<p><small>Generated " + generated + " | BioMate scaffold_hopping pipeline</small></p>\n"
    "</body></html>"
)
with open(f"{meta_id}_scaffold_report.html", "w") as hf:
    hf.write(html)

ranking_summary = {
    "meta_id":               meta_id,
    "total_candidates":      len(scored),
    "lipinski_filter_applied": lip_filter,
    "top_candidate":         scored[0] if scored else {},
    "timestamp":             datetime.utcnow().isoformat() + "Z",
    "mock_mode":             False,
}
with open(f"{meta_id}_ranking_summary.json", "w") as jf:
    json.dump(ranking_summary, jf, indent=2)

print(f"Scaffold hopping live: {len(scored)} candidates ranked")
PYEOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "SCAFFOLD_HOPPING:SCAFFOLD_HOPPING_CANDIDATES":
        rdkit: $(python3 -c "from rdkit import __version__; print(__version__)" 2>/dev/null || echo "N/A")
        python: $(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "false"
    END_VERSIONS
