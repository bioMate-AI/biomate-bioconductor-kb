# Session 2026-05-22 — QC + Auto-Loop Audit, PBPK Auto-Loop Build

**Branch:** `integration/next-phase` (tip: `cd0c5232a`, pushed)
**Net new commits this session:** 6 (sync infra fix + PBPK autoloop + lessons doc)
**Tests added:** 18 PBPK + 28 existing autoloop_bridge still passing
**Production deploy status:** code committed + pushed; not yet synced to dev

---

## Part 1 — QC coverage audit (read-only inventory)

### Summary
Bimodal. ~50 drug-development workflows + 5 auto-loop bridges + cryo-EM
all have evidence-backed QC gates (FDA / ICH / peer-reviewed citations).
**1,818 Bioconductor wrappers ship 0 inline QC** — they are raw `Rscript`
wrappers around the package's main function. Largest gap by *volume* is
Bioconductor; largest gap by *risk* (pre-fix) was PBPK gate-emission.

### Coverage by group

| Group | Audited | With QC | With evidence cite |
|---|---|---|---|
| drug_discovery | ~50 | ~25 (50%) | ~22 (44%) |
| 5 auto-loop bridges | 5 | 100% | 100% |
| cryo_em (incl. autoloop) | 15 | 100% | 100% |
| genomics | 35 | ~50% | partial (GATK best-practices, ENCODE4) |
| single-cell wrappers | 7 | 1/7 | 0/7 (only scrna_doublet_qc) |
| proteomics wrappers | 3 | uses orchestrator | Elias & Gygi 2007 (orchestrator-side) |
| bioconductor sample | 20/1,818 | 0 | 0 |

### Drug-dev QC correctness verdict

| Verdict | Workflows |
|---|---|
| ✅ Evidence-backed | ADMET (Aronov 2008 / Lammert 2010 / Kazius 2005 / Lipinski 1997), NCA (FDA 2003 AUC ≤20%), CYP-DDI (FDA 2020 R1/R2), HTS Z' (Zhang 1999), BOIN (Liu & Yuan 2015), ICH-S5 / ICH-S7B, adaptive trial (O'Brien-Fleming 1979) |
| ⚠️ Threshold disputable | docking (-7 kcal/mol & GlideScore<-8 vendor heuristic), DILI 0.5 cutoff operational not regulatory |
| ❌ Gate logic missing | **PBPK simulation (FIXED this session)** |

### Top-5 QC gaps as of 2026-05-22

1. ~~**PBPK has no thresholded gate output**~~ — **FIXED** (see Part 3)
2. **1,818 Bioconductor wrappers have 0 QC** — DESeq2/edgeR/limma have no padj/FC floor (defer: re-runs are cheap; downstream gates compensate)
3. **Docking cutoffs vendor-heuristic** — either cite Friesner 2006 / Trott & Olson 2010, or downgrade to "advisory-only"
4. **Single-cell wrappers lack mito/min-genes/doublet-rate gates** (Luecken & Theis 2019 standard)
5. **HTS computes signal_window but doesn't gate on it** — Iversen 2006 SW≥2

---

## Part 2 — Auto-loop confidence audit

### Confidence scoreboard (before this session)

| Level | Domains |
|---|---|
| HIGH (cited + tested + wired) | ADMET, CYP-DDI, NCA-PK, Docking, CryoEM SPA |
| MEDIUM (gates exist, not wired) | PBPK, IVIVE, HTS |
| LOW (no autoloop, high leverage) | nf-core/rnaseq, GROMACS/Amber MD, nf-core/scrnaseq, NONMEM popPK, nf-core/sarek |
| N/A | report-generators (CRO export, vCoG grading, ICH-S5 docs) |

### After this session

PBPK moved MEDIUM → **HIGH**. Five autoloops are now wired with cited gates: ADMET, CYP-DDI, NCA-PK, Docking, CryoEM, **PBPK**.

### Phased fill plan (sequenced)

| Phase | What | Status | Effort |
|---|---|---|---|
| A.1 | **PBPK auto-loop wiring** | **DONE this session** | small (done) |
| A.2 | IVIVE auto-loop (well-stirred fold-error gate, Obach 1999) | open | small |
| A.3 | HTS auto-loop (Z'-factor gate, Zhang 1999) | open | small |
| B.1 | nf-core/rnaseq auto-loop (highest-leverage LOW gap) | open | medium |
| B.2 | MD auto-loop (RMSD plateau, Hess 2008) | open | medium-large |
| C | scRNA-seq, ChIP/ATAC-seq, sarek, NONMEM popPK | open | medium each |

**Stop criterion:** ≥10 wired domains with cited gates; ≥80% of runs emit
`autoloop_*` SSE events. After this session: 5/10 done.

---

## Part 3 — PBPK auto-loop build

### What ships

```
backend/experiments/pbpk_autoloop/
├── __init__.py
├── knowledge_base.py     (139 LOC, 4 KnowledgeEntry blocks)
├── qc_evaluator.py       (235 LOC, 4 gates, 2 profiles)
├── params.py             (41 LOC, PBPKParams dataclass)
├── param_tuner.py        (135 LOC, gate→remediation handlers)
├── enriched_tuner.py     (53 LOC, knowledge-citation wrapper)
└── tests/
    └── test_pbpk_autoloop.py  (18 tests)
```

Wired into `backend/experiments/autoloop_bridge.py`:
- `_DOMAIN_KEYWORDS["pbpk"]` = {`PBPK_SIMULATION`, `PBPK_PEDIATRIC`, `PK_SIM_PBPK`, `SIMCYP_PBPK`, `PBPK`, `PHYSIOLOGICALLY_BASED_PK`}
- `_adapt_pbpk` schema adapter (flat or nested keys)
- `_DOMAIN_DEFAULT_PHASE["pbpk"] = "phase_1_pbpk_simulation"`
- `_DOMAIN_DEFAULT_PROFILE["pbpk"] = "pbpk_screening"` (advisory default; opt-in to IND profile for halt-grade)
- `_load_components` extended for the pbpk branch

### Gates + thresholds (matches `qc_trace_monitor.py:690-733`)

| Gate | IND-grade threshold | Screening threshold | Source |
|---|---|---|---|
| pbpk_tmax_fraction | Tmax ≤ 80% of sim window | ≤ 90% | FDA 2018 |
| pbpk_cl_min | CL ≥ 0.01 L/h | ≥ 0.001 | Davies & Morris 1993 |
| pbpk_mass_balance | recovery within ±5% | ±10% | EMA/CHMP/458101/2016 |
| pbpk_auc_fold_error | \|log2(pred/obs)\| ≤ 1 (2-fold) | ≤ log2(3) (3-fold) | FDA 2018 |

### Remediation (gate → knob)

| Gate fails | Knob | New value | Rationale source |
|---|---|---|---|
| pbpk_tmax_fraction | `simulation_duration_h` | × max(1.5, 3 × fraction) | FDA 2018 — capture elimination |
| pbpk_cl_min | `clint_mL_per_min` | × 2 | Davies & Morris 1993 — well-stirred model |
| pbpk_mass_balance | `integration_rtol` | × 1e-2 (tighten) | EMA 2019 |
| pbpk_auc_fold_error | `kp_scale` | × 0.75 | FDA 2018 — 2-fold criterion |

### Test coverage (18 passing)

- All 4 gates: pass + halt + advisory + skipped paths
- All 4 remediations: param mutation verified
- Two profiles: IND HALT, screening ADVISORY-only
- Knowledge enrichment: every remediation includes paper_ref + paper_doi
- Bridge integration: `classify_domain` for 5 process-name variants, end-to-end SSE event emission, no false positives on unrelated process names

### Behavior properties

- **Fail-safe gating:** all 4 gates skip gracefully when their input is None (mass-balance skipped when no recovery field; AUC fold-error skipped when no observed AUC reference)
- **Advisory-only default:** the `pbpk_screening` profile never HALTs — matches `qc_trace_monitor.py` convention for early-stage simulations
- **No regression:** 28 existing `autoloop_bridge` tests pass unchanged

---

## Part 4 — Sync infrastructure fixes (earlier in same session)

| Issue | Fix | Commit |
|---|---|---|
| `sync_to_dev.sh` overwrites dev DB with older local DB | Migrated local universe.sqlite to 204367c6a604; dev no longer downgrades | `c77990b51` |
| Silent try/except in autofix/agent.py + ai_assistant.py hid import failures | `except: log.warning(...)` so prod logs surface degradation | `c77990b51` |
| `aws s3 cp` for universe.sqlite fails 403 on EC2 (no S3 read) | Direct scp workstation→EC2 (3.4 MB, 2 sec); galaxy_ai_tools.db stays on S3 (262 MB, S3 PUT works) | `51450928d` |
| `manage_db.sh upgrade` fails "Multiple head revisions" | Explicit target `LATEST_GXY_HEAD=204367c6a604` (with maintenance comment) | `51450928d` |
| Webapp endpoint singleton bypassed wired class | `__class__` swap on the `get_workflow_search()` singleton → `WiredWorkflowSearch` | `87218c30b` |

Production HTTP smoke (post-fix) — 9/10 canonical routing queries hit the right `nf-core/*` target via the actual gunicorn worker. Latency p95 = 5.9 s (search_ranked LLM cost; library overhead <30 ms).

---

## What's left in the audit's plan

| Item | Effort | Notes |
|---|---|---|
| IVIVE auto-loop (Obach 1999 fold-error) | small | next Phase A item |
| HTS auto-loop (Z'-factor gate) | small | next Phase A item |
| nf-core/rnaseq auto-loop | medium | highest-leverage Phase B (most-used pipeline) |
| MD auto-loop (RMSD plateau) | medium-large | Phase B |
| Bioconductor blanket QC layer | strategic deferral | 1,818 wrappers; downstream gates can compensate |
| Docking citation choice (peer-reviewed cutoff or downgrade to advisory) | small | documentation, not code |
| Sync to dev (manual step) | small | not auto-done — user authorization required |

---

## Files added/modified this session

```
NEW backend/experiments/pbpk_autoloop/__init__.py
NEW backend/experiments/pbpk_autoloop/knowledge_base.py
NEW backend/experiments/pbpk_autoloop/qc_evaluator.py
NEW backend/experiments/pbpk_autoloop/params.py
NEW backend/experiments/pbpk_autoloop/param_tuner.py
NEW backend/experiments/pbpk_autoloop/enriched_tuner.py
NEW backend/experiments/pbpk_autoloop/tests/__init__.py
NEW backend/experiments/pbpk_autoloop/tests/test_pbpk_autoloop.py
MOD backend/experiments/autoloop_bridge.py            (+37 lines: keyword, adapter, phase, profile, loader)
NEW docs/20260521_DEPLOYMENT_MISTAKES_LESSONS.md       (yesterday's mistakes for future-Claude reference)
NEW docs/20260522_PBPK_AUTOLOOP_AND_QC_AUDIT.md        (this doc)
MOD scripts/sync_to_dev.sh                              (scp + explicit alembic target)
MOD backend/lib/galaxy/ai/workflow_ops/autofix/agent.py (log.warning on import fallback)
MOD backend/lib/galaxy/ai/ai_assistant.py               (log.warning on import fallback)
MOD backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py (singleton __class__ swap)
```

---

## Deploy status

| Component | Local | Dev |
|---|---|---|
| Retrieval wiring + libraries | committed | live (synced 51450928d, verified end-to-end) |
| PBPK auto-loop | committed (cd0c5232a) | **not synced yet** |
| Sync script fix | committed | live |
| Local universe.sqlite at correct alembic head | yes | yes |

The PBPK auto-loop is in repo but NOT yet on dev. Awaiting authorization to run `scripts/sync_to_dev.sh` for that change.
