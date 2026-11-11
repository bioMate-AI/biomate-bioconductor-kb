# 2026-11-11 — Models panel: get off NVIDIA, run on our own

## What the founder saw
In Models → 模型库 ("Run a model"), four models (Boltz-2, OpenFold2, Evo2 7B/40B)
were all labelled source **"self-host"**, yet the Boltz-2 row's failure linked to
`docs.nvidia.com` with a CUDA error. They are NVIDIA BioNeMo models; "self-host"
was false.

## Why (audited)
`bionemo_client` picks its backend by auto-detect: **self_host** if
`BIONEMO_SELF_HOST_URL` is set → else **hosted_api** (NVIDIA) if `NVIDIA_API_KEY`
is set → else **stub**. Dev has the key but **no self-host URL**, so every
"Run a model" inference goes to **NVIDIA's hosted API**. The self-host NIM code
is complete (PR #210, runbook `docs/20260904_BIONEMO_SELFHOST_RUNBOOK.md`) but
**no NIM server was ever provisioned**. NVIDIA's hosted Boltz-2 is currently
down (422 `CUDA illegal memory access` for every request, reproduced directly
from dev); OpenFold2 500s; AlphaFold2/ESMFold were already removed as EOL.

Fixed now (commit): the catalog reports the **real** backend
(`self_host` / `hosted_nvidia` / `unconfigured`), localised in the UI — so the
panel stops claiming "self-host" while calling NVIDIA. This is honesty, not the
execution move.

## To actually run on our own — options (founder's call: infra + GPU cost)
| Model(s) | Our own path today | Effort | Cost |
|---|---|---|---|
| **Boltz-2** (structure) | **We already run it on AWS Batch** (cyclic_peptide_cofold, antibody_antigen_complex — `boltz predict` in our ECR image). Route the panel's structure inference to a Batch Boltz-2 run (tracked like training: run record, SSE, polling). | Medium (sync inference → async Batch; a single-sequence/monomer or complex entry) | ~$0.20/run GPU; one test run |
| **Evo2 7B/40B** (genomic) | No own-infra. Self-host NIM (g-series/large GPU) per the runbook, scale-to-zero when idle. | Infra provision | GPU hours while up |
| **OpenFold2** (structure) | No own-infra; NVIDIA hosted is 500ing. Self-host NIM, or drop in favour of Boltz-2. | Infra / remove | — |

### Recommendation
1. **Boltz-2 → our AWS Batch** (reuses what we have; the real "our own"). Needs
   the GPU-sizing decision already open (big complexes OOM on 16 GB g4dn; use a
   ≥24 GB queue or crop the antigen). One ~$0.20 test run validates it.
2. **Evo2 / OpenFold2**: either provision self-host NIMs (standing GPU cost) or,
   until then, mark them honestly as unavailable rather than routing to a broken
   NVIDIA endpoint.

Holding the build for the founder's go-ahead because it spends GPU and (for
Evo2/OpenFold2) touches standing infra.

## VALIDATED on dev (2026-11-11) — Boltz-2 runs on our own Batch

The Models "Run a model" → structure path now folds on **our AWS Batch**, proven end to end:
- `POST /api/models/fold/plan` validates the sequence, stages a Boltz **YAML** (one `protein` chain), returns the `boltz_structure_prediction` launch request.
- `POST /api/workflows/execute` launches a **tracked Batch run** (run record, SSE, Run Manager). Zero NVIDIA.
- Live result (ubiquitin, run 2b212f04): `boltz_input_model_0.cif` — **601 atoms**, confidence_score **0.932**, pTM 0.916, pLDDT **0.936**.

Two bugs the live run caught (unit tests could not):
1. Boltz rejects a `>query` FASTA header (`Invalid record id`) → use the chain-id YAML. Fixed in `model-fold.ts`.
2. The `boltz_structure_prediction` summary globbed only `*.mmcif` but Boltz writes `*.cif` → reported 0 structures on a successful fold. Fixed glob + added loud-fail on no-structure.

Route-order fix: `/api/models/fold/plan` had to be registered before the `/api/models/*` catch-all (else proxied to Galaxy). Regression test added.

Deploy-gate hardening (same session): the ancestry gate now also requires HEAD to contain the deploy ledger's last commit, closing the backend-only-deploy silent-overwrite window (`dev_deploy_ancestry.py` + `sync_to_dev.sh`, 14 tests).
