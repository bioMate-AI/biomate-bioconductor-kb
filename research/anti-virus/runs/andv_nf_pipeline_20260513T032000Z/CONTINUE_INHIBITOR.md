# Continue inhibitor track (after step 4)

**Manifest:** `pipeline_manifest.json` — last good steps: pocket → pharmacophore → ADMET → docking (all **succeeded**).

**GROMACS (step 5):** Latest `05_gromacs_mmgbsa/status.json` shows **`failed`** for run `b35b0e75-…` — tleap built a **huge** solvated system (see `log_tail` volume / residue counts). Full GP assembly MD is unlikely to fit default Batch limits for a demo.

**Continue options (pick one):**

1. **Re-append with smaller MD budget** (may still fail if receptor is whole tetramer):
   ```bash
   python3 research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py \
     --append-to-run research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z \
     --user-id parallel-inhibitor-20260513T032000Z \
     --pdb-input s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb \
     --through-step 6 \
     --reference-actives-s3 s3://biomate-nextflow-work/inputs/andv_campaign/pipeline_demo_20260509/reference_actives.smi \
     --compound-library-s3 s3://biomate-nextflow-work/inputs/andv_campaign/pipeline_demo_20260509/compound_library.smi \
     --ligand-s3 'CC(=O)Oc1ccccc1C(=O)O' \
     --seed-smiles 'CC(=O)Oc1ccccc1C(=O)O' \
     --gromacs-n-steps 20000 \
     --step-timeout 43200
   ```

2. **Publication path without MD:** freeze story at **docking + ADMET**; cite `ANDV_INHIBITOR_INSILICO_PREPRINT_STACK.md` for optional RBFE / AMBER with **trimmed** receptor.

3. **Trimmed receptor on S3** — replace `--pdb-input` with a pocket-only PDB you upload, then re-run **append** as above.

4. **One-shot pocket receptor + append** (uploads `01_pocket/structure_top_pocket.pdb` to `s3://…/20260514/9P3I_top_pocket_only.pdb`, then steps 5–6):

   ```bash
   chmod +x research/anti-virus/scripts/run_inhibitor_continue_pocket_md.sh
   ./research/anti-virus/scripts/run_inhibitor_continue_pocket_md.sh
   ```

5. **REINVENT4 only (skip GROMACS):** when MD is blocked or failed, append step 6 under `06_reinvent4` without re-running step 5:

   ```bash
   python3 research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py \
     --append-to-run research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z \
     --append-only-keys reinvent4 \
     --through-step 6 \
     --pdb-input s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb \
     --reference-actives-s3 s3://biomate-nextflow-work/inputs/andv_campaign/pipeline_demo_20260509/reference_actives.smi \
     --compound-library-s3 s3://biomate-nextflow-work/inputs/andv_campaign/pipeline_demo_20260509/compound_library.smi \
     --seed-smiles 'CC(=O)Oc1ccccc1C(=O)O' \
     --user-id parallel-inhibitor-20260513T032000Z
   ```

Poll **current** GROMACS id: see `STEPS_5_6_RESUME.md` (`RID=$(jq …)`).

`submit.json` may show a **newer** run than `status.json` if a re-submit occurred; trust **`submit.json`** for the latest submission.
