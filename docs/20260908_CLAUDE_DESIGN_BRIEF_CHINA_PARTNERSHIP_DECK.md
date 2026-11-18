# Design Brief for Claude Design — Regenerate the China Partnership Deck + Fix the Document Formatting

**Date:** 2026-09-08
**To:** Claude Design
**From:** BioMate team
**What we need:** (A) regenerate the China hospital/pharma partnership **deck** as a visually compelling, well-designed presentation — the current version is a plain bullet export and reads as boring; (B) redesign the **partnership documents** (requirements + review) into a well-structured, easy-to-read format. Keep the *content/messaging* below intact (it has been carefully corrected); change the *design, structure, and information hierarchy*.

---

## 0. Content sources (use these verbatim for messaging — do not re-invent the story)
- **Deck content (the narrative + slide copy) — CANONICAL SOURCE:** `docs/20260908_CHINA_PARTNERSHIP_DECK_EN.md` (pandoc source: `%` title, `#` per slide, `::: notes` speaker notes). This is the *approved, reframed* messaging (platform-first; Path A platform for pharma+hospital; Path B drug-dev separate; China-appropriate domestic 国产化/信创/PIPL/HGR). Do not change the framing; make it beautiful. The current flat deck was generated from this same source via plain `pandoc` — regenerate it as a designed presentation instead.
- **Full requirements/strategy (for the doc redesign):** `docs/20260908_CHINA_PARTNERSHIP_REQUIREMENTS.md`
- **Multi-lens review (for the doc redesign):** `docs/20260908_CHINA_PARTNERSHIP_MULTILENS_REVIEW.md`
- **Design system to match:** the BioMate public site design at `reference/claude_design/webpage_design_v2/` (`styles.css`, `shell.js`) — reuse its color system, typography, spacing, and component vocabulary so the deck looks like BioMate, not a generic template.
- **Real product screenshots (USE THESE — captured from the data-centric prototype, genomics-forward to keep the platform message un-drug-biased):** `docs/assets/china_deck/`
  - `02_chat_workflow.png` → **Title / opening** slide — plain-language RNA-seq request → validated pipeline → auditable findings (the whole value prop in one image).
  - `01_coldstart_dashboard.png` → **Path A · what it does** — the one front door + general module cards (breadth).
  - `03_run_surface.png` → **Path A · the value** — phase/step/output/quality-gate view ("it shows its work").
  - `04_dataset_object.png` → **Two pilot examples** (or a data slide) — data as a first-class object (identity/quality/versions/lineage, notebook launch).
  - Available but drug-mixed (use only if a chemistry visual is wanted): `05_models.png` (registry incl. ADMET/hERG), `07_workflows_history.png` (3 RNA-seq + 1 ADMET row), `06_findings_report.png` (RNA-seq QC audit — clean, optional).
  - Frame these as browser/product mockups (device frame or subtle shadow); they are the actual UI, so lead with them rather than clip-art.

---

## 1. Audience & purpose
- **Primary audience:** the China partner's **CEO + a non-technical business lead** (decision-makers, not engineers). Also read by our internal team and an external reviewer (Andrew).
- **Purpose:** open a co-development partnership for a **domestic (国产化/信创), on-premise, Chinese-language edition** of the BioMate analysis platform, plus a separate joint drug-development track.
- **Register:** **formal, professional, credible** — senior-scientist / executive audience. **No salesy taglines, no punchy one-liners, no hype.** Confidence through clarity, not adjectives.

---

## 2. Why the current deck fails (fix all of these)
1. **Wall-of-bullets on every slide** — no visual hierarchy; every slide is the same 4-bullet list. → Each slide needs one dominant idea expressed *visually*.
2. **Default template** — plain white, default fonts, no brand, no color system, no iconography. → Apply the BioMate design system.
3. **No diagrams** — concepts that are inherently visual (two paths, the platform as a front door, land-and-expand, two-track economics, department fit) are written as text. → Turn them into diagrams.
4. **No data-visual hero moments** — strong facts (e.g. "~$60B invested, ~175 programs, zero approved") are buried in a bullet. → Make them hero stat blocks.
5. **Flat rhythm** — 20 identical slides. → Vary slide types (section dividers, full-bleed diagram, stat slide, comparison table, 2-column) to create pace.

---

## 3. Design principles (apply throughout)
- **One idea per slide**, stated as a short headline (a claim, not a label), with the support expressed visually.
- **Visual hierarchy:** a clear focal point per slide; ≤ 3 supporting elements; generous whitespace.
- **Show, don't list:** prefer a diagram, a matrix, a stat block, or a 2-column comparison over a bullet list. Where bullets are unavoidable, ≤ 4, short, with icons.
- **Consistent system:** one color palette (BioMate brand + a China-market accent), one type scale, one icon set, consistent slide chrome (section tag, page number, subtle logo).
- **Section dividers** between the deck's acts (see §4) to give structure and breathing room.
- **Accessibility/exportability:** legible at a distance (min body ~20pt equivalent), high contrast, and it must export cleanly to **PDF and PPTX** for sending.
- **Bilingual-ready:** design so a Chinese-localized version can drop in later without breaking layout (allow for text expansion/contraction; keep Chinese terms 国产化/信创/人类遗传资源 renderable).

---

## 4. Deck structure — 5 acts, ~20–22 slides
Group the slides into acts with a **section divider** before each. Per slide: the **headline** (the point), the **visual treatment** we want, and the **content** (from the source deck).

### Act I — What BioMate is (3 slides)
1. **Title** — BioMate × China Hospital & Pharma Partnership. Full-bleed brand visual; confidential/date chip. *(cover)*
2. **BioMate is a general analysis platform** — headline + a **"front door" diagram**: plain-language question → the platform selects & runs the right validated analysis → auditable result. Small omics-breadth chip row (genomics · RNA-seq · single-cell · proteomics · metagenomics · imaging · multi-omics). *Not* drug-centric.
3. **The problem** — data → decision is slow and expert-gated. Visual: a "months / teams of specialists" before-state vs BioMate's guided flow after-state (simple before/after).

### Act II — The two paths (6 slides)
4. **Two separate paths (do not confuse them)** — the single most important structural slide. Visual: a **two-lane diagram** — *Path A · Platform* (recurring software business; nearer-term, lower-risk) and *Path B · Joint Drug Development* (asset business; longer-horizon, shared upside) — with a clear divider showing "different economics, timelines, agreements — priced separately."
5. **Path A — The Platform (what it does + who it serves)** — now TWO slides in the source md. First, **broad-domain breadth is the hero** (genomics & variant interpretation · bulk & single-cell RNA-seq · epigenomics · proteomics · metagenomics & pathogen ID · imaging · multi-omics) with an explicit de-bias caption: "drug-molecule work is just one of many uses — and molecule *design* is Path B." Second, **who it serves** — a **hospital column broken out by department** (*Oncology*: tumor profiling / variant interpretation / biomarkers / stratification · *Infectious disease*: pathogen ID & AMR · *Medical genetics / rare disease*: hereditary variants · *Immunology*: single-cell profiling) and a **pharma/biotech R&D column** (omics analysis, target biology, biomarker discovery, reproducible self-service pipelines). Footnote lane: "clinician signs the clinical report; the platform does the analysis." IMPORTANT: department breadth is the point — this must NOT read drug-centric.
6. **Path A — The value** — 4 value pillars as **icon tiles** (Speed · Trust/auditability · Breadth in one place · Compliant & on-premise). Not bullets — tiles.
7. **Path B — Joint Drug Development (separate)** — headline: a separate co-development track. Visual: a **stage arrow** target → lead compound → candidate → IND-ready, with "co-development partner, not a drug from a button" as the honest caption. Visually distinct styling from Path A so the separation is obvious.
8. **Path B — where we fit along drug development** — the 先导化合物 / 候选药 / 药物疗效验证 question answered as a **positioned bar** (strongest at lead discovery & optimization; supported toward candidate + efficacy/mechanism).

### Act III — The China opportunity (4 slides)
9. **The market opening in China** — headline: foreign clouds are excluded; domestic is required. Visual: a simple gate diagram (data can't leave · 国产化/信创 procurement · foreign platforms shut out · the opening = compliant domestic edition + a partner with hospital access).
10. **The market landscape — two crowded clusters** — Visual: a **2-cluster map** (Model builders vs Platforms/automation) with named players as chips, and a **hero stat block**: "**~$60B invested · ~175 clinical programs · 0 AI-discovered drugs approved**" → the credible reframe ("value is in governed, compliant delivery"). This is the deck's strongest moment — design it as a standout.
11. **Where BioMate fits — differentiated, not uncontested** — Visual: a **seam diagram** showing BioMate at the intersection (conversational front door + validated catalog + QC/provenance + regulator-ready output), with the honest note "each ingredient has a strong competitor (incl. XtalPi 晶泰); our edge is the combination + governance + domestic compliance." Do **not** claim "no competitor."
12. **Local deployment (non-negotiable)** — Visual: a **hospital boundary** graphic — everything runs inside the hospital; domestic AI models on the hospital's own servers (DeepSeek/Qwen-class, orchestrated not built); offline/air-gapped on 信创 stack; full audit/access-control/ethics-IRB. Data never leaves.

### Act IV — Built for China + the model (4 slides)
13. **Built for China — localization, integration, control** — 4 quadrants (Fully Chinese · Fits your systems/LIS-HIS-sequencers · Configurable without code · Compliant by design: PIPL/人类遗传资源/信创).
14. **Only what each department needs** — Visual: **capability-pack cards** across departments (e.g. "Oncology Sequencing," "Infectious Disease / AMR," "Single-Cell Immunology," "Rare-Disease Genetics") — smaller, focused, separately licensed; lower entry cost + stronger IP containment. *(Drug-molecule discovery is its own pack, part of the separate Path B — not the lead example here.)*
15. **Protecting the technology (IP)** — Visual: concentric protection (on-prem inside customer sites · license-controlled, node-locked delivery · department subsets so no site holds the whole system · clear ownership split defined in the term sheet). Keep it business-level (no "compiled non-readable" claim).
16. **The partnership model — two separate tracks** — Visual: a **two-track economics diagram** — Track A (platform licensing revenue-share, recurring, per hospital/dept/pack) and Track B (drug-program milestones + royalties, per program) — explicitly *separate agreements*. Partner owns the China market (sales/deployment/maintenance, trained & certified by us).

### Act V — The path forward (4 slides)
17. **How we reach the market** — Visual: a **land-and-expand motion** (land: one or two paid platform pilots — a lighthouse **hospital department** and/or a **pharma R&D team** → expand: more packs/departments → adjacent hospitals/sites), with the drug-programs track shown as a *separate* parallel motion.
17b. **Two pilot examples (illustrative)** — Visual: **two side-by-side pilot cards**, both labelled *Platform · Path A*. **Pilot 1 · Hospital department** (e.g. Oncology or Infectious Disease: department sequencing → interpreted, auditable Chinese research reports on real governed data; value moment = weeks→a day). **Pilot 2 · Pharma / biotech R&D** (e.g. a bench team self-serving a validated RNA-seq / biomarker pipeline — reproducible, quality-gated, documented). Caption: "same product, two very different customers; drug-molecule programs = Path B, separate." Note it's illustrative — swap per available data/champion.
18. **What we need from you** — a clean checklist card (a first pilot host — hospital department and/or pharma R&D team — with use-case + data; reference DBs; regulatory/procurement navigation; governed pilot data; *separately for Path B* a co-development target; localization review).
19. **Plan & path — two tracks** — Visual: a **phased timeline** (Phase 0 align/term-sheet → localized pilot → real-data validation → productize the China edition), with the drug-programs track as a separate lane on its own timeline.
20. **The ask** — a single, calm closing slide: co-develop the China edition under a shared framework with the two tracks structured separately; nominate the first hospital/department/use-case. One clear next step (a Phase-0 workshop). No hype.

*(Speaker notes from the source deck should be carried into the slide notes.)*

---

## 5. Document redesign (requirements + multi-lens review)
The two accompanying documents are content-complete but **poorly formatted — dense, flat, hard to scan.** Redesign them (keep all content) with:
- **A cover page** (title, subtitle, date, "confidential — for discussion," a small BioMate mark).
- **An executive summary** (½–1 page) at the top of each — the 3–5 things a busy reader must take away.
- **A table of contents** with section numbers.
- **Strong visual hierarchy:** clear H1/H2/H3 styling, section numbers, generous spacing, no wall-of-text paragraphs (break into short paragraphs + lists).
- **Tables for anything comparative** (the department-fit table, the need→fit table, the risk register, the fixes list) — styled, with header shading and zebra rows, not raw markdown pipes.
- **Callout boxes** for the honesty-contract notes, the key risks, and the "what we need" asks (colored side-bar callouts).
- **A consistent color-coded status vocabulary** (e.g. strong / partial / gap; addressed / owed) rendered as pills, not plain text.
- **Running header/footer** with doc title + page numbers.
- **Readability:** a serif or high-legibility body face, ~11pt, comfortable line length; the review's risk register (CC-1…CC-5) rendered as a scannable card grid.
- Output as **styled PDF + editable source** (and DOCX for the requirements doc, since the partner may comment inline).

---

## 6. Output & deliverables
1. **The deck** — a designed, presentation-ready slide deck in the BioMate design system, exportable to **PDF and PPTX** (16:9). If produced as HTML (reveal.js-style or custom), also provide the export.
2. **The two redesigned documents** — styled PDF (+ DOCX for the requirements doc).
3. **A design-token note** — the palette, type scale, and components used, so future decks stay consistent.
4. Keep everything **bilingual-ready** (layouts that survive a later Chinese localization).

---

## 7. Constraints (must-honor)
- **Do not change the approved messaging/framing:** platform-first (pharma + hospital, one engine); drug development is a *separate* track; China build = pure domestic (国产化/信创) on-prem edition; **no US-regulatory framing (GxP/21 CFR)** anywhere — the China bar is PIPL / 人类遗传资源 (HGR) / 信创 / 等保.
- **No method/tool-stack disclosure** in the deck (business value only; light credibility tags are fine — no internal tool names or method recipes).
- **Honest, not hyped:** keep the honest boundaries (e.g. clinician signs the clinical report; drug-dev generator not built; "differentiated, not uncontested"). Credibility with senior scientists depends on it.
- **Formal professional register** — no marketing taglines or exclamation-style punchlines.
