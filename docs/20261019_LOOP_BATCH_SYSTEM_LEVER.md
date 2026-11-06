# Closed-loop system lever — automate the driver + route physics through Batch (design + first step)

**Date:** 2026-10-19 · Internal. The system lever from the cyclic-drug status: make the closed loop run
end-to-end at scale instead of manual per-candidate EC2 runs. **Audit-first** (the gap is usually wiring, not
the primitive). This note = the full plan + what was wired as the first concrete step. **No at-scale Batch
sweep and no real Batch spend here** — the first step is the dispatch seam + a dry-run validation only.

## 1. Audit — what already exists (do not rebuild)
- **Driver / loop:** `cyclic_llm/loop.py::optimize()` already runs `propose → score() → select(gate+Pareto) →
  revise → repeat`, deterministic. `revise` is a labeled symbolic stand-in for the LLM/RL policy (by design).
- **Reward / verifier:** `cyclic_llm/score.py::score(helm, target, tier=)` — cheap tier (rule + FTO +
  developability) built; `tier='full'` calls `physics_dispatch.physics_for()`.
- **Physics tier (the gap):** `physics_dispatch.physics_for()` only **READS** pre-computed physics result files
  (the `REG` registry). Physics is produced out-of-band by the standalone **EC2** launcher
  `launch_cofold_v2.sh` — it **bypasses Batch**. Nothing dispatches a cofold/MM-GBSA job for a *new* candidate.
- **Batch primitive (already there, us-west-2):** queue **`biomate-gpu-spot-queue`** (ENABLED) + Boltz cofold
  job-def **`boltz-snat2-direct`** (`biomate/ai-tools/boltz:latest`, GPU=1, 8 vCPU, 30 GB) + the Nextflow Boltz
  job-def; **`biomate-ambertools-gpu`** / `biomate-gromacs-*-gpu` for the MM-GBSA side. `nextflow_executor.py`
  already submits Nextflow→Batch on these queues.
- **Conclusion:** the GPU-spot Boltz-on-Batch primitive exists; the missing piece is the **dispatch seam** from
  `score()`'s physics tier to those job-defs, plus result retrieval. Pure wiring.

## 2. Full plan (REINVENT/Saturn-style, verifier = reward)
1. **Dispatch seam** (this step): `score(tier='full')` → when a candidate's physics is absent →
   `physics_batch.dispatch_cofold(spec-derived input)` → the existing Boltz GPU-spot job-def → S3 →
   `fetch_result()` → MM-GBSA (AmberTools/GROMACS job-def, or the local metal-aware runner) →
   `physics_dispatch` reads the fresh result. Spec-derived input means metal is just `cofactors`
   (avb6 → `[MN,MN,MN]` automatically; generic for every target).
2. **Automate the driver:** replace `loop.revise` (symbolic stand-in) with a sample-efficient search policy
   (REINVENT4 / Saturn Augmented-Memory, or the LLM-in-the-loop revise) whose **reward is `score()`** —
   multi-objective Pareto (binding × selectivity × developability × FTO × geometry), never generate-then-filter.
3. **Scale through Batch:** the driver fans out candidate physics as spot-GPU Batch jobs (cofold) + CPU jobs
   (MM-GBSA) through the seam, with the control-anchoring gate (A2) enforced every batch; billing/exec already
   flow through the Batch path (`biomate-batch-billing` Lambda, `nextflow_executor`).
4. **Governance:** verifiable stages + provenance (Mozi pattern); honest relative/feasibility labels; the loop
   never advances an ungated candidate; outputs are CRO-ready sheets only after human review.

## 3. First concrete step — what was wired (this commit)
`cyclic_llm/physics_batch.py` — the dispatch seam:
- `dispatch_cofold(target, candidates, dry_run=True)` reuses `target_spec.build_cofold_input` (spec-derived),
  constructs the exact AWS Batch `submit_job` payload against the **real** `biomate-gpu-spot-queue` +
  `boltz-snat2-direct`, and **validates the queue + job-def exist** (read-only `describe_*`).
- **`dry_run=True` by default — spends nothing.** Verified dry-run output: `queue_exists=true`,
  `jobdef_active=true` (image `boltz:latest`), spec-derived `ligands=[MN,MN,MN]` flow through, full payload
  emitted, **no job submitted**.
- `fetch_result(run_id)` — the S3 retrieve half.
- One container-side artifact is still required for a *real* job: `/opt/cofold/json_to_boltz_yaml.py` in the
  Boltz image (the build_cofold_input-JSON → Boltz-YAML converter — the same logic the EC2 launcher embeds).

## 4. Review note for the ONE real validation job (go-ahead gated — NOT run here)
To validate end-to-end, submit a **single** spot-GPU cofold job: `dispatch_cofold('avb6', [one_backbone],
dry_run=False)`. Cost: one `biomate-gpu-spot-queue` GPU job (~a few min of spot GPU, cents), self-terminating,
output to `s3://biomate-nextflow-work/cyclic_peptide/batch_cofold/<run>/complexes/`. **Preconditions:** add
`json_to_boltz_yaml.py` to the Boltz image (or inline the converter in the command). **Do not run without
explicit go-ahead** (guardrail: no unreviewed Batch spend). Predicted: one metal-aware complex CIF in S3,
retrievable by `fetch_result` — proving the seam end-to-end — then feed it to the MM-GBSA job-def.

## 4b. Executed (2026-10-19, go-ahead given)
- **Container artifact built:** `cyclic_llm/json_to_boltz_yaml.py` (build_cofold_input JSON → Boltz-2 YAML,
  receptor chains + cofactor CCD ligands + cyclic peptide; validated locally on avb6 = 3 proteins + 3 MN).
  Pulled from S3 by the job — no image rebuild.
- **ONE validation cofold Batch job submitted** (`physics_batch.dispatch_cofold('avb6', [FRGDLAFPK], dry_run=False)`):
  job id **`68a28fa6-68f6-40d7-91cf-3bec8829af40`**, queue **`biomate-gpu-spot-queue`**, job-def
  `boltz-snat2-direct`, spec-derived ligands `[MN,MN,MN]`. Inputs uploaded; status reached **RUNNABLE** on the
  spot GPU queue (awaiting spot capacity). Output lands at
  `s3://biomate-nextflow-work/cyclic_peptide/batch_cofold/avb6-val-20261019/complexes/`. One job only — no sweep.
- **Driver first slice built + dry-run validated:** `cyclic_llm/loop_batch.py::run_round` — propose →
  (physics-miss → Batch dispatch) → `score(tier='full')` reward → rank → revise. Dry-run: proposed 3
  spec-driven candidates, dispatched their physics through the Batch seam (dry-run), scored + ranked + revised.

## 5. Next steps (after go-ahead)
(a) add the container converter + run the one validation job; (b) wire `physics_dispatch.physics_for` to call
the seam on a miss (behind an `enable_dispatch` flag); (c) add the MM-GBSA Batch job-def call (AmberTools/
GROMACS) with the metal model fix from `20261019_AVB6_METAL_MMGBSA_METHODDEV.md`; (d) swap `loop.revise` for the
REINVENT/Saturn policy with `score()` as reward; (e) only then a reviewed, budgeted at-scale sweep.
