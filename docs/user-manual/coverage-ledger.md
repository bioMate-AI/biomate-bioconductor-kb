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

## Transcriptomics (bulk RNA-seq)
Chapter: `docs/user-manual/domains/transcriptomics.md` (P1, D3). All claims below are code-verified (C)
by reading source; live AWS Batch numeric re-runs are marked L / ⏳ and were NOT fired.

| Chapter / claim | Tier | Status | Evidence / bug ref |
|---|---|---|---|
| Chain `bulk_rnaseq_de_analysis` (transcriptomics): nf-core/rnaseq → nf-core/differentialabundance → clusterProfiler GSEA, with real step→step file hand-off (counts_matrix→counts, de_results→gene_list) | C | ✅ | `backend/scripts/index_all_workflows.py:474-507` (steps + connections); DB `workflow_chains` |
| Step 1 = `nf-core/rnaseq` id **1491**; defaults `aligner=star_salmon`, `genome=GRCh38` | C | ✅ | DB `workflows` id 1491; `backend/biomni_workflows/nfcore/rnaseq/main.nf:12,14`; params_template `index_all_workflows.py:482` |
| Step 2 = `nf-core/differentialabundance` id **1497**; DESeq2 (`method=deseq2`); accepts a `matrix` (count-matrix entry point) | C | ✅ | DB id 1497; `backend/biomni_workflows/nfcore/differentialabundance/main.nf:9 (matrix),16 (normalisation_method='deseq2')`; params_template `index_all_workflows.py:483` |
| Step 3 = `clusterprofiler_gene_set_enrichment_analysis` id **12956**; GO/KEGG/Reactome; clusterProfiler + `org.Hs.eg.db` | C | ✅ | DB id 12956; `backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/clusterprofiler/gene_set_enrichment_analysis.nf`; params_template `index_all_workflows.py:484` |
| Count-matrix DE (freemium fast lane) is a real entry point — differentialabundance takes counts directly; downstream-only chain `bioc_bulk_rnaseq_de_v2` documented | C | ✅ | `differentialabundance/main.nf:9`; `differentiate_ambiguous_chains.py:62-75` |
| Routing keywords for bulk DE chain (DE-intent / processed-input / downstream terms) | C | ✅ | `backend/lib/galaxy/ai/unified_workflow_search.py:2602-2619` |
| Bulk-vs-single-cell guard: single-cell prompts must NOT route to bulk chain; enforced by `_chain_multimodal_context_compatible()` requiring scRNA context terms | C | ✅ | `unified_workflow_search.py:2620-2657` (in-code comment: "share vocabulary but describe completely different assays") |
| FASTQ-alone → nf-core/rnaseq (not the DE chain) is a guarded regression | C | ✅ | `backend/tests/test_workflow_retrieval_semantic.py:356-366` |
| Three bulk-DE chains differentiated by entry point/shape: `bulk_rnaseq_de_analysis` (nf-core prod), `bulk_rnaseq_consensus_de_bioc` (bare-R), `bioc_bulk_rnaseq_de_v2` (count-matrix downstream) | C | ✅ | `backend/scripts/differentiate_ambiguous_chains.py:31-75` |
| Microarray/continuous → limma (not DESeq2/edgeR count model) is the correct disambiguation | C | ✅ | `reference/claude_design/tutorials-work/Bioconductor Tutorial Scenarios.md:24,58,108-112` (design ref); count-model requirement inherent to DESeq2 |
| QC gate: STAR uniquely-mapped **≥70%** (70 pass / 50-70 advisory / <50 fail) — CODE-ENFORCED | C | ✅ | `backend/lib/galaxy/jobs/qc_trace_monitor.py:4589` (default 70.0 STAR_ALIGN); `backend/config/qc_evidence.yaml:1665-1669` (ENCODE-anchored) |
| QC gate: Salmon mapping rate — tutorial says ≥70% but CODE DEFAULT IS **50%** (mismatch; chapter states code truth) | C | 🔧 | `qc_trace_monitor.py:4625` (default 50.0 SALMON_QUANT) vs `Tutorial Demo Scenarios 7-domain.md:77` (70%) — doc-vs-code mismatch, documented honestly |
| DESeq2 sample-distance "clear clusters" is VISUAL/ADVISORY (diagnostic plot produced, no automated 2-cluster pass check) | C | ✅ | no gate in `qc_trace_monitor.py`; plot noted `qc_evidence.yaml:1715-1725`; tutorial `Tutorial Demo Scenarios 7-domain.md:78` |
| No bulk-RNA auto-loop/auto-remediation (unlike ADMET) — QC fails surfaced for manual metadata/reference fix + re-run | C | ✅ | absence confirmed; only ADMET autoloop wired (`autoloop_bridge.py`) |
| Output viewers: MultiQC html→HTML iframe; volcano/heatmap png/pdf→image/PDF; DE table csv/tsv→table (200-row preview+download); enrichment csv→table | C | ✅ | `frontend/client/src/components/step-output-preview.tsx:66-105,209-280,966-976` |
| Worked example GSE49712 (SEQC/MAQC-III): ERCC spike-in ground truth; ~8,400 DEGs, ~92% ERCC recovery, AUC-ROC≥0.95, cell-cycle KEGG top | C (spec) | ✅ (L ⏳: live Batch numeric re-run) | `evaluation/tutorial_demos/gold_standards.yaml:5-15`; `Tutorial Demo Scenarios 7-domain.md:39-96`; validator `evaluation/tutorial_demos/transcriptomics.py` |
| Other bulk-RNA workflows exist (catalog only, not end-to-end documented): rnafusion 12771, rnasplice 12772, dexseq 11259, sgseq 13246/13247, circrna 12681, rnavar 12773 | C | ✅ (existence) 🗺️ (deep coverage) | DB `workflows` |

### Transcriptomics — mismatches found (drafts vs. real system) & roadmap gaps (→ Appendix E)
| Item | Tier | Status | Note / evidence |
|---|---|---|---|
| Salmon mapping-rate gate: tutorial spec says ≥70%, code default is **50%** | C | 🔧 | `qc_trace_monitor.py:4625` vs `Tutorial Demo Scenarios 7-domain.md:77` — chapter states the enforced 50% and treats 70% as an interpretive target only |
| DESeq2 sample-distance "2 clear clusters" presented as a gate in tutorial; real system produces the plot but has no automated pass check | C | 🔧 | chapter labels it visual/advisory, not an enforced gate |
| Old tutorial (20260422 §7) shows STAR+featureCounts + `mapping_rate>80%` gate for the RNA-seq DE tutorial; production chain uses STAR+Salmon (star_salmon) via nf-core/rnaseq | C | 🔧 | `docs/20260422_BIOMATE_USER_TUTORIALS.md:408-416` vs `nfcore/rnaseq/main.nf:14`; chapter follows the real star_salmon path and the code-enforced 70% STAR gate |
| Fusion / splicing / RNA-variant end-to-end worked examples + gold-standard validation | — | 🗺️ | workflows exist and route; deep per-workflow documentation is roadmap (Appendix E) |
| Bulk-RNA auto-loop remediation | — | 🗺️ | not built — QC fixes are manual; Appendix E |
| Interactive tools (RStudio/Jupyter) launch for re-analysis | L | 🗺️ | not provisioned on dev (`/api/interactive/available` → available:false); buttons hidden — shared gap row below |

## Overview / navigation (Part 0)
Pages: `overview/00-what-is-biomate.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| 4 function modules (Search&evidence, Data analysis, Design&generate, Models) + intent router | C | ✅ | `cold-start-dashboard.tsx:225-429` (COLD_MODULES) |
| Two lanes: Instant (in-chat, seconds) vs Cloud (Batch pipeline, min–hrs) | C | ✅ | `lane-preview.tsx` laneForText |
| Platform = chat at `/`; focused surfaces /files,/models,/design,/ind-report,/workflow/:id; NO /dashboard, no runs page | C | ✅ | `App.tsx:673-684`, `:608` (dashboard commented) |

## I.1 Cold start
Page: `modules/I01-getting-started-cold-start.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| Cold start renders in the empty-chat state | C | ✅ | `chat-interface.tsx:2126-2139` |
| Intent bar restates lane+domain; module cards seed the composer (do not send) | C | ✅ | `cold-start-dashboard.tsx:542-560, 639-646`; onSeed→setDraft `chat-interface.tsx:2136-2137` |
| Router returns no counts / no workflow-name list | C | ✅ | `cold-start-dashboard.tsx` header §0.5; DOMAIN_RULES `:448+` |
| GAP: no "Start"/normalized-seed button (seeds raw text); no thin launcher; no project-scope line | C | 🗺️ | `cold-start-dashboard.tsx:542` seeds q.trim(); no thin/scope UI |

## I.2 Composer
Page: `modules/I02-composer-talking-to-biomate.md`. Tier C (full row set in the agent report / chapter footer).

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| Paperclip → OS picker + drag-drop; Database icon → GalaxyDatasetBrowser (This session/Project/History/URL; 50GB chunked; URL import) | C | ✅ | `chat-input.tsx:729-757`; `galaxy-dataset-browser.tsx:428-525, 70-235` |
| Dataset chip name deep-links `/files?file=<id>` (locked by test) | C | ✅ | `chat-input.tsx:479-486`; `chat-input.dataset-references.test.tsx:39-67` |
| Instructions collapsible → `composerInstructions` (project-inherited); Experts (SkillsSelector) → `skillPackIds` from GET /api/skills (honest-empty) | C | ✅ | `chat-input.tsx:623-680`; `skills-selector.tsx:83-103,204-209` |
| Lane override chip forces Instant/Cloud → `intentOverride` | C | ✅ | `lane-preview.tsx:232-250`; `chat-input.tsx:688-707` |
| FIXED: stale comment claiming experts "NOT built here" (they are) | C | ✅ | `chat-input.tsx:615-622` corrected this session |
| GAP: chip has no quality dot/id@version/kind; no @-mention typeahead; no URL-paste/public-repo/pre-attach quality card on composer surface; no project-inherited-vs-deviated experts distinction | C | 🗺️ | `chat-input.tsx:469-494,744-757`; `skills-selector.tsx:210-264` |

## I.3 Search & evidence
Page: `modules/I03-search-and-evidence.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| Knowledge/literature/comparison → Instant lane; 4 tracks are cold-start seeds | C | ✅ | `ai_assistant.py:3131-3141`; `cold-start-dashboard.tsx:225-263` |
| Sources queried = PubMed + arXiv + Semantic Scholar (+PMC/EuropePMC full-text); live DB lookups (Ensembl/GTEx/ClinVar/OpenTargets/…) before synthesis | C | ✅ | `literature_clients.py:581-615`; `research_agent.py:106-335,463-1153` |
| Live answer mounts rich CitationPanel: retrieval transparency (real found/kept, honest-empty), conflicts (opt-in, ≥2 positions), source reader, boundary always shown, 3 exits | C | ✅ | `benchmark-evidence.tsx:479-604`; `citation-panel.tsx:485-535,687-737`; `research_agent.py:2319-2415`; `ai_assistant.py:5276-5316` |
| Citations emit abstract + relevance_score when present | C | ✅ | `ai_assistant.py:5276-5292` |
| GAP: formatted APA/BibTeX empty for literature (only workflow-tool citations); locus/recency never populated on live answers; "Save to project" = knowledge note (not versioned Files doc); Patents track has no patent corpus (returns literature); source reader is link-out only | C | 🗺️ | `benchmark-evidence.tsx:463-477,499`; `research_agent.py:1187-1193`; `literature_clients.py:581-615` |

## I.6 Running an analysis
Page: `modules/I06-running-an-analysis.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| Proposal in chat → run panel opens; Confirm & Run → executeWorkflow (AWS Batch) | C | ✅ | `chat-with-artifacts.tsx:181-184,1074,1179`; `nextflow-workflow-viewer.tsx:3011` |
| Live status via SSE `/api/workflows/:invocationId/events`; phase cards data-status | C | ✅ | `nextflow-workflow-viewer.tsx:2100,608,744` |
| Completed/failed → AfterRunReport (Summary/Outputs/Reproducibility record) in the panel; re-run via `/api/workflows/runs/:id/rerun` | C | ✅ | `chat-with-artifacts.tsx:2371,447`; `nextflow-workflow-viewer.tsx:1663` |
| A run belongs to its chat session (no standalone run page) | C | ✅ | `chat-with-artifacts.tsx:152,181` (panelWorkflowMessageId); `App.tsx:608` |

## I.5 Files & the dataset object
Page: `modules/I05-files-and-dataset-object.md`. Tier C (no mismatches).

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| Data hub at `/files`; `?file=<id>` deep-links one object; project-scoped | C | ✅ | `App.tsx:673-677`; `data-hub.tsx:167-168`; `project-file-tree.tsx:388-430` |
| File tree groups inputs/ + one folder per run; per-row QualityDot (lazy POST /api/perception/profile; green/amber/red/grey) only for profilable exts | C | ✅ | `project-file-tree.tsx:64-101,128-147,154-187` |
| Dataset header = name+type+size + quality pill + version-count chip; 6 tabs (Preview/Quality/Lineage/Consumers/Versions/Origin) + RO-Crate + Download | C | ✅ | `dataset-object.tsx:180-278` |
| Quality verdict backend-computed (FASTQ Phred<20→watch, unreadable→blocked); versions append-only | C | ✅ | `data_perception.py:160-190,288-293`; `dataset-object.tsx:437-525` |
| GAP: lineage/consumers runs are static text (no clickable "Open run"); no cross-project browser | C | 🗺️ | `dataset-object.tsx:361-367,408,544-561`; `data-hub.tsx:242-278` |

## I.7 The full step view & provenance
Page: `modules/I07-full-step-view-provenance.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| StepDetail = step-as-object: provenance row + param-origin badges + rendered⇄raw + claim→output hook; honest "n/a" empty states (never fabricated) | C | ✅ | `steps/step-detail.tsx:6-18,104-138,158-182,188-242,312-337`; `nextflow-workflow-viewer.tsx:198-215` (+tests) |
| Reachable from the LIVE phase view (step "Details" button + preview "Full step view") | C | ✅ | `nextflow-workflow-viewer.tsx:769-776,3162-3173,3453-3474`; `step-output-preview.tsx:863-874` |
| GAP: after-run report Outputs tab reaches StepOutputPreview but NOT the full step view (no onOpenFullStepView) — needs per-step param data the report lacks | C | 🗺️ | `AfterRunReport.tsx:1211-1216` |
| GAP: "Re-run from here" inside StepDetail not wired on run panel (mounted without onAdjustAndRerun); re-run via step-row/report instead | C | 🗺️ | `nextflow-workflow-viewer.tsx:3465-3471` vs `:777-790` |

## I.8 Outputs, viewers & interactive panels
Page: `modules/I08-outputs-viewers-interactive.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| In-app viewer taxonomy (image/pdf/table/sequence/vcf/annotation/structure+pLDDT/density/r-object/html/text) + cryo & DL JSON-sidecar charts, honest empty states | C | ✅ | `step-output-preview.tsx:67-106,209-1167,629-731` |
| Single-cell in-app UMAP/cluster/marker panel from `<h5ad>.summary.json` (graceful fallback) | C(FE)/L | ⏳ | `viewers/single-cell-summary.tsx`; needs pipeline sidecar on a real run |
| After-run Outputs mounts StepOutputPreview; findings numbers link to their output | C | ✅ | `AfterRunReport.tsx:875,1211,958-972` |
| Interactive honesty gate: per-viewer buttons + launcher + Outputs "Explore in" row all hide when unprovisioned | C | ✅ | `use-interactive-tools.ts`; `step-output-preview.tsx:535-623`; `interactive-launcher.tsx:399-413`; **AfterRunReport InteractiveToolsRow gated this session** |
| Interactive tools do not auto-load your data (empty session) | C | ✅ | `interactive-launcher.tsx:261-273` |

## I.9 Reports & reproducibility
Page: `modules/I09-reports-and-reproducibility.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| 3-tab after-run report; Summary=FindingsCard (headline chips + findings→output links) + immutable "Run original" badge | C | ✅ | `AfterRunReport.tsx:148-152,224-282`; `findings-card.tsx:77-96,229-249` |
| Reproducibility record: params + input bindings + outputs (name/type/size/SHA-256) + JSON download; software/citations/QC hide-when-empty | C | ✅ | `AfterRunReport.tsx:1470,1500-1618`; `routes.ts:12193-12269` |
| Per-output SHA-256 real + bounded (≤25 files/≤25MB); chain-of-custody wording honesty-gated on hashedCount | C | ✅ | `reproducibility-record.ts:28,40-68`; `AfterRunReport.tsx:1740-1743,1882-1896` |
| Methods report = versioned object: server-first POST /report/versions + local fallback; v0 immutable "run original" | C | ✅ | `AfterRunReport.tsx:1310-1388`; `routes.ts:12290`; `report-version-store.ts:159-167` |
| GAP: checksums opt-in (`?checksums=1`) but default UI fetch omits it → column shows "—" until hashed on demand | C | 🗺️ | `routes.ts:12228-12263`; `AfterRunReport.tsx:1545` |
| GAP: report chat-edit (propose-diff) not built (hand-edit + Save version only); no manuscript Stage 6; no cross-run report | C | 🗺️ | `AfterRunReport.tsx:1234-1242` |

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
