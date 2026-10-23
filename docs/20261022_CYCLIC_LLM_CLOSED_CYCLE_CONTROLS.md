# Cyclic-LLM closed cycle — controls, placebo result, and honest-status reconciliation (2026-10-22)

Continues the physics-verified closed-cycle work (`methodology_close.py`; thesis in
`docs/20261021_CYCLIC_LLM_INNOVATION_THESIS.md`). This session added the missing **placebo control**,
ran it, and reconciled two over-claims against the team's own rigor docs.

## 1. The defensible closed-cycle result (unchanged)

Verified-reward generator-DPO close on the collected v4 LM, with **anti-circular, cluster-disjoint**
(monomer-Tanimoto ≥ 0.6) permeability oracles (reward oracle A, independent evaluator oracle B):
`results/methodology_close_6seed_leakagesafe.json` — mean Δ(evaluator B) = **+0.098** (SE 0.011),
6/6 seeds, Wilcoxon p = 0.031; reward-oracle→evaluator R² ≈ 0.07–0.17 and dB–dA corr = 0.19 (low →
the gain is genuine generalization, not reward-hacking). Honest number; the earlier +0.251 was an
inflated leaky hash-split.

## 2. NEW — shuffled-reward placebo control (the missing control)

**Question:** does DPO move the independent evaluator *regardless* of the reward (optimization pressure /
diversity collapse), or only when the reward carries real signal? Added `--shuffle-reward` to
`methodology_close.py`: permute the reward labels across candidates before building preference pairs, so
chosen/rejected are random w.r.t. the true reward; the DPO machinery is otherwise identical. Matched
config (gate-OFF, pool 600 / pairs 400 / steps 80 / eval 300), 5 seeds each.

| condition | Δ(evaluator B) per seed | mean |
|---|---|---|
| **real reward** | 0.155, 0.138, 0.131, 0.096, 0.103 | **+0.124** |
| **shuffled (placebo)** | 0.028, 0.022, 0.009, −0.024, 0.038 | **+0.014** |

**Mann-Whitney U = 25/25 (perfect separation), p(real > shuffle) = 0.004.** Diversity is held in both
arms (≈0.96 → 0.93–0.97), so the real-reward gain is not a diversity-collapse artifact. Result:
`results/methodology_close_placebo_control.json`.

**Interpretation.** The closed-cycle improvement is **attributable to the verified reward signal** — a
permuted reward barely moves the evaluator (+0.014, within noise of 0), while the real reward moves it
~9× more (+0.124). Together with the anti-circular dual-oracle and the cluster-disjoint split, the
verified-reward DPO methodology now has the three controls a referee expects: leakage-safe split,
anti-circular evaluator, and a reward-label placebo.

(Note: the +0.124 here is the gate-OFF config; the reported headline remains the gate-ON leakage-safe
+0.098. The placebo compares real vs shuffle at the *same* config, which is what isolates the reward.)

## 3. Honest-status reconciliation (two over-claims flagged this session)

Cross-checked the `20261021_CYCLIC_LLM_PAPER_DRAFT.md` claims against the team's own rigor docs; added a
dated reconciliation note at the top of the draft (not a rewrite — shared worktree):

1. **The within-target AUC 0.94–0.96 is compromised by label-circularity.** Per
   `docs/20261021_CYCLIC_LLM_WITHIN_TARGET_SOTA_BENCHMARK.md`: `is_binder` ≈ a threshold on display
   `enrichment_log2fc`, so a trivial enrichment-sort scores **AUC ≈ 1.0 on all four targets and the LM
   does not beat this null on any** (LM AUC 0.266–0.997, below chance on hPCSK9). The 0.94–0.96
   establishes "beats composition baselines on PADI4," **not** SOTA/null-beating. A defensible claim
   needs a non-circular label (measured affinity) on novel sequences vs the abundance null.
2. **Nothing that has run is "physics-verified."** The closed loop uses a **measured-permeability ML
   oracle**, not FEP/MM-GBSA (wired in `score.py`/`fep_batch.py` but `dry_run=True`, unrun; no
   openmm/boltz locally). "Physics-verified closed cycle" is accurate only as proposed infra.

## 4. Honest status of the thesis

- **Proven (defensible):** a verified-reward DPO methodology that moves an independent, leakage-safe,
  anti-circular evaluator on **permeability**, with a reward-label placebo control (p = 0.004). This is a
  real methodological result — the loop learns from the verified signal.
- **Unproven (the thesis's actual aspiration):** that a physics/binding reward breaks the **cross-target**
  wall. Cross-target transfer is NULL (`xtarget_fm.json` Δ +0.007; own-LM LOTO null; BoltzGen FT Δiptm
  −0.16; binding-model novel-target ceiling ≈ 0.42 Spearman = convergent data wall). The proof paths
  (Slice-0 FIKK13) are themselves circular (`is_binder` ≈ abundance) and underpowered (n ≈ 13/class).

## 5. Next steps (honest)

- The permeability closed-cycle result is publishable as a **methodology** demonstration (generate →
  verified-reward → DPO, with leakage/anti-circular/placebo controls), scoped to "the loop learns from a
  verified property signal" — NOT as binding or cross-target.
- To test the actual thesis needs a **non-circular binding reward** (measured affinity or a run FEP
  control edge) and ≥3 same-chemistry targets for a clean LOTO — both currently blocked (physics engine
  not local; same-chemistry targets n=2). Do not run the circular Slice-0 proof as-is.
- Rescope the paper draft §3.1 per the reconciliation note before any submission.
- Methodology-scoped closed-cycle paper section drafted: `docs/20261022_CYCLIC_LLM_CLOSED_CYCLE_METHODS_SECTION.md`.

## 6. FEP control-edge runbook (why it can't run here; exact steps on handoff)

Goal: replace the permeability oracle with an **execution-verified binding reward** by first recovering
the αvβ6 relative-FEP **control edge** (CTRL-TRIVEHEXIN → CTRL-AVEBEHEXIN, a double Y→F double
perturbation; both states standard, ΔΔG ≈ 0 expected — the A2 anchor that makes any candidate ladder
admissible). Architecture: AWS Batch GROMACS-CUDA GPU-spot (`fep_batch.py`; queue
`biomate-gromacs-fep-gpu`, job-def `biomate-gromacs-cu12-gpu`).

**Why it cannot run from this environment (verified 2026-10-22):**
- No `boto3`/AWS credentials locally → cannot dispatch or even validate the queue/job-def.
- No GROMACS + pmx on the local Mac **or** the Spark box (aarch64: `gmx`/`pmx`/`openmm` all MISSING) →
  the alchemical **hybrid topology cannot be built**, and the GROMACS-CUDA image has **no pip/pmx**, so it
  cannot be built in-container either.
- Guards (correct): `MDRUN_CMD_READY=False` and an `in/FEP_INPUTS_READY` S3 sentinel — `dispatch_control_edge`
  REFUSES to submit until a pre-built, staged system exists (prevents a predicted-failure GPU spend).

**Ordered runbook (on a box with GROMACS 2024 + pmx + CHARMM36m-mut + AWS creds):**
1. Build the hybrid + solvated/equilibrated legs OFFLINE, both legs (solvent + complex), with the
   metal-aware CaDA-Mn parameters (`fep/forcefield/cada_mn.itp`): `pdb2gmx → pmx mutate (charmm36m-mut,
   Y→F ×2) → gentop → solvate/genion`, then per-λ `.tpr` (12 λ windows).
2. `gmx grompp` **preflight on CPU** (fail-fast) on the hybrid topology; must exit 0.
3. Stage the built system to `s3://…/{run_id}/in/` and write the `in/FEP_INPUTS_READY` sentinel.
4. Rewrite `_fep_command` to **mdrun-only** on the staged legs (em→nvt→npt→per-λ HREX production); set
   `MDRUN_CMD_READY=True`.
5. `python fep_batch.py --submit --run-id=<id>` → one GPU-spot job; read ΔΔG from `out/`. Control edge is
   recovered iff |ΔΔG| ≈ 0 within error; only then is `_fep_ddg` admissible and the binding reward usable
   in the closed loop.
See `docs/20261019_AVB6_FEP_CONTROL_EDGE_REVIEW.md` and `docs/20261019_AVB6_CADA_AND_FEP_SETUP.md`.
**Do not flip the guards or submit speculatively** (no-speculative-GPU-spend rule; the build must exist first).
