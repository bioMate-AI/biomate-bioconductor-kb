# Resume steps 5–6 (GROMACS MM-GBSA, REINVENT4)

Steps 1–4 completed in this run directory. A first append attempt for steps 5–6 hit **HTTP 500** on `GET /api/nextflow/status/{run_id}` during a long GROMACS poll (Galaxy blip). The pipeline script now **retries 5xx** on status polls.

## Always poll the **current** GROMACS `run_id` (never hardcode)

Each new `POST /api/nextflow/execute` for GROMACS creates a **new** `run_id`. `05_gromacs_mmgbsa/submit.json` is **overwritten** on every re-submit. The canonical ID to poll is whatever is in that file **now**.

**Wrong pattern (do not do this):** compare `submit.json` to an old UUID copied from a resume note, then “skip poll” if they differ. A different ID usually means a **newer** submission, and that is exactly the job you need to poll.

**Right pattern:**

```bash
cd /home/yzhang/biomate   # repo root
RID=$(jq -r '.run_id' research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/05_gromacs_mmgbsa/submit.json)
echo "Polling run_id=$RID"
KEY=$(grep bootstrap_admin_api_key backend/config/galaxy.yml | awk '{print $2}')
curl -s -H "X-API-Key: ${GALAXY_API_KEY:-$KEY}" \
  "http://127.0.0.1:8081/api/nextflow/status/${RID}" | jq .status,.log_tail
```

Or read `05_gromacs_mmgbsa/status.json` after the driver finishes a poll cycle — it should reflect the same `run_id` as `submit.json` for that attempt.

## If you need the S3 outdir for the **current** attempt

```bash
jq -r '.outputs.outdir // empty' research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/05_gromacs_mmgbsa/submit.json
```

(Historical runs used prefixes like `…/c6fd7029/`; **yours may differ** after a new submit.)

## Re-append steps 5–6 (manifest still has only 4 keys until both succeed)

If the **current** GROMACS job failed or you need a fresh REINVENT after GROMACS completes:

```bash
python3 research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py \
  --api-url http://127.0.0.1:8081 \
  --append-to-run research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z \
  --user-id parallel-inhibitor-20260513T032000Z \
  --pdb-input s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb \
  --through-step 6 \
  --reference-actives-s3 s3://biomate-nextflow-work/inputs/andv_campaign/pipeline_demo_20260509/reference_actives.smi \
  --compound-library-s3 s3://biomate-nextflow-work/inputs/andv_campaign/pipeline_demo_20260509/compound_library.smi \
  --ligand-s3 'CC(=O)Oc1ccccc1C(=O)O' \
  --seed-smiles 'CC(=O)Oc1ccccc1C(=O)O' \
  --gromacs-n-steps 80000 \
  --step-timeout 43200
```

`--ligand-s3` may be a **SMILES string** (best Vina pose ligand from step 4) or an `s3://` path to `.sdf`/`.mol2`.
