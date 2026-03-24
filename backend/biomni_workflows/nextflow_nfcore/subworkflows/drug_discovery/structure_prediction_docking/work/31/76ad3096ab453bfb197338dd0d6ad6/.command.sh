#!/bin/bash -ue
if [ "true" = "true" ]; then
        python3 << 'EOF'
import json, math, random
from datetime import datetime

random.seed(42)
meta_id = "EGFR_kinase"

# Synthetic alpha-helix PDB (same geometry as AF3 mock for pipeline compatibility)
aa_one = list("ACDEFGHIKLMNPQRSTVWY" * 5)[:100]
aa_three = {'A':'ALA','C':'CYS','D':'ASP','E':'GLU','F':'PHE','G':'GLY','H':'HIS',
            'I':'ILE','K':'LYS','L':'LEU','M':'MET','N':'ASN','P':'PRO','Q':'GLN',
            'R':'ARG','S':'SER','T':'THR','V':'VAL','W':'TRP','Y':'TYR'}

lines = [
    "REMARK  BioMate mock Chai-1 structure — synthetic alpha-helix",
    f"REMARK  Target: EGFR kinase domain (mock)",
    f"REMARK  Generated: {datetime.utcnow().isoformat()}Z",
    "REMARK  aggregate_score=0.88  ptm=0.86",
]
atom_idx = 1
for i, aa in enumerate(aa_one, 1):
    angle = math.radians(i * 100.0)
    x_ca = 2.3 * math.cos(angle)
    y_ca = 2.3 * math.sin(angle)
    z_ca = i * 1.5
    res3 = aa_three.get(aa, 'ALA')
    bfac = round(random.uniform(10.0, 28.0), 2)
    lines.append(f"ATOM  {atom_idx:5d}  CA  {res3:3s} A{i:4d}    {x_ca:8.3f}{y_ca:8.3f}{z_ca:8.3f}  1.00 {bfac:5.2f}           C")
    atom_idx += 1
lines.append("END")

with open(f"{meta_id}_structure.pdb", "w") as f:
    f.write("\n".join(lines) + "\n")

cif_lines = [f"data_{meta_id}", f"_entry.id {meta_id}",
             "_struct.title 'BioMate mock Chai-1 structure'",
             "_ma_qa_metric_global.metric_value 0.88",
             "_ma_qa_metric_global.type aggregate_score"]
with open(f"{meta_id}_structure.cif", "w") as f:
    f.write("\n".join(cif_lines) + "\n")

N = 100
pae = [[round(min(abs(i-j)*0.25 + random.uniform(0,0.5), 15.0), 3) for j in range(N)] for i in range(N)]
with open(f"{meta_id}_pae.json", "w") as f:
    json.dump({"pae": pae, "max_predicted_aligned_error": 31.75, "residue_count": N}, f)

scores = {
    "aggregate_score":    0.88,
    "ptm":                0.86,
    "iptm":               0.84,
    "per_sample_scores":  [round(0.88 - i*0.03 + random.uniform(-0.01,0.01), 4) for i in range(int("5"))],
    "num_trunk_recycles": int("3"),
    "num_diffn_samples":  int("5"),
    "model_id":           f"{meta_id}_chai1_s0",
    "mean_plddt":         86.2,
    "timestamp":          datetime.utcnow().isoformat() + "Z",
    "tool":               "chai1",
    "mock_mode":          True,
}
with open(f"{meta_id}_chai1_scores.json", "w") as f:
    json.dump(scores, f, indent=2)

print(f"Chai-1 mock complete: {meta_id}_structure.pdb (100 residues)")
print(f"  aggregate_score={scores['aggregate_score']}  ptm={scores['ptm']}")
EOF

    else
        # Live: Chai-1 via chai-lab Python package
        # pip install chai-lab  (Apache 2.0)
        python3 << 'PYEOF'
from pathlib import Path
import json
from datetime import datetime

meta_id  = "EGFR_kinase"
fasta_in = "mock_EGFR_kinase.fasta"
recycles = int("3")
samples  = int("5")

from chai_lab.chai1 import run_inference

candidates = run_inference(
    fasta_file    = Path(fasta_in),
    output_dir    = Path("chai1_out"),
    num_trunk_recycles      = recycles,
    num_diffn_timesteps     = 200,
    seed                    = 42,
    device                  = "cuda",
    use_esm_embeddings      = True,
)

# Normalise to BioMate convention
import shutil, glob

for f in glob.glob("chai1_out/**/*.cif", recursive=True):
    shutil.copy(f, f"{meta_id}_structure.cif")
    break

if not Path(f"{meta_id}_structure.pdb").exists():
    with open(f"{meta_id}_structure.pdb", "w") as fh:
        fh.write(f"REMARK converted from {meta_id}_structure.cif\nEND\n")

# PAE + scores from candidates
agg_scores = [float(c.aggregate_score) for c in candidates]
best = candidates[0]

pae_data = {"pae": best.pae.tolist() if hasattr(best, "pae") else [],
            "max_predicted_aligned_error": 31.75}
with open(f"{meta_id}_pae.json", "w") as fh:
    json.dump(pae_data, fh)

scores = {
    "aggregate_score":   float(best.aggregate_score),
    "ptm":               float(best.ptm),
    "iptm":              float(best.iptm),
    "per_sample_scores": agg_scores,
    "num_trunk_recycles": recycles,
    "num_diffn_samples":  len(candidates),
    "model_id":          f"{meta_id}_chai1_s0",
    "timestamp":         datetime.utcnow().isoformat() + "Z",
    "tool":              "chai1",
    "mock_mode":         False,
}
with open(f"{meta_id}_chai1_scores.json", "w") as fh:
    json.dump(scores, fh, indent=2)

print(f"Chai-1 live: aggregate_score={scores['aggregate_score']:.4f}")
PYEOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "STRUCTURE_PREDICTION_DOCKING:CHAI1_STRUCTURE_PREDICTION":
        chai_lab: "0.5.0"
        python: $(python3 --version 2>&1 | cut -d' ' -f2)
        mock_mode: "true"
    END_VERSIONS
