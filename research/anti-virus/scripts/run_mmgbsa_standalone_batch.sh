#!/usr/bin/env bash
# Submit MM-GBSA alone to biomate-nextflow-queue using completed MD artifacts on S3.
set -euo pipefail

OUTDIR="${1:-s3://biomate-nextflow-work/nextflow/outputs/parallel-inhibitor-20260513T032000Z/d64daac1}"
JOB_NAME="${2:-MM_GBSA_inh01_standalone}"
QUEUE="${3:-biomate-nextflow-queue}"
JD="nf-399683337364-dkr-ecr-us-west-2-amazonaws-com-biomate-ambertools-gromacs-nf-latest:3"

read -r -d '' SCRIPT <<'EOS' || true
set -euo pipefail
export PATH="/opt/aws-cli/bin:/opt/conda/bin:${PATH}"
AWS="${AWS:-/opt/aws-cli/bin/aws}"
OUTDIR="__OUTDIR__"
mkdir -p /tmp/mmgbsa && cd /tmp/mmgbsa
"$AWS" s3 cp "${OUTDIR}/md/trajectory.xtc" trajectory.xtc
"$AWS" s3 cp "${OUTDIR}/md/production.gro" production.gro
"$AWS" s3 cp "${OUTDIR}/prep/complex.top" complex.top
"$AWS" s3 cp "${OUTDIR}/analysis/analysis_summary.json" analysis_summary.json

cat > rerun.mdp <<'MDP'
integrator = md
nsteps     = 0
continuation = yes
MDP
gmx grompp -f rerun.mdp -c production.gro -p complex.top -o rerun.tpr -maxwarn 10

printf "q\n" | gmx make_ndx -f production.gro -o index.ndx
# GROMACS lists groups from 0; gmx_MMPBSA -cg uses 1-based index numbers.
python3 <<'PY'
groups = []
for line in open('index.ndx'):
    s = line.strip()
    if s.startswith('[') and s.endswith(']'):
        groups.append(s[1:-1].strip())
# gmx_MMPBSA -cg uses make_ndx menu numbers (0 = System, 1 = Protein, …).
prot = groups.index('Protein')
lig = groups.index('LIG')
open('groups.env', 'w').write(f'export REC_G={prot}\nexport LIG_G={lig}\n')
print(f'Using receptor group {prot} (Protein) and ligand group {lig} (LIG)')
PY
source groups.env

cat > mmgbsa.in <<'IN'
&general
   startframe=10, endframe=100, interval=5,
   verbose=2,
/
&gb
   igb=2, saltcon=0.15,
/
&decomp
   idecomp=2, dec_verbose=3,
   print_res="within 6",
/
IN

gmx_MMPBSA -O -i mmgbsa.in -cs rerun.tpr -ci index.ndx -cg "$REC_G" "$LIG_G" -ct trajectory.xtc -cp complex.top \
  -o FINAL_RESULTS_MMPBSA.dat -eo FINAL_RESULTS_MMPBSA.csv -nogui \
  2>&1 | tee mmgbsa_run.log || true

python3 <<'PY'
import json, csv, os, re, sys, math
from datetime import datetime
dg_bind = dg_err = None
if os.path.exists('FINAL_RESULTS_MMPBSA.dat'):
    for line in open('FINAL_RESULTS_MMPBSA.dat'):
        m = re.search(r'(?:DELTA TOTAL|ΔTOTAL)\s+([-\d.]+)\s+[+/-]\s+([\d.]+)', line)
        if m:
            dg_bind, dg_err = float(m.group(1)), float(m.group(2))
            break
rows = []
if os.path.exists('FINAL_RESULTS_MMPBSA.csv'):
    rows = list(csv.DictReader(open('FINAL_RESULTS_MMPBSA.csv')))
with open('mmgbsa_results.csv', 'w', newline='') as f:
    w = csv.writer(f)
    if rows:
        w.writerow(rows[0].keys())
        for r in rows:
            w.writerow(r.values())
    else:
        w.writerow(['residue','chain','dG_total','dG_vdw','dG_elec','dG_gb','dG_total+sd'])
traj = {}
try:
    traj = json.load(open('analysis_summary.json'))
except Exception:
    pass
ki_nm = round(10**(dg_bind / 1.364) * 1e9, 2) if dg_bind is not None else None
summary = {
    'delta_g_bind_kcal_mol': dg_bind,
    'standard_error_kcal_mol': dg_err,
    'ki_estimate_nM': ki_nm,
    'tool': 'gmx_mmpbsa',
    'gb_model': 'igb2',
    'trajectory_analysis': traj,
    'interpretation': (
        'strong binder' if dg_bind and dg_bind < -10 else
        'moderate binder' if dg_bind and dg_bind < -7 else
        'weak binder' if dg_bind and dg_bind < -5 else
        'unfavorable' if dg_bind else 'calculation failed'
    ),
    'timestamp': datetime.utcnow().isoformat() + 'Z',
}
json.dump(summary, open('binding_summary.json','w'), indent=2)
print(f'MM-GBSA complete: dGbind = {dg_bind} kcal/mol')
PY

"$AWS" s3 sync . "${OUTDIR}/mmgbsa/" --exclude "*" --include "binding_summary.json" --include "mmgbsa_results.csv" --include "mmgbsa_run.log" --include "FINAL_RESULTS_MMPBSA.*"
EOS

SCRIPT="${SCRIPT//__OUTDIR__/$OUTDIR}"
SCRIPT_B64=$(printf '%s' "$SCRIPT" | base64 -w0)

JOB_ID=$(aws batch submit-job --region us-west-2 \
  --job-name "$JOB_NAME" \
  --job-queue "$QUEUE" \
  --job-definition "$JD" \
  --container-overrides "$(python3 -c "
import json
print(json.dumps({
  'vcpus': 8,
  'memory': 32000,
  'command': ['bash','-lc', __import__('base64').b64decode('$SCRIPT_B64').decode()],
}))
")" \
  --query 'jobId' --output text)

echo "Submitted $JOB_NAME -> $JOB_ID on $QUEUE"
echo "Output -> ${OUTDIR}/mmgbsa/"
