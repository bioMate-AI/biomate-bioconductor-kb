# BioMate System Documentation — V2 (2026-08-29)

**Status:** authoritative, code-verified · **Branch at capture:** `fix/resolver-prefer-real-nfcore-pipeline` · **Supersedes:** `docs/01-architecture` … `docs/07-onboarding` (Jan 2026) and `docs/architecture/*.drawio.xml` (Jan 2026).

This is a fresh, ground-truth documentation set produced by reading the real code (every count and file:line reference was verified against the checked-out tree, not from memory or prior docs). It is the reference baseline for the **next system-upgrade cycle**: document this version clearly, then upgrade against it.

---

## How this set was built

Eight parallel code-mapping passes, each over one subsystem, each required to cite exact `file:line` and to verify counts by running the query (`wc -l`, `sqlite3`, `grep -c`). Where a mapping contradicted CLAUDE.md or the memory index, the **code won** and the discrepancy is flagged in [§ Corrections](#corrections-to-stale-facts) below.

## Reading guide (grouped into topic folders, like the prior `docs/01-architecture` set)

| Folder | Docs | Covers |
|--------|------|--------|
| [`01-architecture/`](01-architecture/) | `SYSTEM_OVERVIEW.md`, `DIAGRAMS.md` | Topology, tech stack, request lifecycles, process model; Mermaid diagrams for every subsystem |
| [`02-frontend/`](02-frontend/) | `FRONTEND.md` | React client (183 comps + flag-gated `v2/`), Express server (308 routes), SSE, client auth |
| [`03-backend-ai/`](03-backend-ai/) | `AI_ASSISTANT.md`, `WORKFLOW_EXECUTION.md` | AI orchestrator, LLM resolver, routing, generation, search, param extraction · Nextflow executor, run-state/Redis, QC auto-loop, autofix, CryoSPARC |
| [`04-domains/`](04-domains/) | `DOMAIN_MODULES.md` | Drug discovery/ADMET/PBPK/IND/CRO, cryo-EM, multi-omics, ML training, research agent, workflow catalog |
| [`05-data/`](05-data/) | `DATABASES.md` | `galaxy_ai_tools.db` (FTS5+vec), Postgres app+LTM, migrations, Redis, S3, other SQLite |
| [`06-billing-auth/`](06-billing-auth/) | `BILLING_QUOTA.md`, `AUTH_CREDENTIALS_SANDBOX.md` | Flat-tier model, quota ledger, Stripe, Lambdas · JWT/OAuth/MFA, Galaxy provisioning, BYOK stores, gVisor sandbox, interactive tools |
| [`07-memory-connectors/`](07-memory-connectors/) | `MEMORY_LEARNING.md`, `CONNECTORS_MCP.md` | 4-layer memory (design vs code), LTM tables, learning mechanisms · MCP server (24 tools), lab instruments, auto-update |
| [`08-infra-deploy/`](08-infra-deploy/) | `INFRA_DEPLOY.md` | Docker topology, AWS (Batch/ECR/S3/Redis/Lambda), `sync_to_dev`, gunicorn, envs |
| [`09-testing/`](09-testing/) | `TEST_PLAN.md` | Comprehensive module/function-based test plan + coverage matrix + gaps |

---

## The system in one paragraph

BioMate is a full-stack AI bioinformatics platform. A user chats in a React SPA; the **Node/Express server** (`frontend/server`, ~120 modules, one 17k-line route registrar) handles auth, streaming chat, and proxies scientific work to a **Python Galaxy backend** (`backend/lib/galaxy`, gunicorn, 4 workers). The backend's **AI assistant** classifies intent, searches a 4,057-workflow / 12,301-tool index (SQLite FTS5 + BGE vector embeddings), routes to or composes a Nextflow/Galaxy workflow, prefills parameters (rule + LLM), and **launches Nextflow head processes as local subprocesses whose tasks run on AWS Batch**. Live progress streams back over SSE. A **QC auto-loop** grades results against an evidence-graded threshold DB and emits remediation suggestions; an **autofix** agent debugs failed runs with multi-round LLM + tool use. State persists across gunicorn worker recycles via a **Redis run-state store** with an orphan-completion poller. Billing is **flat-tier** (Stripe + an internal Redis cost ledger against `DEFAULT_PLAN_LIMITS`). Cross-session **long-term memory** (Postgres) records user corrections and preferences. External surfaces (Claude Desktop, ChatGPT, Slack, lab instruments) reach the platform through a **separate MCP connector repo** (24 tools).

---

## Product status — canonical use cases (what actually works end-to-end)

The single most important exec-facing view: which flagship journeys are proven versus aspirational. 🟢 verified end-to-end · 🟡 works but with a real caveat · 🔴 not proven end-to-end.

| Use case | Status | Reality |
|----------|:------:|---------|
| **RNA-seq** (nf-core/rnaseq) | 🟢 | Runs end-to-end on AWS Batch; SSE step updates; findings + methods report |
| **CryoEM SPA** | 🟢 | Works — but on a **separate EC2 + CryoSPARC-API path** that bypasses Nextflow/Batch entirely |
| **ADMET / hERG screening** | 🟡 | Prediction workflow runs; QC gate logic exists — **but the hERG auto-loop gate has never fired on live dev data** (loops tested on truth data only). The signature "self-healing" moat is unproven live |
| **WGS / variant calling** (sarek) | 🟡 | Covered by a **single capstone e2e** (`wgs-capstone.e2e.ts`); GATK depth thin |
| **CRO compliance** | 🟡 | Export/campaign modules + hERG-gated `cro_submission_export` exist; **no full "create campaign → attach ADMET → export package" e2e journey** |
| **Drug-discovery IND** | 🟡 | §2.6.1 assembly + DOCX + e-sign have strong unit tests; **the full "PBPK + trial → §2.6.1 DOCX download" journey is not an e2e assertion** |
| **PBPK / BOIN** | 🟡 | Good offline benchmark scores; real-execution evidence thin |
| **Proteomics · Metabolomics · ChIP-seq · Single-cell · Spatial** | 🔴 | **Indexed in the workflow DB but NO real end-to-end run evidence** on S3 |

> The distinction "works vs. aspirational" is deliberate throughout this set: the memory hierarchy is L3-only (L1/L2 are design-only), emergent-procedure learning is a **stub**, feature-tier gating is **flag-off**, and the ADMET hERG live gate is **unfired**. Capability claims sit next to their caveats on purpose — see [09-testing/TEST_PLAN.md](09-testing/TEST_PLAN.md).

---

## Corrections to stale facts

These are places where the live code disagrees with CLAUDE.md / the memory index. **Trust the code column.**

| Topic | Stale statement | Verified reality (2026-08-29) |
|-------|-----------------|-------------------------------|
| Workflow DB size | "2,455 workflows, 34 domains" (CLAUDE.md) | **4,057 workflows, 12,301 tools, 39 domains** (`sqlite3` count) |
| Local DB is a stub | "local is always a stub" (memory) | The local `backend/database/galaxy_ai_tools.db` in **this checkout** is the full **315 MB enriched** DB. True 0-byte stubs are `backend/data/*.db`, `backend/galaxy_ai_tools.db` |
| Default LLM | "Claude Sonnet 4.5" flat | Per-**role** resolver (`model_resolver.py`); global default `claude-sonnet-4-5`, but the **YAML fallback chain** (`gemini-3.1-pro-preview` → … → `claude-sonnet-4-5`) has highest runtime priority. Only ~10 sites use the resolver; ~23 still hardcode literals |
| Interactive Tools gate | "gated behind `BIOMATE_ENABLE_IT=1`" (memory) | **No such env var exists.** Gating is at the Galaxy tool-XML / `job_conf.yml` level |
| MCP tool count | "19-tool MCP" (memory) | **24 tools** (21 cloud + 3 local instrument) in `tools_manifest.py` |
| Tier gating | "zero tier gating in code" (memory) | Half-true: **feature** gating exists behind `TIER_ENFORCEMENT=on` (default off); **spend/quota** gating (402/429) IS live |
| Memory 4 layers | "L1/L2/L3/L4 all present" | Only **L3 (Postgres LTM)** is a real memory store. L1/L2 as memory tiers are design-only; L4 vectors are the workflow/tool search |
| Vector search | (implied FAISS/external) | **No external index** — all in-SQLite (`tools.embedding` BLOB + `cryo_em_chunks_vec` sqlite-vec `float[384]`); workflow embeddings `.npz` being retired |
| Emergent procedures | "3+ episodes → procedure" | Detected but **not written** — `consolidateEpisodes` flags ≥3 but never calls `createProcedure` (stub) |
| Nextflow head | (implied all-Batch) | Nextflow **head runs as a local subprocess**; only tasks land on Batch. Cryo-EM bypasses Batch entirely (EC2 + CryoSPARC API) |
| v2 frontend | "design-reference / dead art" | `v2/` "ResearchApp" is a **live, flag-gated UI flavor** (`?ui=v2` / `localStorage.biomate_ui`, `useUiFlavor`, `App.tsx:194`). Default surface is v1 `components/` |
| Gemini agentic tools | "dead on Gemini — live bug" (memory) | Was a **frontend intent-classification fallback bug** (not the model); fixed by detecting inline data → `workflow_generation`. Memory index `project_agentic_tools_gemini.md` is now stale on this point |

---

## Known architectural debts carried into the upgrade

Short list to steer the next cycle (detail in the relevant docs):

1. **LLM config fragmentation** — `model_resolver.py` is the intended single source of truth but ~23 modules + the frontend still hardcode model literals (some stale). Blocks BYOK "all-tasks" and the model-matrix sweep. (`docs/20260824_LLM_CONFIG_FRAGMENTATION_AUDIT.md`)
2. **Two mega-files** — `frontend/server/routes.ts` (17k LOC) and `galaxy-assistant.ts` (9.7k LOC) concentrate almost all API + LLM logic; `nextflow_executor.py` is 10k LOC.
3. **Two parallel frontend component trees** — mature `components/` (183 `.tsx`, 169 excl. tests) and the flag-gated-live `v2/` "ResearchApp". Not unified, and **v2 lacks the CRITICAL live `data-status` transition contract** (0 `data-status` in `v2/PhaseCard`/`WorkflowPanel` vs 5 in the v1 viewer) — a regression risk if v2 is promoted.
4. **Data-source fragmentation** — 60+ sources across **3 siloed registries** (~30 Galaxy + 20 federation + 14 MCP; `data_sources.py` declares ~64), but **chat sees only ~20**. One source registry all surfaces read is the fix.
5. **Learning loop half-wired** — preference/correction learning works; emergent-procedure distillation is detected but not persisted.
6. **Coverage gaps** — proteomics/metabolomics/ChIP-seq/single-cell/spatial have no real end-to-end run evidence; ADMET hERG auto-loop gate never fired live on dev. (See [09-testing/TEST_PLAN.md](09-testing/TEST_PLAN.md).)
7. **Tool-enrichment ceiling** — 10k+ Galaxy tools still lack `scientific_context_v2`, which caps `NextflowComposer` generation quality (a first-order product-quality debt).
8. **Leakage-suspect research scores** — the 2026-08 immune-LLM/VCC headline numbers were found leakage-inflated in a code audit; **do not cite in product/fundraising decisions until re-run** (`docs/20260828_IMMUNE_LLM_AND_VCC_CODE_AUDIT.md`).

---

## Review panel & changelog

This set was written from 8 parallel code-mapping passes, then **adversarially reviewed** against the code by three role agents (system architect · UI designer · product manager). Their brief: distrust the prose, verify every claim at `file:line`, find errors/oversimplifications/omissions.

**Applied from the UI-designer review:**
- Corrected the biggest UX error: `v2/` "ResearchApp" is a **live, flag-gated flavor** (`?ui=v2`/`localStorage.biomate_ui`, `App.tsx:194`), not dead reference art — added the flag + which surface is default, and flagged the **`data-status` parity gap** (v1 viewer has it; v2 does not).
- Fixed the sidebar entry list (real: New Chat, Workflows, Starred Workflows, Recent Tools, Connectors, IND Report, Billing, Settings — not "Runs/CRO").
- Added the missing `step-output-preview.tsx` per-file preview dispatcher; corrected component count (189 → 183/169-excl-tests).
- Added the **live `data-status` UX contract table** (pre-run/running/completed/failed/QC-blocked → what the user sees) to [FRONTEND §4.1](02-frontend/FRONTEND.md).

**Applied from the PM review:**
- Documented two entirely-missing subsystems: the **expert-skills persona layer** ([DOMAIN_MODULES §9](04-domains/DOMAIN_MODULES.md)) and the **`workflow_ops/` diagnostic-agent fleet** ([WORKFLOW_EXECUTION §4.1](03-backend-ai/WORKFLOW_EXECUTION.md)) — plus test lines for both ([TEST_PLAN §2.4b, §3.6](09-testing/TEST_PLAN.md)).
- Added the **canonical use-case status table** (above) — the exec-facing "what actually works end-to-end" view.
- Corrected the "empty placeholder" dirs (they are **absent**, not empty); quantified the data-source-fragmentation debt (60+/only ~20 to chat); added debts #7 (tool-enrichment) and #8 (leakage-suspect scores); added the ARM64 DIA-NN limitation; added CRO/IND full canonical-journey e2e to the test plan.

**Applied from the system-architect review** (deep `file:line` audit, 45+ spot-checks; verdict **~90–92% of claims exactly accurate**):
- Fixed the 2 genuinely misleading citations: salvage-function line numbers now point at the `def`s (`_looks_like_false_success` L1216 / `_looks_like_false_failure` L1242) not their call sites; `find_best_container_description` cited at its method line (L357, not the class at L273).
- Fixed count/line drift: `qc_thresholds.json` 995→994, `universe.sqlite` 186→187 tables, `orphan_finalizer.py` ~245→312 LOC, `model_resolver.py` ~90→80 LOC and "~10"→"~15" call sites, GPU queue L2851→L2850, `herg_inhibition_prob`→`herg_inhibition_prob_threshold`.
- Added the missing cross-cutting architecture the review flagged: a new **[SYSTEM_OVERVIEW §6](01-architecture/SYSTEM_OVERVIEW.md)** covering HTTP-layer security (rate limiting `rate-limit.ts`, helmet/CSRF/CORS `security-config.ts`), failure modes (chat-stream mid-token failure, non-transactional cross-datastore writes, the `RUN_STATE_STORE` landmine), and concurrency/scaling limits (NF semaphore, shared embed socket, single-EC2 CryoSPARC).

**Trust verdict:** across all three reviews, ~90%+ of the dozens of spot-checked `file:line`/count/function claims were **exactly accurate**; no fabricated function, env var, or DB count was found; all 5 draw.io files are well-formed (`xmllint` clean) and none contradicts the code. The corrections above are applied. The remaining honest weakness — now addressed — was *omission* (two subsystems, security/failure-mode/scaling architecture), not factual error.
