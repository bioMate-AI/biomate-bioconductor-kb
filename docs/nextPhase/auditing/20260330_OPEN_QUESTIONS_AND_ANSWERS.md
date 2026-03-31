# Open Questions & Answers — 2026-03-30 Session
**Status**: Partially resolved. Items marked ✅ are implemented. Items marked 🔲 are deferred for follow-up.

---

## Round 1 — Workflow Ecosystem Audit Feedback

Source document: `docs/nextPhase/20260330_WORKFLOW_ECOSYSTEM_AUDIT.md`

---

### 1a. Domain category overlap: pharmacology vs drug_discovery ✅

**Question:** pharmacology and drug_discovery should be the same. Check for duplicates between R wrappers and existing workflows. Merge ambiguous domain categories and ensure consistency between tools and workflows.

**Answer:**
- `pharmacology/` folder and `drug_discovery/` folder were two separate DB domains with overlapping scope (ADMET, docking were in pharmacology; MD, REINVENT were in drug_discovery — inconsistent with the taxonomy).
- `nca_pknca` existed in both folders (256-line pharmacology version vs 1044-line drug_discovery version).

**Implemented:**
- DB: All 28 `domain='pharmacology'` workflows migrated → `domain='drug_discovery'` (41 total now).
- DB: 10 stale/duplicate entries deleted (old `biomni_nf/` paths + shadow `nextflow_nfcore/pharmacology/` entries + pharmacology nca_pknca duplicate).
- File: `pharmacology/nca_pknca/main.nf` deleted (obsolete 256-line version; drug_discovery version is canonical).
- `domain_taxonomy.py`: Removed `pharmacology` as a separate user domain; expanded `drug_discovery` topics to include PK/PD, NCA, IVIVE, radiotherapy dosimetry, drug combinations, FDA labels.
- `index_all_workflows.py`: Added `_FOLDER_DOMAIN_MAP = {"pharmacology": "drug_discovery"}` so future re-indexing is consistent.
- `unified_workflow_search.py`: Removed `'pharmacology'` from preferred domain set (no DB entries with that domain).
- **No R-wrapper vs Nextflow duplicates found.** Bioconductor wraps single R packages; biomni_nextflow composes multi-step analyses — different abstraction levels.

---

### 1b. Bioconductor sub-granularity ✅

**Question:** `bioconductor/` should be more fine-grained in domain classification.

**Answer + Implemented:**
- DOMAIN_KEYWORDS in `index_all_workflows.py` expanded from 19 → 64 entries. Added: microarray/affy → transcriptomics; nmr/metabolom/lipidom → metabolomics; single cell/scrna → single_cell; copy number/cnv → genomics; etc.
- DB direct reclassification: 158 packages moved out of `general`; `general` reduced from 547 → 389.
- New sub-domains now represented in bioconductor: `single_cell` (21), `metabolomics` (21), `imaging` (39, +20).
- Remaining 389 `general` = infrastructure/annotation packages (BiocManager, alabaster_*, AnVIL) — intentionally broad, cannot be classified more specifically without per-package manual review.

---

### 1c. Leveraging existing workflows for composition ✅ (documented, gap noted)

**Question:** How exactly does the code leverage existing workflows? What skill file is used to avoid common errors?

**Answer (documented in audit):**
The 4-level `nextflow_composer.py` pipeline:
- **L0**: SubworkflowLibrary JSON cache (0 LLM calls on hit; Jaccard ≥ 0.75 + quality ≥ 70)
- **L1**: Tool retrieval from SQLite FTS
- **L2**: Wrapper path validation; NF-WRAPPER tools get `include{}` directives; bad-path tools are substituted with same-category alternatives; tools without wrappers go to GENERATE
- **L3**: Single LLM call with 6 injected DSL2 rules (the "skill file" equivalent)
- **Skill files**: `skill_loader.py` loads domain YAML prompts from `claude-scientific-skills-biomate/`

**Remaining gap (not yet implemented):** L2 does not yet search the 93 nf-core subworkflow library for matching `include`-able modules before generating fresh process code.

---

### 1d. QC gate consistency and HTML report accessibility ✅ (documented, partial gap)

**Question:** There should be more than 230 workflows. Check QC step/gate consistency. Make QC report HTMLs directly accessible in UI. QC profile selection should be intuitive and prepared ahead.

**Answer:**
- **Total workflows: 2,435** (not 230; the 230 refers to `source='nfcore'` full pipelines only).
- **QC gate**: 95+ process parsers covering all major nf-core process names; compatible with standard Nextflow trace format.
- **HTML reports**: `classifyFileType()` correctly classifies `html` as `'interactive'` (checked before `textExts`); renders as sandboxed iframe with Open/Download buttons.
- **Remaining gap**: Output scanner for direct Nextflow runs may not traverse subdirectories like `multiqc/`. A recursive glob for `**/multiqc_report.html` would fix this.
- **QC profile selection**: Auto-inferred at workflow generation time by `_infer_qc_profile()` and shown in the viewer header before Run. 30+ curated profiles. No manual dropdown selector yet (gap documented).

---

## Round 2 — Session Fixes & Audit Feedback

Source document: `docs/nextPhase/20260330_SESSION_FIXES_AND_AUDIT.md`

---

### 2a. Package auto-recovery at runtime 🔲

**Question:** What is the current auto-solution if any package is missing in runtime?

**Answer:**
| Execution mode | Missing package behaviour |
|----------------|---------------------------|
| Docker/Singularity (default) | Impossible — containers are self-contained |
| Host mode (fallback) | `_auto_install_host_modules()` → `pip install <module>`; R packages: NO auto-recovery |
| Bioconductor wrappers (host) | Will fail with R library load error; must use `--profile docker` |

**Open item 🔲:** No auto-recovery for R packages in host mode. Future improvement: detect R `library()` failures in the Nextflow log and surface a "run with Docker instead" suggestion in the error recovery card.

---

### 2b. ANTHROPIC_API_KEY and local LLM fallback ✅

**Question:** The key is not set in the running Galaxy process — why? Why is only regex used as backup instead of a local LLM?

**Answer:**
- **Key IS set**: `start_backend.sh` line 7 `export ANTHROPIC_API_KEY=sk-ant-...`. The D4 "llm_used=False" was caused by the `anthropic` Python package missing from the venv — fixed by `pip install anthropic`.
- `llm_client.py` already has Ollama support (provider=`local_ollama`; models: qwen3, llama3, mistral). This is the Python-side local LLM path.
- `/api/llm/classify` in `routes.ts` previously fell directly to regex when API key absent.

**Implemented (2026-03-30):** 3-tier fallback chain in `routes.ts /api/llm/classify`:
1. Anthropic API (primary, uses `claude-haiku-4-5`)
2. **Ollama** at `OLLAMA_BASE_URL` env var (default `http://localhost:11434`), model `OLLAMA_CLASSIFY_MODEL` (default `llama3`)
3. Keyword regex (last resort)

**Open item 🔲:** D4 `explain_error` endpoint uses the Python `llm_client.py` which already has Ollama as a provider. The `PROVIDER=local_ollama` config path is available but not yet exposed as a user-configurable fallback (requires setting `AI_PROVIDER=local_ollama` + `OLLAMA_BASE_URL` env vars).

---

### 2c. Domain taxonomy — consistency, topics, relation to workflows/tools ✅ (documented)

**Question:** What is the relation between the 14 taxonomy domains and workflow/tool categories? Are they consistent? How are topics determined and how do they relate to workflows/tools? How does the domain profile function in BioMate? Fix domain profile persistence (was read-only due to psycopg2 requirement).

**Answer:**

**Three separate but related systems:**

| System | Location | Purpose |
|--------|----------|---------|
| `DOMAIN_TAXONOMY` (13 domains + topic lists) | `domain_taxonomy.py` (code) | Registration UI display; search personalization (+2.0 score boost) |
| `workflows.domain` field (30 DB categories) | SQLite `galaxy_ai_tools.db` | Workflow indexing, FTS filter, QC profile inference |
| `tools.topics` / `tools.edam_topics` | SQLite `galaxy_ai_tools.db` | Bioconductor domain inference via `infer_domain()` |

**Consistency note:** The 13 taxonomy domains are a *user-facing subset* of the 30 DB domains. Bioconductor DB domains (`transcriptomics`, `genomics`, etc.) map 1:1 with taxonomy keys. DB-only domains (`imaging`, `immunology`, `cell_biology`, `lab_automation`, `glycoengineering`) have no taxonomy entry — they're not considered primary user research domains.

**Note on pharmacology:** The taxonomy previously listed 14 domains including `pharmacology`. As of 2026-03-30 this is merged into `drug_discovery` → **13 domains now**.

**Topics mechanics:**
- `DOMAIN_TAXONOMY` topics are **display-only** checkboxes in the registration UI.
- When a user selects topics, they are stored in `user_domain_profiles.topics` but used only as a display record.
- At search time, only the *parent domain key* (e.g., `genomics`) is used for the +2.0 score boost — topics do not individually filter workflows.
- Direct relation: topics → parent domain → all `domain=<key>` workflows in DB get +2.0 boost.

**Domain profile persistence fix (2026-03-30):**
- Previous state: `POST /api/user/domain-profile` returned 503 when `_DOMAIN_PROFILE_AVAILABLE=False` (psycopg2/PostgreSQL unavailable).
- **Fixed**: SQLite fallback implemented in `webapps/galaxy/api/ai_assistant.py`:
  - `user_domain_profiles` table in `galaxy_ai_tools.db`
  - Primary: PostgreSQL agentic_memory (when available)
  - Fallback: SQLite (always available in dev)
  - Response includes `"storage": "sqlite"` or `"storage": "postgres"` to indicate which was used.

**Open items 🔲:**
- Topics could be used for finer-grained workflow scoring (e.g., "WGS" → bonus for sarek, GATK workflows).
- The user taxonomy (`domain_taxonomy.py`) and DB domain list (`workflows.domain`) could be formally reconciled so every DB domain has a taxonomy entry (currently ~17 DB domains have no taxonomy equivalent).

---

### 2d. Preflight — what is it? ✅ (documented)

**Question:** What is C2 Preflight Proxy?

**Answer:** `POST /api/workflows/preflight` is a **pre-run validation** step triggered before "Confirm & Run":

1. **Parameter validation**: Checks all required params have values → `{ready: false, parameters: [{name, status: "missing"}]}` if any are absent.
2. **Parameter suggestions** (C2 Phase 2): Analyzes uploaded input files and suggests values → `parameter_suggestions: [{param_id, suggested_value, confidence, rationale}]`.
3. **QC profile validation**: Confirms the assigned QC profile is valid for the workflow domain.

The "C2 Phase 2 UI auto-fill" gap: suggestions are returned in the API response but not yet wired as auto-fill badges on param input fields in the workflow viewer.

**Open item 🔲:** Wire `parameter_suggestions` from preflight response into `nextflow-workflow-viewer.tsx` param field components — add a suggestion badge/button that pre-fills the value with one click.

---

### 2e. Sequential pipeline — bullet format ✅

**Question:** B4 sequential pipeline should not depend on LLM detecting "then/followed by". User should be able to express it in bullet/numbered format. Also, multi-workflow chains should work naturally.

**Answer + Implemented (2026-03-30):**

`detectBulletPipeline()` added to `galaxy-assistant.ts`, called **before** `analyzeIntent()` (no LLM needed for formatted input):

- Detects: `1. Step` / `2. Step` / `Step 1: ...` (numbered)
- Detects: `- Step` / `* Step` / `• Step` (bulleted)
- Requires ≥ 2 list items; non-list lines must be fewer than list items (avoids false-positives on casual lists)
- Returns fully-formed `IntentDecomposition` with `isSequential: true` and `dependsOn` chains

**Usage example:**
```
1. FastQC quality control on raw reads
2. Adapter trimming with Trim Galore
3. Alignment to hg38 with STAR
4. Differential expression with DESeq2
5. Pathway enrichment with clusterProfiler
```
→ 5-step sequential pipeline, no LLM call needed.

**Curated chains (complementary path):** The 8 curated chains (`target_to_lead_full`, `bulk_rnaseq_de_analysis`, etc.) are triggered via `search_chains()` when the user describes a known multi-workflow pattern in prose. Bullet format → `detectBulletPipeline()`; prose → LLM or chain search.

**Remaining LLM path (unchanged):** Prose with "then", "followed by", "after that" still goes through `analyzeIntent()` → LLM sets `is_sequential: true`. The system prompt was updated to also mention bullet format as a signal for the LLM (for mixed input).

**Open item 🔲:** The chain mechanism uses sequential execution only (step N completes before step N+1). Parallel chain steps are display-only in `PipelineListView` — the executor doesn't support them yet.

---

## Deferred Items (return together)

| # | Item | Where | Priority |
|---|------|--------|----------|
| D1 | R package auto-recovery in host mode | `nextflow_executor.py` | Medium |
| D2 | Ollama as default LLM provider fallback (configurable via env) | `llm_client.py` config | Low |
| D3 | Topic-level workflow scoring (topics → individual workflow boost) | `unified_workflow_search.py` | Low |
| D4 | Reconcile DB domain list ↔ DOMAIN_TAXONOMY (add missing 17 domains) | `domain_taxonomy.py` | Low |
| D5 | C2 Phase 2: wire `parameter_suggestions` into viewer UI | `nextflow-workflow-viewer.tsx` | High |
| D6 | Recursive MultiQC HTML scan for direct Nextflow run outputs | `routes.ts` output scanner | Medium |
| D7 | QC profile manual selector dropdown in execution control panel | `execution-control-panel.tsx` | Medium |
| D8 | Parallel chain step execution in `workflow_chain.py` | `workflow_chain.py` | Medium |
| D9 | nf-core subworkflow `include` matching in L2 of `nextflow_composer.py` | `nextflow_composer.py` | High |
