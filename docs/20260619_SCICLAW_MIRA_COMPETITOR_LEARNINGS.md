# SciClaw / Mira — Competitor Learnings + BioMate Adoption Plan

**Date:** 2026-06-19
**Source:** Crawled https://sciclaw.ai/help/ — all 8 sidebar pages (getting-started, projects, board, foundry, skills, persona, im, billing). Companion to the next-phase plan + references addendum.
**Why this matters:** SciClaw is shipping the same "AI co-worker for scientific research" positioning we're targeting. Their UX is mature; some patterns are worth adopting directly, others are weaknesses we can lead with.

---

## Their architecture in one map

```
SciClaw / Mira

┌─ Project (basic unit of organization)
│  ├─ Library (file repo — auto-indexed, search/retrieval)
│  ├─ Task list
│  └─ Conversation space (each chat = its own context window;
│                         manual Library retrieval toggle)
│
├─ Board (visual canvas inside Project)
│  ├─ Drag-drop files / outputs / notes
│  └─ Rich preview: PDF, MD, CSV, Jupyter, HTML, PNG,
│                   PDB / CIF / MOL / XYZ ← unique for bio
│
├─ Foundry (output generator, 🔨 button)
│  ├─ Presentation (PPTX, 10-slide consulting-style default)
│  ├─ Academic Poster (PNG)
│  ├─ Web Report (HTML)
│  ├─ Structured Dataset (CSV)
│  └─ Professional Document (Markdown)
│  Each template = packaged default prompt (editable, not a fixed layout)
│
├─ Skills (callable task capabilities, /skill-name)
│  ├─ Direct: /skill-name in chat
│  ├─ Browse: ⚡ Skills button → modal
│  ├─ Auto: Mira picks the skill
│  ├─ Built-in: unlimited
│  ├─ User-uploaded: capped at 20 concurrent
│  ├─ /skill-finder: marketplace discovery
│  └─ Export as skill packages (sharing / migration)
│
├─ Persona (file-based AI behavior + user context)
│  ├─ SOUL.md (AI character)
│  ├─ USER.md (user context; encouraged to update regularly)
│  └─ Global scope — one persona system-wide
│
├─ Messaging apps (Telegram + Discord) — chat from outside the platform
│
└─ Scheduled tasks (recurring automated work)
    └─ Plan-tier differentiator: 20 / 200 / 1000 / 1000

Billing: credits (not tokens)
  Free: 10K one-time + 2K/day
  Lite / Plus / Pro / Max: 200K / 430K / 900K / 2.4M credits
  Storage tiers separate (200MB → 20GB)
  No real-time cost display surfaced
```

---

## Side-by-side: SciClaw vs BioMate today

| Concept | SciClaw / Mira | BioMate today | Honest gap |
|---|---|---|---|
| Project | First-class with Library + tasks + chats | Schema + CRUD shipped (31/31 audit pass 2026-06-13); not yet UX-surfaced | Project entity exists; **Library UX is missing** |
| Library (per-project file repo) | Single tree, auto-indexed, retrieval toggle | Drizzle has `projectDocumentSchema` but no file-browser UI; chat uploads land in Galaxy History (per-session, not per-project) | **Real gap — no project-scoped file browser** |
| Board (visual canvas) | Drag-drop, rich preview (PDB/CIF/MOL!) | None — we have `step-output-preview.tsx` per-file inline previewer but no canvas | **Real gap; PDB/CIF preview is a bio differentiator they have, we should match** |
| Foundry-style output gen | 5 formats: PPTX / PNG poster / HTML report / CSV dataset / Markdown | Methods + Findings + Citations Markdown report (just shipped today as research-doc style). No PPTX / poster / HTML. | **Real gap on output variety** |
| Skill invocation `/skill-name` | Discoverable, browsable, marketplace, export | We have 60+ chains + 4000+ workflows; no `/chain-name` chat shortcut; no marketplace UX | **UX gap, capability is there** |
| Skill marketplace | `/skill-finder` for open ecosystem | None | **Real gap** — though `BioTender-max/awesome-bio-agent-skills` is a community alternative |
| Persona | SOUL.md + USER.md files, editable | `projectSchema.instructions` field; one-line text; not file-based, not surfaced | **Real gap on UX, capability partial** |
| Per-project vs global persona | Global only | Per-project (we have project_id FK) | **WE'RE BETTER HERE** — labs need per-project context |
| Messaging apps integration | Telegram + Discord | None | Real gap; their list is consumer-friendly, not lab-friendly (no Slack/Teams either) |
| Scheduled / recurring tasks | Plan-tier-gated (20-1000) | None | **Real gap** — recurring nightly runs are valuable for labs |
| Compliance / 21 CFR Part 11 framing | None visible | Our IND §2.6.1 LLM narrative + QC chain-of-custody (shipped Apr 2026) | **WE'RE BETTER** for IND / regulatory work |
| Real exec on AWS Batch | Their compute model unclear (likely sandbox-only) | nf-core orchestration on AWS Batch + Lago billing per invocation | **WE'RE BETTER** for real bioinformatics pipelines |
| Multi-tenant + project members | Not documented | Project framework with members + RBAC scoped (audit passes) | **WE'RE BETTER** |
| Cost transparency | Credits framing; no real-time display | Lago per-invocation billing; not surfaced inline in chat | Both have gaps |
| Workflow chains vs single tools | Skills = single capability; no equivalent of our 60 curated chains | 60 curated chains + chain composer + chain_meta narrator (shipped today) | **WE'RE BETTER for multi-step pipelines** |
| Conclusion docs (auto-generated per task) | `conclusion.md` lands in Library after every task | After-run report exists but isn't auto-saved to project Library | **Real gap — easy fix** |

---

## Patterns worth adopting (sorted by ROI)

### High-ROI, easy to ship

| # | Pattern | Effort | Value |
|---|---|---|---|
| 1 | **`conclusion.md` per run** — after every chain dispatch, save the After-run findings + report path as `conclusion.md` in the project Library | ~1 day | Compounding project context across runs; matches our existing After-run pipeline. Trivial win. |
| 2 | **`/skill-name` chat shortcut + browser modal** | ~3 days | Discoverability for the 60+ existing chains; no backend change. Pure UX. |
| 3 | **Persona-as-files (SOUL.md + USER.md)** at project level | ~2 days | Cleaner than our current single `instructions` field; matches what users already understand from Cursor/Claude Projects |
| 4 | **Project Library file browser** (read-only first iteration) | ~3 days | Activates the `projectDocumentSchema` already in our DB. Closes the gap our prior plan flagged. |

**Total: ~9 days for the 4 fastest wins. All UX-only — no infra/AWS work.**

### Medium-ROI, medium effort

| # | Pattern | Effort | Value |
|---|---|---|---|
| 5 | **Foundry-shape output picker** — extend Download Report to PPTX + HTML + Markdown variants | ~1 week | Pairs with the research-doc Report we shipped today (commit `15193afb9`). Same backend (LLM-render); 3 new format adapters. |
| 6 | **Board canvas with PDB/CIF/MOL preview** — drag-drop project files | ~1 week | Leverages existing `step-output-preview.tsx` dispatch; new component layer above |
| 7 | **Scheduled tasks** — cron-style recurring chain dispatch | ~3 days backend + 2 days UI | Plan-tier differentiator (we already have Lago billing — easy to gate) |
| 8 | **Skill marketplace integration** — link to `BioTender-max/awesome-bio-agent-skills` from `/skill-finder`-style modal | ~2 days | Adopts their UX, leverages existing public catalog |

### Low-ROI / questionable

| # | Pattern | Reason to skip |
|---|---|---|
| - | Telegram + Discord integration | Wrong audience for labs/clinical (Slack would matter; Telegram/Discord don't) |
| - | Replace per-project context with global persona | We're already better here — keep our per-project model |
| - | Each chat = its own context window | We have chat-history persistence; ours is better. Don't regress. |

---

## What we have that SciClaw doesn't (lead with these)

1. **Real nf-core execution on AWS Batch** — they appear sandbox-only; we orchestrate sarek, drop, rnaseq, cutandrun, cryosparc, etc. End-to-end production-grade.
2. **60 curated chains + chain composer with provenance** — they have "skills" = single capabilities; multi-step chains are absent.
3. **Per-workflow QC gates + auto-loop remediation** — ADMET, docking, CYP-DDI, NCA-PK, cryo-EM all shipped with QC-loop pytest infra. Not in their docs.
4. **IND §2.6.1 LLM narrative + 21 CFR Part 11 framing** — regulatory-grade reporting they don't appear to support.
5. **Per-project members + RBAC + audit-log** — 31/31 audit assertions pass. Their docs don't mention multi-user models.
6. **Per-output presigned-URL endpoint with audit-log** (shipped today, commit `7a605a4089`) — compliance-ready output access.
7. **2,455 indexed workflows + BGE dense-retrieval** — their skill catalog scale unstated.
8. **chain_meta narrator + (why?) rationale popover** — per-phase scientific justification with DOI links. Not in their docs.
9. **Multi-tenant + Lago billing per invocation** — their credit system is opaque; ours has explicit per-run cost.
10. **Bioinformatics-specific QC vocabulary** in qc_evidence.yaml — they ship generic skills without per-domain QC.

---

## Recommended action

**Pick 4-week sprint adopting the top-4 patterns from §"High-ROI, easy to ship":**

1. Week 1: `conclusion.md` per run + persona-as-files
2. Week 2: `/skill-name` chat shortcut + skill browser modal
3. Week 3: Project Library file browser (read-only)
4. Week 4: Foundry-shape output picker (PPTX + HTML + .md variants of the Report)

After 4 weeks, BioMate matches SciClaw's UX maturity in the workflow-discovery and output-generation dimensions, while keeping our lead on real-execution + regulatory-grade reporting + multi-tenant + chains.

**Out of scope for sprint:**
- Board canvas (~1 week, valuable but big)
- Scheduled tasks (~5 days, big-bang feature; ship after billing-side gating is in place)

**Pitch to land later:**
> "BioMate is what SciClaw aspires to be once they're done with their MVP — same chat-driven research UX, but actually runnable on AWS Batch, with regulatory-grade audit trail, and a per-project compliance model that supports real lab teams."

---

## Open items the SciClaw docs raised

1. **Skills schema** (YAML? JSON? code?) — they keep it opaque. We should publish ours from day one if we want our skill marketplace to win.
2. **Foundry's "packaged default prompt"** — model for our future report-format templates. Look at theirs once we extend Download Report.
3. **`/skill-finder` open ecosystem** — confirm `BioTender-max/awesome-bio-agent-skills` is the canonical bio analog they could pull from.
4. **Plan-tier credit math** — their tiers (200K/430K/900K/2.4M) anchor our Lago pricing comparison. Cross-reference with BioMate workflow pricing table.
5. **No mention of compliance** — our IND/21CFR positioning differentiates. Confirm by checking enterprise SciClaw demos (if their sales team publishes).

---

## Verbatim quotes worth keeping

> "An AI co-worker built for scientific research" — their headline positioning. Echoes our "biology AI native" framing. Theirs is more co-pilot, ours is more execution-engine. Both legitimate.

> "Skills are callable task capabilities … users can /skill-name in chat to prioritize that skill" — argues for adopting `/chain-name` shortcut.

> "Foundry uses all indexed content in the current project Library as source material" — argues for project-scoped retrieval in output generation.

> "Persona shapes the AI's behavior with editable persona files — mainly SOUL.md and USER.md — so it fits the way you work." — file-as-config pattern, very Cursor/Claude-projects-like.

> "Each conversation operates as its own independent context window without automatic inheritance of other conversation history" — they punt on cross-chat context; we already do better with persisted chat history per project.
