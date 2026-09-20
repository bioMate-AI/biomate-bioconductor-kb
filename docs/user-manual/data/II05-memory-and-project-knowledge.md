# Memory & project knowledge

> One-line promise: understand precisely **what BioMate remembers** and **what the assistant actually
> reads back into a chat** — your project's research goal and standing instructions are injected;
> your private notes are the safety boundary that stays out of the prompt. For: PIs and
> bioinformaticians who want the agent to carry context across a project without leaking the wrong
> things into an LLM.

<!--
Part II.5 (Databases & retrieval). Tier C, cited file:line. This is the BACKBONE view of memory; the
USER-FACING notes/instructions UX lives in I.4 — cross-reference it, don't duplicate. HONESTY RULE:
be exact about what is injected vs. not. The explicit <project_context> path injects
name/description/research_goal/instructions + project_instruction rows and NOT user_notes/notes_synthesis
(routes.ts:6061-6105) — this honors the safety boundary. BUT the secondary LTM "memory-hint" path
(memory-integration.ts addMemoryHints) injects up to 2 project-knowledge rows UNFILTERED by type, so a
high-relevance user_notes snippet can reach the model that way. State this honestly as a caveat/mismatch.
Also: "memory" is really project-scoped knowledge + episodic learning, not user-scoped cross-session
recall — say so. recall_memory reads session summaries only.
-->

## What this is for

BioMate keeps two kinds of durable context so you don't re-explain your project every session:

1. **Project knowledge** — the goal, standing instructions, notes, and saved answers attached to a
   project.
2. **Episodic / long-term memory (LTM)** — a record of past sessions and interactions the assistant can
   draw hints from.

The question this chapter answers is the one that actually matters for trust: **which of these does the
assistant read back into an LLM prompt, and which stays out?** The user-facing experience of *setting*
goals, instructions, and notes is documented in **I.4 — Projects, instructions & collaboration**; this
chapter is the backbone view of *what persists and what the agent reads*.

> **Tip — the mental model.** "Standing instruction" = *the agent should follow this.* "Note" = *this is
> for humans; keep it out of the model.* Getting that split right is the whole design.

## Use cases

| Goal (researcher's words) | What persists | Read into chat? | Where |
|---|---|---|---|
| "Always analyse against GRCh38 in this project" | `projects.research_goal` / `instructions` | **Yes** — injected as project context | `routes.ts:6061-6076` |
| "Apply this standing rule the agent set from a search answer" | `project_knowledge` type `project_instruction` | **Yes** — up to 8 rows, 300 chars each | `routes.ts:6087-6105` |
| "Keep this private reasoning note for my team" | `project_knowledge` type `user_notes` | **No — safety boundary** (explicit `<project_context>` path) | `project-routes.ts:934-939` |
| "Save this evidence answer to the project" | `project_knowledge` type `notes_synthesis` | **No** — stored for the Notes UI, not injected | `notes-routes.ts:8-27` |
| "What did we do in past sessions here?" | `sessions` summaries (LTM) | On demand via `recall_memory` | `routes.ts:17040-17043` |

## How to ask

You don't "ask" memory directly in most cases — it works in the background when a **project is active**.
The one explicit handle is the agent's `recall_memory` tool, which the assistant calls when you ask
about prior work:

> "What did we conclude in earlier sessions on this project?"

**Disambiguation to avoid:**
- "Remember that I prefer X" is best expressed as a **standing instruction** (I.4), which the agent
  *does* read — not a **note**, which it deliberately does not.
- Memory is **project-scoped**. Outside a project there is no goal/instruction context to inject; the
  chat runs without it (`if (_resolvedProjectId)` guard, `routes.ts:6063, 6087`).

## Tools & workflows behind this

### What persists — `project_knowledge` types

Project knowledge is a Postgres `project_knowledge` table (LTM schema, keyed by `project_id`), written
and read through the memory repository (`memory-repository.ts`: `addProjectKnowledge` `:355-360`,
`getProjectKnowledge` `:365-378`). Four `knowledgeType` values are used in production:

| Type | Meaning | Written by | Where |
|---|---|---|---|
| `research_goal` | The project's goal *(note: stored as a `projects` column, not a knowledge row)* | Project setup (I.4) | `projects.research_goal` |
| `project_instruction` | A standing instruction the agent applies | "Make instruction" from a search answer (I.3) | `citation-panel.tsx` → `POST /knowledge` |
| `user_notes` | Human-only free text | Project Notes UI | `project-routes.ts:939` |
| `notes_synthesis` | A saved/LLM-synthesised answer or project summary | "Save to project" (I.3); notes refresh | `notes-routes.ts:27` |

> **Pitfall — the schema comment lists aspirational types that aren't the ones in use.** The LTM schema
> comment enumerates `dataset_info / experimental_design / analysis_approach / key_finding /
> technical_note`, but the *deployed* types are the four above. Don't rely on the schema comment as the
> live contract. (`ltm-schema.ts` comment vs. actual writers in `notes-routes.ts` / `project-routes.ts`.)

### What the agent reads — the `<project_context>` injection

When a project is active, the chat stream builds one project-context block and injects it into the LLM
prompt (`routes.ts:6061-6105`). It contains, in order:

- `Project: <name>`, `Description: <description>` (`:6072-6073`)
- `Research goal: <research_goal>` (`:6074`)
- `Background instructions: <instructions>` (`:6075`)
- `Standing instructions set by the user (apply when relevant): …` — the `project_instruction` knowledge
  rows, **capped to 8 rows and 300 chars each** so a long list can't flood the prompt (`:6087-6100`).

Crucially, this block **does not read `user_notes` and does not read `notes_synthesis`.** That is the
safety boundary: human notes and saved answers persist for *you*, but the explicit project-context path
never puts them in the prompt.

> **QC gate — user_notes is the human-only boundary (explicit-context path).** The Notes route states it
> plainly: `user_notes` rows are "never injected into prompts" and "the assistant's directives live in
> projects.researchGoal (Standing instructions)" (`project-routes.ts:934-939`). The `<project_context>`
> builder honours this — it only ever reads `research_goal`, `instructions`, and `project_instruction`
> rows (`routes.ts:6066, 6089-6091`). Cross-ref **I.4** for the user-facing Notes-vs-Instructions split.

> **Pitfall — one honest edge on the boundary.** There is a *secondary* long-term-memory path. When
> memory-enhanced processing is active, `processWithMemory` loads **all** of a project's knowledge rows
> (unfiltered by type — `loadProjectContext` → `getProjectKnowledge(projectId)` with no type filter,
> `memory-repository.ts:401-420, 365-378`) and `addMemoryHints` prepends a short
> `[Memory: Project knowledge - …]` line built from the **top 2** rows by relevance, using each row's
> title or first ~50 characters (`memory-integration.ts:298-340`). Because that path does **not** filter
> by type, a high-relevance `user_notes` snippet *can* surface there — a narrower exposure than the full
> note, but not a strict zero. The dedicated explicit-context path (above) keeps `user_notes` out; this
> memory-hint path is the caveat. (Recorded as a mismatch in the ledger; if privacy of a note is
> critical, keep sensitive reasoning out of project knowledge entirely.)

### Long-term / episodic memory (LTM)

`memory-integration.ts` wraps the assistant with episodic learning: it loads user + project context at
session start, records an **episode** after each interaction, and surfaces hints from similar past
episodes and matching procedures (`processWithMemory`, `memory-integration.ts:103-165`;
`recordEpisode` `:342-370`; `getSimilarEpisodes` `:281-296`). The LTM tables (`ltm_users`, `sessions`,
`project_episodes`, `project_procedures`, `project_knowledge`) are Postgres, bootstrapped per user by
`ensureLtmUser` on every authenticated chat (`memory-repository.ts` MemoryService;
`routes.ts` bootstrap around `:6032`).

> **Pitfall — "memory" is project-scoped knowledge + episodic learning, not user-scoped cross-session
> recall.** The naming oversells it. Project knowledge is read *passively* only when a project is active;
> the agent's explicit `recall_memory` tool reads **session summaries** (`/api/memory/relevant`,
> `routes.ts:17040-17043`), not project-knowledge rows. There is no automatic, cross-project "the agent
> remembers everything about you" recall. Set durable behaviour as a **standing instruction** if you
> want it reliably applied.

### Writing project knowledge

Project knowledge is written via `POST /api/memory/projects/:id/knowledge` (→
`addProjectKnowledge`). The endpoint itself doesn't enum-restrict `knowledgeType`; the *type* is set by
the caller — "Make instruction" writes `project_instruction`, "Save to project" / notes-refresh write
`notes_synthesis`, and the Notes UI writes `user_notes`. See **I.3** (the three save/exit actions) and
**I.4** (Notes vs Instructions) for the user-facing side.

### The `recall_memory` tool

The assistant can call `recall_memory` at runtime; it proxies to `/api/memory/relevant`, which scores
recent **session summaries** by keyword overlap with the query and returns the top matches
(`routes.ts:17040-17043`). It does **not** return project-knowledge rows, `user_notes`, or
`project_instruction` — only session-level summaries.

## QC gates & how to read them

The "gate" here is a read-boundary you can reason about:

- **Injected into every chat (project active):** name, description, `research_goal`, `instructions`, and
  up to 8 `project_instruction` rows.
- **Never injected by the explicit path:** `user_notes`, `notes_synthesis`.
- **Possibly surfaced (top-2, title/snippet) by the LTM memory-hint path:** any high-relevance knowledge
  row, including `user_notes` — the one honest edge above.
- **On-demand only:** past-session summaries, via `recall_memory`.

## Outputs & visualization

Memory has no run artifact and no dedicated viewer. Its effects show up as (a) the assistant behaving
consistently with your project goal/instructions in chat, and (b) the **Project detail / Notes** surfaces
where instructions, notes, and saved syntheses are listed — documented in **I.4**. Saved evidence
answers land as `notes_synthesis` rows in the Notes list, not as versioned Files documents
(cross-ref I.3, "Save to project").

![Placeholder: project detail showing Standing instructions (agent-read) alongside Notes (human-only), illustrating the injection boundary](../assets/ii05-1-instructions-vs-notes.png)

## Pitfalls & tips

> **Tip — put durable behaviour in a Standing instruction, not a Note.** Instructions (`research_goal`,
> `instructions`, `project_instruction`) are the reliably-injected path (`routes.ts:6074-6100`). Notes
> are for humans and are kept out of the explicit prompt.

> **Pitfall — don't store secrets in project knowledge.** The explicit context path keeps `user_notes`
> out of prompts, but the LTM memory-hint path can surface a high-relevance snippet of any knowledge row.
> Treat project knowledge as "content the model may see," and keep genuinely sensitive material out of
> it. (Ledger mismatch; Appendix E.)

> **Tip — memory is project-scoped.** No active project → no goal/instruction injection. Work inside a
> project to get carried context.

## What's not covered

Honest scope — **not** claimed as present; these live in **Appendix E (Coverage & roadmap)**:

- **User-scoped, cross-project automatic recall.** "Memory" is project-scoped knowledge + episodic
  learning; `recall_memory` reads session summaries only (`routes.ts:17040-17043`).
- **A strict guarantee that `user_notes` never reaches the model.** The explicit `<project_context>`
  path excludes it, but the LTM memory-hint path (`memory-integration.ts:298-340`) can surface a
  top-relevance snippet — a recorded mismatch, not a promised zero.
- **Injection of `notes_synthesis` into chat.** Saved answers persist for the Notes UI and are not read
  into the prompt (`notes-routes.ts:8-27`).
- **The aspirational `knowledgeType` set.** `dataset_info / experimental_design / …` from the schema
  comment are not the deployed types; only the four documented types are in use.

---
_Verification: this page depends on the coverage-ledger rows under **"## II.5 Memory & project
knowledge"** — four project_knowledge types (research_goal/project_instruction/user_notes/notes_synthesis)
(C); `<project_context>` injects name/description/research_goal/instructions + ≤8 project_instruction rows
(C); user_notes NOT injected on the explicit path (safety boundary, cross-ref I.4) (C); LTM memory-hint
path injects top-2 knowledge rows UNFILTERED by type → user_notes-snippet exposure edge (🔧); memory is
project-scoped not user-scoped cross-session recall (C); recall_memory reads session summaries only (C);
POST /knowledge writer + type set by caller (C); notes_synthesis stored not injected (C); and the gap rows
for cross-project recall / strict user_notes guarantee / aspirational schema types (🗺️)._
