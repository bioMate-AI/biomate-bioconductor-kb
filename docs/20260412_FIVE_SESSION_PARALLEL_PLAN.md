# BioMate — Five Parallel Session Plan
**Date:** 2026-04-12  
**Branch:** integration/next-phase  
**Status:** Planning — sync paused, sessions start simultaneously

---

## How to Read This Document

Five teams execute in parallel. Within each session, parallel tracks run concurrently. Each track begins with **Current State** (what exists today) and **Remaining Work** (what must be built). Every track ends with a **Definition of Done** that must be met before the session is closed.

---

## Session 1 — Website & Registration Personalization

### Context
The current website is static. The registration form collects research domain and topics but this data has almost no downstream effect: a personalization audit (2026-03-30) gave the system a **C+ grade** — the infrastructure exists (5-tier mechanism) but critical wiring is missing. The domain search bonus (`+2` score) is **never passed** into `generate_workflow_unified()`. Behavioral patterns only affect tool ranking text, not workflow selection.

---

### Track 1A — Website: Competitive Analysis & Design Brief

**Current State:** BioMate website is a single landing page. No systematic comparison against competitors.

**Reference Material:**
- `/home/yzhang/Desktop/business/BioMate_Introduction.md`
- `BioMate Competitive Model.xlsx` (business folder)
- Competitors to analyze: Benchling, Labforward, LIMS players (Bika/SENAITE), Basepair, Illumina DRAGEN, Seven Bridges, DNAnexus, TetraScience, Benchling, Egnyte for Life Sciences, Labguru

**Work:**
1. Extract competitor list from `BioMate Competitive Model.xlsx`
2. For each competitor: screenshot landing page, catalogue key messaging, CTAs, visual design patterns, pricing display, social proof
3. Identify gaps vs BioMate: what do they show prominently that we don't?
4. Produce `docs/20260412_WEBSITE_COMPETITIVE_ANALYSIS.md` — structured comparison matrix

**Definition of Done:** Competitive matrix doc with ≥8 competitors, screenshots, and specific actionable design recommendations

---

### Track 1B — Website: Local Prototype Subfolder

**Current State:** No design prototyping environment.

**Work:**
1. Create `frontend/client/src/pages/website-prototypes/` subfolder
2. Build 2–3 alternative landing page variants as React components:
   - Variant A: Science-forward (emphasize workflows, data, publications)
   - Variant B: Product-forward (speed, automation, cost reduction emphasis)
   - Variant C: Trust/compliance-forward (SOC2, HIPAA-ready, institution-grade)
3. Each variant uses real BioMate branding, pilot study testimonials, actual workflow categories
4. Add route `/design-preview/:variant` accessible only in dev mode (behind `NODE_ENV === 'development'` guard)
5. Do not change any production routes or replace the existing landing page

**Definition of Done:** Three navigable prototype variants accessible at `/design-preview/a`, `/design-preview/b`, `/design-preview/c`

---

### Track 1C — Registration: Topic Taxonomy Redesign

**Current State:** `domain_taxonomy.py` has 14 research domains with 5–15 example topics each. Registration form shows these as flat options. Topics are sparse and not ontology-backed. The form doesn't ask enough granular questions to inform personalization.

**Work:**
1. Audit current taxonomy: `backend/lib/galaxy/ai/domain_taxonomy.py`
2. Expand to ≥30 topics per domain, organized into sub-categories with ontology references (MeSH, GO, ChEBI where applicable)
3. Add three new domains not yet covered: `spatial_omics`, `synthetic_biology`, `computational_chemistry`
4. Add `institution_type` field (academic / pharma / biotech / hospital / CRO) — affects workflow priority and terminology
5. Update `UserPreference` model and migration
6. Update registration UI (`registration.tsx` or equivalent) to show expanded fields
7. Add multi-select sub-topic picker with search within domain

**Definition of Done:** Updated taxonomy Python file, DB migration applied, registration form shows expanded topics and institution type, user profile saved with all new fields

---

### Track 1D — Personalization: Wire Domain Profile into Workflow Search & Tool Priority

**Current State (from personalization audit):**
- Domain profile stored in DB, 5-min cached in `galaxy-assistant.ts`
- System prompt prefix mentions user domains — but this only colors the text response
- **Critical gap:** `generate_workflow_unified()` calls `workflow_search.search()` WITHOUT passing `user_profile` → the `+2` domain bonus is never applied
- Behavioral pattern analysis (`user-patterns-service.ts`) affects tool ranking text only — not the workflow generator
- Session memory is wired but cross-session memory retrieval is not injected into workflow search

**Work:**
1. `backend/lib/galaxy/ai/ai_assistant.py`: in `generate_workflow_unified()`, fetch user domain profile and pass into `self.workflow_search.search(trial, limit=5, user_profile=profile)`
2. `backend/lib/galaxy/ai/unified_workflow_search.py`: confirm `user_profile` parameter propagates into scoring; add domain match → `+2` bonus already coded but dormant
3. Add **tool priority pre-loading**: on login, based on domain profile, load the top 5 most-likely workflows into a per-user warm cache (no waiting for cold FTS). Store in `UserPreference` as `preferred_workflow_ids`
4. Add **scope extension logic**: when user query falls outside their declared domain topics, the AI response should note "this extends beyond your declared scope (genomics) — would you like to explore [new domain]?" — use `galaxy-assistant.ts` intent detection
5. Add **scope extension logic**: when user query falls outside their declared domain topics, the AI response should note "this extends beyond your declared scope (genomics) — would you like to explore [new domain]?" — use `galaxy-assistant.ts` intent detection
6. E2E test: register two users with different domain profiles; verify different workflow search rankings for the same ambiguous query

**Definition of Done:** Same query returns top-3 differently ordered workflows for genomics user vs drug_discovery user; E2E test passing

---

## Session 2 — Function Consolidation: UX Surfaces

### Context
The to-do lists four items where backend implementation exists but is not surfaced in the UX. The goal of this session is to close that gap: every backend capability should be visible, testable, and usable from the chat interface and workflow panel.

---

### Track 2A — Data Upload: S3 / URL Fully Wired in Chat Input & Workflow Panel

**Current State:**
- S3 upload backend: presigned URL generation, multipart for >100MB, user-tagged for billing — all working
- `file-upload.tsx`: UI exists for local file upload, URL import, FTP source
- **Problems identified:**
  - The file upload popover in `chat-interface.tsx` / `ChatInput` does not fully complete the S3 upload flow — files are uploaded but not injected as message context or workflow `input_data`
  - Workflow panel "Dataset Upload" section exists but returned Galaxy IDs instead of real file paths (partially fixed 2026-04-07 with `GalaxyDatasetBrowser` fix, but URL-upload path never tested)
  - No UI feedback showing upload progress percentage, file size, or estimated time
  - After upload, the file reference is not surfaced as a chat attachment or auto-filled into workflow parameter

**Work:**
1. **Chat input upload flow:**
   - When user uploads a file via chat input → show upload progress bar → on complete, attach file reference as a chat message attachment (small chip showing filename, size, S3 key)
   - File reference persists in `ConversationState.uploadedFiles[]` across turns
   - AI assistant `_inject_uploaded_files_into_params()` uses these references when generating workflow parameters
2. **URL import in chat:**
   - User pastes a URL (NCBI, ENA, EMDB, public S3) into the upload popover
   - Backend validates URL accessibility (HEAD request), reports file size
   - If URL is an accession (SRR*, EMDB-*, PDB*), resolve to actual download URL and format
   - URL stored in session state; passed as `source_url` to workflow params
3. **Workflow panel dataset upload:**
   - Verify local file upload → S3 presigned URL → S3 key → workflow `input_data` is fully working
   - Add URL-paste input field in the workflow panel (separate from chat input)
   - Show uploaded datasets as a list with filename, size, upload timestamp, and a "use in workflow" button that injects into the relevant parameter field
4. **Upload progress UX:**
   - Progress bar with percentage and MB/s estimate during upload
   - Error state with retry button
   - Success state with checkmark + S3 path summary

**Definition of Done:** User can upload a .fastq.gz via chat input, see it attached as a file chip, then generate a workflow and see the file path auto-filled in the relevant parameter; URL import from NCBI SRA accession works end-to-end

---

### Track 2B — Per-Phase Parameters, Phase Control, and Output Management

**Current State:**
- `nextflow-workflow-viewer.tsx` has `ViewerPhase[]` type with `status`, `outputs`, and `params` per phase
- PhaseCard renders per-phase status and outputs
- **Problems:** Parameter inputs shown at top-level workflow level only; individual phases don't have their own parameter editors in the UI; "Run Step" button was broken (fixed 2026-04-08 but only for rerun, not per-step parameter override); output management per phase (download individual phase outputs, view only one phase's results) is not implemented

**Work:**
1. **Per-phase parameter override panel:**
   - Each `PhaseCard` gets an expandable "Override Parameters" section
   - Shows only the parameters relevant to that phase (from `phase.params` in `ViewerPhase`)
   - User can edit these before clicking "Run Step"
   - Parameters saved to backend (`POST /api/nextflow/runs/:runId/phases/:phaseId/params`)
2. **Phase control:**
   - "Skip phase" button (marks phase as skipped, proceeds to next)
   - "Re-run from this phase" button (re-executes from a specific checkpoint using Nextflow's `-resume` with entry point override)
   - "Pause after this phase" toggle (workflow pauses at phase N completion and waits for user approval)
3. **Phase output management:**
   - Each phase's output section has its own "Download phase outputs" button
   - Phase outputs shown as a separate collapsible panel below the phase card
   - Individual file download buttons per output file
   - Phase-level QC status indicator (pass / warn / fail with QC metric values)
4. **Backend support:**
   - `POST /api/nextflow/runs/:runId/phases/:phaseId/params` — store per-phase param overrides
   - `GET /api/nextflow/runs/:runId/phases/:phaseId/outputs` — list outputs for one phase
   - Phase checkpoint resume: use Nextflow's `-entry <process>` flag or `-resume` with selective process selection

**Definition of Done:** User can expand a phase card, edit its parameters, click "Run Step", see that phase re-execute with new params, download its outputs independently

---

### Track 2C — Experiment Test Harness UX

**Current State:**
- Full test harness at `backend/lib/galaxy/ai/test_harness/` with `benchmark_suite.py`, `evaluators.py`, `metrics_collector.py`, `results_analyzer.py`, `sgi_bench_adapter.py`
- Referenced in `backend/tests/e2e_pilot_qc_professional_test.py` and `e2e_sgi_bench_test.py`
- **Problem:** Zero UI exposure — only accessible via Python test runner; no way for a researcher to trigger a pilot experiment or see test harness results in the app

**Reference:** Nature paper "AI Scientist" (CS domain) — the test harness concept should mirror how the AI Scientist proposes, executes, and reports on mini-experiments autonomously

**Work:**
1. **"Run Experiment" mode in workflow panel:**
   - Add a "Pilot Experiment" tab or mode toggle in `nextflow-workflow-viewer.tsx`
   - In this mode, the user specifies: hypothesis, control condition, experimental condition, metric to evaluate
   - BioMate auto-generates a benchmark run: runs the workflow twice (control vs experimental), captures outputs, runs `evaluators.py`, renders comparison
2. **Experiment results view:**
   - Side-by-side comparison of control vs experimental results
   - Metrics table (from `metrics_collector.py` output): sensitivity, specificity, runtime, cost per run
   - Automated narrative: "Experimental condition improved precision by X% with Y% increase in runtime"
   - Export as PDF report
3. **Experiment history panel:**
   - Left sidebar "Experiments" section showing past experiments for this user
   - Status (pending / running / completed / failed)
   - Quick link to view comparison
4. **Backend API:**
   - `POST /api/experiments` — create experiment run (hypothesis, conditions, workflow_id, metrics)
   - `GET /api/experiments/:id/results` — poll results
   - `GET /api/experiments` — list for user
   - Wire into `benchmark_suite.py` as the executor

**Definition of Done:** User can initiate a pilot experiment from the UI, see it running, and view a comparison report when done

---

### Track 2D — Input Data Analysis UX

**Current State:**
- `dataset-validation-dialog.tsx` exists for basic workflow-requirements validation
- `dataset-validator.ts` uses Claude to validate uploads against workflow schema
- **Problem:** No exploratory data analysis UI — when a user uploads a FASTQ or CSV, they can't see basic QC stats, file format validation results, or data preview before launching a workflow

**Work:**
1. **File preview panel:**
   - When a file is uploaded in chat or workflow panel, auto-trigger a lightweight analysis
   - FASTQ: show read count, avg quality score, sequence length distribution (using `FastQC`-equivalent lightweight Python)
   - CSV/TSV: show row count, column names, first 5 rows as a table, missing value count per column
   - VCF: show variant count, chromosome distribution, FILTER pass/fail ratio
   - FASTA: show sequence count, length distribution, GC content
   - BAM: show alignment rate, coverage summary
2. **Data quality gate before workflow launch:**
   - If a file fails minimum quality thresholds, show a warning before "Run" button is enabled
   - Thresholds per file type (e.g., FASTQ: ≥1M reads, avg Q>20; VCF: ≥100 variants; CSV: ≤20% missing values)
   - User can override with explicit confirmation
3. **Analysis result display:**
   - Inline in the chat as a compact card (not a modal) — shows key stats, a mini histogram
   - Full analysis accessible via "View details" expanding to a larger panel
4. **Backend:**
   - `POST /api/data/analyze` — accepts S3 key or inline data, returns analysis JSON
   - Lightweight analysis runs in Galaxy container (no separate compute job needed for small files)
   - For large files: async with SSE progress; show "Analyzing... X% complete"

**Definition of Done:** User uploads a FASTQ file, within 30 seconds sees a compact card with read count, quality distribution, and pass/fail gate; VCF and CSV also supported

---

## Session 3 — Backend Intelligence & Knowledge

### Context
BioMate has extensive backend infrastructure that is underused: hundreds of database tools registered in Galaxy, rich domain knowledge files, 8 AI tool containers in ECR (colleague-validated), citation enrichment, and an autofix framework. This session wires and validates each.

---

### Track 3A — Database Access: Clear Strategy & Priority Tool Wiring

**Current State:**
- `backend/biomni_workflows/galaxy/tools/biomni/database/` contains: `biomni_wrapper.py`, `blast_sequence.xml`, `get_genes_near_ccre.xml`, `get_hpo_names.xml`, `reduce_tokens.xml`, `region_to_ccre_screen.xml`
- `galaxy_ai_tools.db` contains the full tool registry
- **Problem:** No clear routing logic for when to invoke database tools vs. computational tools. The AI routes queries to workflows, but doesn't know when a user question should trigger a database lookup (e.g., "what's the structure of BRCA1?" should trigger UniProt/PDB lookup, not a full workflow). Hundreds of registered tools are essentially invisible to the AI routing layer.

**Work:**
1. **Tool inventory audit:**
   - Query `galaxy_ai_tools.db` for all database-category tools
   - Classify into: sequence retrieval (BLAST, FASTA), variant databases (dbSNP, ClinVar, gnomAD), pathway (KEGG, Reactome), structure (PDB, AlphaFold), phenotype (HPO, OMIM), chemical (ChEBI, PubChem), literature (PubMed, Europe PMC)
   - Document which ones are callable vs just registered
2. **Direct-answer intent detection:**
   - Add a new intent class in `galaxy-assistant.ts`: `database_lookup` (distinct from `run_workflow`)
   - Trigger conditions: user asks a factual question about a gene / protein / variant / compound without requesting computation (e.g., "what is the molecular weight of ibuprofen?", "show me the HPO terms for Marfan syndrome")
   - When `database_lookup` detected, route to `query_database()` instead of `generate_workflow()`
3. **Wire top-10 highest-value tools:**
   - Priority: UniProt (protein info), PDB (structure), NCBI Gene (gene info), dbSNP (variant), KEGG pathway, PubMed (literature), AlphaFold DB (predicted structure), ChEBI (compound), HPO (phenotype), STRING (protein interactions)
   - Each tool: add a Python wrapper callable from `ai_assistant.py`, format results as a chat artifact card
4. **Result display:**
   - Database query results shown as structured cards (not raw text): protein info card, structure viewer link, variant consequence table
   - "Use this in workflow" button on relevant results (e.g., "Use this protein structure as input to DiffDock")

**Definition of Done:** Query "show me the BRCA1 protein structure" returns a structured protein card with UniProt accession, domains, and AlphaFold structure link without launching a workflow; ≥5 database tools wired and callable

---

### Track 3B — Domain Knowledge Leverage: Audit & Demonstration Cases

**Current State:**
- Knowledge files exist (tool knowledge, workflow knowledge, QC knowledge)
- Domain taxonomy with 14 domains
- `retrieve_knowledge` tool in Galaxy tool registry
- **Problem:** No evidence that knowledge files actually influence workflow generation, parameter defaults, or QC threshold selection. The system prompt includes knowledge retrieval but no test cases demonstrate that the knowledge changes behavior vs. a version without it.

**Work:**
1. **Knowledge audit:**
   - List all knowledge files: paths, sizes, last updated
   - For each: what does it contain? Is it referenced in any code path?
   - Identify dead knowledge (files never read by any running code)
2. **Knowledge injection audit:**
   - Trace `retrieve_knowledge` tool call through to its effect on the response
   - Add logging: every time knowledge is retrieved, log which file, how many characters injected, and the tool call that followed
3. **Build 5 demonstration cases** (one per major domain):
   - Drug discovery: ask about ADMET parameters — verify knowledge file provides ADMET-specific defaults (hERG IC50 threshold, DILI risk cutoffs)
   - Genomics: ask about variant filtering — verify GATK best practices knowledge file sets VQSR thresholds
   - Cryo-EM: ask about resolution criteria — verify EMDB standard knowledge file sets map-to-model FSC = 0.143
   - Proteomics: ask about LC-MS QC — verify mass spec knowledge file provides appropriate filters
   - Single cell: ask about clustering — verify Seurat/Leiden knowledge file informs resolution parameter default
4. **Fix gaps found:** if any of the 5 domains show no knowledge effect, trace and fix the injection path
5. **Create demo script:** `docs/20260412_DOMAIN_KNOWLEDGE_DEMO.md` with 5 before/after examples showing knowledge-influenced vs. naive responses

**Definition of Done:** All 5 domain demo cases show measurably different parameter defaults when knowledge is retrieved vs. when it's absent (controlled A/B comparison)

---

### Track 3C — AI Container Tools: Integrate ECR-Validated Containers into Workflow Catalog

**Current State:**
- 8 AI tool containers in `backend/docker/biomate-ai-tools/`: boltz, chai1, drugclip, profam, protrek, scfv-pmpnn, state, syncraft
- All colleague-validated and pushed to ECR at `399683337364.dkr.ecr.us-west-2.amazonaws.com`
- **Problem:** None are registered as Nextflow workflows in `biomni_workflows/nextflow_nfcore/`; they cannot be invoked from BioMate chat

**Tool capabilities:**
| Container | Capability | Domain |
|-----------|-----------|--------|
| `boltz` | Structure prediction (Boltz-1, AlphaFold-class accuracy, open weights) | Structural biology |
| `chai1` | Multi-chain structure + ligand co-folding | Drug discovery / structural |
| `drugclip` | Drug-target interaction (CLIP-based, zero-shot) | Drug discovery |
| `profam` | Protein family classification | Genomics / proteomics |
| `protrek` | Protein function retrieval (multi-modal) | Proteomics |
| `scfv-pmpnn` | Antibody (scFv) sequence design via ProteinMPNN | Drug discovery / biotech |
| `state` | Virtual cell perturbation (Perturb-seq prediction) | Single cell / systems biology |
| `syncraft` | Synthetic biology part design | Synthetic biology |

**Work (each container gets the same treatment):**
1. Write `main.nf` Nextflow workflow wrapping the container
2. Write `nextflow_schema.json` with parameter documentation (input PDB/FASTA, output path, key hyperparameters)
3. Write `nextflow.config` with ECR image URI, AWS Batch queue assignment, and CPU/GPU resource spec
4. Write test data path (small input that completes in <5 min) and register in `nf-test` or equivalent
5. Register in Galaxy DB with FTS index entries and routing tags
6. Add routing clauses in `galaxy-assistant.ts` system prompt for each tool's trigger conditions

**Parallel sub-tracks (can each be assigned to a different person):**
- Sub-track C1: boltz + chai1 (structure prediction — related)
- Sub-track C2: drugclip + scfv-pmpnn (drug/antibody design — related)
- Sub-track C3: protrek + profam (protein annotation — related)
- Sub-track C4: state + syncraft (perturbation + synthetic biology — different but can be parallel)

**Definition of Done:** All 8 tools appear in BioMate workflow search, can be triggered by a natural language query, and run to completion on test data via AWS Batch

---

### Track 3D — Reference/Citation, Auto-Fix Audit, LLM Determinism

Three parallel sub-tracks:

**Sub-track 3D-i: Reference/Citation in Workflow Descriptions**

**Current State:**
- `citation_enricher.py` enriches Galaxy tool citations (DOIs via CrossRef, PMIDs via bio.tools)
- Individual Galaxy tools have `<citations>` blocks
- **Problem:** Nextflow workflow descriptions shown in the chat response do not include citations for (a) the tools used, (b) the starting parameter justifications, (c) the QC gate thresholds

**Work:**
1. In `ai_assistant.py` `_build_workflow_description()` (or equivalent): add a "References" section at the end of the workflow description response
2. For each tool in the workflow: fetch citation from `citation_enricher.py`
3. For starting parameters: cite the knowledge file source (e.g., "GATK Best Practices v4.3")
4. For QC gates: cite the standard (e.g., "ENCODE ChIP-seq standards v2.0", "ICH S7B hERG guideline")
5. Format: `[1] Ewels PA et al. (2020). The nf-core framework. Nature Biotechnology. DOI: 10.1038/s41587-020-0439-x`
6. Show inline in the chat workflow card as a collapsed "References" section; expandable

**Sub-track 3D-ii: Auto-Fix Audit**

**Current State:**
- Full autofix framework at `backend/lib/galaxy/ai/workflow_ops/autofix/`
- 15+ modules: `base.py`, `orchestrator.py`, `agent_fixer.py` etc.
- Frontend shows autofix state in viewer: status (idle/analyzing/fixing/restarting/succeeded/failed), attempt count, message
- **Problem:** No E2E test for autofix; unclear if the autofix loop actually resolves real failures (vs. theoretical)

**Work:**
1. Run a workflow that is designed to fail with a known fixable error (e.g., wrong genome build, missing index file, wrong container param)
2. Observe whether autofix triggers, what it attempts, and whether it succeeds
3. If autofix doesn't trigger: trace the trigger condition in `orchestrator.py` and `nextflow_workflow_runner.py`
4. Document: what error classes does autofix handle? What is the fix success rate on real failures?
5. Write an E2E test that deliberately triggers a fixable error and asserts autofix resolves it

**Sub-track 3D-iii: LLM Output Determinism**

**Current State:**
- All LLM calls use default temperature (varies by call site)
- No seed control
- Workflow generation is non-deterministic: same query may produce different parameter sets

**Work:**
1. Audit all LLM call sites in `ai_assistant.py`, `galaxy-assistant.ts`, `routes.ts` — list each with current temperature
2. For workflow generation and parameter inference: set `temperature=0.0`, `seed=42` on the Anthropic API call (or equivalent)
3. For conversational responses (not generation): keep temperature at 0.3–0.5
4. For tool calls (`search_nextflow_workflow`, `validate_prerequisites`): `temperature=0.0`
5. Add a `DETERMINISTIC_WORKFLOW_GENERATION=true` env var that forces temp=0 on all generation calls
6. Run the same query 5× before and after; measure parameter variance

**Definition of Done (3D):** Workflow descriptions include a "References" section with ≥2 citations; autofix E2E test passes; same workflow query run 5× returns identical parameters ≥4/5 times

---

## Session 4 — Interface Extension, Safety, and Docker

### Context
BioMate's roadmap targets Jupyter/RStudio/VS Code extensions (Jun–Dec 2026), LIMS/EHR integration, and instrument connectors. Instrument connection has been designed (3 architecture docs from Oct 2025) but never deployed. MCP support enables BioMate to be used as a tool provider for any MCP-compatible AI client. Safety guardrails are minimal. The two largest Docker images need analysis for size reduction.

---

### Track 4A — MCP Server: Design + Implementation

**Current State:**
- No MCP implementation exists
- Anthropic SDK dependencies include `mcp-client-2025-04-04` but no server code
- BioMate has a rich tool set (workflow generation, database queries, autofix) that would be valuable as MCP tools

**Work:**
1. **Design MCP server interface:**
   - Identify which BioMate capabilities to expose as MCP tools:
     - `search_workflow(query: string) → WorkflowCard[]`
     - `run_workflow(workflow_id: string, params: object) → RunStatus`
     - `get_run_status(run_id: string) → RunStatus`
     - `query_database(db: string, query: string) → Result`
     - `analyze_file(s3_key: string) → DataAnalysis`
     - `get_workflow_results(run_id: string) → ResultFiles`
2. **Implementation:**
   - Create `backend/lib/mcp/biomate_mcp_server.py` using `mcp` Python SDK
   - Each tool maps to an existing API endpoint
   - Auth: per-user API key in MCP tool call context
3. **Transport:** stdio transport for local use (Claude Desktop); SSE transport for remote/web use
4. **Configuration file:** `mcp_config.json` with server name, version, tool list
5. **Test with Claude Desktop:** verify BioMate tools appear in Claude Desktop's tool list; run a workflow via Claude Desktop → BioMate
6. **Document:** `docs/20260412_MCP_SERVER_GUIDE.md` — installation, configuration, example usage

**Definition of Done:** BioMate MCP server starts with `python -m biomate_mcp_server`; Claude Desktop can list BioMate tools and invoke `search_workflow` and `run_workflow`

---

### Track 4B — Secured Open Claude + Messaging Platforms

**Two parallel sub-tracks:**

**Sub-track 4B-i: "Open Claude" — Claude API Direct Access with BioMate Tools**

**Work:**
1. Design a "power user mode" where users interact with Claude directly (not through BioMate's AI layer) but with BioMate tools available as function calls
2. Expose BioMate's tools as a tool use schema to the Claude API (`tools` parameter)
3. Build a minimal UI mode: raw conversation panel with tool invocations visible to the user (shows `<tool_use>` blocks, not hidden)
4. Security: all tool calls still go through BioMate's auth layer; rate limiting applies; sensitive params filtered
5. This mode is for advanced users who want full control over the AI reasoning

**Sub-track 4B-ii: WeChat & Slack Integration**

**Current State:** No messaging integrations exist.

**Work (WeChat):**
1. Register BioMate as a WeChat Work (企业微信) service
2. Build webhook handler: incoming WeChat message → BioMate AI assistant → response with workflow card (formatted as WeChat message)
3. Workflow card in WeChat: text summary + "Open in BioMate" deep link
4. Auth: WeChat user ID maps to BioMate account via OAuth binding

**Work (Slack):**
1. Create Slack app with slash command `/biomate <query>`
2. Slash command handler → BioMate AI → response as Slack Block Kit message
3. Workflow card as Slack attachment: title, description, parameter summary, "Run in BioMate" button
4. Auth: Slack workspace admin links workspace to a BioMate organization account
5. Deploy as a separate service: `backend/lib/integrations/slack_bot.py`

**Definition of Done:** `/biomate run ADMET analysis on this compound list` in Slack returns a workflow card with a link to the running job

---

### Track 4C — Instrument Connection: Next Phase Based on Prior Work

**Prior Work Summary (from Oct 2025 docs):**
- `INSTRUMENT_CONNECTION_ANALYSIS_20251025.md`: analyzed Mirth Connect (HL7 integration engine) and OpenELIS Global 2 (LIS with 8+ analyzer interfaces) from the `bioMate-AI` GitHub org
- `INSTRUMENT_CONNECTION_ARCHITECTURE.md`: full architecture diagram covering sequencers, clinical analyzers, mass specs — using file-based export, HL7/ASTM protocols, SiLA2
- `INSTRUMENT_CONNECTION_DEPLOYMENT.md`: deployment guide for SENAITE (60+ instruments), OpenELIS (13+ instruments), and a Unified Instrument Service on ports 8082–8086
- `docker/docker-compose.instruments.yml` referenced but never deployed
- Roadmap: "sequencer connectors" targeted for Jun–Dec 2026; "robot integration" for 2027+

**Covered instruments in prior analysis:**
- Sequencers: Illumina NovaSeq (FASTQ), Nanopore MinION (FAST5/POD5), PacBio (BAM)
- Clinical analyzers: Sysmex XN (hematology), Roche Cobas (chemistry), via ASTM/HL7
- Mass spec: Thermo Fisher LCMS (.RAW → .mzML), SCIEX TripleTOF
- CryoEM: Titan Krios outputs (.mrc, .tif) — already handled by BioMate Cryo-EM workflows

**Lab Automation & LIMS Ecosystem — Virtual Lab Connectors:**
The "virtual lab" vision connects BioMate to every layer of the physical lab stack. Key categories:

| Category | Systems | Interface Type |
|----------|---------|---------------|
| **LIMS / ELN partners** | **Benchling** (potential partner), LabArchives, LabVantage, SENAITE, OpenELIS | REST API / OAuth2 |
| **Cloud lab / CaaS** | Strateos (Transcriptic), Emerald Cloud Lab, Arctoris | REST API — submit protocols, retrieve results |
| **Open-source liquid handlers** | **OpenTrons OT-2 / Flex** (Python API, fully open), Opentrons Protocol Library | Python SDK + HTTP API |
| **Open-source robot frameworks** | **LabOP** (Laboratory Open Protocol language), **SiLA2** (standardized device interface), **Lego Mindstorms** for education | SiLA2 gRPC / LabOP SPARQL |
| **Proprietary but API-exposed** | Hamilton VENUS (STAR line, REST addon), Tecan Fluent (API available), Biosero / Green Button Go | HTTP REST or COM/TCP |
| **Sequencer data APIs** | Illumina BaseSpace, Nanopore MinKNOW REST API, PacBio SMRT Link API | OAuth2 / REST |
| **Mass spec software** | Thermo Xcalibur (file-based + COM), Waters MassLynx (file-based), Bruker Data Analysis (CLI) | File watch + CLI trigger |
| **Flow cytometry** | FlowJo (file export), BD FACSDiva (FCS format), CytExpert | FCS file watcher + FlowJo API |

**OpenTrons as priority open-source robot connector:**
- OT-2 and OT-Flex have a full Python SDK and a local HTTP server (`http://<robot-ip>/server/update/health`)
- Protocol uploaded via `POST /protocols`, run started via `POST /runs`
- BioMate can: (a) generate an OpenTrons Python protocol from a user's experimental description, (b) push it to the robot via API, (c) monitor run status, (d) pull plate reader output files when complete
- This creates a full "describe experiment → robot executes → BioMate analyzes" loop — the core of the virtual lab

**Benchling partnership angle:**
- Benchling exposes a full REST API: notebooks, samples, workflows, registry
- BioMate can pull: Benchling notebook entries (experiment context), sample inventory (map to workflow inputs), assay results (pass to analysis workflows)
- Push back: BioMate workflow outputs written as Benchling results entries
- Integration makes BioMate the computational backbone of a Benchling-managed lab

**Work:**
1. **Gap analysis:** cross-reference Oct 2025 architecture docs vs. current codebase; list what was designed but never built
2. **OpenTrons connector (highest priority open-source robot):**
   - Build `backend/lib/integrations/opentrons_connector.py`:
     - `list_robots()` → scan network or use configured robot IP list
     - `upload_protocol(protocol_py: str) → protocol_id`
     - `start_run(protocol_id) → run_id`
     - `get_run_status(run_id) → RunStatus`
     - `get_run_outputs(run_id) → List[FileRef]`
   - BioMate AI: when user says "run this assay on the robot", generate a valid OT-2/Flex Python protocol from their description, push to robot, monitor
   - UI: "Send to Robot" button in workflow panel when an OpenTrons-compatible protocol is detected
3. **Benchling connector:**
   - `backend/lib/integrations/benchling_connector.py` using Benchling REST API (OAuth2)
   - Pull: notebook entries, sample inventory, assay results
   - Push: BioMate workflow outputs as Benchling result entries
   - UI: "Import from Benchling" in data upload; "Export to Benchling" in results panel
4. **Sequencer connectors:**
   - Illumina BaseSpace → BioMate: OAuth2 flow to pull completed FASTQ runs; auto-detect sample sheet; map to RNA-seq or WGS workflow
   - Nanopore MinKNOW REST API → BioMate: pull completed POD5 runs; trigger basecalling workflow
   - Both: UI "Import from instrument" button in the data upload panel
5. **CryoEM file watcher:**
   - `instrument_watcher.py` daemon watches NFS/S3 prefix for new `.mrc` / `.tif` files
   - On new files: create a BioMate session, attach files, suggest CryoSPARC workflow, notify user
6. **SiLA2 generic adapter:**
   - Survey which open-source lab devices expose SiLA2 gRPC interfaces
   - Build a generic `sila2_adapter.py` that can connect to any SiLA2-compliant device
   - Priority SiLA2 devices: Hamilton, Tecan, some centrifuges and plate readers
7. **Produce `docs/20260412_VIRTUAL_LAB_CONNECTOR_SURVEY.md`:**
   - Full survey of open-source robot APIs, cloud lab APIs, LIMS APIs
   - For each: API availability, authentication, BioMate integration path, effort estimate
   - Rank by: open-source score × pilot relevance × API quality

**Definition of Done:** OpenTrons connector implemented and tested with a simulated robot (OT-2 emulator); Benchling connector imports a sample list; Illumina BaseSpace OAuth flow shows run list; virtual lab survey doc completed with ≥8 systems mapped

---

### Track 4D — Safety Guardrails + Docker Image Analysis

**Two parallel sub-tracks:**

**Sub-track 4D-i: Safety Guardrails**

**Current State:**
- Basic domain-boundary enforcement: `galaxy-assistant.ts` profile-based intent detection
- User pattern service detects domain context
- No explicit content filtering (e.g., bioweapons, dangerous pathogens, unrestricted chemical synthesis)
- No HIPAA/SOC2 audit trail structure

**Work:**
1. **Ability boundary enforcement:**
   - Define a blocklist of intent classes that BioMate should refuse: gain-of-function experiments on select agents, synthesis routes for scheduled substances, clinical diagnosis (not analysis), patient PII extraction
   - Implement as a pre-check in `galaxy-assistant.ts` before any tool call: `isSafeQuery(intent) → {safe: bool, reason: string}`
   - Add to system prompt: clear statement that BioMate is for scientific data analysis only, not clinical diagnosis or agent synthesis
   - Hard-reject responses: "BioMate is designed for scientific data analysis. This query falls outside supported use cases." — no partial answer
2. **Non-scientific domain rejection:**
   - If user query has zero biological/chemical/clinical signals: "BioMate specializes in life science workflows. Your question about [topic] is outside scope. Try asking about your data analysis instead."
3. **SOC2 / HIPAA audit trail:**
   - Log every AI call with: timestamp, user_id, query hash (not plaintext), tool called, result status
   - Audit log table in DB: `audit_events(id, timestamp, user_id, event_type, resource_type, resource_id, ip_address, result)`
   - Expose admin endpoint `GET /api/admin/audit-log` (admin role only)
   - PHI detection: if user message contains what looks like a patient name + DOB + diagnosis (regex), flag and strip before passing to LLM
   - Document: `docs/20260412_SOC2_HIPAA_AUDIT_FRAMEWORK.md`

**Sub-track 4D-ii: Docker Image Shrink Analysis**

**Current State (two largest):**
- `biomate-interactive` (161-line Dockerfile): Jupyter + RStudio + CellxGene — all three in one image. Likely 8–12 GB.
- `biomni-tools` (112-line Dockerfile): ViennaRNA + AutoDock Vina + RDKit + Biopython + OpenBabel — 6–8 GB estimated.

**Work:**
1. **Measure actual sizes:**
   - Pull images from ECR, run `docker image inspect` for exact sizes
2. **`biomate-interactive` split strategy:**
   - Split into three dedicated images: `biomate-jupyter` (Jupyter + bioconductor), `biomate-rstudio` (RStudio + R packages), `biomate-cellxgene` (CellxGene standalone)
   - Workflows that need RStudio use `biomate-rstudio`; single-cell viz workflows use `biomate-cellxgene`
   - Remove the all-in-one; no workflow needs all three simultaneously
3. **`biomni-tools` split strategy:**
   - Split by domain: `biomni-cheminformatics` (RDKit + OpenBabel + ChEMBL tools), `biomni-rna-structure` (ViennaRNA + RNA secondary structure tools), `biomni-docking` (AutoDock Vina + GNINA + pocket tools)
   - Audit which Nextflow workflows use which tools; map each workflow to its dedicate image
4. **Estimate size reduction:** document before/after in `docs/20260412_DOCKER_SHRINK_ANALYSIS.md`
5. **Build and push reduced images to ECR; update workflow `.nf` container directives**

**Definition of Done:** SOC2 audit log table deployed and capturing events; PHI detection working; biomate-interactive split into 3 images each ≤40% of original size; biomni-tools split into 3 images

---

## Session 5 — Benchmarking, Autotest, and AI Scientist Comparison

### Context
Current state: 9/9 pilot E2E passing, routing benchmark at 93.3% (112/120 exact). No consistency testing (does the same query produce the same result across 5 runs?). No autofix benchmark. No public benchmark results. The simulated user in E2E tests is naive — it doesn't carry conversation context and often fails to progress through multi-turn workflows.

---

### Track 5A — Consistency & Stability Benchmark

**Current State:**
- No repeat-run variance testing exists
- Routing benchmark run once → 93.3% accuracy, but we don't know if this varies run-to-run
- Pilot study E2E passing, but no test for "same query, same result" stability

**Reference:** Release preparation documents in `docs/` regarding evidence-based launch criteria.

**Work:**
1. **Consistency test suite:**
   - Take the 120 routing benchmark queries
   - Run each query 5× with `temperature=0.0` (after Track 3D-iii fix)
   - Measure: % of queries where all 5 runs select the same workflow (target: ≥95%)
   - Measure: % of queries where parameter set is identical across all 5 runs (target: ≥90%)
2. **Stability under re-phrasing:**
   - For 30 representative queries, create 3 paraphrase variants
   - Each paraphrase should route to the same workflow
   - Measure: % of paraphrases routed correctly (target: ≥85%)
3. **Session stability:**
   - Run the same 9 pilot E2E sessions 3× each
   - Measure: % that reach completed workflow status all 3 times (target: ≥90%)
4. **Report:** `docs/20260412_CONSISTENCY_BENCHMARK_REPORT.md` with pass/fail tables, failure examples, root causes

**Definition of Done:** Consistency benchmark passing ≥90% same-result across 5 runs; report published with before/after for temperature fix

---

### Track 5B — Auto-Fix Benchmark + AI Scientist Comparison

**Current State:**
- Autofix framework exists with 15+ modules; no measurement of its effectiveness
- AI Scientist (CS domain) paper in Nature — the closest comparison for autonomous experiment execution and self-correction

**Reference:**
- The AI Scientist paper (Lu et al., 2024, Nature) — measures: number of successful experiments per run, error recovery rate, output quality score. BioMate's equivalent is: workflow auto-fix success rate, parameter recovery from bad initial params, QC gate recovery.

**Work:**
1. **Autofix benchmark suite:**
   - Design 20 deliberately-broken workflow runs:
     - 5× wrong genome build (hg38 vs hg19 mismatch)
     - 5× missing required input file
     - 5× wrong container parameter type (string where integer expected)
     - 5× resource constraint failure (OOM, timeout)
   - Run each; record: did autofix trigger? Did it succeed? How many attempts? Final status?
2. **Metrics:**
   - Fix success rate: % of fixable errors resolved by autofix without human intervention
   - Mean attempts to resolution
   - False trigger rate: % of times autofix triggered but shouldn't have
3. **AI Scientist comparison:**
   - Map BioMate's error recovery metrics to the AI Scientist paper's reported metrics
   - Where we're below: identify root cause (too conservative trigger? wrong fix strategy? max attempts too low?)
4. **Improvement loop:**
   - For the top 3 failure modes: implement targeted fixes in `orchestrator.py` or `agent_fixer.py`
   - Re-run benchmark; report improvement delta
5. **Report:** `docs/20260412_AUTOFIX_BENCHMARK_REPORT.md`

**Definition of Done:** 20-case benchmark run; fix success rate measured; ≥2 improvements implemented; before/after delta documented

---

### Track 5C — Public Benchmark Positioning

**Current State:**
- No public benchmark runs recorded
- Routing at 93.3% on hand-authored BioMate-specific benchmark
- No comparison against published AI systems for bioinformatics (CARE, BioGPT, Med-PaLM, etc.)

**Work:**
1. **Identify relevant public benchmarks:**
   - SGI-Bench (from `sgi_bench_adapter.py` — already partially wired): survey what it tests
   - BEIR (biomedical IR): workflow search quality
   - BioASQ: biomedical question answering
   - BigBio: structured biomedical NLP
   - Any bioinformatics-specific workflow quality benchmarks (search recent papers)
2. **Run BioMate on SGI-Bench:**
   - `sgi_bench_adapter.py` already exists — run it, record scores
   - Compare to published SGI-Bench leaderboard numbers from other systems
3. **Identify competitive baselines:**
   - Other "AI for bioinformatics" systems with public benchmark results: Biomni (the original), BioAgent, ClinicalBERT, GeneGPT
   - For each: find their reported benchmark number on any shared benchmark
4. **Gap analysis:**
   - Where is BioMate below baseline? Which capabilities are not captured by existing benchmarks?
   - Define BioMate-specific benchmarks for: workflow generation quality (run-to-completion rate), QC defensibility score, time-to-result
5. **Report:** `docs/20260412_PUBLIC_BENCHMARK_POSITIONING.md`

**Definition of Done:** SGI-Bench run completed with score; ≥3 other systems compared on ≥1 shared benchmark; BioMate-unique benchmark dimensions defined and measurable

---

### Track 5D — E2E Autotest Expansion: Smarter Simulated User + Full Coverage

**Current State:**
- 9/9 pilot E2E passing (drug discovery, cryo-EM, WGS germline, UX suite, UX-7 param autofill)
- Simulated user is naive: sends a fixed query, then clicks buttons — no understanding of the conversation state, no ability to respond meaningfully to clarification questions, often abandons the test at the first clarification prompt
- No E2E tests for: autofix, multi-turn conversation, error recovery, billing events, messaging integrations
- Test timeout relies on static waits; no adaptive polling based on workflow complexity

**Work:**
1. **Smarter simulated user:**
   - Replace fixed-query pattern with a context-aware user model:
     - Maintains a "goal state" (e.g., "run ADMET analysis on ibuprofen and see results")
     - When BioMate asks a clarification question, user model formulates a contextually appropriate answer (using Claude Haiku as the simulated user brain)
     - System prompt for simulated user: "You are a molecular biology PhD student. Your goal is: {goal}. Respond naturally to the AI assistant's questions. Provide real-looking data when asked."
   - Implement as `SimulatedUser` class in `frontend/e2e/helpers/simulated-user.ts`
2. **Full conversation arc tests:**
   - Each test must: send initial query → handle clarifications → fill parameters → run workflow → verify results displayed → download outputs → rate as complete
   - No test exits early on a clarification prompt
   - No test passes unless it reaches workflow `completed` or `failed` status
3. **New test coverage:**
   - Autofix E2E: deliberately inject a bad parameter; assert autofix resolves it
   - Multi-turn memory: ask a follow-up question about a previous workflow result; assert correct context carried
   - Billing E2E: run a workflow; assert a Lago billing event was emitted
   - Error recovery: network error mid-stream; assert graceful recovery and retry
   - Upload + workflow E2E: upload a real FASTQ via chat; assert it appears in workflow params
4. **Adaptive timeout:**
   - Each test class has a `computeTimeout(workflowComplexity)` based on estimated Batch runtime
   - Simple workflows (ADMET, pocket detection): 10 min timeout
   - Medium workflows (RNA-seq, drug MD): 30 min timeout
   - Complex workflows (WGS germline, CryoEM): 90 min timeout
5. **Test infrastructure:**
   - Add a `--focus-session <session_name>` CLI flag to run one pilot session at a time
   - Add `--record-video` flag to capture screenshots on failure for audit
   - Test report auto-written to `docs/postsync_test_results/` after each run

**Definition of Done:** Simulated user class implemented; ≥15 tests total (vs. current ~9); all reach terminal state (completed or failed); no test exits at clarification prompt

---

## Cross-Session Dependencies & Coordination

| Dependency | Blocks | Note |
|------------|--------|------|
| Track 1D (personalization wiring) | Track 5A (consistency benchmark) | Determinism fix must land before consistency can be measured meaningfully |
| Track 3D-iii (LLM determinism) | Track 5A (consistency benchmark) | Same dependency |
| Track 3C (AI containers registered) | Track 5D (E2E tests for new tools) | New tools need DB registration before E2E can target them |
| Track 4D-ii (Docker split) | Track 3C (AI container integration) | Container base images should be finalized before wiring |
| Track 2A (data upload wired) | Track 5D (upload + workflow E2E) | Upload flow must be complete before E2E can test it |

## Parallel Execution Map

```
Session 1: [1A] [1B] [1C] [1D]  → all parallel
Session 2: [2A] [2B] [2C] [2D]  → all parallel
Session 3: [3A] [3B] [3C-c1][3C-c2][3C-c3][3C-c4]  → sub-tracks parallel
           [3D-i][3D-ii][3D-iii]  → parallel
Session 4: [4A] [4B-i][4B-ii][4C][4D-i][4D-ii]  → all parallel
           (4D-ii can start as soon as image sizes are measured)
Session 5: [5A] [5B] [5C] [5D]  → all parallel
           (5A must wait for 3D-iii temperature fix)
```

## Sync Points

After all 5 sessions complete a first pass:
1. Integration review: merge personalization wiring (1D) with determinism (3D-iii) and re-run consistency benchmark (5A)
2. Docker split (4D-ii) → update all workflow `.nf` container directives → re-run pilot E2E (5D) to verify no regressions
3. AI containers (3C) registered → add E2E coverage (5D Track addition)
