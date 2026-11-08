# C3 — Generator plateau & the all-atom fine-tune lever: resolved from real artifacts

**Date:** 2026-10-21 · Challenge C3 (cyclic-peptide generator DockQ plateau; "all-atom fine-tune = untried lever").
**Verdict:** the all-atom FT was **already run and is flat (+0.0097 DockQ)**, and the apparent "0.506 vs 0.7754 SOTA gap" is a **linear-vs-cyclic / different-harness conflation**. On the cyclic task we already lead the published baselines. Modeling is **not** the lever for generation either. No GPU fired (the real results already existed).

## 1. Resolving the UniMoMo "SOTA" number (traced)
- **0.7754 is UniMoMo's number on LINEAR peptide design**, not cyclic. The program's own launcher states it explicitly:
  `launch_unimomo_cyclic_ft.sh:274` — *"base = reproduced UniMoMo 0.7754-on-LINEAR; here both scored on the CYCLIC test set, same harness. **NOT comparable to PepGLAD 0.403/0.506** (different format/harness)."*
- So "0.506 vs 0.759/0.7754" (the challenge-map framing) compares a **cyclic** number to a **linear** number — apples-to-oranges. On the **cyclic** task the real published comparator is **PepGLAD = 0.403** (DockQ thresholds: 0.23 acceptable / 0.49 medium).
- Reproduction status: the 0.7754-linear figure is UniMoMo's **published** number; the surviving real artifacts in-repo are the **cyclic** evals below, not a 0.7754-linear reproduction log — so treat 0.7754 as *published (linear)*, not independently confirmed here.

## 2. The all-atom fine-tune was ALREADY run — and it is flat (real artifacts)
Real GPU run `results/unimomo-cyclic-ft-20261002T204906Z/` (`ft_summary.json`, `eval_final_{base,ft}.log`, `audit.json`), UniMoMo-format PepBDB-cyclic test, oracle best-of-N:

| Model (UniMoMo harness, cyclic) | DockQ oracle | DockQ pick-1 | receptor-disjoint (leakage-safe) oracle |
|---|---|---|---|
| UniMoMo base | **0.4029** | 0.1997 | 0.3936 |
| **UniMoMo all-atom FT** | **0.4126** | 0.2195 | 0.4025 |
| Δ (ft − base) | **+0.0097** | +0.0198 | +0.0089 |

→ The all-atom fine-tune gives a **negligible +0.0097 DockQ** (and a realistic pick-1 of only ~0.22). **The all-atom lever is not "untried" — it was tried and did not break the plateau.** (The challenge-map's "untried" status appears to have read the *simulated* sibling run `...-20261003T170124Z/SIMULATED_dpo_integration/` + `smoke_report.json` rather than this real 20261002 run.)

## 3. Our best cyclic generator vs cyclic SOTA (real)
- `results/cyclic_official_metrics.txt`: **DockQ(mean) = 0.5063**; `official_test_metrics.txt`: 0.5124 — the PepGLAD-harness "0.506" is a **real measured number**.
- On the **cyclic** benchmark: **ours 0.506 > PepGLAD 0.403 ≈ UniMoMo-cyclic 0.403** → we already **lead the published cyclic baselines**, in the "medium" DockQ band. UniMoMo is strong on *linear* (0.7754) but only ~0.40 on *cyclic* out of the box; fine-tuning it for cyclic barely moved it (§2).

## 4. Verdict
- **Resolved UniMoMo:** 0.7754 = linear (published); on cyclic, base ≈ 0.403.
- **Our baseline:** 0.506 cyclic (real), **already above cyclic SOTA (PepGLAD 0.403).**
- **All-atom FT:** real, **+0.0097 — does not close any gap / break the plateau.**
- **Consequence:** consistent with C1 (affinity) — **modeling is not the lever for generation either.** The "gap to SOTA" was a harness conflation; the all-atom bet is already spent and flat. No further generation-model lever is worth firing. Leverage remains C2 (closed-loop learning) / C4 (MD permeability), not a bigger generator.

## 5. Compute
No GPU fired. The real base/FT cyclic evals already existed (20261002 run); the benchmark re-eval launcher (`launch_cyclic_benchmark_eval.sh`) is an **`aws ec2 run-instances`** job (a worker fork can't launch EC2) — and re-running was unnecessary since the real result is in-repo. Ready-to-run command, if a fresh eval is ever wanted: `bash research/guangzhou_all_atom/launch_cyclic_benchmark_eval.sh` (spot EC2, ~4h; review the cost in the script header; must be launched by the parent/user since EC2 run-instances is denied to worker forks).
