# First real closed-loop round — review note before spend

**Date:** 2026-10-19 · **Driver:** `research/guangzhou_all_atom/cyclic_llm/loop_batch.py::run_round`
**Target:** αvβ6 (RGD/MIDAS, Mn²⁺ MIDAS cofactor) · **Round id:** `avb6-r1-20261019`
**Gate:** user green-lit the first real round ("all, in parallel", 2026-10-19). This note satisfies
CLAUDE.md "Review Code Before Testing — No Speculative Deploys".

## What is being dispatched

One bounded round, **3 candidates**, from the spec-driven proposer (`propose.propose`, αvβ6 spec):

| id | HELM | backbone cofolded |
|----|------|-------------------|
| C000 | `cyclo(W-R-G-D-L-G-F-[dP]-[NMeK])` | WRGDLGFPK |
| C001 | `cyclo(Y-R-G-D-L-G-[2Nal]-[dP]-[NMeK])` | YRGDLGFPK |
| C002 | `cyclo(Y-R-G-D-L-G-F-[dP]-[NMeK])` | YRGDLGFPK |

**3 AWS Batch cofold jobs**, one per candidate, distinct S3 prefix each
(`s3://biomate-nextflow-work/cyclic_peptide/batch_cofold/avb6-r1-20261019-C00N/`).

- **Queue:** `biomate-gpu-spot-queue` (ENABLED, **spot only** — verified live, read-only).
- **Job-def:** `boltz-snat2-direct` (ACTIVE; image `…/biomate/ai-tools/boltz:latest`, GPU=1 — verified live).
- **Input:** spec-derived (`target_spec.build_cofold_input`): receptor chains + **3× MN** CCD cofactors +
  one cyclic peptide chain. Receptor is prepped (no cold-start). Converter `json_to_boltz_yaml.py` shipped
  to S3 with the input — no image rebuild.

## Cost + wall-clock estimate

- 3 jobs × 1 GPU (A10G/T4-class spot) × ~15–40 min cofold (receptor + 3 ions + 9-mer, `--use_msa_server`).
- Spot g5.xlarge ≈ $0.35–0.45/hr → **~$0.10–0.30/job → ≈ $0.3–0.9 total.** Bounded, negligible.
- Jobs go **RUNNABLE** and fire when spot GPU capacity returns; no capacity = they wait = correct, no spend.
- **MM-GBSA is NOT in this submit.** It is the next stage, gated on the cofold `complex.cif` outputs existing.

## What the round should produce (predicted outcome)

1. Each job writes `complex.cif` to its prefix on success.
2. `physics_batch.fetch_result(run_id)` → `ready=True` once a `.cif` lands.
3. `loop_grade_bridge.record_round(..., run_kind="cofold", campaign="avb6-r1-20261019")` grades each via the
   `cyclic_peptide_cofold` CONTRACT: `complex.cif` present → **tier=pass, reward=1.00**; absent → lower tier.
   Rewards persist in `graded_run_store` and read back by `get_reward(run_id)`.
4. Pending (not-yet-finished) candidates are skipped by `record_round` and picked up in a later poll — no
   fabricated scores. The MM-GBSA ΔG tier (content-checked `mmgbsa_result.json`) is a **later** job, not now.

**Honest status this writes:** cofold dispatched → awaiting spot capacity → graded only when `.cif` lands.
No score is synthesized before the real output exists.

## Not in scope (deliberately held)

- At-scale fan-out (this is one job per candidate, 3 total).
- MM-GBSA Batch jobs (next stage, after cofold completes).
- REINVENT4/Saturn policy swap for `loop.revise` (still the symbolic stand-in).
- αvβ6 affinity *ranking* — remains inadmissible under single-point MM-GBSA; FEP/TI is the validated path
  (`docs/20261019_AVB6_CADA_AND_FEP_SETUP.md`). This round exercises the loop/reward plumbing on real
  physics outputs; it does not claim an admissible ΔG ranking.
