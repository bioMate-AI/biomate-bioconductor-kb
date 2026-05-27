# §2 Methods — Intake Notes

**Purpose:** Record what evidence anchors each Methods subsection draws from, so claims in the prose can be traced back to specific files/lines.

---

## §2.1 — Auto-loop architecture

- `backend/experiments/admet_autoloop/orchestrator.py` — phase loop with iteration budget.
- `backend/experiments/admet_autoloop/qc_evaluator.py` — `PhaseQCResult` with `.halts` list of `GateResult(gate, value, threshold, action)`.
- `backend/experiments/admet_autoloop/param_tuner.py` — `ADMETParamTuner.remediate()` dispatch table at line 172–178.
- `backend/experiments/admet_autoloop/enriched_tuner.py` — wraps the param tuner with knowledge-base citation injection.
- Worked example for §2.1 prose: `_fix_herg` at `admet_autoloop/param_tuner.py:99–121`. Cites Aronov 2008, DOI `10.1021/jm0707476`.

## §2.2 — Knowledge-base design (GOLD/SILVER/BRONZE)

- Schema definition: `backend/experiments/admet_autoloop/knowledge_base.py:46–80` (`@dataclass KnowledgeEntry`).
- Provenance audit framework reproduced from: `docs/20260522_AUTOLOOP_EVIDENCE_PROVENANCE_AUDIT.md`.
- Aggregate provenance partition (from `results/e2_provenance_per_domain.csv`):

| Domain | n_entries | GOLD | SILVER | BRONZE |
|---|---|---|---|---|
| ADMET | 6 | 3 | 3 | 0 |
| CYP_DDI | 5 | 4 | 1 | 0 |
| Docking | 5 | 0 | 0 | 5 |
| NCA_PK | 5 | 3 | 1 | 1 |

## §2.3 — Per-domain remediation rules

### ADMET (`backend/experiments/admet_autoloop/param_tuner.py`)
- `_fix_herg` (lines 99–121) — `logp_max` −0.5; conditional `mw_max_da` ×0.9 if above 400 Da. Cites Aronov 2008 *J Med Chem* 51:6632, DOI 10.1021/jm0707476.
- `_fix_dili_probability` (lines 123–136) — `logp_max ≤ 4.0`, `mw_max_da ≤ 400`. Cites Lammert 2010 *Toxicol Sci*, DOI 10.1093/toxsci/kfq059.
- `_fix_dili_risk_level` (lines 138–148) — `logp_max ≤ 4.0`. Same anchor.
- `_fix_ames` (lines 150–168) — `ames_strict=True`; `num_candidates −10`. Cites Kazius 2005 *J Med Chem*, DOI 10.1021/jm040835a.

### CYP-DDI (`backend/experiments/cyp_ddi_autoloop/param_tuner.py`)
- `_fix_clinical_isoforms` (lines 57–65) — `cmax_ss_uM ×0.5`. Cites FDA 2020 DDI Guidance (R1 ≥ 1.1 = CLINICAL_STUDY threshold).
- `_fix_investigate_isoforms` (lines 67–75) — `cmax_ss_uM ×0.7`. Cites FDA 2020 DDI Guidance (R1 ≥ 1.02 = INVESTIGATE threshold).

### NCA-PK (`backend/experiments/nca_pk_autoloop/param_tuner.py`)
- `_fix_auc_extrapolation` (lines 44–52) — `last_sampling_time_h ×1.5`. Cites FDA 2003 BA/BE Guidance (AUC extrap ≤ 20%).
- `_fix_terminal_slope` (lines 54–64) — `terminal_phase_points +2`; `last_sampling_time_h ×1.3`. Same anchor.

### Docking (`backend/experiments/docking_autoloop/param_tuner.py`)
- `_fix_valid_poses` (lines 44–52) — `exhaustiveness ×2` (cap 32); `center_box_expand_A +1.0` (cap 5.0). No GOLD anchor; flagged BRONZE per provenance audit.
- `_fix_binding_score` (lines 54–69) — `exhaustiveness +4`; Glide SP → XP. Vendor heuristic; BRONZE.

## §2.4 — Benchmark design

- `evaluation/adapters/autoloop_benchmark_adapter.py` — 4-domain scenario catalog.
- Scoring rubric (lines 19–24): 1.0 / 0.8 / 0.5 / 0.0 by iteration count.
- Published baselines (lines 25–29): ADMET 40%, CYP-DDI 30%, Docking 20%, NCA-PK 50%.
- E2 result counts (per `results/e2_convergence_per_domain.csv`): ADMET 36, CYP_DDI 27, Docking 35, NCA_PK 27 — total **125 scenarios** wired (the 139-scenario catalog includes additional clean-pass variants not part of the E2 convergence subset; reconcile this in Results §3).

## §2.5 — Fail-safe architecture

- Iteration budget: 3 — set in orchestrator (each `*_autoloop/orchestrator.py`).
- Hard halt: when `remediate()` returns no `param_changes` (handler missing or guard floor hit), the orchestrator exits with the audit trail preserving original failure + all attempts.
- Anti-collision: guard floors in tuners (`MIN_LOGP=0.5`, `MIN_CMAX_uM=0.05`, `MAX_LAST_SAMPLING_H=168`, `MAX_EXHAUSTIVENESS=32`) prevent runaway parameter excursions.

## Open methodological questions

1. Reconcile 125 (E2 actual) vs 139 (adapter docstring) scenario counts before Results §3.
2. Whether to include CYP-DDI `tdi_concern` (advisory-only gate) in any benchmark count.
3. PBPK auto-loop is excluded from this paper; confirm decision (flagship reports it under governance-only, this paper omits).
