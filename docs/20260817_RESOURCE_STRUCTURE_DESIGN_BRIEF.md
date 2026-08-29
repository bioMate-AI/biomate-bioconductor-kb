# Design brief for claude-design — make BioMate's capabilities *legible* without exposing the inventory

**Date:** 2026-08-17
**For:** the claude-design reference process (localhost:7779 design system)
**From:** platform/eng
**Status:** brief — asking design to propose structure options; NOT a spec

---

## The problem to solve

BioMate has deep capability (many validated workflows across many domains; a fast local lane of search + `run_code`; expert skills; 60+ databases; MCP + lab-instrument connectors). **Almost none of it is visible** — it all hides behind a single chat box. The current sidebar is deliberately lean (New Chat · Workflows · Connectors · IND Report · Projects · history), and it surfaces *none* of the capability depth. There is even a dead `toolCategories` mock left in `app-sidebar.tsx` (never rendered) — the ghost of an abandoned resource browser.

New users don't discover what BioMate can do; power users can't quickly get to a capability they know exists. We want to make capability **legible and navigable**.

## The hard constraint (read this first)

**Do NOT design a surface that enumerates our resources explicitly.** We will *not* ship a browsable list of all workflows/tools/skills. A full, copyable catalog is an IP-disclosure risk — it hands a competitor our coverage map. This rules out the obvious "resource browser / tool directory / list all N workflows" pattern.

So the design challenge is specifically: **convey the *shape and reach* of our capability — by intent, by domain, by execution tier — WITHOUT a catalog a visitor could scrape.** Think "capability is organized like *this*, and you can get to *that kind of thing*," not "here are the 4,055 items."

Acceptable signals: categories, intents, example *shapes* of tasks, the two execution tiers, domain groupings. Off-limits: exhaustive named lists, per-item counts that reveal coverage depth, anything that reads as a competitive coverage map.

## The organizing structure we already have (use this as the backbone)

BioMate's real architecture gives a clean, honest way to structure capability — two execution tiers by intent:

1. **Instant lane (runs on our backend, seconds):**
   - **Ask** — cited research over literature + curated databases
   - **Compute** — `run_code`: writes & runs Python/R on the user's data in a network-isolated sandbox
   - **Skills / Experts** — domain reasoning packs the user can activate
2. **Cloud lane (AWS Batch, minutes–hours):**
   - **Workflows** — validated multi-step pipelines, organized *by domain* (genomics, transcriptomics, drug discovery, structural biology, clinical, …), with QC gates + audit-ready reports

Plus reference surfaces that already exist as dialogs: **Connectors** (Databases · AI Models · Skills · MCP), **Projects**, run **history**.

The design opportunity is to make the **intent → lane** mental model visible (the manual's single most useful concept, §3), so a user understands "a quick question → Ask; a calculation on my data → Compute; a standardized pipeline → a Workflow" *before* they type — organized by domain where it helps, but never as an exhaustive list.

## What we're asking design to explore

Propose 2–3 structural options for surfacing capability, e.g.:
- A new **Workspace** entry (a "Capabilities" / "What can I do here" surface) that teaches the intent→lane model and lets users jump into a *category* — using progressive disclosure (domain → example task shapes → start a chat pre-seeded), never a flat catalog.
- **In-composer affordances** that hint at the lanes/skills contextually (without a full menu of everything).
- **Onboarding / empty-state** structure that shows reach by domain via representative *example intents*, not lists.

For each option, show: the sidebar/nav change, the surface layout (wireframe), and how progressive disclosure keeps the full inventory hidden while still feeling deep.

## Design constraints
- Match the existing reference design language (localhost:7779) and the current lean sidebar (`app-sidebar.tsx`); BETA minimalism — don't over-build.
- Everything shown must be backed by real endpoints we already have (`/api/skills`, workflow search, the database registry) — no new mock data. Replace the dead `toolCategories` mock, don't extend it.
- The IP constraint above is non-negotiable: prefer *categories and example shapes* over *named inventories*; no per-item coverage counts.
- Reproducibility/trust is our brand — any capability surface should reinforce "cited, QC-gated, audit-ready," not just "look how many tools."

## Success criterion
A new user, in 15 seconds on the surface, can answer: *"What kinds of things can BioMate do for me, and how do I start one?"* — without us having published a catalog anyone could copy.

---

# Part 2 — Data-centric UI & information flow (added 2026-08-17)

Second, related design question. The first part is about *capability* discovery; this part is about **the user's data as the central object** — how it enters, moves through the system, and comes back out. We want claude-design to assess whether the current data flow can be given a better UI.

> **Interpretation note (please correct if off):** by "data-centric / data centroid UI" we mean treating the **user's dataset(s)** as the persistent hub that everything else (chats, workflows, runs, outputs, reports) hangs off — rather than data being a transient thing scattered across many surfaces.

## The current information flow (grounded in the real components)

Today data moves through **five stages, each rendered by a different surface** — there is no single place that represents "my data" across its whole life:

1. **Ingest** — the paperclip opens an uploader with three tabs: Local (`file-upload.tsx`, S3 multipart, multi-GB), URL import, and a public **Dataset Browser** (`galaxy-dataset-browser.tsx`, GEO/SRA/ENA). *(Manual §6; Fig 6.1.)*
2. **Instant read** — on landing, a **data card** shows quick stats + a green/amber **QC badge** (rows/cols & missing-rate for tables; reads/quality for FASTQ; variant count for VCF). *(Manual §2.2 Recipe B, §6.1.)*
3. **Attach & map** — datasets become chips (`dataset-attachment.tsx`, typed input/output) and are mapped to workflow input slots by `dataset-validation-dialog.tsx`, which assigns each mapping a **confidence (high/medium/low) + reasoning**.
4. **Consume → produce** — datasets feed workflow parameters (`parameter-preview-dialog.tsx`); a run emits per-step files rendered inline by `step-output-preview.tsx` (image → lightbox, table → grid, density map → 3-axis viewer, FASTA/VCF → record list) and `chat-output-attachments.tsx`.
5. **Report** — outputs land in the 7-tab After-Run Report (Findings / **Outputs** / Methods / Parameters / Software / Citations / QC Audit); prior outputs can be reused as next inputs ("use the structure from my last run"). *(Manual §10.)*

Data *also* appears in the sidebar **Projects → Files** tab and `project-file-tree.tsx`. So a single dataset can surface in **at least five disconnected places**: the chat chip, the dataset browser, the project Files tab, the step-output previews, and the report Outputs tab.

## The problem we want design to solve

- **No data centroid.** There is no single view that answers "what is *this dataset*, where did it come from, which runs consumed it, and what did they produce?" Lineage/provenance exists in the audit log but is not a navigable data-first surface.
- **The flow is stage-fragmented.** Ingest, QC, mapping, outputs, and report each live in a different component with different visual language; the continuity of *one dataset moving through* is implicit, not shown.
- **Inputs↔outputs are not a graph.** "Reuse a prior output as the next input" works, but the user can't *see* the input→run→output→next-input chain — the thing that makes a data-centric tool feel coherent.

## Questions for claude-design

1. **Can a better UI be generated for a data-centric flow?** Propose 2–3 options. Is a persistent **"Data" hub** (a dataset as a first-class object with tabs: Overview/QC · Lineage · Runs that used it · Derived outputs) the right centroid — or is an **inline lineage graph** in the workflow panel better, or something else?
2. **How should the five stages (ingest → QC → map → outputs → report) be unified** into one coherent visual narrative for a single dataset, without a heavy new page?
3. **Provenance as a first-class visual:** design a dataset **lineage/DAG** view (input → run → output → next input) that reuses the audit-log data we already capture — legible to a bench scientist, exportable for a deposit (GEO/PRIDE/EMDB).
4. **Where should the data hub live?** New sidebar entry, an expansion of Projects→Files, or a panel mode? Weigh against the current lean sidebar (see Part 1).
5. **Trust signals in the data view:** how to carry the QC badge (green/amber) and mapping confidence (high/medium/low) through the whole journey so the user always sees data quality, not just at ingest.

## Materials for claude-design
- **Descriptions above** are grounded in the actual components (paths named) and the User Manual figure callouts (§2.2, §6, §10).
- **Screenshots captured (2026-08-17, live dev):** `docs/20260817_data_ui_screenshots/` (see its `README.md` for a per-image data-flow map). They show the current state: `00_workspace` (composer/ingest), `01_runs_history` (run inventory), `20_run_panel` + `21_report_*` (results panel & After-Run sub-tabs), `30_completed_run_panel` (info flowing back via chat step-logs + the QC auto-loop). Two documented gaps: the uploader is a **native OS file picker** (the instant data-card couldn't be captured headlessly), and the clean completed-run *panel* would need a small re-run to capture — both noted in the README.
- **Constraints from Part 1 still apply:** reuse real endpoints (the audit log / run APIs already hold the lineage data), match the reference design language (localhost:7779), no new mock data, keep it lean.

## Success criterion (Part 2)
A user can point at any dataset and, in one view, see *where it came from, what ran on it, and what it produced* — the data is the centroid, and the flow through it is legible end-to-end.
