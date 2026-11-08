# BioMate Internal Evidence Base & Manuscript Inventory

Scope: read-only survey of `/Users/kky/biomate-review`. All citations are repo file paths.
Labels: **Evidenced** = committed measurements / live run IDs; **Partial** = verified on
idealized/known-answer inputs or single datasets, or real but with major caveats;
**Aspirational** = planned, designed-not-run, or asserted without committed data.

## (A) Evidenced differentiators vs aspirational claims

### Takeaway
BioMate's strongest, data-backed claims are (1) the **orchestration/retrieval harness** (routing
0.965 same-item vs 0.345–0.615 for direct LLMs) and (2) a **broad, structure-validated workflow
knowledge base**. Production execution on AWS Batch is real but validation is **uneven** across
domains. The on-prem domain-LLM story is now, by the team's own fresh analysis, mostly a
**harness-context / cost-compliance** result, NOT a model-capability win. CRO/IND, Chinese UI, and
cyclic-peptide are largely **Partial/Aspirational**. The team's own docs are unusually candid about
these limits.

### Cited Findings — per differentiator

**1. Production execution (real Nextflow/nf-core on AWS Batch, live SSE, QC auto-loop gate) — EVIDENCED (infra) / PARTIAL (breadth of validated domains)**
- Live AWS Batch production-path run proof for proteomics MS/MS search: run `fb3440ec-6ef0-43f4-be39-5e249e7bc1b6`, three per-tool containers (DECOYDATABASE→SAGE→MOKAPOT, all SUCCEEDED); 35,821 Sage PSMs → 1,145 Mokapot PSMs / 136 peptides @1% FDR — `docs/20260822_FLAGSHIP_REALBIO_STATUS_AND_PLAN.md` §3c.
- Cryo-EM real benchmark runs: EMPIAR-10028 3.98 Å FSC, 7.4 h wall, $6.29, 24 CryoSPARC jobs; P52 1.78 Å (Nyquist), 4-GPU, 3.4× speedup, $0.75 — `docs/20260428_CRYO_PILOT_AND_MANUSCRIPT_PLAN.md`.
- Production dispatch path exercised live on dev: `POST /api/nextflow/execute`, executor `awsbatch`, real BioMate run id `7f46cbc7-...` + Batch jobId `73fff0de-...` — `docs/20260923_DOMAIN_VALIDATION_RESULTS.md`.
- SKEPTIC FLAG: that same metabolomics run **FAILED** (obsolete `ReplaceMin` API), after a chain of prior CSV-assembly bugs — real execution, but several domain workflows only succeed after stacked fixes — `docs/20260923_DOMAIN_VALIDATION_RESULTS.md`.
- SKEPTIC FLAG (from user memory + repo): proteomics/metabolomics/ChIP/single-cell/spatial had **no real E2E run evidence** and the "ADMET hERG gate didn't fire live" at the time of the validation-gaps audit; several tutorials were mockups — MEMORY note `project_workflow_validation_gaps`; corroborated by the bug-chains in `docs/20260923_DOMAIN_VALIDATION_RESULTS.md`.
- QC auto-loop gate / live SSE: described as required UX in `CLAUDE.md` ("UX E2E Completeness Standard", real-time SSE phase transitions, ADMET hERG QC gate) but I found **no committed E2E screenshot/log artifact in docs/ proving a QC gate fired on a live run**; BC-PARAM E2E is 8/9 pass with one soft-skip (MEMORY `project_e2e_bc_param_status`). → the *plumbing* is Evidenced; a *live QC-gate-fires-and-auto-remediates* demonstration is Partial/Aspirational.

**2. Breadth (~2,455–4,000 workflows / ~36 domains) — EVIDENCED but NUMBER IS INCONSISTENT across docs**
- `CLAUDE.md`: "2,455 workflows across 34 biological domains" (workflow DB section).
- MCP server instructions (live): "4,017 workflows across 36 domains".
- On-prem manuscript: "4,017 workflows across 36 domains" — `docs/20260918_ONPREM_DOMAIN_LLM_MANUSCRIPT.md` §1; and "4,200 workflows across 36 domains and 12,312 tools" — `docs/20260912_onprem_llm/MANUSCRIPT.md` §3.
- Structure-validated subset is independently evidenced: **15,641 executable workflow steps** from 1,970 Bioconductor packages (87.9% coverage), NAMESPACE-validated ~96%, EDAM 94.7%, Biocontainers 98.8% — `docs/papers/bioconductor_kb_paper/20260601_PAPER1_NAR_DATABASE.md`.
- SKEPTIC FLAG: the headline workflow count drifts 2,455 → 4,017 → 4,200 depending on the document; "~36 domains" is stable. The *validated* breadth (real E2E) is far smaller than the catalog count.

**3. RealBio benchmark results (orchestration/routing) — EVIDENCED (committed score.py), with disclosed conflict-of-interest**
- Cross-domain routing: BioMate (engine-free curated retrieval) **0.965 [0.930, 0.983]** vs frontier LLMs used directly 0.345–0.615 (Opus-5 0.615, GPT-5.6 0.530); n=200 — `docs/20260817_REALBIO_BENCHMARK_PAPER_DRAFT.md` §5.2.
- Honest split (flagship status doc): BioMate "leads the orchestration tasks decisively … on same-item execution tasks it is competitive, not dominant" — pbpk **ties** best LLM at 0.20 (3/15), does NOT lead; boin same-item still pending — `docs/20260822_FLAGSHIP_REALBIO_STATUS_AND_PLAN.md` §2.
- SKEPTIC FLAG (self-disclosed): the earlier pbpk "100%" headline was removed from the public leaderboard 2026-08-27 because it was a cross-harness/different-item set, not same-item — `docs/20260822_FLAGSHIP_REALBIO_STATUS_AND_PLAN.md` §2. The C0 condition gives LLMs no candidate list while BioMate uses its catalog — disclosed as "product vs deployment-default," not model-vs-model — `docs/20260817_REALBIO_BENCHMARK_PAPER_DRAFT.md` §4. BioMate is an author's own system; "not independent third-party validation" (paper §6 limitations).

**4. Routing / param / admet / pbpk / boin / stability benchmarks (CLAUDE.md targets) — MOSTLY EVIDENCED vs targets; a few below target**
Full committed matrix in `docs/20260429_BENCHMARK_MATRIX_COMPLETE.md` (run from `evaluation/results/`):
- Routing v11 94.6% (target ≥80 ✅); Param Prefill v10 84.8% (≥80 ✅, +21pp); ADMET v3 96.3% (≥70 ✅); Protocol Thresholds v4 92.5% (≥80 ✅); BOIN v6 80.0% (≥70 ✅, +39pp); PBPK v5 75.6% (≥60 ✅); Docking v2 78.9% (≥70 ✅).
- BELOW target: BixBench v5 30.0% (target ≥50 ❌); BiomniEval1 screen_gene 42.0% (≥70 ❌).
- Pharmacology validation 18/18 (100%) on FDA renal/hepatic PBPK + BRIM-3 enrichment + CSD polymorph — `docs/20260429_PHARMACOLOGY_BENCHMARK_RESULTS.md` (but these are known-answer / synthetic-realistic inputs, with documented model-limitation caveats, e.g. gabapentin 3.57× vs clinical ~5×).
- SKEPTIC FLAG: `docs/20260429_BENCHMARK_MATRIX_COMPLETE.md` itself states the big wins "came from **format/extraction bugs**, not model capability gaps" (regex fixes, prompt overrides, scoring fixes). So these are capability-of-the-*system*, achieved substantially via harness engineering.
- "stability" target (≥90%, in CLAUDE.md table): I found **no committed stability benchmark score** in the matrix docs. → Aspirational/unmeasured as a reported number.

**5. On-prem domain LLM — PARTIAL (works) but the differentiator claim is WEAKENED by the team's own fresh results**
- Three overlapping manuscripts/drafts exist (see §B). Core measured results:
- Our served 27B base is "on par with the far larger hosted Qwen3.8-Max" across the suite — `docs/20260912_onprem_llm/MANUSCRIPT.md` abstract/§5.
- **Fresh (2026-10-04):** SFT of our 9B gives **no end-to-end advantage over base** with the harness (routing 0.805 vs 0.815; param 0.657 vs 0.664); only bare-routing improves (0.285 vs 0.18) — a mode the product never uses — `docs/20260912_onprem_llm/20261004_REALBIO_LLM_VS_HARNESS.md`. Verdict: "on-prem = cost/compliance play; small-model domain-adaptation does not move the system bar."
- **Fresh (2026-10-04) routing gap:** 100% of the base-vs-frontier routing gap is SELECTION-miss (gold always in menu). The fix is a **harness-context fix** (describe candidates), model-invariant: base 9B routing 0.68 (bare names) → **0.885 (+20.5pp)** with described menu; survives paraphrase (0.675→0.900, +22.5pp) → semantic not lexical — `docs/20260912_onprem_llm/20261004_CLOSE_THE_GAP_ROUTING.md`.
- Contrastive retriever: recall@1 0.233→0.767, recall@5 0.377→0.915 (random split, leaks); honest family-holdout 0.244→0.399 @1, 0.374→0.694 @5 — `docs/20260918_ONPREM_DOMAIN_LLM_MANUSCRIPT.md` §4.
- SKEPTIC FLAG: "No end-to-end training numbers yet" — mid-training/SFT/RL require GPU; only retriever has final numbers; round-2 joint training "built but not trained" due to GPU-host failure — `docs/20260918_...MANUSCRIPT.md` §8, `docs/20260912_onprem_llm/MANUSCRIPT.md` §5/§7. A zero-delta "training didn't help" result was an **eval artifact** (adapter no-op), caught by a logit probe — same docs §5.1.

**6. Agentic decompose + orchestrate — PARTIAL (designed + grounded SFT data exists; limited live proof)**
- SFT task families include `decompose` (phase→step DAG) and `interwf_decomp` (cross-workflow parallel/sequential DAG; 74% of examples multi-phase) — `docs/20260918_ONPREM_DOMAIN_LLM_MANUSCRIPT.md` §3.2; T01–T28 task map in `docs/20260912_onprem_llm/MANUSCRIPT.md` §3.
- SKEPTIC FLAG (user memory): `run_code`/data-plane agentic tools reported "dead in live chat" on Gemini — a prompt/classification bug, model-independent — MEMORY `project_agentic_tools_gemini`. So decomposition is well-specified in training data but the live agentic-tool firing has a known defect.

**7. CRO compliance / IND narrative — PARTIAL→ASPIRATIONAL (feature set hidden in product)**
- Extensive planning/positioning docs: `docs/20260420_CRO_COMPLIANCE_UX_REQUIREMENTS.md`, `docs/20260420_PHASE2_21CFR11_COMPLIANCE.md`, `docs/20260421_CRO_COMPLIANCE_PRODUCTION_INTEGRATION.md`, `docs/20260421_CRO_USECASES_AND_E2E_TESTS.md`.
- SKEPTIC FLAG: billing nav + IND Report + CRO Library are **commented out intentionally** in the product because they crash — "do NOT propose restoring" — MEMORY `project_billing_hidden`. So the IND/CRO UX is not live. §2.6.1 DOCX narrative appears in the CLAUDE.md UX standard as a required scenario, not as a committed produced artifact.

**8. MCP / ChatGPT / Claude connectors (19-tool manifest) — EVIDENCED (contract) / PARTIAL (dev UI parity)**
- Source of truth `backend/lib/mcp/tools_manifest.py` exposes exactly **19 tools** (listed verbatim: biomate_session, search_workflow, get_workflow_spec, run_workflow, get_run, cancel_run, list_runs, watch_run, preview_file, export_report, analyze_results, explain_error, query_database, resolve_accession, browse_data, fetch_public_data, search_literature, recall_memory, upload_file) — `docs/20261003_CONNECTOR_AND_MCP_VALIDATION_AUDIT.md`.
- Dev public connector routing PASS (19 backend + 19 ChatGPT adapter routes + OpenAPI); manifest tests 31 passed; security core 80 tests passed (SELECT-only, secret redaction, SSRF blocking, ownership isolation) — same doc.
- Corroboration: the live MCP server in this very session exposes these 19 `mcp__biomate__*` tools.
- SKEPTIC FLAG: dev **browser UI is stale** — private-DB/remote-MCP forms don't render in the deployed dev bundle (deployment-parity gap); docs previously claimed 14 tools and were corrected to 19; installer version 0.1.0 vs documented external biomate-connector 2.0.0 discrepancy — same doc, release gates 1–4.

**9. Dry/wet loop + cyclic-peptide design — ASPIRATIONAL (plan + datasets staged; models not validated)**
- `docs/20260719_CYCLIC_PEPTIDE_MODALITY_TRACK.md`: `cyclic_peptide_design` workflow exists; CycPeptMPDB dataset staged to S3; macrocycle-ADMET gap identified as the intended moat.
- SKEPTIC FLAG: the permeability baseline gate was still "running"; macrocycle permeability model is "a commodity (~R² 0.3 ceiling)", only a PAMPA proxy R²≈0.23 exists, and the real moat is framed as a future "wet-lab flywheel" — MEMORY `project_peptide_pk_learning_gap`, `project_macrocycle_closedloop`. No clinical-macrocycle PK validation. Closed dry/wet loop is designed, not demonstrated.

**10. Chinese UI — PARTIAL (display-only i18n, execution-safe, but degrades input quality)**
- `docs/20260923_CHINESE_UI_BACKEND_SAFETY.md`: i18n `t()` wraps display strings only; execution safety holds (schema guardrail drops non-canonical Chinese values → never a garbage Nextflow param).
- SKEPTIC FLAG: the entire rule-based inference layer is English-regex-keyed, routing uses English-only embeddings (`bge-small-en-v1.5`) + CJK-stripping FTS + 200-entry English keyword table → a pure-Chinese query "routes materially worse"; output-localization gap (English workflow names in Chinese chrome). Fixes are a proposed plan, not shipped. So "Chinese UI" = display translation + safe-but-degraded Chinese understanding, NOT full Chinese-native routing.

### Inferences
- BioMate's defensible, data-backed differentiator is the **harness (curated catalog + retrieval + extraction rules + QC governance)**, not the LLM — stated almost verbatim by the team: "The harness is the differentiator, not the LLM" (`20261004_REALBIO_LLM_VS_HARNESS.md`) and the routing gap is "a harness-context artifact" (`20261004_CLOSE_THE_GAP_ROUTING.md`).
- Many headline benchmark numbers improved via format/extraction fixes, so they measure the *system's* reliability engineering, which is legitimate but should be positioned as "engineered reliability," not "model intelligence."
- The product's maturity is bimodal: infra + routing + KB are solid; domain E2E breadth, CRO/IND UX, wet-lab loop, and Chinese-native routing are early.

### Gaps
- No committed `stability` benchmark score found despite the ≥90% target in CLAUDE.md.
- No committed artifact (screenshot/log) found in docs/ proving the ADMET QC auto-loop gate fired and auto-remediated on a live run; CLAUDE.md treats it as a required-but-apparently-unproven standard.
- `docs/20260819_MANUSCRIPT_STATUS_FOR_TEAM.xlsx` not parsed (binary); may hold a canonical status table.

---

## (B) Manuscript inventory + gaps

### Takeaway
There are ~15+ distinct manuscript drafts/plans across six arcs: (1) **RealBio benchmark** +
**C1 flagship systems paper** (most mature, submission-form); (2) **on-prem domain LLM** (three
overlapping drafts, results incomplete); (3) **Bioconductor-KB** two-paper set (strongest real
data); (4) **autoimmune/translational M1–M5** (framework papers, explicitly "not run end-to-end on
real cohort"); (5) **cryo-EM** (one real-data paper ~70% ready, one surrogate-model paper flagged);
(6) **application notes** (anti-TNF IBD, preprocessing-QC). Pervasive honesty caveats; the biggest
gap is that the flagship/benchmark depend on BioMate grading itself and several translational papers
have no real-cohort results.

### Cited Findings — manuscript-by-manuscript

**RealBio benchmark paper** — `docs/20260817_REALBIO_BENCHMARK_PAPER_DRAFT.md`
- Title: "RealBio: an open, objectively-scored benchmark for real-world bioinformatics workflow automation." Venue: NeurIPS D&B / Bioinformatics App Note / GigaScience. Authors: Yaoyun Zhang, Andrew Dike. Status: manuscript-complete, 8 tasks (660 items), CC-BY-4.0 scorer. Core claim: open anti-self-grading cross-system benchmark; no single system dominates; BioMate routing 0.965 engine-free. Evidence: committed `score.py` on committed predictions in `evaluation/datasets/public_export/`. Gap: BioMate is authors' own system (not independent); HuggingFace publish + DOI blocked on user creds (`docs/20260822_FLAGSHIP_REALBIO_STATUS_AND_PLAN.md` §4 #1).

**C1 flagship systems paper** — `docs/20260822_FLAGSHIP_REALBIO_STATUS_AND_PLAN.md` (status doc; docx on Drive `C1_Flagship_Orchestrated_Agent_QC_Governance.docx`)
- Title theme: "BioMate: a curated, executable, governed catalog for trustworthy biomedical workflow automation" (companion to RealBio, ref 11 of the benchmark paper). Venue: Nature Methods form. Status: "structurally submission-ready," 17 verified refs, Figs 1–5, 151-word abstract, ~6,861 words. Core claim: orchestrated agent + QC governance + curated catalog. Evidence: BixBench Phylo Verified-50 92.0% vs Biomni 88.7%; BiomniEval1 71.1% macro vs Biomni-R0 66.9%. Gap: not committed as a repo .md (lives as Drive docx); BioMate cells for autofix/wf_gen/dd still "—".

**On-prem domain LLM — THREE overlapping drafts (consolidation gap):**
- `docs/20260918_ONPREM_DOMAIN_LLM_MANUSCRIPT.md` — "Building a Private, On-Premise Domain LLM for Bioinformatics Workflow Orchestration." Working manuscript. Claim: grounded SFT + paraphrase diversity (3,969→17,291) + contrastive retriever (recall@5 0.915). Status: retriever has final numbers; training/RL deferred to GPU.
- `docs/20260912_onprem_llm/MANUSCRIPT.md` — "Grounded, Leakage-Controlled Fine-Tuning of an On-Premises Multimodal LLM…" Living draft, authors TBD. Claim: transfer-failure is the central result; format-matched joint training recovers gains (routing-bare +10.5pp, param restraint −32%) with no negative transfer; 27B on par with Qwen3.8-Max. Status: round-2 joint training "built but not trained" (GPU-host failure).
- `docs/20260912_onprem_llm/20261004_REALBIO_LLM_VS_HARNESS.md` + `..._CLOSE_THE_GAP_ROUTING.md` — fresh (2026-10-04) analyses feeding the manuscript: definitive "harness ≫ LLM" + described-menu +20.5pp routing fix + task-split thesis + execution-grader framing. Decision row (full-corpus CPT catalog score) still pending.
- GAP: three documents cover the same project with divergent workflow counts (4,017 vs 4,200) and overlapping-but-not-identical results; needs consolidation before submission.

**Bioconductor-KB two-paper set** — `docs/papers/bioconductor_kb_paper/`
- Paper 1 `20260601_PAPER1_NAR_DATABASE.md`: "BioMate-KB: A Structure-Validated, Executable Workflow Knowledge Base for 2,241 Bioconductor Packages." Venue: NAR Database Issue. Claim: 15,641 validated steps, NAMESPACE ~96%, dual-agent κ=0.96, 90% step correctness. Evidence: strongest real-data numbers in the inventory. Status: submission draft; top-100 bundle on GitHub CC-BY-4.0.
- Paper 2 `20260601_PAPER2_METHODS_AI.md`: "Structure-Grounded LLM Extraction Suppresses Hallucination…" Venue: Nature Methods / Bioinformatics / PLOS CB. Claim: function-citation accuracy 71.4%→88.2% (+16.8pp), wrong-package 14.3%→2.1%, dual-agent κ→0.96. Evidence: 20-task benchmark across 7 domains.
- Also `20260601_PAPER_SUBMISSION_v1.md`, `20260226_PAPER_DRAFT.md` (earlier). Overall strategy `docs/papers/20260225_1545_MULTI_PAPER_PUBLICATION_STRATEGY.md` (6-paper arc: QC governance, drug discovery, proteomics, PK/PD + proteomics + cryo-EM).

**Autoimmune/translational M1–M5** — `docs/20260727_M1..M5_*.md` (Nature Methods/Medicine form, cover letters embedded, authors bracketed-placeholder)
- M1 `..._MULTIOMIC_ENDOTYPING_MANUSCRIPT.md`: "A reproducible pipeline for multi-omic endotyping of autoimmune disease" (Nature Methods Analysis). Claim: reproducibility-by-construction pipeline. Evidence gap (stated in cover letter): "the full pipeline has not yet been run end-to-end on a real cohort."
- M2 `..._ENDOTYPE_REPRODUCIBILITY_MANUSCRIPT.md`: "Reproducibility is the missing endotype…" (Perspective). No new clinical data.
- M3 `..._ISOTYPE_GATE3_MANUSCRIPT.md`: autoantibody-isotype FcRn vs BAFF/APRIL predictive-biomarker framework in myasthenia gravis (Analysis). Explicitly "framework and validation design, not a validated biomarker."
- M4 `..._ANTIGEN_RESOLUTION_MANUSCRIPT.md`: TCR–HLA–peptide antigen resolution, HLA-DP/DQ emphasis (Methods). Explicitly prioritisation, not experimentally validated antigens.
- M5 `..._FIVE_GATES_MANUSCRIPT.md`: "Prognostic is not predictive: five gates…" (Nature Medicine Perspective). Open Gate-3 test implementation.
- GAP: all five are frameworks/perspectives; none has real-cohort end-to-end validation (consistent with the 🟡 maturity in `docs/20260727_CAPABILITY_WHITEPAPER.md`).

**Cryo-EM papers** — `docs/20260428_CRYO_PILOT_AND_MANUSCRIPT_PLAN.md` (+ `20260427_CRYOEM_BENCHMARK_RUN_AND_PAPER_STATUS.md`, `20260416_CRYOEM_SPEEDUP_AND_PAPER_IMPLEMENTATION_PLAN.md`, `20260504_MANUSCRIPT_SESSION_AND_STATUS.md`)
- BioMate-Cryo Benchmark Paper (`research_repos/cryo_em_benchmark_paper/`): "strongest — REAL benchmark results" (EMPIAR-10028 3.98 Å; P52 1.78 Å); ~70% ready, highest priority. Missing: protocol-discrimination experiment, comparison vs CryoSPARC Live/RELION/Warp.
- CryoEnsemble Paper (`research_repos/cryoensemble_paper/`): SKEPTIC FLAG — "ALL results use a Gaussian perturbation model, NOT actual BioEmu or cryoDRGN"; must be reframed as surrogate proof-of-concept or re-run on real data.

**Application notes:**
- `docs/20260728_MANUSCRIPT_antitnf_ibd.md`: "Calibrated, cross-cohort… infliximab response in IBD" (bioRxiv / clinical-informatics). Authors Yuhan Zhang, Andrew Dike. Deliberately NOT a novelty claim; honest negatives (pathway features MATCH not beat full transcriptome; random-gene control p=0.051). Real public GEO data (GSE12251/14580/16879); cross-cohort AUROC 0.833. The most rigorously-caveated draft.
- `docs/20260812_PREPROCESSING_QC_PAPER_SKELETON.md`: "Verify, don't just clean…" over-correction QC gate (Applications Note). Honest: "do NOT claim first to detect over-correction" (RBET 2025 is prior art); delta = automation + cross-modality. Gates 1–2 DONE on sim + real scIB pancreas.
- Earlier cryo-EM masters-paper analyses: `docs/20260401_cryo_em_masters_paper_analysis.md`.

**Status tracker (not parsed):** `docs/20260819_MANUSCRIPT_STATUS_FOR_TEAM.xlsx` — binary, likely the canonical cross-manuscript status table.

### Inferences
- Two publication "tiers": (a) **methods/benchmark/KB** papers with real committed numbers (RealBio, C1, Bioconductor-KB ×2, cryo-EM benchmark, anti-TNF, preprocessing-QC) and (b) **translational framework** papers (M1–M5) that are deliberately pre-validation. Marketing should separate these.
- The recurring, self-imposed "honesty contract" (every number traces to committed output; placeholders for unmeasured cells) is itself a credibility asset but also signals how much remains unvalidated.

### Gaps
- Author lists are placeholders in M1–M5 and one on-prem draft; venue/DOI not finalized for most; HF/DOI publication of RealBio blocked on credentials.
- Flagship C1 lives only as a Drive docx (not a repo .md), so its exact current text could not be fully verified from the repo.
- The three on-prem LLM drafts are not yet consolidated and disagree on catalog size.
