# Deploy runbook — `alternate_state_generation` workflow

This PR adds the **alternate-state generation** subworkflow + the cryo-em-tools **structure renderer**
to BioMate. It is purely **additive** (8 new files, no edits to existing code). Registration and routing
are automatic once the indexer runs — there is **no migration code or router wiring** to write
(routing is semantic DB search; `structural_biology` is already a canonical domain).

## What this PR contains (code, review-safe)
- `nextflow_nfcore/subworkflows/structural_biology/alternate_state_generation/` — the subworkflow:
  - `main.nf` — two independent blind generators (AFsample2 = AF2 MSA column-masking; Boltz-2 = diffusion
    co-folding, a different model family → genuine consensus) → `SCORE_CONSENSUS` (pore-vestibule
    discriminator) → memorization-aware consensus gate. Fail-loud.
  - `scripts/score_alt_states.py` — consensus driver (validated end-to-end on real SNAT2 + Mhp1).
  - `scripts/pore_discriminator.py`, `scripts/robust_score.py` — validated, renumbering-immune scorer.
  - `Dockerfile` — builds `biomate/ai-tools/pore-discriminator` (miniforge + numpy/scipy).
  - `nextflow.config` — `process_gpu` label.
- `pipeline_composition/modules/cryo_em_tools/`:
  - `scripts/structure_visualization.py` — PyMOL renderer backing `STRUCTURE_OVERVIEW`
    (inward↔outward superposition coloured by Cα displacement; PNG + py3Dmol viewer).
  - `Dockerfile` — makes the previously-stub cryo-em-tools module a real buildable image.

## Pre-merge verification already done (no prod creds needed)
- The `.nf` parses cleanly through the **real indexer** (`scripts/index_all_workflows.py`):
  - name → `Alternate State Generation`; domain → `structural_biology`; steps → 3 processes;
    inputs → `input_fasta, input_msa, ref_pdb, mask_fraction, max_msa_sweep, nstruct`; output → `pdb`.
  - `description` populates (routing keywords: inward/outward, alternating access, transporter, SLC,
    alt-state) — a `/**` header bug that blanked the description was fixed to `/*`.
- Consensus logic validated end-to-end on real data: SNAT2 (AFsample2 −1.51 + del Alamo −1.60 converge,
  consensus accepted) and public Mhp1 (3/3 blind models flip to the outward basin +1.1..+1.4 vs inward
  −4.2). See `docs/20260902_ALTSTATE_USECASE_MHP1.md` (in the main docs tree).

## Human-gated deploy steps (require prod creds / review / dev access — NOT done in this PR)
Do these **after merge**, in order:

1. **Build + push the two containers to prod ECR** (`399683337364.dkr.ecr.us-west-2.amazonaws.com`),
   requires ECR push creds:
   ```bash
   aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com
   # pore-discriminator (scorer)
   docker build -t biomate/ai-tools/pore-discriminator:latest \
     backend/biomni_workflows/nextflow_nfcore/subworkflows/structural_biology/alternate_state_generation/
   docker tag biomate/ai-tools/pore-discriminator:latest 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/pore-discriminator:latest
   docker push 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/pore-discriminator:latest
   # cryo-em-tools renderer
   docker build -t biomate/cryo-em-tools:latest backend/biomni_workflows/pipeline_composition/modules/cryo_em_tools/
   docker tag  biomate/cryo-em-tools:latest 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/cryo-em-tools:latest
   docker push 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/cryo-em-tools:latest
   ```
   AFsample2 (`kyogesh/afsample2:v1.1`, Docker Hub) and Boltz (`biomate/ai-tools/boltz:latest`, already
   in ECR) need no new build.

2. **Sync to dev** — from the **main repo** on `integration/next-phase` (never from a worktree):
   ```bash
   cd /Users/kky/biomate && git checkout integration/next-phase && git pull && scripts/sync_to_dev.sh
   ```
   (Run the PRE_SYNC_CHECKLIST first: `tsc --noEmit`, `vitest run`, and the Python module-load check on
   any changed `backend/lib/galaxy/**/*.py` — none changed here, but keep the habit.)

3. **Register the workflow in the live DB** — on dev, run the indexer **incrementally**
   (⚠️ NEVER `--rebuild` — it destroys the enriched DB; incremental skips existing hashes):
   ```bash
   docker exec biomate-galaxy-dev bash -lc 'cd /galaxy/backend && python scripts/index_all_workflows.py'
   ```

4. **Verify on dev** (both must pass before announcing):
   - Routing: a chat request like *"generate the outward-open alternate state of a transporter"* returns
     the **Alternate State Generation** workflow card.
   - Steps: `GET /api/nextflow/steps?nextflow_path=nextflow_nfcore/subworkflows/structural_biology/alternate_state_generation/main.nf`
     returns the 3 steps (AFsample2 Generate, Boltz2 Generate, Score Consensus).

## Comms gating (do not publish until deploy verified)
The blog/social/video drafts (`docs/20260901_ALTSTATE_WORKFLOW_COMMS.md`) and the two manuscripts are
marked DO-NOT-PUBLISH until: (1) this workflow is live + verified on dev, (2) the 16-transporter
generation-recovery benchmark + reliability calibration are complete, (3) the "first online" claim is
verified by a competitive pass.
