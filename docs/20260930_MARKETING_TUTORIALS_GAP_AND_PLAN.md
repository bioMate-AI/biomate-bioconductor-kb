# Marketing Section — Review, Gap Analysis & Plan

**Date:** 2026-09-30
**Source task:** `reference/0930_todo.md` §1–2 (Marketing)
**Scope of this doc:** the Marketing section only — (A) website scope tuning, (B) drug-development platform manual + videos, (C) hospital-instrument + other-module manual + videos, plus the cross-cutting screenshot/chat-cleanup/new-UI work. ACT accelerator (§3) and the two hospital surveys (§4–5) are separate tasks, not covered here.

---

## 0 · What the todo asks

1. **Website — tune the scope** to signal BioMate is for **immune-mediated disorders**: target identification → peptide development → closed-cycle optimization.
2. **User manual + tutorial videos (EN + CN) for the drug-development platform** — especially drug-generation tools, workflows, multi-objective optimization, closed cycles, and the **input/output of each process**.
3. **User manual + tutorial videos (EN + CN) for hospital instrument workflows** and other function modules.
4. Cross-cutting: reference prior manuals, make them **user-friendly with enriched, high-resolution screenshots**; current screenshots are **low-res**, some are debug/duplicate junk; **clean up chat history before screenshotting**; **many screenshots are missing**.
5. New UI: **every workflow needs new tutorials on the new UI**; review current tutorials to find the gap — what must be **added/highlighted** for the new UI and its new function modules.

---

## 1 · What we have now (ground truth)

### Website
- **`reference/claude_design/webpage_design_v2/`** — the live public site (73 HTML pages). Hero today: *"BioMate is your AI assistant for biomedical research and application."* Positioned as **general-purpose bioinformatics across 36 domains**, all weighted equally.
- Immune-mediated disease content exists **only in blog deep-dives** (MG, RA, CIDP, complement, CD40L, IL-6) — not in the hero/about/services front-facing narrative.
- **`reference/claude_design/biomate_market_v1/`** — the newer **BD/pharma deck** (10 slides, CN+EN) that *already* carries the target positioning: drug-discovery platform, generate→verify→learn **closed-loop flywheel** (hero), **macrocycle/peptide** generative model, target-ID→clinic coverage.

### Manuals & tutorials
- **`docs/20260403_BIOMATE_USER_MANUAL.md`** (EN) + **`docs/20260923_BIOMATE_USER_MANUAL_ZH.md`** (CN) — parallel general manuals, 5 domains, older UI.
- **`docs/20260422_BIOMATE_USER_TUTORIALS.md`** — 6 use-case tutorials (incl. ADMET, drug CRO) + 7 feature guides, older UI.
- **`docs/user-manual/`** — structured 46-chapter book. Design & generate (I11), Models (I10), Drug-discovery→IND (D1, code-verified) exist. **EN only.**
- **Videos:** 4 published YouTube demos (intro, cryo-EM SPA, after-run report, IND §2.6) — **EN only**; recording pipeline (`reference/claude_design/tutorials-work/`, Playwright + ElevenLabs) is ready.

### New UI
- Canonical spec: **`reference/claude_design/data_centroid_design_v2/spec/*.html`** (§00–08) + standalone HTML prototype.
- Partially live in the React app: `cold-start-dashboard.tsx`, `findings-card.tsx`, `auto-loop-panel.tsx`, `steps/step-detail.tsx`, `app-sidebar.tsx`.

### Screenshots (audited in `docs/20260922_USER_MANUAL_SCREENSHOT_AUDIT.md`)
- 11 embedded in the book: 6 clean, **3 debug-scaffold leaks** (i08-1, i09-1 shows a forbidden "Analysis in progress…" spinner on a completed run, i09-2 empty record), **1 low-res** (capabilities). **~29 broken/missing** image links. Chat history used for capture has **duplicate topics**. → Manual is **not publishable as-is**.

---

## 2 · The gap (what's missing vs. the todo)

| # | Todo item | Gap |
|---|---|---|
| A | Website → immune-mediated-disorder scope | Front-facing site is generic. Zero hero mention of **immune-mediated disorders**, **peptide/macrocycle development**, or **closed-loop optimization**. Positioning is settled (deck v1 + brief) but **not ported to the website**. |
| B | Drug-dev manual + videos (EN+CN) | No end-to-end tutorial on the **new-UI Design & Generate** flow: generate→predict→optimise→rank, **multi-objective view** (affinity/safety/synthesizability shown separately), **2D depiction grid**, **closed-loop** (measured overrides predicted, rounds table), and **I/O at each step**. I11 chapter exists but has old/absent screenshots and no worked closed-loop example. **No CN book, no CN videos.** |
| C | Hospital-instrument + other-module manual + videos (EN+CN) | **Largest content gap.** No instrument-workflow tutorials at all (connectors live in `biomate-connector`: `list_instruments`/`get_instrument_status`/`run_instrument_protocol` + 10 lab-instrument connectors). "Other function modules" (Search & evidence, Models, Projects, Connectors, Billing) lack new-UI tutorials. |
| D | High-res, enriched screenshots | 3 debug leaks + 1 low-res + ~29 missing; chat history dirty. Need a **clean capture harness** (dedicated demo project/chat per domain, high-DPI). |
| E | New-UI re-shoot + highlight new modules | Every tutorial screenshot is on the **old UI**. New modules that must be taught/highlighted: cold-start **intent router**, **Search & evidence**, **Models as first-class**, **Design & Generate**, **full step view/provenance**, **quality gates + auto-loop**, **human approval gates**, **findings-as-clickable-links**, **dataset objects**, **3-tab after-run report**, **unified Settings & workspace**, **composer controls (lane override / experts / attachments)**. |

---

## 3 · Constraints that shape the work (from settled docs)

- **Positioning (deck brief `20260922`):** three moat pillars = closed loop · speed · in-house generative model for hard-to-drug chemistry (macrocycles/peptides). Multi-objective = delivered capability, **not** claimed as our invention.
- **Content rules (HARD):** no "our / your"; **no method/tool-stack disclosure** (no model class, no nf-core/REINVENT/AWS/etc.); no named-competitor jabs; honest — no "first/only" absolutes; illustrative numbers labeled as such; **bilingual, CN-primary** for the deck/website audience.
- **Honesty (committee review `20260922`):** do **not** claim the dry↔wet loop is GLP/Part-11 compliant or that it "beats baselines." Present the closed loop as architecture + moat with **wet-lab validation forthcoming**.
- **Disease framing (landscape `20260926`):** immune-mediated / immuno-oncology; multi-target macrocyclic peptides are near-white-space. Keep claims measured.

---

## 4 · Plan (phased)

### Track A — Website scope tuning  *(no live-dev / no screenshot dependency — unblocked now)*
A1. Rewrite `index.html` hero + `about/services/features` to **lead with the immune-mediated-disorder drug-discovery narrative**: *target identification → peptide (macrocycle) development → closed-loop optimization*, with the 36-domain platform framed as the **engine underneath** (breadth retained, not headlined).
A2. Add a **closed-loop (generate→verify→learn)** section mirroring deck v1 slide 5; add a **peptide/macrocycle** capability block.
A3. Apply the hard content rules; keep it bilingual-ready. Cross-check every claim against §3 honesty constraints.
A4. Self-audit against the deck brief acceptance criteria (zero forbidden phrases, honest numbers).

### Track B — Drug-development platform manual + videos (EN + CN)
B1. Author a **new-UI "Drug Discovery & Design" tutorial**: cold-start intent → Design & Generate (generate→predict→optimise→rank) → multi-objective view → closed-loop rounds → step provenance → findings/report, **documenting input & output at each step**.
B2. Refresh book chapter **I11 (Design & generate)** + **I10 (Models)** with new-UI screenshots and a worked closed-loop example.
B3. Produce the **CN** manual for the above (idiomatic, native-reviewed).
B4. Draft EN + CN **video scripts** (reuse the ElevenLabs/Playwright pipeline); record in the screenshot batch.

### Track C — Hospital-instrument + other-module manual + videos (EN + CN)
C1. Survey the instrument capability in `biomate-connector` (10 connectors + MCP instrument tools) and how it surfaces in the app.
C2. Author manual + tutorials for **hospital instrument workflows** and **other function modules** (Search & evidence, Models, Projects, Connectors, Billing). EN + CN.
C3. Video scripts as in B4.

### Track D — Screenshot + chat-cleanup harness  *(prerequisite for B/C/E capture)*
D1. Verify **what of the new UI is live on dev** vs. only prototype; decide capture source per panel (live dev where available; HTML prototype in a clean browser frame otherwise — the deck brief explicitly permits framed shots).
D2. **Clean the fixture-account chat history** (`lifeifei163361@163.com`) — collapse duplicate topics, seed one clean demo chat/project per domain.
D3. Build a **high-DPI Playwright capture harness** (deviceScaleFactor ≥2), fixed viewport, CN and EN locales; re-shoot the 3 debug leaks + 1 low-res + the ~29 missing figures.
D4. Capture the **new-UI highlight set** (§2 row E) once per language.

### Track E — Gap-close on new-UI tutorials
E1. Walk every existing tutorial/chapter; for each, list which new-UI modules it must now teach/highlight (from the §2-E list) and re-shoot accordingly.
E2. Update the coverage ledger + screenshot audit as items close.

---

## 5 · Recommended sequence & rationale

1. **Track A (website)** first — unblocked, highest external visibility, positioning already settled. Days, not weeks.
2. **Track D (capture harness + chat cleanup)** next — it's the shared prerequisite for all manual/video work; nothing high-res ships without it.
3. **Track B (drug-dev manual)** — the deck's flagship story; highest-value manual.
4. **Track C (instrument + other modules)** — largest gap but lower external urgency.
5. **Videos** batched after written+screenshots are locked (avoid re-recording).

---

## 6 · Open verification items (resolve during execution, not blockers to planning)
- Is the **full data-centric new UI live on dev**, or only the partial React components? (Determines D1 capture source.)
- Are the 10 instrument connectors surfaced in the **public app UI** or only via MCP/connector repo? (Determines whether C tutorials are UI-based or API/MCP-based.)
- Confirm CN i18n UI is live on dev for CN screenshots (deck brief flagged "recapture in Chinese once i18n UI is live").

---

## Change log
- 2026-09-30 — created from a 3-agent inventory sweep (website/positioning, manuals+tutorials, new-UI gap) + the settled deck brief, committee review, and IO landscape docs.
