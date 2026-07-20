# Template Alignment Assessment — Which Use Cases Fit the Case-Study Templates

**Date:** 2026-07-15 | Prepared for the BioMate white-paper case-study set

## How alignment is judged

The **Commercial Case Brief** is fillable for almost any use case (headline + rough time/cost/quality). The **Scientific & Technical Validation Report** is the gate — it demands two hard sections filled with *real, executed* numbers:

- **§4.1 Performance** — manual-vs-BioMate wall-clock, peak memory, analyst-hours, analyst-cost (a measured comparison, not an estimate).
- **§4.2 Concordance & Accuracy** — a quantitative accuracy metric vs an accepted reference standard.

A structural note: the template's §4.2 rows (cross-tool Jaccard/κ, Pearson r, sensitivity/specificity, FDR) were written around an **RNA-seq differential-expression concordance** example. Our strongest finished evidence is *not* DE concordance — it is AUROC, gate-convergence, resolution (Å), P@1, and within-2-fold PK. So §4.2 must be **re-labelled per use case** with the domain-appropriate metric (done in the drafted reports). This is expected, not a defect.

---

## TIER A — Well-aligned; both templates fillable now with real data

| Use case | §4.1 Performance | §4.2 Accuracy | Residual gap |
|---|---|---|---|
| **Cryo-EM SPA (EMPIAR-10028)** | ✅ real wall-clock, GPU-h, $27 vs $900, analyst-hours | ✅ FSC 1.78 Å vs published 2.2 Å | Best template fit of all. Only gap: metrics.json 5.46 Å run to reconcile |
| **Drug-discovery pipeline (ADMET/CiPA/PBPK/IND/BOIN)** | ⚠️ time real, analyst-$ estimated | ✅ AUROC vs ADMET-AI; CiPA FP 58→8%; EMA 2-fold | Analyst-cost is estimated, not timed |
| **Clinical PBPK cohorts** | ⚠️ time strong, $ estimated | ✅ EMA 2-fold (100% AUC); semaglutide vs SUSTAIN-1 | Cohort models guidance-grounded, not cohort-validated |
| **Workflow retrieval (key-term injection)** | ⚠️ latency yes, memory/$ N/A | ✅ 100% P@1 (54) & 63.4% (41) vs Claude 85.2% | §4.1 is latency, not cost — re-label |

These four already have drafted report pairs (drug-discovery, cohorts, QC/auto-loop done; cryo-EM data ready, draft pending).

---

## TIER B — Mostly aligned; publishable with 1–2 fields marked [GAP] or after a small run

| Use case | Strong section | Weak/missing section | Work to close |
|---|---|---|---|
| **QC governance + auto-loop** | §4.2 auto-loop 96.4%; audit 1.0 vs 0.0 (p=1.6e-4) | §4.1 wall-clock; governance FP/FN = **placeholder** | Run the 5-dataset AWS governance benchmark (~$500) |
| **Flagship agent evals (BixBench/BiomniEval1)** | §4.2 48% vs 29.2%; 71.3% vs 65% | §4.1 no cost/time; BixBench = 50-q subset | Full 296-q confirmation run |
| **Paper2Workflow tool-locator** | §4.2 Hit@5 1.00, MRR 0.631 | Lexical-only lower bound; pipeline stages untested | Run dense+LLM re-rank; wire end-to-end |
| **Speedup: ADMET Nextflow fan-out** | Design + local 8/8 | §4.1 core metric (20–50×) is a **target, not measured** | Dev AWS Batch before/after run |
| **Speedup: ref-DB cache** | Latency 5–15 s→<1 ms | No production hit-rate A/B | Measure cache hit-rate in prod |
| **Routing (production 94.6%)** | §4.2 headline number | Self-reported; v13 drift to 61.9% | Independent labeler, 200+ real queries |
| **Param prefill** | Framework + 170 cases | ~72% F1 is an **estimate**, rerun pending | Complete the rerun |
| **Allometric / PopPK / NCA** | Implemented, regulatory-referenced | Thin standalone benchmark | Fold into the cohort study, not standalone |

---

## TIER C — Not aligned yet; need substantial additional work (proposal / in-progress)

| Use case | Status | What's missing before it can fill the template |
|---|---|---|
| **CryoEnsemble (rare conformer)** | In-progress | Pivotal H1d neural-DPS run; real-data forward-model fix |
| **Multi-omics systems-bio gold standards** | Planned | Stage datasets; execute vs Sturm/NeurIPS/BEELINE |
| **Virtual-cell / spatial / autoimmune** | Routing-only | Load datasets; containerize MEFISTO/AlphaFold3/Space Ranger; execute (local synthetic gold 0.05–0.45) |
| **SLE Banchereau autoimmune pilot** | Planned | Run GSE65391; report κ/FDR/r vs published modules |
| **Proteomics QC** | Planned | Build QC layer (~9 days); run PRIDE benchmarks |
| **Cross-run stability** | Planned | Build harness; 5 workflows × 10 runs |

These belong in the white paper's **"pipeline / roadmap" tier**, not as finished case studies.

---

## TIER D — Real, but does not fit the "BioMate wins vs manual" template shape

| Use case | Why it doesn't fit | Where it belongs |
|---|---|---|
| **SGI-Bench positioning** | Third-party benchmark; BioMate not scored on the same tasks | White-paper *narrative* ("why orchestration beats autonomous codegen"), not a case-study template |
| **Auto-update tool ingestion** | Honest **negative** result (0/14 wrappers pass) | A "capability + open research problem" sidebar, or omit from customer-facing briefs |

---

## Bottom line

- **4 use cases (Tier A)** can fully populate both templates now → these are the white-paper anchors.
- **8 use cases (Tier B)** are one measured run or one confirmation away → schedule those runs; they are the highest-ROI additions.
- **6 use cases (Tier C)** are proposal/in-progress → present as roadmap, not evidence.
- **2 use cases (Tier D)** are real but need reframing → narrative/sidebar, not templates.

**Highest-leverage next actions to convert Tier B → Tier A:** (1) the ~$500 AWS QC-governance benchmark, (2) the ADMET fan-out dev-Batch speedup measurement, (3) the independent-labeler routing eval, (4) the param-prefill rerun. Each turns a self-reported/placeholder/target number into a defensible one.
