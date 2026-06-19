# Next-Phase Plan — Output Lockdown, Project Collaboration, User Skills + BYO Code

**Date:** 2026-06-19
**Driver:** product direction memo (this session)
**Supersedes / extends:** `docs/20260619_OUTPUT_AND_PROJECT_MODEL_AUDIT.md` (the 9-question audit; revised section §3 below — projects DO exist)
**For:** product + engineering planning

## Correction to prior audit

Prior audit (`docs/20260619_OUTPUT_AND_PROJECT_MODEL_AUDIT.md` §3) said *"projects do not exist in DB schema."* That was wrong — I missed `projectSchema` in `frontend/shared/schema.ts:330` because I only grep'd for `pgTable.*project` and Drizzle's projects-related code lives elsewhere. Verified now:

- **Projects DO exist** — `frontend/shared/schema.ts:330` `projectSchema` with `instructions, documents[], chatSessions[], tags, category, progress, status`
- **Backend CRUD shipped 2026-06-13** — `/api/projects` endpoints fully tested
- **Cross-user isolation, cascade delete, archive lifecycle verified** — `docs/20260613_PROJECT_FRAMEWORK_AUDIT_RESULTS.md` reports **31/31 assertions pass**
- **Project-id FK already wired to chat_sessions** (S4 of audit)
- **Project documents schema exists** — `projectDocumentSchema` (line ~325)

What's missing is **UX surface** and **per-project output organization** + **document indexing** + **skill storage** + **BYO code** — the gap is product surface, not backend foundation.

---

## Part 1 — IMMEDIATE (this week)

### P0 — Lock down Channel 5: no direct S3 access for users

**Current state:** users with IAM creds can `aws s3 cp` from `s3://biomate-nextflow-work/<user_id>/<run_id>/output/`. This bypasses BioMate's audit log, billing counters, and access control.

**Target state:** all output access via counted BioMate endpoint. S3 bucket policy denies direct user access; only the BioMate service role can read it. Outputs are served through `/api/runs/:id/output/<filename>` which signs short-lived presigned URLs per-request, logs the access, and (optionally) decrements an egress quota.

**Acceptance:**
- S3 bucket policy restricts `s3:GetObject` on `biomate-nextflow-work/*` to the BioMate IAM role; user IAM principals get `Deny`
- Each output download generates an audit log row (run_id, file, user_id, timestamp, IP)
- The 7 existing access channels continue to work (the endpoint just becomes the single gateway)
- Optionally: per-user / per-org egress quota counter (defer if not needed for Phase 1)

**Effort:** ~1–2 days backend + 1 day testing
**Files to touch:** `frontend/server/routes.ts` (`/api/runs/:id/output/<filename>` proxy), AWS bucket policy (manual or via terraform), `frontend/server/storage.ts` (audit-log writer)

### P0 — User-assigned output location

**Current state:** `outdir` is hardcoded to `s3://biomate-nextflow-work/<user_id>/<run_id>/output/`. The user has no choice.

**Target state:** workflow-settings panel has an "Output location" picker with options:

| Option | Description |
|---|---|
| **Default (BioMate-managed)** | Current behavior — managed S3 prefix. Cleaned per BioMate lifecycle policy. |
| **My project folder** | Routes outputs into `s3://biomate-projects/<project_id>/runs/<run_id>/` (new bucket; per-project IAM) — see §2 below |
| **My S3 bucket (paste URI)** | User supplies `s3://my-org-bucket/some-path/`. BioMate assumes the role to write. Requires bucket policy allow grant. |
| **My Galaxy history** | Outputs land as datasets in the chat's existing Galaxy History — leverages Galaxy's native dataset model |

**For the Liu Phase 2 PHI case:** user-assigned bucket is the answer — they keep their data in their compliance perimeter; BioMate writes once, then forgets.

**Effort:** ~3 days (~half day per option × 4 options + ~1 day plumbing)
**Files to touch:** `frontend/client/src/components/nextflow-workflow-viewer.tsx` (picker UI), `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` (accept `outputLocation` in request, set Nextflow `publishDir` accordingly)

### P0 — Fix Download Report content (report ≠ data dump)

**Current state:** `buildFullReportMarkdown` lists output files by name only — no URLs, no sizes, no checksums. Methods is verbatim Methods-tab text. No data-citation block. No PDF/DOCX. Footer says "v2 preview".

**Target state (research-document style, per product memo):**

| Section | Content shape |
|---|---|
| Header | Run ID, Project, Workflow, Researcher (real name from auth), Generated timestamp, BioMate version |
| **Dataset description** | Per input dataset: name, source (e.g. UDN cohort X / GTEx v8 / SRA SRR-id / upload-by-user), data-format, sample count, total size, hash of sample sheet. **NO file bytes.** |
| **Findings** | AI summary + key results + caveats + next steps (current) |
| **Output description** | Per output: file name, size, MD5 hash, format, **link to BioMate download endpoint** (not S3 directly). One paragraph "what this file represents" per output. NO file bytes. |
| **Visualization figures** | Embedded PNG/SVG (small, inline) of key plots: PCA, volcano, MA, heatmap, manhattan — actual figures, since they're small (KB) and the point of the report |
| **Methods** | Publication-paragraph form (LLM-generated from the manifest), with inferred values flagged italic |
| **Parameters** | Table with origin tagging (default / user override / autoloop) |
| **Software** | Tool + version + container digest |
| **Citations** | DOI links from qc_evidence |
| **QC audit** | Gate table + chain-of-custody (signed digest of the run state) |
| Footer | "Generated by BioMate v<X>. Run is reproducible by re-dispatching with the same chain_id + parameters + container digests." |

The report is a **navigable summary**, not an archive. Bytes live at the download endpoint.

**Effort:** ~4 days frontend (report builder rewrite + figure embedding) + ~1 day backend (input-dataset metadata endpoint) + ~1 day pandoc-PDF route

**Suggested format:** Markdown source → PDF via WeasyPrint (Python, native HTML+CSS, better figures than pandoc) → DOCX via pandoc for Word users.

---

## Part 2 — Project as the collaboration unit (next 2–3 weeks)

Projects exist but most product surface treats them as invisible. To make project the collaboration anchor, ship:

### Project = first-class workspace

| Capability | What it does | Effort |
|---|---|---|
| **Project dashboard** | Lists all runs across all chats under project, sorted by timestamp. Filters by status, workflow, owner. | ~2 days |
| **Project file browser** | One folder tree per project. Inputs (user-uploaded), outputs (organized `runs/<run_id>/`), reports (one per run, dated). Mirrors S3 layout. | ~3 days |
| **Project-scoped chat creation** | "New chat in project X" auto-links chat_sessions.project_id; subsequent runs land outputs into project's S3 prefix | ~half day (wiring + UI) |
| **Project members** (team collab) | invite by email; roles = owner / editor / viewer; per-row ACL on chats and runs | ~1 week (auth + UI) |
| **Project instructions** | Persistent system-prompt fragment appended to every chat under this project ("This project studies rare neuro disease X; prefer pseudobulk over single-cell DE; use GRCh38."). Field already exists in schema (line 335). | ~2 days (UI + plumbing to chat-stream) |
| **Project document index** | User drops PDFs / notebooks / .md files into the project; BioMate extracts content, embeds, stores in a per-project RAG index. Chat can retrieve from it. | ~1 week (see §3) |
| **Project skills** | User attaches a "skill" = a reusable workflow chain definition + sample inputs + expected outputs. Future chats in the project auto-route to skills first. | ~1 week (see §3) |
| **Run history per project** with explicit timestamps + status + cost (Lago) | Already partially via execution_runs; just needs project-scoped query | ~1 day |
| **Project archive / unarchive / delete** (with CASCADE) | Already shipped per 2026-06-13 audit | ✅ done |

### Per-project output organization (the user's specific ask)

When a user has a project, outputs go to `s3://biomate-projects/<project_id>/`:

```
biomate-projects/
└── <project_id>/
    ├── inputs/               ← user uploads (raw FASTQ, sample sheets)
    │   ├── 2026-06-19_uploads/
    │   └── manifest.json
    ├── runs/
    │   ├── <run_id_1>/        ← workflow_name, chain, params, timestamp in metadata.json
    │   │   ├── metadata.json
    │   │   ├── parameters.json
    │   │   ├── output/        ← Nextflow publishDir target
    │   │   ├── logs/
    │   │   └── report.md      ← downloaded report goes here too
    │   └── <run_id_2>/
    ├── reports/
    │   └── 2026-06-19_<run_id_1>_report.pdf
    ├── skills/                 ← user-defined reusable chains (JSON manifests)
    │   └── liu_rare_disease_workup.json
    └── docs/                   ← project-uploaded reference docs
        ├── lab_protocol.pdf
        └── sample_metadata_v2.xlsx
```

Each run row in the project dashboard links to its `runs/<run_id>/` folder; each report link is a presigned URL into `reports/`. The **project IS the file management directory** the user asked about.

---

## Part 3 — Instructions, document-intent indexing, skills, BYO code

### Document intent indexing

User uploads documents (papers, lab protocols, sample metadata, prior notebooks) → chat interprets intent and stores in per-project RAG index.

| Capability | Status today | What's needed |
|---|---|---|
| Document upload | ✅ `projectDocumentSchema` exists | none |
| Content extraction (PDF→text, .docx→text, .xlsx→tables, .ipynb→cells) | ⚠️ partial — `run_code` can extract; no upload-time pipeline | Add upload handler that triages by type + extracts |
| Intent classification | ❌ not specific to documents | Add classifier: is this a protocol / sample sheet / prior analysis / paper reference / data dict? |
| Vector embedding + per-project RAG | ⚠️ existing chain-search uses BGE embeddings (per memory `feedback_unified_e2e_fixture_user`-adjacent); same encoder reusable | Build `projects.<id>.documents` index in a vector DB (Postgres + pgvector, or LanceDB) |
| Chat retrieval from project docs | ❌ not wired | Extend chat-stream to query project RAG before answering |

**Effort: ~1.5–2 weeks for a robust version; ~1 week for an MVP that handles PDFs + spreadsheets.**

Pattern to follow: Galaxy's "Tool form" auto-detects dataset types and binds them to tool inputs. Similar — document type detection drives where it's indexed (prior-analysis → memory; protocol → instructions; sample sheet → dataset)

### Skills

A skill = a reusable workflow chain + sample inputs + expected outputs. User defines once; chat can dispatch by name later.

Galaxy precedent: **Galaxy Workflows** are essentially this — saved workflow definitions that any user in an org can run. BioMate's `workflow_chains` table is already 95% there; what's missing is:

- Per-project skill registry (`projects.<id>.skills` linking to workflow_chain rows)
- User-authored skill: UI form to create a skill from a completed chat session (1-click "save this run as a skill: title + description + sample inputs + tags")
- Chat-side skill matching: when user query mentions a skill name verbatim, route to that skill first (same pattern as the `_isClusterProfilerQuery` fast-path detector shipped today)

**Effort: ~1 week.**

### Bring-your-own (BYO) code execution

User provides own Python / R / shell from local file or git repo → runs inside BioMate.

| Capability | Status today | What's needed |
|---|---|---|
| Single-cell `run_code` execution | ✅ `run_code` tool exists (Python + R + shell) | none |
| Persisted code (re-runnable) | ❌ each `run_code` call is ephemeral | Add `projects.<id>.code_snippets` table — title, language, content, container |
| Git import (clone a repo and run) | ❌ not wired | Add `/api/projects/:id/import-git` that clones into a project workspace, sandboxed in a container |
| Code-as-workflow (treat a script as a registered workflow step) | ❌ | Wrap user code as a one-step Nextflow `.nf` shim and register in `workflow_chains` |
| Sandboxing + resource limits | ⚠️ `run_code` uses docker but `biomate-biotools:1` image issue surfaced earlier — needs robust image | Fix the image; add CPU/mem caps; restrict network egress |

**Pattern to follow:** **Galaxy's Tool Shed** — a marketplace of community-contributed tools, each with a definition file + container. BYO code in BioMate could be "personal tool shed" per user/project.

**Effort: ~2 weeks for git-import + persisted code; ~1 month for full Tool-Shed parity.**

---

## Part 4 — External references to stand on

### A — Galaxy (we are based on it; leverage natively)

What Galaxy has that BioMate doesn't surface today:
- **History compare view** — visual diff of datasets + parameters across two histories (https://galaxyproject.org/learn/managing-histories/)
- **Tool Shed** — marketplace of community tools, with version pins and dependency resolution (https://galaxyproject.org/toolshed/)
- **Workflow runtime parameters dialog** — the canonical "fill in params" UI BioMate's panel inherits from
- **Library system** — `libraries.py` / `library_datasets.py` already in `backend/lib/galaxy/managers/` — institutional shared dataset store. Maps directly to "project shared files."
- **Pages and Visualizations** — saved analysis pages, like notebooks. Could back project-dashboard reports.
- **Genomics workflow patterns** in `nf-core/{rnaseq,sarek,drop,scrnaseq,cutandrun}` — all already indexed

**Specific code to leverage:**
- `backend/lib/galaxy/managers/libraries.py` for project file management (already there!)
- `backend/lib/galaxy/managers/histories.py` for per-run snapshots
- Galaxy's `provenance.py` for the chain-of-custody audit trail needed in the report

### B — AWS BioSkills Hub / AWS HealthOmics (TBD — survey doc not found)

**Honest gap:** the product memo mentions a prior survey of "AWS BioSkills Hub" — no doc in this repo matches that name (verified via grep on `docs/`, `business/`, `research_repos/`). Three possibilities:
1. The doc exists under a different name → please point at it
2. It's about **AWS HealthOmics** (formerly Amazon Genomics CLI) — managed bioinformatics platform; published ref pipelines for variant calling, RNA-seq, secondary analysis
3. It's about **AWS Bioinformatics Sample Solutions / Bioinformatics on AWS architectures** in the AWS Solutions Library

Likely-relevant AWS resources to leverage:
- **AWS HealthOmics** — managed Nextflow + WDL execution, reference-store, variant-store. Pattern for "BioMate as managed orchestrator over user's data" — could replace Channel 5 self-managed S3 with HealthOmics-managed.
- **AWS Open Data — Registry of Open Data** — pre-staged public datasets (UKB demo subsets, 1000G, ENCODE, GTEx). Could surface as "Add public dataset" in project file browser. Zero ingress cost when in same region.
- **AWS Cost & Usage Reports** — for per-project cost tagging that integrates with Lago

### C — Google AI Co-scientist (Gottweis et al., *Nature* 2025; preprint Feb 2025)

**Relevance to BioMate:** multi-agent LLM system for scientific hypothesis generation + experimental design. Their "Supervisor → Generation → Reflection → Ranking → Evolution → Proximity → Meta-review" agent architecture is reusable for BioMate's research-intelligence-agent. Their evaluation framework (DRECK / Doctorate-Level expert review) is the gold standard for AI scientific output evaluation.

**Concrete leverages:**
- Their **tournament-style ranking** of competing hypotheses (Elo-based) — directly applicable to BioMate's chain disambig ranking (the BC-10 problem)
- Their **meta-review agent** that synthesizes across multiple agent outputs — pattern for BioMate's After-run Findings synthesis
- Their **proximity graph** for spotting near-duplicate hypotheses — applicable to chain catalog deduplication

Citation: Gottweis J et al. *Towards an AI co-scientist.* arXiv:2502.18864 (Feb 2025) → expected Nature publication 2025.

### D — Robin (mentioned in user memo, may be one of)

User said *"the nature publication of co-scientist of robin and others"* — most likely candidates:
- **"AI agents for scientific research"** by Demis Hassabis et al. — Nature Reviews 2024 perspective piece
- **Lab in the Loop / GenAI for biology** papers — Anthropic + Inceptive teams
- **Robin Cui** group (Princeton/Harvard) — agent-based scientific discovery

**Honest gap:** if "Robin" is a specific author, please confirm citation. Otherwise I'll default to Gottweis 2025 as the primary co-scientist reference.

### E — HeurekaBench / sc-HeurekaBench (already cited in repo)

`docs/papers/20260401_COMPETITOR_BENCHMARK_LANDSCAPE.md` already references **HeurekaBench (ICLR 2026, arXiv:2601.01678, EPFL Brbić group)** as the canonical AI co-scientist benchmarking framework. **Reuse: adopt HeurekaBench's scoring rubric (MCQ exact-match + OEQ LLM-judge) for BioMate's own multi-agent research-intelligence evaluation.**

### F — Open-source projects worth referencing

| Project | What to take |
|---|---|
| **nf-core/tools** | Pipeline scaffolding, schema-based parameter validation, MultiQC integration |
| **Snakemake** | Reentrant DAG execution + `--rerun-triggers` (cleaner than Nextflow `-resume` for partial re-execution) |
| **Cromwell / WDL** | Cloud-native execution backends; Terra (Broad) uses this stack |
| **Renku** (Swiss Data Science Center) | Project-as-first-class concept; provenance graph baked in. Closest open-source analog to what's being proposed. https://renkulab.io |
| **Pluto.jl** + **Marimo** | Reactive notebook pattern — every cell re-runs when its input changes. Could inform BioMate's reactive chain re-run UX. |
| **Pachyderm** | Data-lineage-first pipeline platform; every pipeline output is content-addressed. Pattern for our chain-of-custody report. |
| **MLflow** | Per-run tracking with parameters / metrics / artifacts. Pattern for project run dashboard. |
| **Hugging Face Spaces** | BYO code execution sandbox pattern (Docker + git import). Maps to §3 BYO code. |

---

## Part 5 — Priorities (recommended ordering)

| Priority | Item | Why now | Effort |
|---|---|---|---|
| **P0** | Lock down Channel 5 (no direct S3) | Compliance — needed before Liu Phase 2 PHI lands | 1-2 days |
| **P0** | User-assigned output location picker | Same compliance + UX gap | 3 days |
| **P0** | Fix Download Report (research-doc style; no file bytes) | Closes design promise; needed before pitching | 5-6 days |
| **P1** | Project dashboard + per-project file browser | Activates the project entity that's already in the DB | 5 days |
| **P1** | Per-project output organization (`biomate-projects/<id>/runs/...`) | Pairs with P0 picker; gives "My project folder" option real backing | 3 days |
| **P1** | Project instructions wired to chat | Quick UX win (field exists; just plumbing) | 2 days |
| **P2** | Project document index (RAG over uploaded docs) | Differentiator vs Galaxy; sets up skills | 5–10 days |
| **P2** | Project skills (save chain as named skill) | Compounds Project value; light effort | 5 days |
| **P3** | BYO code: git import + persisted snippets | Power-user feature; needed for advanced researchers (Zhi, Liu) | 10 days |
| **P3** | Project members / RBAC for team collab | Lab-scale collaboration; can defer until 2+ paying labs request it | 5 days |
| **P4** | Tool-Shed-like personal marketplace | Long-term vision; defer | 1 month+ |

---

## Part 6 — Five use cases to clarify input/output channels concretely

Picking five that span input modalities and output complexity, drawn from chains we've shipped or have specs for:

### UC1 — Liu rare-disease workup (chain id 1, paired WGS + RNA-seq)

| Channel | Input | Output | Report |
|---|---|---|---|
| Inputs | FASTQ pairs (WGS + RNA-seq), HPO terms | — | Dataset description |
| Run | nf-core/sarek + VEP + rnaseq + drop + case_report_aggregation | VCF, annotated VCF, expression outliers (TSV), splicing outliers (TSV), case_report.json | Findings: top variants + outlier genes |
| Visualizations in report | none yet (could add OUTRIDER PCA, FRASER heatmap) | — | embed PCA + 2 heatmaps |
| File sizes | input ~30 GB; output ~5 GB | — | metadata only — bytes via endpoint |

### UC2 — BIO DESeq2 (bulk RNA-seq differential expression)

| Channel | Input | Output | Report |
|---|---|---|---|
| Inputs | count matrix CSV, sample metadata | — | dataset description (samples, contrast, design) |
| Run | DESeq2 → apeglm → clusterProfiler → EnhancedVolcano | results.rds, volcano.png, GO dotplot.png, top50_heatmap.png | Findings: 2841 DE genes at FDR<0.05 |
| Visualizations in report | volcano + GO + heatmap embedded | — | yes |
| File sizes | input <100 MB; output ~20 MB + 3 figures | — | embed figures; describe data |

### UC3 — ZZ02 scGWAS for immune cell types (Zhao lab)

| Channel | Input | Output | Report |
|---|---|---|---|
| Inputs | GWAS sumstats (MAGMA boxcox txt), scRNA panel (TSV), network file | — | dataset description |
| Run | scGWAS Java jar | combined-z.txt (724 KB), all.random_modules.txt (19 MB), shared_genes.calibration.txt (35 MB) | Findings: top trait × cell-type associations |
| Visualizations in report | trait × cell-type heatmap (BioMate-generated) | — | embed heatmap |
| File sizes | input ~10 MB; output ~55 MB | — | metadata only |

### UC4 — Z01 TorchGWAS on UDIP phenotypes (Zhi lab)

| Channel | Input | Output | Report |
|---|---|---|---|
| Inputs | UDIP phenotype matrix (CSV, 256 cols × N samples), PLINK bed/bim/fam | — | dataset description (UKB ancestry, sample N, variant N) |
| Run | torchgwas_udip_phenotype_scan (4 phases) | per-phenotype Manhattan/QQ PNGs, novel-loci TSV, GWAS Catalog overlap JSON | Findings: 1142 GW-sig hits, 18 novel |
| Visualizations in report | top 4 Manhattan + QQ plots embedded | — | yes |
| File sizes | input ~1 GB; output ~500 MB | — | metadata + embed top figures |

### UC5 — Tier-0 T01 bispecific format triage (drug design)

| Channel | Input | Output | Report |
|---|---|---|---|
| Inputs | target pair (PD-1, VEGF), indication (NSCLC), constraints | — | brief inputs description |
| Run | bispecific_format_triage (4 phases) | mechanism_inference.json, format_scoring.csv, ranked_recommendation.json, report.md | Findings: tetravalent cooperative format #1 with mechanism + indication weighting |
| Visualizations in report | format-scoring radar chart (BioMate-generated from CSV) | — | embed radar chart |
| File sizes | input <1 KB; output <500 KB | — | embed everything; full report inline |

### Common output-channel pattern across 5 use cases

All 5 follow the same rule:
1. **Input bytes** — never in report. Description only (size, count, format, hash).
2. **Output bytes** — never in report. Per-output description + download URL via BioMate endpoint.
3. **Visualization figures (PNG/SVG, <500 KB each)** — embed in report when ≤5 figures total per run; otherwise gallery-link.
4. **Tables (TSV/CSV, <100 rows)** — embed as Markdown table; larger tables linked.
5. **Provenance** — chain_id, parameter snapshot, container digests, timestamp, signed run-state hash — always in report.

This is the "research document" shape the product memo asks for.

---

## Open questions for the user

1. **AWS BioSkills Hub doc** — please point to it; couldn't find by name in repo.
2. **Robin & co-scientist paper** — confirm authors (Gottweis 2025? Lab in the Loop? Robin Cui?).
3. **Compliance scope** — for Liu Phase 2, is target compliance HIPAA / 21 CFR Part 11 / GDPR / all? Drives the audit-log + chain-of-custody specifics.
4. **Project members** — single-tenant per user, or invite-by-email team support needed for Phase 1?
5. **BYO code policy** — what languages must we support (Python only? R also? Shell? Containers?), and what's the sandbox boundary (network access yes/no, GPU yes/no)?
6. **Output retention policy** — how long do per-project outputs live by default? User-configurable per project?

Please confirm any of these so I can tighten the P0 list and start implementation.

---

## Appendix — Resource inventory snapshot

**Already in BioMate (verified):**
- ✅ `projectSchema` + `projectDocumentSchema` + `/api/projects` CRUD (31/31 audit pass, 2026-06-13)
- ✅ Galaxy `libraries.py` + `histories.py` managers (`backend/lib/galaxy/managers/`)
- ✅ `run_code` tool (Python + R + shell)
- ✅ Pilot Experiment Panel (A/B comparison) at `frontend/client/src/components/pilot-experiment-panel.tsx`
- ✅ chain composer + `_resume` rerun-from-step
- ✅ BGE embeddings used for chain search (reusable for project document RAG)
- ✅ Lago billing per workflow run

**Already-paid-for external infra:**
- ✅ AWS Batch + ECR
- ✅ S3 bucket `biomate-nextflow-work`
- ✅ Lago for billing + quotas

**Need to acquire / set up:**
- new S3 bucket `biomate-projects` (per-project layout)
- bucket policy lockdown on `biomate-nextflow-work`
- pgvector or LanceDB for project document RAG (could reuse existing PG instance with `CREATE EXTENSION vector`)
- WeasyPrint or playwright-headless for PDF report rendering

**External references for design + benchmarking:**
- Google AI co-scientist (Gottweis et al. 2025) — multi-agent architecture pattern
- HeurekaBench (Panigrahi/Brbić ICLR 2026) — already cited in `competitor_benchmark_landscape.md`
- Renku — closest open-source analog to project-first design
- Galaxy History compare + Tool Shed — native code we inherit
- nf-core schema-based param validation — adopt for project skills registry
