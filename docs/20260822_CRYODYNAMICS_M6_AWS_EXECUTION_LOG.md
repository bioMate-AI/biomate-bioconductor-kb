# CryoDynamics M6 — AWS Execution Log (OM-TPS proof on public data)

**Dates:** 2026-08-19 → 08-22. **Goal:** prove the M6 method — *does anchoring a cryo-EM-style density on the
transition PATH measurably change the generated path/kinetics?* — on **public data** (alanine dipeptide / DESRES
fast-folders via OM-TPS), before ever touching the SNAT2 collaborator data.

**Honesty contract:** every failure below is recorded with its real (log-read) root cause. Scope is stated
explicitly: the **scaffold is proven on GPU**; the **M6 scientific claim is NOT yet proven** (the ON/OFF ablation
is set up and validated component-by-component but the guided runs have not yet produced a clean ON-vs-OFF number).

Companion docs: `20260818_CRYODYNAMICS_M6_DESIGN_AND_ABLATION.md` (design + ablation gate),
`research/m6_density_guidance/` (validated code), `research/m6_density_guidance/deploy/` (all AWS artifacts).

---

## 1. Tooling decision (recap)
Build M6 on **OM-TPS** (`ASK-Berkeley/OM-TPS`, MIT, arXiv:2504.18506) — a zero-shot transition-path layer whose
Onsager–Machlup action is a differentiable additive-scalar `torch.nn.Module` (`actions.py`). The cryo-EM density
log-likelihood is injected as one more additive term → **verified injection point**. Base model = the bundled
MDGen two-for-one diffusion model (alanine/fast-folder weights ship in the repo, `saved_models/`).

## 2. Local science de-risk (all $0, CPU) — DONE
- `research/m6_density_guidance/density_guidance.py` — differentiable Gaussian map sim + cross-correlation nll +
  soft-min-over-frames waypoint term. **Validated against the real `actions.py`**: gradient finite-diff vs autograd
  **1.2e-10**; composes with `TruncatedAction` + `HutchinsonAction` (caught a double-backward integration bug for
  free); path responds; **λ must scale to the OM-action magnitude** (finding).
- `research/m6_density_guidance/deploy/m6_patch.py` — runtime overlay that injects the density block into
  `models/flow_matching.py`'s `om_interpolate` loop, right before `noised_xs.grad = grads_accumulator`, gated by
  env `M6_DENSITY_LAM` (absent → OFF baseline; set → ON). **Validated locally**: inserts at the correct anchor,
  patched file parses. Frame: `noised_xs` is center-zeroed & ÷norm_factor, so the patch uses `noised_xs *
  norm_factor` = center-zeroed physical coords; the density is built in that frame.
- `deploy/build_ala_density.py` — builds the alanine density anchor in-frame. **Validated locally** against the
  real 1000 K trajectory: uses the pipeline's own dihedral method (`md.compute_dihedrals` on CG atoms
  `[4,6,8,14,16]` + `ala2_cg.pdb`, matching `evaluators_CGflowmatching.get_torsions`) and the code's **own
  endpoint clusters** (`saved_cluster_centers_alanine_dipeptide.npy`, `CLUSTER_ENDPOINTS_ALA=[0,1]`) so the
  intermediate is the periodic midpoint of the true endpoints C7eq[-2.38,2.88]→C7ax[1.26,-1.18] = **[2.58,-2.29]
  rad** (a genuine transition intermediate, not a within-basin point — an earlier histogram approach was wrong and
  the local test caught it).

## 3. Container build — 5 iterations, every failure log-read (no guessing)
No local Docker → built on a **self-terminating EC2 builder** (c5.4xlarge, `ec2-ecr-builder-profile`, user-data
builds + pushes to ECR + `shutdown`; dead-man `shutdown -h +150`). Region us-west-2, acct 399683337364.

| # | Failure (from build.log) | Root cause | Fix |
|---|---|---|---|
| v1 | `conda create` exit 1 | Anaconda channel **ToS gate** (new Miniconda) | → **Miniforge** (conda-forge default) |
| v2 | `mdtraj` wheel: `fatal error: zlib.h` | mdtraj builds from source, no zlib headers | install compiled sci stack from **conda-forge** |
| v3 | `LibMambaUnsatisfiableError` | `numpy=1.21.2` + `mdtraj=1.9.9` **double pin** unsatisfiable | loosen: `numpy>=1.21,<1.24`, unpin mdtraj (validated the solve locally) |
| v4 | (built 13.5 GB) job "Task failed to start" | **image too big for the 30 GB Batch instance disk** | **slim** image (`--no-cache-dir`, strip caches/tests/`.a`) → 7.6 GB |
| slim-a | pip step exit 1 | over-trimmed `build-essential` (a pip pkg compiles) | restore build tools |
| final | build **SUCCESS** + **import smoke test `OMTPS_IMPORTS_OK`** | — | complete deps + build-time import test |

**Key hardening (per user "make it work first, then proceed"):** the final Dockerfile ends with a **build-time
import smoke test** — `RUN python -c "import evaluate.evaluate_fastfolders, evaluate.evaluators,
datasets.dataset_utils_empty, models.flow_matching, models.ddpm, dynamics.langevin, utils, actions,
density_guidance"` — so a green build **guarantees** the run's full import chain works (no more one-error-per-GPU-job
whack-a-mole). Missing deps found by static import-tree analysis and added: ipython, scienceplots, deeptime,
scikit-learn, scipy, networkx, statsmodels, pillow. Confirmed **openfold / pytorch_lightning NOT needed** (only in
the unused protein-model path). torch resolved to **2.8.0+cu128** (torch-geometric upgraded it); imports pass on it.

**Image:** `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/om-tps:v2` (7.6 GB, reusable).
**Job def:** `om-tps-m6:3` (GPU 1 / VCPU 8 / MEM 40 GB, `ecsInstanceRole`). **Queue:** `biomate-gpu-t4-queue`
(On-Demand T4 `g4dn.4xlarge`, NOT the SPOT CE).

## 4. Baseline (density OFF) — ✅ SCAFFOLD PROVEN ON GPU
Runtime blockers after imports (each log-read, fixed in the run script):
1. `aws: command not found` — outer fetch ran before `conda activate` → activate first.
2. `No module named IPython/scienceplots` — slimmed deps (later baked into the image).
3. `OSError: ./datasets/folded_pdbs/ala2.pdb` — **OM-TPS repo path bug**: `ala2.pdb` ships at
   `datasets/ala2/data/`, not `folded_pdbs/` → `cp` at runtime (endpoints hardcoded, no traj data needed for the
   dataset).
4. `NotImplementedError: Ground truth trajectory not found` — sample.py **hardcodes**
   `/data/sanjeevr/Ala2Train/trajectories1000.0K.pt` and uses it to pick the transition endpoints → stage
   `Ala2Train.zip` (1.3 GB, on S3) to that path.

**Result (job `fccd6fe0`, exit 0):** the 5000-step OM optimization **ran and converged** on the T4 — OM Action
26.77M → 25.63M → 24.60M → 21.33M …, Path/Force/Laplace contributions tracked. Full outputs produced:
transition-path PDB/GSD, **energy profile** (png+gif), Ramachandran plots, action-convergence plot, and
**`final_metrics.json → js_divergence = 0.4712`** (the OFF baseline metric). Archived:
`s3://biomate-nextflow-work/builds/omtps/run/results_baseline_OFF/`.

> **This is the scaffold gate PASSED** — OM-TPS runs end-to-end on AWS Batch GPU with a real metric. It is NOT the
> M6 proof (that is the ON/OFF ablation below).

## 5. Guided ablation (density ON) — set up, first attempt caught+killed, builder now fixed
- **Ablation design:** run the *same* image/command with `M6_DENSITY_LAM` set (+ `m6_patch.py` overlay + the
  intermediate density), sweep λ ∈ {1e3, 1e5, 1e7} to bracket the OM magnitude (~2.7e7), compare `js_divergence`
  (and path shift toward the anchored intermediate) vs the OFF baseline 0.471. Gate (per design doc §4): ON must
  move the path/kinetics beyond seed noise; endpoint-only shift = FAIL (reduction trap).
- **First attempt (jobs `35f48c86`/`13566c68`/`1c24ab78`): killed.** Live log showed `[m6_patch] injected` ✓ but
  then `IndexError` in `build_ala_density.py` — `md.compute_phi` returned empty (mdtraj doesn't recognize φ/ψ on
  the ACE-ALA-NME naming), so the density npz was never built. Terminated the 3 jobs rather than waste GPU on an
  invalid density.
- **Fix (validated locally, §2):** builder rewritten to use the pipeline's explicit-index dihedral method + the
  code's real endpoint clusters. Local run against the true 1000 K trajectory produces a valid npz (grid 4096×3,
  d_exp∈[0,20.2], sigma 1.5) anchored at the true intermediate [2.58,-2.29].
- **Next action (ready):** resubmit the λ-sweep guided jobs on `om-tps-m6:3` with the fixed builder (re-uploaded to
  `s3://…/builds/omtps-ctx/build_ala_density.py`), then compare `js_divergence` ON vs 0.471 OFF + path-to-anchor.

## 6. Infra facts / provenance
- ECR: `biomate/ai-tools/om-tps:{v1(13.5GB, disk-too-big), slim, v2(7.6GB, current)}`.
- Batch: job def `om-tps-m6:3` → `:v2`; queue `biomate-gpu-t4-queue`; On-Demand `g4dn.4xlarge`.
- S3 (`biomate-nextflow-work`): build ctx `builds/omtps-ctx/`; run scripts + results `builds/omtps/run/`; baseline
  `builds/omtps/run/results_baseline_OFF/`; data `builds/omtps-ctx/data/Ala2Train.zip` (1.3 GB).
- Local repos (gitignored): `research/OM-TPS`, `research/mdgen`. Env `omtps-core` (torch 2.2.2 + numpy 1.26.4 +
  mdtraj) for local science tests.
- **Spend to date ≈ $1–2** (5 short builder runs + baseline + 3 killed guided starts).

## 7. Operational finding (surfaced during this work) — cross-session EC2 termination
CloudTrail (us-west-2) showed a **sibling Claude session** on this Mac terminating GPU instances via the **shared
`biomate-admin` IAM user** (aws-cli, IP 104.63.31.236) — it killed an On-Demand `g5.xlarge` `immune-llm-qlora`
training instance mid-flight (2026-08-19 14:50), plus similar earlier. **Not Spot, not a budget guardrail.** The
shared IAM user means CloudTrail can't attribute by ARN. Recommendation: tag disposable builders and terminate only
by tag; or give each session a scoped IAM user. (Details in the CloudTrail section of the session.)

## 8. Honest status
- ✅ Container (reusable ECR image) + Batch pipeline + **baseline scaffold on GPU** (js=0.471, full outputs).
- ✅ All M6 science code validated locally (density term gradient, patch injection, density builder).
- ⏳ **The M6 proof itself (ON/OFF ablation number) is not yet produced** — guided λ-sweep ready to resubmit with
  the fixed builder. This is the immediate next step.
- Nothing has been requested from the SNAT2 collaborator (gated behind the public-data proof, per design doc).

## Change log
- **2026-08-22** — created. Full record of the OM-TPS container build (5 iterations), scaffold confirmation on
  Batch GPU (baseline js=0.471), density-guidance implementation + local validation, and the guided-ablation setup
  (first attempt killed on a density-builder bug, now fixed and re-staged). Scope kept honest: scaffold proven,
  ablation pending.
