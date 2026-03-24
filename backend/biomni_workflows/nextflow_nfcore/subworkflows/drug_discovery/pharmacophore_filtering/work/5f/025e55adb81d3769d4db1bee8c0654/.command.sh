#!/bin/bash -ue
python3 << 'EOF'
import json
from datetime import datetime

model  = json.load(open("pharmacophore_model.json"))
scores = json.load(open("screened_scores.json"))

# Extract passing compounds and write filtered SMILES
passed = [r for r in scores["results"] if r["pass"]]

with open("filtered_compounds.smi", "w") as f:
    for r in passed:
        f.write(f"{r['smiles']}  {r['compound_id']}\n")

# Copy inputs through for publication (guard against same-file error when
# Nextflow stages inputs under their original names as symlinks)
import shutil
try:
    shutil.copy("pharmacophore_model.json", "pharmacophore_model.json")
except shutil.SameFileError:
    pass
try:
    shutil.copy("match_report.tsv", "match_report.tsv")
except shutil.SameFileError:
    pass

# Write summary JSON
summary = {
    "pipeline":         "pharmacophore_filtering",
    "mock_mode":        bool("true" == "true"),
    "min_features":     int("3"),
    "n_reference_actives":  model.get("n_references", 0),
    "n_model_features":     model.get("n_features", 0),
    "n_library_screened":   scores["n_screened"],
    "n_passed_filter":      scores["n_passed"],
    "pass_rate_pct":        round(100 * scores["n_passed"] / max(scores["n_screened"], 1), 1),
    "filtered_smiles_file": "filtered_compounds.smi",
    "match_report_file":    "match_report.tsv",
    "pharmacophore_model_file": "pharmacophore_model.json",
    "timestamp":            datetime.utcnow().isoformat() + "Z",
}

with open("summary.json", "w") as f:
    json.dump(summary, f, indent=2)

print(f"Pharmacophore report written:")
print(f"  Screened:     {summary['n_library_screened']} compounds")
print(f"  Passed:       {summary['n_passed_filter']} ({summary['pass_rate_pct']}%)")
print(f"  Min features: {summary['min_features']}")
print(f"  Model features: {summary['n_model_features']}")
for r in passed:
    print(f"  -> PASS: {r['compound_id']}  {r['smiles']}  matched={r['features_matched']}")
EOF

    cat <<-END_VERSIONS > versions.yml
    "PHARMACOPHORE_FILTERING:PHARMACOPHORE_REPORT":
        python: $(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "true"
    END_VERSIONS
