# BioMate physics/MD workflow acceleration — make expensive GPU pipelines run as fast as possible

**2026-10-22. Internal design note.** Scope: FEP/MD and other expensive GPU workflows (docking ensembles,
cryo-EM, QSAR sweeps). The αvβ6 control-edge FEP is the worked microcosm; the levers generalize. Grounded
in the live infra: AWS Batch (`biomate-gpu-spot-queue`, job-def `biomate-gromacs-cu12-gpu`), the Nextflow
executor, and the Redis run-state/orphan-poller.

## The core problem
Expensive workflows are run **monolithic + sequential inside one Batch job**, when the dominant cost axis
is **embarrassingly parallel**. The FEP runs 24 windows (12 λ × 2 legs) sequentially in one job (~2
GPU-days wall-clock) when the 24 windows are independent and could run concurrently (~1 window of
wall-clock). Same root cause recurs across physics workflows.

## Levers, by impact

### 1. Fan-out parallelism — biggest wall-clock win (days → hours, cost unchanged)
Model the parallel axis as concurrent jobs, not an inner loop.
- **FEP**: λ-windows × legs × replicas → AWS Batch **array job** (`arrayProperties.size=N`) + a
  dependency-gated **collect** job (BAR/MBAR).
- **MD**: replicas/seeds. **Docking/ADMET**: compounds. **Cryo-EM**: classes/particles.
- Engine: independent workflow steps as **parallel Nextflow processes**; the collect step depends on the
  array. **Status:** Batch + run-state exist; the GAP is that physics steps aren't fanned out.

### 2. GPU efficiency per job (2–5× cost AND time) — WITH a critical FEP caveat
- **Full GPU residency** (`-nb -pme -bonded -update gpu`, pmemd.cuda, OpenMM CUDA) for plain MD/docking.
- **CAVEAT discovered empirically (2026-10-23): FEP breaks full-GPU residency.** GROMACS 2024 **cannot run
  PME on GPU with perturbed charges** (the alchemical B-state), so an FEP mdrun with `-pme gpu` fails and
  falls back to `-nb gpu` only → **PME/bonded/update run on CPU**. A large FEP complex leg (here 205k atoms)
  is therefore **CPU-PME-bound**, and a faster GPU does NOT help (T4 and g5/p3 both failed to finish 2 ns in
  ~2 h). The right levers for FEP complex legs are: **(a) many CPU cores for PME** (request high vCPU → land
  on g5.12xlarge/g6.12xlarge-class, or use `-npme` PME ranks), **(b) fewer steps** (HMR/larger dt, shorter
  sampling), **(c) a smaller/truncated+restrained pocket** (receptor cancels in relative FEP). Do NOT assume
  GPU-residency speedups transfer to FEP.
- **Right GPU by system size** still holds for the GPU-amenable (nonbonded) part; but for FEP, **CPU is the
  bottleneck**, so size the instance by vCPU, not just GPU.

### 3. Algorithmic / physics (2–4×)
- **HMR** (H-mass repartitioning) → 4 fs steps, ~2× fewer steps; first-class template toggle.
- **Stiff-bond timestep traps** (this FEP): the complex leg is pinned to 0.5 fs by the stiff bonded
  CaDA-Mn (2 fs SIGSEGVs). Fix = **constrain the M–D bonds / virtual-site metal** → 2 fs → ~4×.
- **Convergence-gated sampling**: run short, check BAR/dH-dλ overlap, extend ONLY non-converged windows —
  vs a fixed 5 ns × 12. Non-equilibrium fast-switching (Jarzynski/Crooks) can be cheaper again.

### 4. Never recompute — content-addressed caching/reuse (highest ROI, lowest effort)
The single biggest waste is **redoing done work** (equilibrated systems, built topologies, forcefields).
Cache them content-addressed and reuse across edges/runs. (This session's own lesson: GROMACS was rebuilt
4× and a preflight re-run that was already equilibration-accepted — see
`feedback_fep_gromacs_already_built` memory.)

### 5. Infra / cold-start
- **Spot GPU** (already) + compute envs **min=0 / high-max** so an N-way fan-out actually gets N GPUs.
- **Pre-pulled / warm ECR images** to cut container cold-start.
- **Checkpoint/resume** so spot reclaims don't lose progress (per-window FEP is naturally checkpointable).
- **Same-region staging** — a cross-region bucket (us-east-1 data, us-west-2 compute) is pure latency tax.

## Worked example — this FEP
| | sequential (today) | fast (fan-out) |
|---|---|---|
| windows | 24 in one job, serial | 18 (9 λ × 2 legs) concurrent array jobs + 1 collect |
| per window | nb-GPU only | full-GPU residency |
| sampling | 5 ns × 12 | 2–2.5 ns × 9, BAR-overlap gated |
| wall-clock | ~2 GPU-days | **~1–3 GPU-hours** |
| cost | ~$50–100 | **~$10–25** (≈$5–15 once the 2-fs metal fix lands) |

Physics unchanged (same equilibrated system, same CHARMM36m + CaDA-Mn, same BAR estimator).

## Recommended BioMate defaults (the actionable change)
Make **fan-out array jobs + full-GPU-residency + convergence-gated sampling + content-addressed reuse**
the defaults in the MD/FEP workflow templates, with HMR and the right-GPU selector as toggles. The engine
(Batch + Nextflow + Redis run-state) already supports it; the change is in how physics steps are templated
— parallel + cached, not monolithic + recomputed.
