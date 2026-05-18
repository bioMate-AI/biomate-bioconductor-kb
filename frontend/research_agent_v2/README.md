# research_agent_v2 — sandbox copy of the new Claude-Design UI

**Status:** isolated sandbox; **not** imported anywhere in BioMate.
**Source:** `reference/claude_design/research_agents/src/` (Claude-Design output, 2026-05-18 handoff)

This folder holds the new chat-driven research-agent UI from the Claude-Design
handoff, copied verbatim into a folder that is deliberately **outside**
`frontend/client/src/`. Nothing here is imported by the live app. Promotion
happens later, one surface at a time, after each is tested in isolation.

## What's here

`src/` — 17 files copied from the handoff. **`ResearchTweaks.jsx` is NOT
copied** — per scope decision, that panel is a Claude-Design tooling
artifact for previewing the design and is not a BioMate product feature.

`docs/00_HANDOFF_FROM_CLAUDE_DESIGN.md` — the design handoff doc.
`docs/01_DEMO_NARRATIVES.md` — the narrated tutorial scripts (cryo, drug
screen, after-run report, etc.).

## Why a sandbox

Three reasons we don't copy into `frontend/client/src/` yet:

1. **Avoid accidental regression** — many of the new components have the
   same filename as existing ones (`WorkflowPanel.jsx`, `PhaseCard.jsx`,
   `Modals.jsx`, `Tour.jsx`, `Chrome.jsx`, `AutoLoop.jsx`). Co-locating
   would risk import collisions or quiet overwrites.
2. **Allow side-by-side testing** — we want to be able to render the new
   UI under a dev-only route (e.g. `/_/research-agent-v2`) without
   touching the production tree.
3. **Mappings are not 1:1** — several new components (PlanChecklist,
   ChatStream, ChatCards) need to be merged with existing BioMate
   features rather than dropped in. See the integration plan.

## Files NOT brought over

- `ResearchTweaks.jsx` — Claude-Design dev tool, not a product feature.
- `research-data.js` — kept as a fixture for sandbox demos; will be
  deleted before any production merge (live data comes from the SSE
  event stream + workflow APIs, not from a static `tape`).

## How to promote a single surface to production

1. Pick one surface (start with Surface 2: speaker pills — lowest risk,
   highest visibility win).
2. Cherry-pick the relevant pieces from this folder into
   `frontend/client/src/components/`.
3. Add a feature flag (`BIOMATE_RESEARCH_AGENT_<SURFACE>=1`) so the new
   path is opt-in until proven.
4. Re-run the Playwright suite + the 5 use-case tutorial scenarios
   listed in `02_TUTORIAL_USE_CASE_COVERAGE.md`.
5. Sync to dev EC2; verify the specific surface against the live data
   stream.

The integration plan in `02_INTEGRATION_PLAN.md` (next to this file)
covers the component-by-component mapping, including what to keep from
the existing BioMate (the recently-shipped chat-progress 🔹 lines, the
TaskList task-management box, etc.) and how to reconcile each
overlapping concept.
