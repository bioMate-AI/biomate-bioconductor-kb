# Mira Upgrade (June 10 2026) vs BioMate — Honest Side-by-Side

**Date:** 2026-06-19
**Sources:**
- `business/mira.pdf` — Deep Principle's June 10 2026 product-upgrade announcement, all 15 pages
- Prior crawl of `sciclaw.ai/help/*` (now superseded by Mira branding)
- BioMate codebase audit (`docs/20260619_NEXT_PHASE_*` + `docs/20260619_SCICLAW_MIRA_COMPETITOR_LEARNINGS.md`)

**Why this update matters:** the Mira upgrade lands three substantial new features (Expert Team / Research Canvas / WIKI) that materially change the competitive picture vs the SciClaw learnings I wrote earlier today. This doc supersedes that one for the Mira-specific dimensions.

## Correction to my earlier docs

| What I said | Reality |
|---|---|
| "They have Telegram + Discord; we have nothing" — earlier SciClaw doc | **Wrong.** BioMate ships Slack + Email + Webhook + Database notifications via `backend/lib/galaxy/ai/workflow_ops/notification_service.py` (`NotificationChannel.SLACK / EMAIL / WEBHOOK`). Closer to enterprise. No WeChat in code (user mentioned it; may be planned or in a separate worktree — flagged). Mira's Telegram+Discord is consumer-friendly; ours is enterprise-friendly. **Neither is universally better.** |
| "SciClaw is sandbox-only" | The Mira upgrade reveals proprietary self-developed compute models (Reactify quantum chemistry, MPA materials properties, ReactBO active-learning) + integrated DFT/MD compute. They DO compute — just materials/chemistry, not bioinformatics pipelines. **Refined: they compute materials science; we compute bioinformatics. Different verticals.** |

## What the Mira upgrade ships (three core features)

### 1. 专家小队 (Expert Team) — user-configurable multi-agent team builder

**What it is:** *not* a fixed workflow template. User opens an empty "Expert Team" config panel; describes each agent's role in natural language (e.g. "literature retrieval agent," "code execution agent," "peer-review revision-suggestion agent"). User defines collaboration order + information passing between agents.

**Concrete case from the announcement:** a new PhD configured an Auto Research framework in **3 minutes**, fed in a research direction, and the autonomous team produced a complete AI Paper draft (literature review → experimental design → results analysis) by the same afternoon.

**Underlying pattern:** essentially **AutoScientists (Harvard, arXiv:2605.28655)** applied to user-configurable scenarios, with shared state + role-based agents. Plus Robin/Co-Scientist-style hypothesis-driven coordination.

### 2. 科研画布 (Research Canvas) — infinite multi-file canvas

**What it is:** infinite-surface canvas inside each project. Sidebar = full file list. Center = freely-draggable canvas with simultaneous-open file viewers.

**Supported file types (highlighted in announcement):** CIF crystal structures, XRD spectra, band-structure diagrams, density-of-states curves, PDF papers, Python code outputs, experimental charts, handwritten notes. All rendered side-by-side with linked notes.

**Persistence:** real-time cloud-saved. "When you reopen, everything is exactly where you left off" — survives computer crashes.

**Use case quoted in announcement:** a bioinformatics user combined RNA-seq + proteomics + metabolomics analysis results side-by-side: *"the only problem was screen real estate."*

### 3. WIKI — auto-overnight project-knowledge consolidation

**What it is:** background job that runs each night. Processes that day's chats + tasks + uploaded materials. **Does NOT just dump everything** — judges which concepts you repeatedly raised, which conclusions are worth distilling, which open questions need persistent tracking. Writes structured per-project knowledge base.

**Output structure:** chapters with logical hierarchy, mutual cross-references via clickable links, navigable.

**Use case quoted:** a computational neuroscience user said *"if I had this in college, it would be better than all 4 years of my notes."* WIKI used to auto-generate HTML brainstorm boards on demand.

## "Vibe Researching" — their positioning frame

Mira's stated philosophy. Compares to "Vibe Coding":
- Vibe Coding: requirements are clear; AI builds.
- Vibe Researching: requirements are vague/exploratory; "you walk in front, AI walks beside."
- User owns direction, intuition, insight. AI clears obstacles, remembers paths walked, retrieves forgotten knowledge.

**This is well-framed.** Similar to what BioMate's chain composer + research_agent + persisted chat memory already enables; they articulate it better.

## In-house science stack (their materials/chemistry moat)

**Self-developed models** (Deep Principle proprietary):
- **Reactify** — quantum chemistry compute
- **ReactNet** — reaction prediction
- **ReactNavi** — synthesis design
- **ReactGen** — molecule / reaction generation
- **MPA** — material properties prediction
- **ReactBO** — active-learning optimization

**Integrated open/third-party:**
- FluidSim (fluid dynamics simulation)
- ChemProcess (chemical engineering simulation)
- ESM (protein structure)
- DiffDock (molecular docking)

**Databases bundled:**
- Chemistry: PubChem, ChEMBL, ChemSpace
- Protein: AlphaFold DB, PDB, UniProt
- Materials: Materials Project, DIPPR, NIST
- General: Google Scholar, PubMed, Patents

**Important nuance:** Deep Principle is positioned as **AI for Materials** company. Their primary moat is in materials/chemistry. The bioinformatics use case in the announcement (multi-omics canvas) is a single user quote — not a flagship.

---

## Direct side-by-side: Mira (upgrade) vs BioMate (today)

| Capability | Mira | BioMate | Honest call |
|---|---|---|---|
| **Real wet-lab pipeline execution** (sarek, drop, rnaseq, cutandrun, cryosparc) | ❌ not visible in announcement | ✅ nf-core on AWS Batch + Lago billing, 2,455 indexed workflows | **We're ahead for bioinformatics** |
| **Materials/chemistry proprietary compute** (DFT, ReactBO, MPA) | ✅ 6 in-house models | ❌ not in scope | **They're ahead for materials/chemistry** |
| **Multi-step curated chains with provenance** | ❌ skills are single-capability | ✅ 60 curated chains + chain composer + chain_meta narrator (shipped today) | **We're ahead** |
| **User-configurable multi-agent team builder (Expert Team)** | ✅ 3-minute natural-language config; shared state; pixel-art UI | ⚠️ Pilot Experiment Panel exists (A/B only); no N-agent team builder | **They're ahead — meaningful gap, AutoScientists-pattern** |
| **Infinite canvas multi-file analysis (Research Canvas)** | ✅ shipped; CIF/XRD/orbital plot/PDF/code side-by-side | ⚠️ per-file `step-output-preview.tsx` only; no canvas surface | **They're ahead — meaningful gap** |
| **Auto overnight project WIKI consolidation** | ✅ judges importance + writes structured KB + cross-references | ❌ project memory exists but no auto-WIKI synthesis | **They're ahead — meaningful gap** |
| **Per-project file Library** | ✅ shipped, auto-indexed | ⚠️ schema exists (`projectDocumentSchema`); UX missing | We have the data model; need the UX |
| **Persona / system prompts** | ✅ SOUL.md + USER.md global files | ✅ per-project `instructions` field (better scope than theirs) | Mixed — different design tradeoff |
| **Slack / Email / Webhook notifications** | ❌ Telegram + Discord only | ✅ Slack + Email + Webhook + Database | **We're ahead for enterprise** |
| **WeChat integration** | ❌ | ❌ in code (user mentioned; may be planned) | Both gap |
| **Counted output endpoint + bucket lockdown + audit log** | ❌ no visible compliance framing | ✅ shipped today (commits `7a605a4089` + `930aab12c`) | **We're ahead — compliance gap they have** |
| **IND §2.6.1 LLM narrative + 21 CFR Part 11** | ❌ not mentioned | ✅ shipped Apr 2026 | **We're ahead for regulatory** |
| **Multi-tenant + project members + RBAC** | ❌ not mentioned | ✅ 31/31 audit assertions pass 2026-06-13 | **We're ahead for team collab** |
| **Skill marketplace `/skill-finder`** | ✅ shipped | ❌ none; `BioTender-max/awesome-bio-agent-skills` is the community alternative | **They're ahead on discoverability UX** |
| **`/skill-name` chat shortcut** | ✅ | ❌ | **They're ahead on UX** |
| **Output formats: PPTX + poster + HTML report + CSV + Markdown** | ✅ 5 Foundry formats | ⚠️ Markdown only (shipped today, research-doc style) | **They're ahead on output variety** |
| **Real-time cost display in chat** | ❌ credits framing, no inline display | ❌ Lago billing per run, no inline display | Both gap |
| **Scheduled / recurring tasks** | ✅ plan-tier-gated (20/200/1000) | ❌ | **They're ahead** |
| **Vibe Researching framing** | ✅ articulated | ⚠️ similar capability, no name | They're better positioned; we should adopt language |

## Three big gaps I'd act on (re-prioritized after Mira upgrade)

### Gap A — User-configurable Expert Team builder (NEW PRIORITY)

**What's there today:** `frontend/client/src/components/pilot-experiment-panel.tsx` does A vs B param-comparison only. Backend infrastructure (chain composer + `_compute_chain_meta` + research_agent) supports N-agent coordination but is not surfaced as a team-builder UX.

**What's needed for parity:**
1. UI: a "New Expert Team" panel where user adds N agents, each with a natural-language role description
2. Backend: orchestrator that fans out to N agents (chain composer can already do this) + collects results + AutoScientists-style shared state
3. Persistence: save team configs in `projects.<id>.skills` (re-runnable later)

**Effort estimate:** ~2 weeks. Builds on existing chain composer + Pilot Experiment Panel.

**Why this matters:** their concrete demo (PhD configures Auto Research in 3 min, produces complete paper draft by afternoon) is a strong recruiting pitch. We have the underlying capability; just not the UX.

### Gap B — Research Canvas (multi-file infinite-surface)

**What's there today:** `frontend/client/src/components/step-output-preview.tsx` dispatches by file extension (image/html/table/sequence/vcf/structure/text/density/annotation). One file at a time, in a modal.

**What's needed for parity:**
1. New canvas component with drag-drop layout, save/restore via Y.js or simple JSON state
2. Multi-file open simultaneously, each in its own draggable panel
3. Linked notes / annotations layer
4. PDB/CIF/MOL preview already supported by existing viewers; reuse them
5. Cloud-saved state per project

**Effort estimate:** ~2 weeks. Heavier than gap A because canvas state-management + multi-file rendering is non-trivial.

**Why this matters:** bioinformatics multi-omics workflow (RNA-seq + proteomics + metabolomics side-by-side) is exactly the user quote from Mira's announcement. Our users would benefit identically.

### Gap C — Project WIKI auto-consolidation

**What's there today:** `projectSchema` carries `instructions` + `documents[]`. After-run reports are saved per-run but not aggregated across runs.

**What's needed for parity:**
1. Nightly cron (or `Scheduled tasks` infra if we build it) per project
2. Job: read all of today's chat sessions + completed runs + uploaded documents in this project
3. LLM synthesis: identify recurring concepts, conclusions worth distilling, open questions
4. Write structured Markdown to `projects.<id>.wiki/`
5. Cross-link with `[[wiki-link]]` syntax + UI navigation

**Effort estimate:** ~1 week. Pure backend + a basic viewer.

**Why this matters:** "if I had this in college, better than 4 years of notes" — exact same problem labs have. Compounding project knowledge is a sticky-product feature.

## What we should NOT chase

| Mira feature | Why we shouldn't replicate |
|---|---|
| 6 in-house quantum chemistry / materials models | Wrong vertical for us. Deep Principle's identity = AI for Materials. Ours = AI for Bioinformatics/Health. Stay focused. |
| Global-only persona | We already have per-project — strictly better scope |
| Each chat = independent context window | We have persistent chat history per project — strictly better |
| Telegram + Discord | Wrong audience for clinical/lab/regulated use cases |
| Per-run cost opacity | Lago gives us real per-run cost; surface it as a future UX win |
| Self-uploaded skill cap of 20 | Arbitrary limit; ours doesn't need this |

## Strategic positioning lessons from Mira's framing

**Their winning frames (worth borrowing):**

1. *"科研流程不会被预先定义"* — *"the research process is not pre-defined."* Sharp framing of why fixed-flow tools (or rigid templates) lose. Our chain catalog can be reframed as a starting point, not a prescription.

2. *"Vibe Researching"* — better articulation of "user leads, AI assists" than what we say today.

3. *"专家小队 — 每个人都能组建自己的科研团队"* — *"Expert Team — everyone can assemble their own research team."* Democratizes the AutoScientists vision.

4. *"科研画布 — 一张无限大的科研桌面"* — *"Research Canvas — an infinitely large research desktop."* Concrete physical metaphor for digital workflow.

5. *"WIKI — 自动整合零散信息的AI助手"* — *"WIKI — AI assistant for auto-consolidating scattered information."* Names a real pain (information scatter at end of day).

**Our angles they don't have (lead with these):**

1. *"BioMate is what Mira aspires to be once they leave their materials-science vertical"* — true on bioinformatics breadth
2. *"Real nf-core orchestration, real AWS Batch, real Lago billing — not a sandbox demo"* — true on compute reality
3. *"Multi-tenant + per-project members + audit-log + 21 CFR Part 11 — regulatory-grade from day one"* — true on enterprise/clinical
4. *"60 curated multi-step chains with provenance — they ship only single-capability skills"* — true on workflow depth
5. *"Slack + Email + Webhook + Database notifications — enterprise-friendly out of box"* — true on team integration

## Updated recommended action

Replaces the 4-week sprint I proposed in `docs/20260619_SCICLAW_MIRA_COMPETITOR_LEARNINGS.md` (which was based on incomplete picture):

**6-week parity sprint:**

| Week | Item | Closes Mira gap | Builds on |
|---|---|---|---|
| 1 | `conclusion.md` per run + project Library file browser | Library / persistent context | Existing `projectDocumentSchema` |
| 2 | `/skill-name` chat shortcut + skill browser modal | Skill discoverability | Existing 60 chains |
| 3 | Persona-as-files (SOUL.md + USER.md) per project | Persona UX | Existing `instructions` field |
| 4 | Foundry-shape output picker (PPTX + HTML in addition to Markdown) | Output variety | Existing methods-section LLM endpoint |
| 5-6 | **Project WIKI auto-consolidation** (Gap C) | WIKI | Existing After-run findings + project_documents |

**Then quarter-2:**

| Time | Item | Closes Mira gap |
|---|---|---|
| Month 2 | **User-configurable Expert Team builder** (Gap A) | Expert Team |
| Month 3 | **Research Canvas** (Gap B) | Research Canvas |

After this, BioMate has full parity with Mira's announced features + retains all our advantages (real execution, regulatory, multi-tenant, chains).

## Open question worth raising with the team

Mira's positioning is explicitly *"we make tools and frameworks; you define the flow"*. Our chain catalog reads as *"we pre-curate proven workflows for you."* These are subtly opposite messages.

**Do we want to reposition** toward the Mira frame ("BioMate provides the chain composer; you define your own chains") and demote our 60 curated chains to "reference examples"? Or **double down** on our current "curated chains with provenance" as the differentiator?

My honest read: **stay curated for the bio audience.** Researchers want known-good RNA-seq pipelines, not an empty canvas. But adopt Mira's framing for the **Expert Team / Custom Workflow** mode that we'd build per Gap A — *"compose your own team"* is a strong pitch for the power-user segment.
