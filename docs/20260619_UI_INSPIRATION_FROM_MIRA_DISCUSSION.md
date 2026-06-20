# UI Inspiration from Mira — Discussion Notes & Decisions

**Date:** 2026-06-19
**Trigger:** User shared `business/mira.pdf` (Deep Principle's June 10 2026 product upgrade) and asked what we can *inspire* from them — explicitly not copy.
**Companion docs:**
- `docs/20260619_MIRA_UPGRADE_COMPARISON.md` — full feature side-by-side
- `docs/20260619_SCICLAW_MIRA_COMPETITOR_LEARNINGS.md` — earlier crawl-based learnings (corrections folded into MIRA_UPGRADE_COMPARISON)
- `reference/claude_design/design_handoff_bench_prototype/Bench-Prototype Requirement.md` — design handoff written from this discussion

## What we took from Mira (the inspirations, not the features)

Three things Mira does well that we can borrow at the *craft* level:

1. **Naming via metaphor, not function.** Their feature names ("Expert Team," "Research Canvas," "WIKI," "Vibe Researching") describe an *experience* the user already understands. Ours ("chain composer," "auto-loop," "QC gate," "step output preview") describe a *mechanism*. Same capability, different felt meaning.
2. **Visual storytelling does the explanation.** A pixel-art office with agents at different desks tells a user what a multi-agent product *is* before any docs. Our screenshots show interfaces; theirs show worlds.
3. **Internally consistent metaphor system.** Mira → red dwarf → "stars change brightness" → 三大能力闭环 (execute / record / distill). Coherent story-world.

## Candidate metaphor (one option, not the answer)

**The Lab Bench.** A scientist's workspace: drawer of reagents, notebook beside the bench, crew of collaborators leaning in, end-of-day write-up. Scales from solo PhD to multi-tenant CRO.

| Today | Bench-metaphor |
|---|---|
| Project | Bench |
| Project Library | Drawer |
| Chain / workflow | Protocol |
| Chain composer | Protocol designer |
| Pilot Experiment Panel | Side-by-side bench |
| Research agent / multi-agent team | Bench crew |
| Auto-loop | Re-run with adjustments |
| QC gate | Bench-check |
| After-run findings | Notebook entry |
| Project memory | Lab notebook |
| Methods report | Write-up |
| step-output-preview | Pin to bench |
| Future canvas | The bench surface |
| Skill / tool catalog | Toolkit |

**Dual register** is the key trick: warm metaphors in chat / empty-state / marketing surfaces; precise regulatory vocabulary in report / audit-log / compliance surfaces. Same product, two voices, audience-appropriate. Without dual register, the metaphor risks feeling whimsical to clinical / CRO users.

**Pushback worth keeping:**
- "Bench" may read too wet-lab for compute-only users (alternatives: Workstation, Studio)
- "Crew" may feel infantilizing to senior PIs (alternative: Collaborators)
- Single-scientist metaphor fights our multi-tenant story — needs "shared bench" extension

## Five UI changes ranked by impact-per-effort

| # | Change | Why | Effort |
|---|---|---|---|
| 1 | Empty-chat-state becomes a *scene*, not a chip list | Sets tone for entire product; user understands *what it is* before *what it does* | 1 illustration + small refactor of empty-state component |
| 2 | Workflow card de-emphasizes phase grid post-completion | Phases matter while running, not after; right now they dominate the panel forever | Medium — re-layout of `nextflow-workflow-viewer.tsx` for terminal states |
| 3 | **After-run report becomes its own auto-opened surface, not a download** | Closes "user finishes a run and doesn't know what just happened" gap we have today | Small-medium — re-route `AfterRunReport.tsx` rendering, no new code |
| 4 | Sidebar promotes user's benches (projects) over feature list | Sidebar becomes map of *your work*, not menu of *features* | Medium — sidebar restructure + project-status one-liner backend |
| 5 | Commission one coherent illustration system (~10 scenes) | Cheapest "looks like a real product" lever; one style applied everywhere | ~$2-5k illustrator + integration |

**The one to do regardless of priority:** #3 (report-as-surface). It directly closes a known UX hole. The rest are taste moves that matter for investor / BD / academic-recruiting perception but don't move benchmark scores.

## Decision

User requested: document this + write a Claude design handoff to prototype first. Capability work (Project WIKI synthesis, Expert Team builder, Research Canvas) remains the strategic backlog from `docs/20260619_MIRA_UPGRADE_COMPARISON.md`. The prototype is to **validate the metaphor + visual direction** before committing to it across the codebase.

Prototype scope (full requirement in design handoff):
- 4 mockup screens: empty bench, bench mid-run, notebook entry after run, sidebar with bench list
- 1 illustration scene (the bench itself)
- Both registers shown side-by-side on one screen (warm voice vs regulatory voice) so we can react to the dual-register tradeoff concretely
- Metaphor table in screen captions so we can hover-test the renames

## Open items

- Confirm metaphor choice (Bench / Workstation / Studio / Notebook / Observatory). User to react after seeing the prototype.
- Confirm "Crew" vs "Collaborators" vs "Team" for the agents.
- Decide whether dual-register split is acceptable, or if regulatory voice should be the only one (safer for CRO/IND audience).
- Whether to push prototype on the live reference at `localhost:7779` or as a standalone Figma / HTML mock.
