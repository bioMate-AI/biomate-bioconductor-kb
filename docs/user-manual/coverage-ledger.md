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
| GAP: after-run report Outputs section reaches StepOutputPreview but NOT the full step view (no onOpenFullStepView) — needs per-step param data the report lacks | C | 🗺️ | `AfterRunReport.tsx:1211-1216` |
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
| two-tab after-run report; Results-tab banner=FindingsCard (headline chips + findings→output links) + immutable "Run original" badge | C | ✅ | `AfterRunReport.tsx:148-152,224-282`; `findings-card.tsx:77-96,229-249` |
| Reproducibility record: params + input bindings + outputs (name/type/size/SHA-256) + JSON download; software/citations/QC hide-when-empty | C | ✅ | `AfterRunReport.tsx:1470,1500-1618`; `routes.ts:12193-12269` |
| Per-output SHA-256 real + bounded (≤25 files/≤25MB); chain-of-custody wording honesty-gated on hashedCount | C | ✅ | `reproducibility-record.ts:28,40-68`; `AfterRunReport.tsx:1740-1743,1882-1896` |
| Methods report = versioned object: server-first POST /report/versions + local fallback; v0 immutable "run original" | C | ✅ | `AfterRunReport.tsx:1310-1388`; `routes.ts:12290`; `report-version-store.ts:159-167` |
| GAP: checksums opt-in (`?checksums=1`) but default UI fetch omits it → column shows "—" until hashed on demand | C | 🗺️ | `routes.ts:12228-12263`; `AfterRunReport.tsx:1545` |
| GAP: report chat-edit (propose-diff) not built (hand-edit + Save version only); no manuscript Stage 6; no cross-run report | C | 🗺️ | `AfterRunReport.tsx:1234-1242` |

## I.4 Projects, instructions & collaboration
Page: `modules/I04-projects-instructions-collaboration.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| Projects user-owned; cross-user → 404 (existence not leaked); ensureLtmUser bootstrap | C | ✅ | `project-routes.ts:11-13,278,304,195,222` |
| Standing instructions → `researchGoal` (agent-read, injected as "Research goal"); Notes = human-only `user_notes` NEVER injected; "Promote ↑" appends | C | ✅ | `project-detail.tsx:907-921,956-961,443-461`; `routes.ts:6061-6099` |
| Plans: GET-list + POST(owner/editor, 403 viewer) + GET-by-id; card on project-detail | C | ✅ | `project-routes.ts:870-929`; `project-detail.tsx:1025-1075` |
| Roles = owner/editor/viewer (no "member"); collaboration tier-gated (402 TEAM_REQUIRED) | C | ✅ | `project-detail.tsx:73-77`; `project-routes.ts:151-163` |
| GAP: owner-transfer has backend (PATCH /owner) but NO UI; share-link expiry honored but no create-UI | C | 🗺️ | `project-routes.ts:762-791`; `project-detail.tsx` (no control) |

## I.10 Models
Page: `modules/I10-models.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| `/models` → ModelsPanel (focused panel, not the chat run-panel); 5 tracks (Train·House style·Rounds·Run a model·Registry) | C | ✅ | `App.tsx:654-660`; `models-panel.tsx:41-47` |
| Registry lists BioNeMo (Boltz-2/AF2/OpenFold2/Evo2) + custom scorers, honest-empty; Run a model = live inference (labelled stub when NIM unreachable) | C | ✅ | `models_inference.py:201-247,888-944,972-998` |
| House style: read DPO pairs + "Re-train on my edits" queues a real tracked job | C | ✅ | `models_inference.py:521-672` |
| GAP: 3 of 5 tracks read-only — no "start training"/"launch loop" control on the panel; cold-start advertises Train/Adapt/Optimise | C | 🗺️ | `models_inference.py:487-514`; `models-panel.tsx:16-19` |

## I.11 Design & generate
Page: `modules/I11-design-and-generate.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| `/design` → DesignGenerate; small-molecule generate→predict→optimise→rank in one round (RDKit BRICS); objectives molecule-derived; safety gate real; affinity/hERG NOT fabricated | C | ✅ | `App.tsx:662-668`; `generation.py:156-262,269-414` |
| Results in-panel (HitGrid, Pareto, re-rank, order-sheet); NOT a chat/I.6 run (no SSE/after-run/files object) | C | ✅ | `DesignGenerate.tsx:1852-1900` |
| GAP: peptide/biologic modalities gated (forms render, generators not wired); entry chips navigate-only; reinvent4_lead_design is a separate chat-routed workflow | C | 🗺️ | `DesignGenerate.tsx:1523,1539,1747-1757`; `generation.py:96-111` |

## I.12 Connectors & skills
Page: `modules/I12-connectors-and-skills.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| Connectors = primary nav item opening ConnectorsDialog; 2 tabs (Scientific Databases ~64, AI & Platforms); declared-facts model + per-connector scope (localStorage) | C | ✅ | `app-sidebar.tsx:251-262,482`; `connectors-dialog.tsx:75-217,279-284` |
| Skills/experts via SkillsSelector → GET /api/skills → thread `skillPackIds`; honest-empty | C | ✅ | `skills-selector.tsx:83-103,204-209`; `chat-input.tsx:271-287`; `ai_assistant.py:6291-6319` |
| GAP: Skills tab in the dialog commented out (0 entries); Connectors in nav not Settings (spec) | C | 🗺️ | `connectors-dialog.tsx:65,524-526` |

## I.13 Billing & quotas
Page: `modules/I13-billing-quotas-two-lane-cost.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| `/billing` reads /api/billing/usage (LLM/compute/storage/total, zeros-on-Redis-fail) + /quota (quota_usd/used/pct/over) | C | ✅ | `App.tsx:614-618`; `billing_router.py:187-290` |
| Flat-tier + internal quota (DEFAULT_PLAN_LIMITS free/premium/team/enterprise); Stripe + Redis ledger; Lago off | C | ✅ | `quota_enforcer.py:40-49`; CLAUDE.md billing |
| Two-lane cost model (Instant light / Cloud billed); pre-run panel shows NO per-run estimate (CostEstimateBadge off) | C | ✅ | `nextflow-workflow-viewer.tsx:445-476` |

## Screenshots captured (live from dev)
| Asset | Surface | Status |
|---|---|---|
| i01-1-cold-start.png | cold start (4 modules + intent bar + composer) | ✅ wired overview/I.1 |
| i05-0-data-hub.png · i05-1-file-tree.png · i05-2-dataset-header.png · i05-3-quality-tab.png | data hub picker · file tree · dataset object · quality tab | ✅ wired I.5 |
| i10-1-models.png · i11-1-design.png · capabilities.png | models · design · capabilities | ✅ wired I.10/I.11 |
| Run-dependent shots (after-run report, outputs, full step view) | need a completed run | ⏳ placeholders kept (not faked) |

## Domain: Cryo-EM
Page: `domains/cryo-em.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| Live pipeline `cryosparc_standard_spa` (23 steps): patch motion/CTF → blob+template pick → 2D×2 → ab-initio → homo→local-CTF→NU refine → FSC → local-res → sharpen | C | ✅ | `.../cryo_em/cryosparc_standard_spa/main.nf:7-31,680,841,978,2162,1420,1505,2654,2725,2476,2907` |
| FSC 0.143 gate ≤4Å pass / 4–8 advisory / >15 FAIL (metric GOLD, cutoffs SILVER); CTF fit-quality ≥0.70 + 0.5 red-line | C | ✅ | `main.nf:2631-2640`; `qc_evaluator.py:77`; `qc_trace_monitor.py:41-45`; `qc_evidence.yaml:740-758` |
| MISMATCH: tutorial "MotionCor2/Topaz/DeepEMhancer, CTF>0.2, GSFSC<3.5Å, hetero-refine" ≠ code (CryoSPARC-native, ≥0.70, ≤4Å, no hetero) — chapter uses code truth | C | 🔧 | narrative vs code |
| GAP: EMPIAR-10025 gold missing from gold_standards.yaml; cryo autoloop not wired to live executor; cryo-ET + cryptic-pocket mega-chain excluded | C | 🗺️ | `gold_standards.yaml`; `backend/experiments/cryo_em_autoloop/` |

## Domain: Single-cell RNA-seq
Page: `domains/single-cell.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| `scrnaseq_standard_endtoend` 7 stages + outputs (annotated.h5ad, celltypes/markers/qc csv, umap png); STAGE 6.5 fail-soft summary.json sidecar powers the in-app panel | C | ✅ | `.../single_cell/scrnaseq_standard_endtoend/main.nf:47-193,66-69,132-172` |
| Bulk-vs-single-cell routing guard; pseudobulk DE is the correct cross-condition path | C | ✅ | `unified_workflow_search.py:2620-2657` |
| MISMATCH: `.nf` max_pct_mito=20% vs evidence 10% for most tissues — chapter documents code truth + tip | C | 🔧 | `main.nf:39` vs `qc_evidence.yaml:1460` |
| In-app single-cell panel on real runs needs the sidecar (data-gated) | C(FE)/L | ⏳ | `single-cell-summary.tsx`; no live scRNA run fired |

## Domain: Variant calling / genomics
Page: `domains/variant-calling.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| Germline: gold chain `bioc_variant_annotation_workflow` (sarek id 1493 → VariantAnnotation → filter → maftools); full `Wgs Germline Gatk` id 10685 (14 steps); DeepVariant id 1805 | C | ✅ | DB ids; `nfcore/sarek/main.nf:12-15,47-112`; `wgs_germline_gatk/main.nf:10-25` |
| QC gates CODE-ENFORCED: mapped ≥70%, dup ≤40% (profile-overridable), coverage ≥30× WGS/50× WES | C | ✅ | `qc_trace_monitor.py:4640,4649,4773-4790,147-151` |
| MISMATCH: Ts/Tv 1.8–2.2 is in-pipeline ADVISORY not a gate; hard-filter (not VQSR) is single-sample default | C | 🔧 | `wgs_germline_gatk/main.nf` MULTIQC; `qc_evidence.yaml` |
| GAP: SOMATIC (Mutect2 tumor-normal) = coverage gap — workflows exist+route (1771/1779/1744/10608) but NO chain, NO gold demo | C | 🗺️ | no somatic `workflow_chains`/`gold_standards` entry; TESTER_GUIDE Q16 |

## II.1 Workflow catalog & routing
Page: `data/II01-workflow-catalog-and-routing.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| Catalog = galaxy_ai_tools.db (workflows + workflow_chains w/ connections); routing = hybrid LLM-browse + BGE dense + FTS; bulk-vs-single-cell guard; disambiguation card; indexed-preferred + generated fallback | C | ✅ | `index_all_workflows.py:845-883,473-507`; `unified_workflow_search.py:825,2638`; `ai_assistant.py:4600-4613,5032-5134` |
| MISMATCH: live catalog = **4,200 workflows / 42 domains / 70 chains**, NOT "2,455/34" (CLAUDE.md, tools_manifest.py:118) nor "4,017/36" (MCP blurb) | C | 🔧 | direct DB count; stale strings → Appendix E |

## II.2 Public datasets & accession resolver
Page: `data/II02-public-datasets-accession-resolver.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| `resolve_accession` supports GEO (→ id 10672) + SRA/ENA/DDBJ/BioProject/ArrayExpress (→ nf-core/fetchngs id 12704); unmatched→422; fetch runs in-workflow on Batch; From-URL import registers hosted data | C | ✅ | `routes.ts:8552-8595,8610-8621`; `galaxy-dataset-browser.tsx:585`; `routes.ts:3599` |
| GAP: PDB/EMDB/PRIDE/MassIVE + UniProt/Ensembl/ChEMBL/dbSNP/ClinVar detected for VALIDATION only, NOT resolvable (422); dbGaP absent | C | 🗺️ | `nextflow_executor.py:576-709` |
| MISMATCH: a 2nd `/api/accession/resolve` (with PDB/EMDB) is shadowed DEAD CODE (Express serves the first handler) | C | 🔧 | `routes.ts:16771-16835` vs `:8532` |

## Screenshot-audit fixes (from live dev screenshots, 2026-09-19)
| Fix | Where | Status | Evidence |
|---|---|---|---|
| Reproducibility record: "Compute checksums" control (SHA-256 was "—" — UI never sent ?checksums=1) | I.9 | ✅ | `AfterRunReport.tsx` ReproducibilityTab (computeChecksums) |
| Record: workflow-name + completed-timestamp fallbacks (was "Untitled Workflow"/"—") | I.9 | ✅ | `reproducibility-record.ts:137-150` |
| Perception panel: FASTQ → Reads/Read length (bp), FASTA → Sequences/Length (bp) (was Rows/Columns) | I.5 | ✅ | `data-perception.tsx` (rowLabel/colLabel) |
| Dataset header quality pill verified rendering live (amber "Watch") | I.5 | ✅ L | dev capture i05-2 post-sync |
| Models Train copy no longer implies a missing "Start" button (train via chat) | I.10 | ✅ | `models-panel.tsx:365` |

## II.3 Literature & evidence retrieval
Page: `data/II03-literature-and-evidence-retrieval.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| Sources = PubMed + arXiv + Semantic Scholar only (no patents); parallel search_all + per-source rate limits; PMC/Europe PMC full-text (~6000-char cap) for synthesis | C | ✅ | `literature_clients.py:581-650,82-100,411-427`; `research_agent.py:106-217,220-290` |
| Live DB lookups before synthesis (Ensembl/GTEx/ENCODE/ClinVar/MyGene/GWAS/OpenTargets/Monarch); query-widening ≤6; found/kept by identity; conflicts ≥2 positions | C | ✅ | `research_agent.py:463-1041,834-871,2319-2353,2355-2415` |
| Benchmark-evidence card opt-in, honest-empty, ≥0.5 similarity floor | C | ✅ | `research_agent.py:2008-2044`; `benchmark_knowledge.py:351-407` |
| GAP: no patent/FTO corpus; formatted BibTeX only for tool citations (literature APA-only); locus/recency unpopulated; full-text not rendered in reader | C | 🗺️ | `literature_clients.py:581-593`; `research_agent.py:1176-1193` |

## II.4 Reference data & indexes
Page: `data/II04-reference-data-and-indexes.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| Genome build param + regex detection + alias normalisation + pre-wired iGenomes FASTA & GATK known-sites (no upload) | C | ✅ | `nfcore/rnaseq/main.nf:12`; `ai_assistant.py:2527-2563,2535-2549` |
| AlphaFold-DB fetch-by-accession client + indexed workflows (id 12647/14469); Foldseek (id 14456) + MMseqs2 (id 14462) wired & indexed | C | ✅ | `alphafold_client.py:14-121`; `alphafold_db_search/main.nf`; `mmseqs2_sequence_search/main.nf`; DB ids |
| MISMATCH: FAERS is WIRED + indexed (id 11363) — contradicts prior "coverage-gap" notes/CLAUDE.md; not yet E2E-verified | C | 🔧 | DB id 11363; `bioconductor/faers/main.nf` |
| GAP: Foldseek/MMseqs2/MD/AF-Multimer (T17–T20) E2E UNVERIFIED; no local Foldseek/AF-DB copy; DepMap/BindingDB = snapshot wrappers not live API | C | 🗺️ | `run_phase1.py:76-88` |

## II.5 Memory & project knowledge
Page: `data/II05-memory-and-project-knowledge.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| `<project_context>` injects name/desc/research_goal/instructions + ≤8 project_instruction rows @≤300 chars; project-scoped; does NOT read user_notes/notes_synthesis | C | ✅ | `routes.ts:6062-6100` |
| Memory = project-scoped knowledge + episodic; recall_memory reads session summaries only (not knowledge rows) | C | ✅ | `memory-integration.ts:103-165`; `routes.ts:17040-17042,7765-7800` |
| FIXED (safety): LTM memory-hint path (`addMemoryHints`) injected top-2 knowledge rows UNFILTERED → a user_notes snippet could leak. Now filtered via `filterModelVisibleKnowledge` (excludes user_notes + notes_synthesis); unit-tested | C | ✅ | `memory-integration.ts:324`; `memory-knowledge-filter.ts` + `.test.ts` (this session) |

## II.5 — notes trust boundary (fixed this session)
The Notes UI promises user_notes are "not read by the assistant" (I.4). The explicit
`<project_context>` path honored that, but `addMemoryHints` did not — it pulled the top-2
knowledge rows unfiltered, so a `user_notes` (or `notes_synthesis`) title/snippet could surface in a
"[Memory: Project knowledge …]" hint. Fixed: extracted `filterModelVisibleKnowledge`
(`memory-knowledge-filter.ts`), applied it in the hint path, and locked it with a unit test.

## Domain: Structural biology
Page: `domains/structural-biology.md`. Tier C. (IDs verified by direct DB query.)

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| Structure prediction (Boltz-2 id 12853 / AF2 / OpenFold2 via BioNeMo) + AF3 predict→dock chain (Structure Prediction Docking id 10644 → DiffDock‖Vina); docking Vina id 12824 — all SUPPORTED | C | ✅ (L ⏳) | `bionemo_client.py:65-116`; `boltz_structure_prediction/main.nf`; `structure_prediction_docking/main.nf`; DB ids |
| QC: pLDDT ≥70 (GOLD, Jumper 2021) / confident-frac ≥0.70 / max-PAE ≤8Å (SILVER); Vina >−7 kcal/mol (BRONZE); in-app 3Dmol + pLDDT chart | C | ✅ | `qc_evidence.yaml:330-412`; `step-output-preview.tsx:1032-1167` |
| GAP: Foldseek(14456)/MMseqs2(14462)/GROMACS-MD/AF-Multimer wired but E2E-UNVERIFIED (do NOT claim MD works); PaeHeatmap built but not routed; no MolProbity; no auto-loop | C | 🗺️/🔧 | `run_phase1.py:76-88`; `viewers/pae-heatmap.tsx` (unrouted) |

## Domain: Pharmacology & clinical
Page: `domains/pharmacology-clinical.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| NCA (nca_pknca id 10642), PopPK (nonmem_poppk id 12918, nlmixr2 fallback + VPC), BOIN (clinical_trial_simulation id 14511), PGx (id 12876) — SUPPORTED | C | ✅ (L ⏳) | respective `main.nf`; `qc_gate_reader.py:113-139` |
| PGx maps PRE-CALLED diplotypes → CPIC (NOT star-allele calling from VCF) | C | 🔧 | `pharmacogenomics_pgx_report/main.nf:8-19` |
| FAERS (id 11363) WIRED + indexed but demo-shaped (2004Q1 + insulin, needs pre-standardized RDS), E2E-unverified | C | 🔧 | `bioconductor/faers/main.nf:74-135` (id confirmed via DB query) |
| GAP: star-allele-from-VCF, general FAERS service, mechanistic DDI, one-click PopPK→MTD; no pharm gold dataset | C | 🗺️ | Appendix E; `gold_standards.yaml` (absent) |

## Domain: Multi-omics & systems biology
Page: `domains/multi-omics.md`. Tier C (+ recorded live run).

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| MOFA2 (id 11853) + SNF (id 14639) + omics_normalize real; universal `omics` input contract; method-selection from data shape | C | ✅ | `bioconductor/mofa2/main.nf`; `snf_multiomics/main.nf`; `integration_planner.py:27-38` |
| Worked example: Dietrich CLL normalize→MOFA2 (runs af1f0a1f/7e8979d1 SUCCEEDED); Factor-1 vs IGHV AUC 0.962; MOFA2>SNF (ARI 0.526 vs 0.375) | C + L | ✅ | `docs/20260811_MULTIOMICS_PIPELINE_LIVE_RUN.md` |
| GAP: GWAS→scRNA→eQTL chain "runs but capability-incomplete" (no coloc/PP4 — binary gate; hardcoded demo scRNA; not DB-registered) → NOT supported; one-click MULTIOMICS_ROUTING default-OFF; curated MOFA+ 4-step chain not live-verified | C | 🔧/🗺️ | `gwas_scrna_eqtl_target_chain/main.nf`; `ai_assistant.py:4234` |

## Domain: Epigenomics (ChIP-seq / ATAC-seq)
Page: `domains/epigenomics.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| Chain `bioc_chipseq_annotation_v2` = ChIPseeker(11090)→clusterProfiler(11122); nf-core/chipseq(1492)/atacseq(12673) are pre-steps; DiffBind(11262), HOMER(10667) | C | ✅ | `bioc_chain_templates.py:184-228`; DB ids |
| ATAC gates code-enforced HALT: TSS≥5, FRiP≥0.2, NRF≥0.9, peaks≥1000; ChIP FRiP is advisory-only (tutorial "FRiP≥0.20 gate" is wrong for ChIP) | C | ✅/🔧 | `qc_trace_monitor.py:4832-4872,4810-4827` |
| GAP: narrowPeak/broadPeak → download (not table viewer); NSC/peak-range spec-only; validator `epigenomics.py` absent from repo | C | 🗺️ | `step-output-preview.tsx:66-105`; `evaluation/tutorial_demos/` (only transcriptomics.py) |

## Domain: Proteomics (DIA / label-free)
Page: `domains/proteomics.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| Gold chain `bioc_proteomics_de_v2` = MSnbase(11894)→limma(11697); front-ends diaproteomics(1495)/proteomicslfq(1496); DEqMS(11248); msqrob2 DIA | C | ✅ | `bioc_chain_templates.py:318-358`; DB ids |
| Code-enforced QC: PSM+protein FDR<1% (GOLD/HALT), CV≤20/15% DDA/DIA, missed-cleavage≤20%, missing-value≤30%; 4 profiles | C | ✅ | `qc_trace_monitor.py:4915-5061` |
| MISMATCH: prompt "DIA-NN→MaxLFQ→DEqMS/limma" ≠ real chain; DIA-NN/MaxLFQ NOT standalone workflows (surface via diaproteomics/msqrob2); validator `proteomics.py` absent | C | 🔧/🗺️ | DB; `evaluation/tutorial_demos/` |

## Domain: Metabolomics (untargeted LC-MS)
Page: `domains/metabolomics.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| Chain `lcms_metabolomics_consensus` = xcms(12631)→CAMERA(11032)→biosigner(10990); NMR path ASICS(10905); HMDB via separate biodbHmdb(10977) | C | ✅ | `chain_composer/proposed_chains/lcms_metabolomics_consensus.json`; DB ids |
| GAP: metabolomics has ZERO code-enforced QC gates (no parser/verdict/qc_evidence entry) — all QC advisory/spec; validator `metabolomics.py` absent | C | 🔧/🗺️ | absence in `qc_trace_monitor.py` + `qc_evidence.yaml` |

## Domain: Metagenomics (profiling / MAG)
Page: `domains/metagenomics.md`. Tier C.

| Chapter / claim | Tier | Status | Evidence |
|---|---|---|---|
| Chain `shotgun_metagenomics_to_mag` = CONCOCT(10499)→MMseqs2(10541)→PathoStat(12019), starts from assembled contigs; profiling Kraken2/Bracken(1807)/MetaPhlAn(1811) separate | C | ✅ | `chain_composer/proposed_chains/shotgun_metagenomics_to_mag.json`; DB ids |
| Read-classification % gate <30 HALT/<60 warn (profiling only, Wood 2019) | C | ✅ | `qc_trace_monitor.py:4874-4909` |
| GAP: CheckM2/MetaSPAdes/MEGAHIT/MetaBAT/MaxBin/AMBER NOT catalog workflows; bin completeness/CAMI recovery spec-only; assembly is a prerequisite; validator `metagenomics.py` absent | C | 🗺️ | DB; `evaluation/tutorial_demos/` |

## Appendices A–F
Pages: `appendix/A-glossary.md … F-api-cli-quickref.md`. Compiled from this ledger + cited source (step-output-preview taxonomy, qc_evidence.yaml, tools_manifest.py). Appendix E is the 1:1 sweep of every 🗺️/🔧 row (the honest "not yet supported" counterweight). Cross-cutting: domain validator scripts (epi/prot/metab/metag).py absent from repo — only transcriptomics.py exists → all P2 gold numbers are C-spec, L ⏳.

## Known coverage gaps (→ Appendix E, do NOT document as present)
| Item | Note | Source |
|---|---|---|
| Interactive tools (RStudio/Jupyter/CellxGene) launch | 400 on dev — not provisioned in the Galaxy toolbox | dev probe 2026-09-19 |
| Somatic variant calling (Mutect2 full chain) | coverage-gap tracked | 20260701_TESTER_GUIDE_21_USE_CASES.md |
| FAERS pharmacovigilance | WIRED + indexed (id 11363) — NOT a gap; pending E2E verification | II.4 finding 2026-09-19 |
| GWAS→scRNA→eQTL target chain | verify it runs before documenting | 20260718_CONFERENCE_BD_X_WORKFLOW_PRIORITY.md |
| T17–T21 (Foldseek, MMseqs2, MD, AF-Multimer, atlas integration) | UNVERIFIED / smoke-test-gated | 20260817_COMPARISON_TASKLIST_REPRESENTATIVE_USECASES.md |
| Cryo-EM ensemble→cryptic-pocket mega-chain | does not run — exclude | synthesis 2026-09-19 |
| Manuscript assembler (Stage 6) | not built | trace 2026-09-18 |
