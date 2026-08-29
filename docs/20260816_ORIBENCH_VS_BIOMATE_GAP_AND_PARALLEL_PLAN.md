# OriBench vs BioMate — honest gap analysis + parallel implementation plan

**Date:** 2026-08-16
**Source reviewed:** `药物科研的AI原生工作台——OriBench.mhtml` (WeChat article "BioTender 观测日志", 2026-08-11) describing OriBench = "OriGene AI Workbench" (https://oribench.lglab.ac.cn/).
**BioMate baseline reviewed (authoritative, code-verified):** `docs/20260804_BIOMATE_USER_MANUAL.md` (v1.0, Aug 2026) + code (`skill_manager.py`, `skill-selector.tsx`, `/api/skills`, `memory-repository.ts`/`memory-integration.ts`, `provenance.py`, `execution-env-policy.ts`, `connectors-dialog.tsx`).

> **Honesty note (per our over-claiming discipline):** I first assumed BioMate lacked Skills, Experts, Memory, provenance, and compute-mode routing. **That was wrong.** Reading the current manual + code shows BioMate already has all of them. The genuine deltas are narrow and mostly UX/packaging. This doc leads with the parity, then the real gaps.

---

## 1. What OriBench actually is (from the article)

An "AI-native workbench for drug R&D." A **desktop client** where a user creates drug-research tasks, references local files, calls expert Agents + drug-research Skills, orchestrates long tasks, and dispatches local or remote compute — with the whole process recorded, sourced (溯源), and archived. Core pieces:

- **Tri-modal command palette in the composer:** `/` = invoke a **Skill** (druggability filter, antibody info extraction, target-evidence organization, patent search); `#` = pick an **Expert Agent** (medicinal-chemistry expert, literature-intelligence expert); `@` = reference a file.
- **Skill vs Expert distinction:** Skills = well-defined subtasks; Experts = tasks needing professional judgment.
- **Local vs remote compute:** small tasks local; big/batch on remote GPU/enterprise; sandbox isolation for sensitive data; private deployment preferred.
- **Modules:** *Activity* (task status), *Memory* (project background, output-format prefs, team analysis standards, data-egress rules), *Customize* (manage experts/skills/plugins/**private MCP**).
- **Enterprise:** private deployment, container isolation, RBAC, process 留痕.
- **Honesty stance:** don't use outputs as final decisions; annotate evidence basis/strength per conclusion; flag what needs human review.

---

## 2. Parity — what BioMate ALREADY has (do NOT rebuild)

| OriBench feature | BioMate equivalent (verified) | Evidence |
|---|---|---|
| Skills (domain subtasks) | **Skills system** — 9 expert packs (drug-discovery-chemist, regulatory-affairs, structural-biologist, rnaseq-analyst, single-cell-analyst, multiomics-integrator, gwas-statistician, clinical-biostatistician, ml-bioinformatics) **PLUS the whole `bioconductor_skill/` package** (biobase, biostrings, genomicranges, …); user-selectable + auto-detected + composable + shareable `.md` | `backend/lib/galaxy/ai/skill_manager.py`, `skills/*.md`, `bioconductor_skill/`, `skill-selector.tsx`, `/api/skills`, Connectors→Skills tab (manual §14) |
| Expert Agents (personas) | Same skills act as expert-reasoning packs injected into the system prompt | `skill_manager.build_system_block()` |
| **Customize → add a Skill** | **SHIPPED** — Connectors→Skills → "upload your own .md skill files"; validates `name`+`triggers` frontmatter, writes to skills dir, hot-reloads | `connectors-dialog.tsx:285,338`, `POST /api/skills/upload` → `ai_assistant.py:6130 upload_skill` |
| **Customize → add a private/external MCP** | **SHIPPED** — "Add an MCP server" with validated **probe → preview → confirm** flow; tools visible-only until reviewed | `connectors-dialog.tsx:505`, `/api/mcp/servers` (+`/probe`), `mcp-registry.ts` |
| Memory module | **Memory** — long-term project memory (goals, organisms, data types, tools, decisions, run outcomes; records corrections; account/project-scoped) | manual §4.4; `memory-repository.ts`, `memory-integration.ts`, `memoryService` in `routes.ts` |
| `@` reference a file | Paperclip uploader (Local/URL/Dataset-browser), data cards, **reuse prior outputs** | manual §6 |
| Local vs remote compute | **Three lanes**: Ask (cited research) / Compute (`run_code`, network-isolated sandbox) / Run (4,055 workflows on AWS Batch incl. GPU); executor inferred by size/resource | manual §3, §8.4; `execution-env-policy.ts` `inferExecutor()` |
| Activity (task status) | Workflows list + `/dashboard` + live phase/step SSE + sidebar status dots + notifications | manual §5, §8 |
| Provenance / 留痕 / archival | **Audit log** (timestamped JSON, every step/param/version/QC/fix) + **21 CFR Part 11** SHA-256 hash-chained immutable trail + TOTP e-sign | manual §10.3, §12.8; `provenance.py` (dataset lineage) |
| Customize / private MCP | Connectors dialog: Databases / AI Models (BYOK) / Skills / **MCP**; 24-tool MCP server; 10 lab-instrument connectors | manual §14; `connectors-dialog.tsx` |
| Enterprise RBAC | Project roles Viewer / Editor / Owner + per-project **instructions** | manual §11 |
| Evidence-strength annotation | **GOLD/SILVER/BRONZE** QC threshold grading + per-parameter citations + applicability-domain flags + "trust but verify" | manual §7.2, §9.1, §12.8 |
| Human-review stance | Halt vs advisory QC gates; remediation requires user confirm; cited answers, no fabricated refs | manual §9, §4.1 |
| Long-task orchestration | Multi-workflow planning / chain composer | `docs/20260509_..MULTI_WORKFLOW_PLANNING..`, `docs/20260610_CHAIN_COMPOSER_FINAL_STATE.md` |

**Where BioMate is clearly AHEAD of OriBench's described scope:** 4,055 validated workflows / 40 domains (vs a handful of named pipelines); Auto-Loop QC with evidence-graded gates + auto-remediation; the `run_code` sandbox lane; 21 CFR Part 11 regulatory stack + IND §2.6 dossier; anti-confabulation cited research; 60+ live databases; 10 lab-instrument bridges.

---

## 3. Genuine gaps (verified absent in code)

Only four, and they are narrow:

### G1 — Inline `/` `#` `@` command palette in the composer  *(UX; capability already exists)*
BioMate's skills live in a separate `skill-selector.tsx` popover; files come through the paperclip; the model lives in Connectors. There is **no inline slash/hash/at menu in the chat composer** (verified: no command-menu handler in `chat-interface.tsx`). OriBench's single biggest ergonomic win is that `/`, `#`, `@` invoke skill / expert / file *without leaving the keyboard*. This is a discoverability + speed gap, not a capability gap — the backend (`/api/skills`, file datasets, tool search) already exists to power it.

### G2 — Skill vs Expert as discrete, explicitly-invocable units  *(model refinement)*
BioMate treats "skills" as **passive** reasoning packs (auto-detected or toggled), always folded into one assistant. OriBench separates a **Skill** (a bounded, parameterized subtask you fire once) from an **Expert** (a persona you converse with). BioMate has no "run just this skill as a discrete task" path distinct from "set the assistant's persona." Worth adding as an explicit invocation contract behind G1.

### G3 — Specific info-synthesis skills: patent search (+ target-evidence dossier, antibody-info extraction)  *(net-new content)*
Verified: **no patent capability** anywhere (`grep patent` → business docs only, no skill/tool). Target-evidence "dossier" and antibody-information extraction are also not first-class skills (antibody *redesign* exists as a structure workflow; evidence *organization* does not). Patent search is the clearest net-new user value and needs a real data source (Lens.org / PatentsView / Google Patents API) plus federation wiring.

### G4 — On-prem / private-deployment-first posture  *(distribution/deployment; strategic, mostly sales-gated)*
OriBench defaults to **on-prem / container-isolated / sandboxed-for-sensitive-data** (its target is Chinese pharma that won't send IP to SaaS). BioMate is SaaS with on-prem as a sales motion ("contact your representative", manual §16). The *self-service Customize pieces are already done* (add-skill and add-private-MCP both shipped — see parity table). What remains is genuinely **deployment strategy**: a packaged on-prem / air-gapped install with container isolation. Note BioMate's `run_code` lane is **already a network-isolated sandbox** (manual §3.3, §4.3), so the "sandbox sensitive data" primitive largely exists; the gap is the *packaged private deployment*, not a missing runtime control. Highest-effort, most sales-gated item — build only when a named deal pulls it.

**Explicitly NOT gaps** (don't build — all shipped): Memory, Activity/status, audit/provenance, RBAC, evidence-strength grading, compute-mode routing, the Skills system, **add-your-own Skill**, **add-your-own private MCP**, MCP-driven-from-other-tools, network-isolated compute sandbox, cited research.

---

## 4. Parallel implementation plan (file-disjoint workstreams)

Four streams, deliberately non-overlapping in files so each runs in its own worktree/PR without merge collisions. Ordered by leverage-per-effort.

### WS-1 — Inline command palette `/` `#` `@`  *(FRONTEND-led; highest leverage)*
- **Deliver:** composer typeahead — `/` searches Skills + workflows + tools; `#` picks one of the 9 expert personas; `@` references uploaded files / dataset-browser / prior-run outputs.
- **Files (owned):** `frontend/client/src/components/chat-interface.tsx` (composer key handling), NEW `frontend/client/src/components/command-palette.tsx`, reuse `skill-selector.tsx` + `/api/skills`; `@` resolver hits existing file/dataset endpoints.
- **Backend contract needed from WS-2:** a `/api/skills/invoke` (or reuse chat with an explicit `skill_id`) + a lightweight `/api/tools/search`. Coordinate on the JSON shape only; no shared files.
- **Effort:** M. **Risk:** low (additive UI). **Depends on:** WS-2 contract (can stub first).

### WS-2 — Explicit Skill/Expert invocation model  *(BACKEND-led)*
- **Deliver:** separate "Expert" (persona for the turn/session) from "Skill" (bounded parameterized task); add an explicit-invoke path so the palette can fire a named skill with args instead of relying on auto-detect.
- **Files (owned):** `backend/lib/galaxy/ai/skill_manager.py`, the skill-routing hook in `backend/lib/galaxy/ai/ai_assistant.py`, a thin route in `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`.
- **Effort:** M. **Risk:** medium (touches routing — gate behind a flag, additive branch, mirror the multiomics-routing env-gate pattern). **Depends on:** none (defines the contract WS-1 consumes).

### WS-3 — Info-synthesis skills: patent search + target-evidence + antibody extraction  *(BACKEND/DATA-led)*
- **Deliver:** a **patent-search** federation source (Lens.org or PatentsView API) surfaced as a Skill; a **target-evidence dossier** skill composing existing DB calls (UniProt/OpenTargets/ClinVar/ChEMBL/literature); an **antibody-information extraction** LLM skill (CDR/isotype/epitope from a supplied doc/seq).
- **Files (owned):** NEW `backend/lib/galaxy/ai/skills/patent-intelligence.md`, `target-evidence.md`, `antibody-intel.md`; NEW patent connector under the federation/data-source layer; register in the source registry.
- **Effort:** M–L (patent API integration + keys). **Risk:** low-medium (net-new, isolated). **Depends on:** none. **Note:** patent APIs need credentials/ToS review — flag before wiring.

### WS-4 — Packaged on-prem / air-gapped deployment  *(INFRA/DEPLOY-led; sales-gated)*
- **Scope reduced:** add-private-MCP and add-skill are already shipped, and `run_code` is already a network-isolated sandbox. What's left is a **packaged private/air-gapped install** with container isolation + a data-egress policy doc — pure deployment engineering, not missing product features.
- **Files (owned):** deployment manifests / compose / helm under a new `deploy/` tree, `run_code` egress-policy config, a deployment runbook under `docs/`.
- **Effort:** L. **Risk:** medium (security surface). **Depends on:** none. **Note:** most sales-gated; build only when a named enterprise deal pulls it forward.

**Disjointness map:** WS-1 = chat composer + new palette component; WS-2 = skill_manager + ai routing; WS-3 = new skill `.md` + federation source; WS-4 = connectors-dialog + sandbox/deploy. Only coupling is the WS-1↔WS-2 **API contract** (agree the JSON, then build independently). Recommended order: WS-2 contract → WS-1 + WS-3 in parallel → WS-4 last.

---

## 5. Recommendation

BioMate is at or ahead of OriBench on capability; the differentiator OriBench actually ships is **composer ergonomics** (the `/ # @` palette) and a **private-first deployment posture**. The single highest-ROI item is **WS-1 + WS-2** — surface the Skills/Experts/files we already have through a fast inline palette. **WS-3 (patent search)** is the clearest net-new user value. **WS-4** is real but sales-gated; defer unless a deal pulls it.

Do NOT spend effort rebuilding Memory, provenance, RBAC, evidence-grading, or compute routing — they exist and are, in several cases, more mature than OriBench's.
