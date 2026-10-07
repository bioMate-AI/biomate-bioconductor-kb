# BioMate UI Style-Gap Audit — product appearance vs `data_centroid_design_v2`

**Date:** 2026-10-07. **Method:** 4 parallel audits comparing the **live dev** product
(`dev-public.biomate.ai`, captured today) against the claude design prototype
`reference/claude_design/data_centroid_design_v2/` and its spec. Judged from actual pixels.

**Framing (per user, [[feedback_design_mockup_is_style_ref]]):** the mockup defines the target
**visual style/appearance/attractiveness**, NOT the function set. The product legitimately has MORE
functions than the mockup. Every item below is about **styling** an existing function to match the
design — not removing functions. Genuine defects are in the separate **Bugs** section.

**Canonical target tokens:** `docs/20261007_BIOMATE_DESIGN_SYSTEM_GUIDE.md` (extracted from the
prototype CSS: Inter UI + JetBrains Mono, OKLCH cool-neutral palette, single blue accent used
sparingly, **no serif anywhere**, radii 4/6/8/12/16, subtle slate shadows, monochrome line icons,
primary button = solid near-black, sidebar 220px / panel 500px, dense 12.5–13.5px type).

## Headline
The delta is **not** uniform. The search answer, dataset-object, and multi-objective results views
are already ~90% on-design (clean cards, mono values, verdict colors). The attractiveness gap is
concentrated in **(1) the app shell / logo / sidebar** and **(2) the workflow panel + after-run area**.
Three fixes alone close most of the gap: fix the logo, delete the serif panel title, and de-densify
the sidebar.

---

## P0 — highest visual impact (do first)

| # | Element | Current (product) | Target (design) | Fix / source |
|---|---------|-------------------|-----------------|--------------|
| P0-1 | **Logo** | Large busy multicolor DNA-helix + green-leaf raster, full-bleed to edges (`objectFit:cover`, negative margins); trailing **"AI" clipped/overlapped** by the collapse button + BETA chip stacked over it | Small calm wordmark in a padded, bordered header | `frontend/client/src/components/app-sidebar.tsx:193-230` — shrink/contain the logo, move collapse button + BETA chip out of the logo box |
| P0-2 | **Serif panel title** | Workflow-panel title renders in **DM Serif Display / Georgia serif**, clashing with the sans/mono body | Inter 600, ~22px, `#101828`, -0.02em | `frontend/client/src/styles/workflow-panel.css:146` — delete the serif line, use `var(--font-ui)` (the var already = Inter) |
| P0-3 | **Two-line nav density** | Every sidebar item carries a 2nd gray 11px sub-label ("Start a fresh AI conversation", …), doubling row height → dense/noisy | icon + 13px label only (single line, `6px 10px`) | `app-sidebar.tsx` nav rows — drop the description spans (move to tooltips if wanted) |

## P1 — clear polish wins

| # | Element | Current | Target | Fix |
|---|---------|---------|--------|-----|
| P1-1 | Nav/folder icons | render **blue** | monochrome `--text-muted` gray (~0.7 opacity), accent only when active | force `currentColor` |
| P1-2 | Count badges | heavy pills ("Workflows 103/135") | quiet right-aligned mono numeral in `--text-dim` (like Files 10 / Runs 3) | restyle; also see Bug (count instability) |
| P1-3 | Top bar | only "New thread", no breadcrumb | `project ▸ new chat` breadcrumb over a "New chat" title | add breadcrumb |
| P1-4 | Projects tree | flat list | expands to Files/Runs/Instructions + chat rows with green/gray/red status dots, left-border indent | nest + status dots |
| P1-5 | Panel progress bar | only a tiny inline `0/2` + small pill | slim full-width blue bar under header ("Completed ▰▰▰ 100% 11/11"), persistent across tabs | add progress bar |
| P1-6 | Pre-run param strip | each param a big bordered input box inside a bordered accordion; loud blue "Recommended" pills — very tall/boxy | dense `label → mono value → subtle UPPERCASE mono source-tag` on hairline dividers (~60% shorter) | `nextflow-workflow-viewer.tsx` + panel css |
| P1-7 | "Recommended" badge | loud solid blue | quiet mono-uppercase gray `.tag`; reserve blue for genuinely new/changed | restyle |
| P1-8 | **"Run again" footer** | washed-out ghost-gray full-width pill — reads as **disabled** on a completed run | solid near-black bold primary with ▶ icon (consistent with pre-run/running footers) | restyle; **verify it isn't actually disabled** (see Bugs) |
| P1-9 | Report download | tiny blue text link ("↓ 下载报告") | report card: version pill `v1` + ⚙Edit / ↓Download (blue filled) / In Files | restyle to a report card |
| P1-10 | Outputs tab | flat dense table (步骤/文件/类型 · 查看 下载, no previews) | 2-col grid of output **cards** with per-type preview thumbnails (figure/log/table), type pills + glyphs, filename+metadata subline, search bar | biggest after-run attractiveness surface |
| P1-11 | Status pills | inconsistent, no legend | unified token pills (green DONE / blue running / gray waiting-skipped) + colored-dot legend; active tab count badge blue | unify |

## P2 — refinement

| # | Element | Fix |
|---|---------|-----|
| P2-1 | Raw `snake_case`/title-cased labels (`Cipa Qnet High Risk Threshold`, `Admet Infer Shard`, `Apd90`) | humanize + acronym-casing (hERG / APD90 / CiPA / DILI) |
| P2-2 | Findings numbers plain text | style measured numbers as dotted-underline blue links tied to their output (design's auditability signature) |
| P2-3 | File-type labels bare uppercase (JSON/TXT/YML) | colored type pills with glyphs |
| P2-4 | Domain eyebrow ("药物发现 · 工作流") bold sans normal-case | mono, uppercase, letter-spaced, light gray |
| P2-5 | Footer/account block cluttered ("Sign out" text + gear, email overflow) | clean avatar + name + "early access" tag + light/dark toggle; ellipsis the email; mute the saturated-orange BETA chip |
| P2-6 | Global font loading | ensure Inter + JetBrains Mono load (spec.css IBM Plex styles the SPEC docs, not the product) |

---

## Bugs (genuine defects — not styling; fix regardless of the redesign)

1. **Duplicate project rows** — the sidebar lists the same project (e.g. "IL-17A Cyclic Peptide Pilot") 4× identically (also stacked E2E Team/Share/AUTHZ rows). Dedupe by project id.
2. **Logo "AI" clipping** — the wordmark's trailing "AI" is cut by the overlapping collapse button + BETA chip (same as P0-1).
3. **Workflows count instability** — the count differs across identical cold-starts (103 vs 135 vs 9); non-deterministic/unscoped query.
4. **Run Manager badge drift** — 1 in the design vs 9/15 on dev; confirm it is user-scoped, not global.
5. **Footer email hard-truncates** — needs ellipsis + max-width.
6. **"Run again" may be truly disabled** on a completed run — confirm it's enabled (styling is P1-8).
7. **SMILES used as param NAMES** in the panel (`CN1C`, `SMILES` as labels with SMILES-string values) + duplicate/redundant SMILES params on one run — extraction/schema bug in the workflow spec.
8. **QC-gate operator looks contradictory** (`…Max Pct ≥ 30`) — verify operator direction.
9. **search-answer overlapping/garbled label** under the Citations toggle ("ool Citations tion") — a control colliding with the Citations header; z-index/position bug.

---

## Recommended order
1. **P0 trio** (logo, serif title, sidebar density) — ~80% of the perceived "ugliness" for the least effort.
2. **Bugs 1–2 & 9** (duplicate projects, logo clip, garbled citations label) — visible defects, cheap.
3. **P1 panel + after-run** (progress bar, param strip, Run-again, report card, outputs-as-cards, status pills) — the drug-dev videos live here.
4. **P1 shell** (icon color, breadcrumb, projects tree, count badges).
5. **P2 refinements.**

After the P0 trio + panel P1s land on dev, re-capture the product screenshots and re-render the
tutorial videos (branding already baked into the decks per
`docs/20261006_REQUIREMENT_DRUGDEV_FULL_PROCESS_TUTORIAL.md` §8).

## Source reports
Per-area raw audits (scratchpad): `gap_shell.md`, `gap_panel.md`, `gap_chat_afterrun.md`.
Canonical target tokens: `docs/20261007_BIOMATE_DESIGN_SYSTEM_GUIDE.md`.
