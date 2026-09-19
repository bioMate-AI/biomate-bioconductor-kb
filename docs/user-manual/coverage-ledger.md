# User-Manual Coverage Ledger

The book ships only content that is **green** here. Each row is a claim the manual makes; it is not
written as "supported" until verified against the real system. On mismatch we **fix the system**
(root cause, per CLAUDE.md) or move the claim to Appendix E (roadmap) — we never soften the manual to
match a broken feature.

**Verification tiers**
- **C** = code-level (the workflow/endpoint/UI exists and behaves as described; read the source).
- **L** = live on dev (`https://dev-public.biomate.ai`, fixture `lifeifei163361@163.com`) — the actual
  flow exercised. Expensive Batch runs are done selectively / reuse `evaluation/tutorial_demos`
  gold-standard runs rather than firing speculative jobs.

**Status:** ✅ verified · 🔧 mismatch → fix filed · ⏳ pending · 🗺️ roadmap (Appendix E, not sold as present)

| Chapter / claim | Tier | Status | Evidence / bug ref |
|---|---|---|---|
| _(rows added per chapter as it is drafted)_ | | | |

## Drug discovery → IND
Chapter: `docs/user-manual/domains/drug-discovery-ind.md` (flagship, D1). All claims below are
code-verified (C) by reading source; expensive live Batch re-runs are marked L / ⏳ and were NOT fired.

| Chapter / claim | Tier | Status | Evidence / bug ref |
|---|---|---|---|
| ADMET screen predicts 16 endpoints (solubility, lipophilicity, Caco-2, HIA, Pgp, bioavailability, BBB, PPBR, 5 CYPs, half-life, clearance, ClinTox) | C | ✅ | `backend/biomni_workflows/nextflow/subworkflows/pharmacology/predict_admet_properties.nf`; property list in `pharmacology.py:249-360` |
| ADMET screen + auto-loop is the moat demo (T09; aspirin clean, C16 hexadecylbenzene halts) | C | ✅ (L ⏳: fresh Batch numeric re-run) | `docs/20260817_COMPARISON_TASKLIST_REPRESENTATIVE_USECASES.md` T09; Demo Narratives R02 |
| `out_of_domain`/applicability = "model hasn't seen this chemistry" (leverage + Tanimoto<0.20), NOT "bad compound"; compound still ranked+kept, flagged in §2.6.1.5 | C | ✅ | `backend/lib/galaxy/ai/drug_discovery/applicability_domain.py` (TANIMOTO_OOD_THRESHOLD=0.20; ad_status verdict) |
| ADMET QC gates with cited thresholds: hERG <10µM (Redfern/ICH S7B), DILI >0.5 (Lammert), Ames >0.5 (Kazius/ICH M7), Ro5 logP>5 / MW>500 (advisory) | C | ✅ | `backend/experiments/admet_autoloop/qc_evaluator.py:106-183` |
| Gate verdicts are HALT / ADVISORY / PASS; HALT stops+remediates, ADVISORY logs but continues | C | ✅ | `qc_evaluator.py` `passed` property (action != HALT) |
| QC profiles: admet_standard / admet_cns / admet_oncology change which compounds fail | C | ✅ | `qc_evaluator.py:106-183` |
| Auto-loop re-tunes SCREENING THRESHOLDS (logp_max, mw_max_da, ames_strict) with was→now diff; ≤2 retries then escalate; does NOT generate analogues | C | ✅ | `backend/experiments/admet_autoloop/param_tuner.py:123-185`, `orchestrator.py:95-196` |
| Auto-loop wired to production (not just experiment dir): SSE inject at completion | C | ✅ | `nextflow_executor.py:3380-3409` (`from experiments.autoloop_bridge import evaluate_and_emit`); `qc_trace_monitor.py:549,1359`; `/api/invocations/{id}/autoloop-suggestions` at nextflow_executor.py:7486 |
| ADMET output parsing + methods narrative uses only extracted values (no invented numbers) | C | ✅ | `frontend/server/routes.ts:5288-5540` |
| PBPK: 8-compartment Rodgers–Rowland ODE (SciPy LSODA); outputs pk_profile.csv + NCA (Cmax/tmax/AUC/t½/CL/Vss/F) | C | ✅ (L ⏳) | `backend/.../subworkflows/drug_discovery/pbpk_simulation/main.nf` |
| Allometric scaling HED exponent = **0.33** (FDA 2005), MRSD=HED/10, MABEL=MRSD/2; R² gate ≥0.85 | C | ✅ | `backend/.../subworkflows/pharmacology/allometric_scaling/main.nf:146,152-156`; R² gate `qc_gate_reader.py:247-255` |
| pbpk_pediatric_pregnancy (CYP maturation Hill fn) + pbpk_disease_state (FDA §8.6-8.7 label text) exist | C | ✅ | `backend/.../subworkflows/pharmacology/pbpk_pediatric_pregnancy/main.nf`, `pbpk_disease_state/main.nf` |
| IND workspace = exactly 5 steps (Setup, ADMET, PBPK, Leads, Document); per-project pipeline data fetched, DEMO_* is only initial-load fallback | C | ✅ | `frontend/client/src/components/ind-report/IndSteps.tsx`; `pages/ind-report.tsx:163-166` (pipelineData ?? DEMO_*), `fetchPipelineData` |
| INDSectionAssembler generates §2.6.1.1–§2.6.1.6, §2.6.2, §2.6.4 (3 tables), §2.6.5, §2.6.6, §2.6.7 as Markdown → DOCX via pandoc | C | ✅ | `backend/lib/galaxy/ai/drug_discovery/ind_assembly.py:1068-1211`, `_pandoc_convert()` ~3691 |
| §2.6.1 Pharmacology + §2.6.4 tabulated summary are FULL generation (not stubs) | C | ✅ | `ind_assembly.py` `_section_overview/_section_pbpk/_section_admet/_section_prioritization/_section_applicability_domain/_section_pharm_tabulated` |
| DOCX / Markdown / audit-trail-PDF export endpoints real | C | ✅ | `frontend/server/routes.ts` `/api/ind-report/projects/:id/document.docx|.md`; `ind_actions_router.py` (reportlab audit PDF) |
| 21 CFR 11 audit trail: SHA-256 hash chain, prev_hash link, records user/action/timestamp; e-sig TOTP (RFC 6238); immutable superseded versions | C | ✅ | `ind_assembly.py:1956-2014`; `ind_actions_router.py` sign/versions |
| Rerun-with-new-params (ADMET/PBPK) wired via RerunParamsModal | C | ✅ | `pages/ind-report.tsx:585,670-677`; `RerunParamsModal.tsx` |
| Wet-lab attachment upload (measured overrides predicted) | C | ✅ | `frontend/server/routes.ts:4731-4762` (`/attachments` multipart) |
| "Generate IND" handoff from ADMET chat result | C | ✅ | `reference/.../cro/DrugDiscoveryAction.jsx`; `/api/drug-discovery/:id/ind-assembly` proxy routes.ts:4643 |

### Drug discovery → IND — mismatches found (drafts vs. real system) & roadmap gaps (→ Appendix E)
| Item | Tier | Status | Note / evidence |
|---|---|---|---|
| Reference draft says PBPK model = "one-compartment · well-stirred liver"; real is **8-compartment Rodgers–Rowland ODE** | C | 🔧 | draft `data-ind.js` IND_PBPK.model vs `pbpk_simulation/main.nf` — draft prose is a doc bug; chapter uses the real model |
| Draft/tasklist "C16→C4 remediation" implies analogue generation; real auto-loop only tightens library filter (compound drops out) | C | 🔧 | `param_tuner.py:123-185` — chapter clarifies; do not claim analogue generation |
| Dev TOTP e-signature accepts any 6 digits (`_verify_totp`) | C | 🗺️ | `ind_actions_router.py` — chapter flags dev caveat; real MFA enroll/verify is roadmap |
| Toxicology §2.6.3 (single/repeat/genotox in-vivo) render "Awaiting GLP data" placeholder without wet-lab data | C | 🗺️ | `ind_assembly.py` `_section_2631_single_dose` etc. — partial, honest |
| Non-FDA region section rendering returns `not_implemented` | C | 🗺️ | `ind_actions_router.py` `/sections/render` |
| "Submit to FDA" button disabled — no submission endpoint | C | 🗺️ | `IndSteps.tsx`; IND honest audit 20260603 |
| NDA-fetch (NDA → PK params) honestly disabled ("coming soon") | C | 🗺️ | `IndSteps.tsx`; no scraper |
| No manuscript "Stage 6" — IND ends at DOCX; post-assembly edit is a user edit flow only | C | ✅ (confirmed absent) | `IndSteps.tsx` (5 steps), `ind_assembly.py assemble()`; matches prior trace note |
| PBPK reference set = 30 marketed drugs (smaller than 100–300 full-regulatory sets) | C | 🗺️ | `pk_marketed_drugs.json`; stated as-is in chapter |
| Analogue / de-novo generation as remediation | — | 🗺️ | not built — Appendix E |

## Recently shipped features to fold into the modules (already verified this session)
| Feature | Where | Status | Evidence |
|---|---|---|---|
| Search evidence: retrieval transparency + conflicts (CitationPanel wired to live answer) | I03 | ✅ C (+abstract/relevance ✅ L) | citation-panel.tsx; research_agent retrieval/conflicts; live research_query returns relevance_score 5/5 |
| Projects: Notes vs Instructions split + plans list | I04 | ✅ C | project-routes.ts (plans list, notes-list); project-detail.tsx |
| Outputs: in-app single-cell UMAP/cluster/marker panel | I08 | ✅ C (⏳ L: needs scRNA run to populate sidecar) | single-cell-summary.tsx; scrnaseq_standard_endtoend STAGE 6.5 (fail-soft) |
| Outputs: rich viewer in after-run (StepOutputPreview) + findings→output click | I08 | ✅ C | AfterRunReport.tsx OutputsTab; FindingsCard onOpenOutput |
| Files: dataset object header shows quality pill (Good/Watch/Blocked) + version count (identity not hidden behind tabs) | I05 | ✅ C | dataset-object.tsx header (profile.quality + dataset.versions); tsc + data-hub tests green |
| Interactive tools honesty gate (RStudio/Jupyter hidden when unprovisioned) | I08 | ✅ L | /api/interactive/available returns available:false on dev → buttons drop |
| Reports: versioning + reproducibility record (checksums/software/citations) | I09 | ✅ C | report-version-store.ts; AfterRunReport ReproducibilityRecordTab |
| Re-run from after-run report (handler wired) | I06/I09 | ✅ C | chat-with-artifacts.tsx:447 biomate:run-again-with-edits |

## Known coverage gaps (→ Appendix E, do NOT document as present)
| Item | Note | Source |
|---|---|---|
| Interactive tools (RStudio/Jupyter/CellxGene) launch | 400 on dev — not provisioned in the Galaxy toolbox | dev probe 2026-09-19 |
| Somatic variant calling (Mutect2 full chain) | coverage-gap tracked | 20260701_TESTER_GUIDE_21_USE_CASES.md |
| FAERS pharmacovigilance | coverage-gap tracked | tester guide |
| GWAS→scRNA→eQTL target chain | verify it runs before documenting | 20260718_CONFERENCE_BD_X_WORKFLOW_PRIORITY.md |
| T17–T21 (Foldseek, MMseqs2, MD, AF-Multimer, atlas integration) | UNVERIFIED / smoke-test-gated | 20260817_COMPARISON_TASKLIST_REPRESENTATIVE_USECASES.md |
| Cryo-EM ensemble→cryptic-pocket mega-chain | does not run — exclude | synthesis 2026-09-19 |
| Manuscript assembler (Stage 6) | not built | trace 2026-09-18 |
