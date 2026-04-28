# Auto-Loop QC Benchmark — Design & Plan

**Date:** 2026-04-20  
**Status:** Design approved, implementation planned  
**Relevant code:** `backend/experiments/{admet,cyp_ddi,docking,nca_pk}_autoloop/`

---

## 1. Should the benchmark be combined with QC?

**Yes — they must be combined.** The auto-loop *is* the QC enforcement mechanism; evaluating them separately would create an artificial split:

- The **QC evaluator** decides if outputs pass scientific gates
- The **param tuner** proposes remediations when they fail
- The **orchestrator** drives the loop until convergence or escalation

The benchmark should measure whether this complete cycle — run → QC → remediate → re-run — converges to a valid, gate-passing result. A benchmark that only measures QC classification accuracy misses the key capability: autonomous remediation.

---

## 2. What the benchmark measures

### Three metrics (all novel vs. existing benchmarks)

| Metric | Definition | Existing reference? |
|--------|-----------|-------------------|
| **Gate-pass@1** | Fraction of compounds passing all QC gates on first attempt | Partial — TDC ADMET tasks measure individual gates |
| **Convergence rate** | Fraction reaching all-green within ≤3 loop iterations | **Novel** |
| **Mean iterations-to-convergence** | Lower is better; measures remediation efficiency | **Novel** |

### Secondary metrics (QC layer only)

| Metric | Definition |
|--------|-----------|
| Gate classification accuracy | Correct PASS/FAIL per individual gate |
| Escalation rate | Fraction requiring human escalation after max retries |
| Remediation direction correctness | Was the proposed remediation scientifically valid? |

---

## 3. Existing benchmarks as reference points

### ADMET

- **TDC (Therapeutics Data Commons) ADMET Benchmark Group**  
  URL: `tdcommons.ai/benchmark/admet_group/overview`  
  Datasets: hERG, DILI, Ames, Caco-2, Pgp, PPBR, VDss, CYP3A4/2C9 inhibition (~7,600 compounds)  
  Use: Compounds that *fail* our QC gates seeded from TDC test sets = benchmark inputs
  
- **MoleculeNet ADMET datasets**  
  Overlaps with TDC; useful for held-out test compounds not in training distribution

### CYP-DDI  

- **FDA DDI Guidance 2020** (the normative reference)  
  The R1/R2 thresholds (`R1 = 1 + Cmax_ss_uM / Ki > 1.02` → INVESTIGATE) define correct vs. incorrect classification. No ML benchmark exists — FDA guidance IS the ground truth.

### Docking

- **DUD-E / CASF-2016**  
  Standard pose-quality benchmarks. Our metric is different (does the loop improve Vina/GlideScore to cross the gate?), but CASF-2016 active compounds can seed "failing docking" inputs.

### NCA-PK

- **FDA Pharmacokinetics Guidance (2003/2022 update)**  
  AUC extrapolation ≤20%, R² ≥0.90 for terminal slope. No public ML benchmark — FDA guidance defines correctness.  
  Note: This is the most novel benchmark dimension; no comparable public dataset exists.

---

## 4. Dataset design

### Seeding strategy: "deliberately failing" compounds

Each benchmark task is a compound/protocol that is engineered to fail one or more QC gates, with known ground-truth outcomes:

```
Task structure:
  - input: SMILES or PK parameters
  - failing_gates: [hERG, DILI]          # pre-determined failures
  - expected_convergence: True/False     # can remediation fix it?
  - ground_truth_gates: {hERG: FAIL, DILI: FAIL, Ames: PASS, ...}
  - remediation_direction: {hERG: "reduce_logP", DILI: "reduce_MW"}
```

### Sources

| Domain | Failing compound source | N proposed |
|--------|------------------------|-----------|
| ADMET | TDC hERG + DILI test set positives | 50 |
| CYP-DDI | Known strong CYP3A4 inhibitors (ketoconazole, clarithromycin) + FDA DDI examples | 30 |
| Docking | DUD-E decoys for known targets (low Vina score guaranteed) | 40 |
| NCA-PK | Synthetic PK profiles with poor terminal slope coverage | 30 |
| **Total** | | **150** |

---

## 5. Scoring rubric

```python
def score(task, loop_result):
    """
    loop_result: {gates_final: {gate: PASS/FAIL}, iterations: int, escalated: bool}
    """
    all_pass = all(v == "PASS" for v in loop_result["gates_final"].values())
    
    if loop_result["escalated"]:
        return 0.0   # Failed to converge
    
    if all_pass and loop_result["iterations"] == 1:
        return 1.0   # Passed on first attempt (gate-pass@1)
    elif all_pass and loop_result["iterations"] <= 3:
        return 0.8   # Converged within 3 iterations
    elif all_pass:
        return 0.5   # Converged but slowly (>3 iterations)
    else:
        return 0.0   # Did not converge
```

### Published baselines to beat

| Domain | Baseline (no auto-loop, 1 attempt) | Auto-loop target |
|--------|-----------------------------------|-----------------|
| ADMET gate-pass@1 | ~40% (TDC random compound) | ≥70% convergence rate |
| CYP-DDI | ~30% (known inhibitors fail R1/R2) | ≥80% convergence |
| Docking | ~20% (decoys) | ≥60% convergence |
| NCA-PK | ~50% (sparse sampling) | ≥80% convergence |

---

## 6. Implementation plan

### Phase 1 — Adapter (1-2 days)

```
evaluation/adapters/autoloop_benchmark_adapter.py
evaluation/datasets/autoloop_benchmark/
  admet_cases.yaml       # 50 ADMET failing compounds
  cyp_ddi_cases.yaml     # 30 CYP-DDI failing compounds  
  docking_cases.yaml     # 40 docking failing compounds
  nca_pk_cases.yaml      # 30 NCA-PK failing protocols
evaluation/runners/run_autoloop_benchmark.py
```

The adapter calls the actual BioMate auto-loop endpoints (not mocked) per `CLAUDE.md` E2E testing rules.

### Phase 2 — Integration with QC profiles

The existing QC profiles (`/api/qc/profiles`) return 32 profiles. The benchmark should:
1. Test all 3 profiles per domain (standard / strict / oncology)
2. Measure how profile strictness affects convergence rate
3. Report per-profile breakdown in results

### Phase 3 — CI integration

Add `run_autoloop_benchmark.py --max-per-domain 10` to the CI regression suite. If convergence rate drops >5pp vs. baseline, flag as regression.

---

## 7. Connection to publication plan

The auto-loop benchmark is the most novel contribution for a potential BioMate methods paper. The claim:

> "BioMate autonomously converges compounds from failing QC to gate-passing status in ≤3 iterations for X% of cases, versus Y% without auto-remediation (p<0.001, Fisher's exact test)."

Required sample sizes for this claim:
- n=150 total tasks → power ~85% to detect 15pp improvement at α=0.05
- Stratified by domain (ADMET/CYP-DDI/Docking/NCA-PK) and profile (standard/strict/oncology)

---

## 8. Priority vs. other benchmark work

| Benchmark | Status | Publication readiness |
|-----------|--------|----------------------|
| BiomniEval1 | v18 done (65.9%), v19 in progress | Ready (n=223, CI ≤±3pp) |
| LABBench | Adapter ready, not yet run | Run when server is idle |
| Auto-loop | Design done (this doc) | Build adapter next |
| Routing | v9 93.3%, needs 540+ queries | Expand before publication |

**Recommended order:** finish BiomniEval1 v19 → run LABBench → build auto-loop adapter → expand routing benchmark.
