# UX / Product-Design Audit — BioMate Tutorial Videos (T0–T4 + drug-dev flagship)

**Reviewer lens:** visual polish, information hierarchy, slide composition/balance, legibility,
pacing, transitions, cross-video consistency, and whether live-UI focal crops read clearly.
**Method:** read all six walkthrough HTML sources + narration listing; extracted and inspected
rendered MP4 frames with ffmpeg (I cannot watch MP4s, so I judged still frames). Frame files
referenced below live in the session scratchpad; the defects are reproducible from the cited
HTML + timestamps.

**Artifacts audited**
- Sources: `reference/claude_design/tutorials/{drug-dev,t0-getting-started,t1-design-and-generate,t2-models-and-the-closed-loop,t3-run-and-report,t4-bringing-your-own-data}-walkthrough.html`
- Narration: `reference/claude_design/tutorials/narration/*.{en,zh}.md` (all 6 present in both languages)
- Rendered: `recording/output/*-{en,zh}.mp4`
- Design bar: `reference/claude_design/data_centroid_design_v2/spec/00..14 *.html`

---

## 1. Verdict

The **drug-dev flagship is genuinely strong** — its concept scenes pair a bespoke SVG diagram
with a teaching card in a two-column layout (DBTL loop, hERG channel, cost ladder, Pareto
scatter, QC-gate flowchart, PK curve, provenance DAG), and its live scenes are clean,
center-composed focal crops. The **T0–T4 set is visibly weaker and not yet at that bar.** Two
concrete, high-severity problems dominate: (a) **every concept scene in T0/T1/T2/T4 is
composition-unbalanced** — the recent "compaction" fix made the card content-height and
vertically centered, so each slide now reads as a title block at the top, a ~200px dead band, a
card floating in the lower-middle, and an empty bottom fifth; with **zero SVG diagrams** to
anchor the stage, roughly a third of the slide is whitespace (confirmed on `t1_70`, `t1_150`,
`t1_190`, `t2_190`); and (b) **T0 and T3 still use the old 0.6s cross-dissolve** the flagship
explicitly removed, producing a visible double-exposure where the outgoing scene's text is
legible behind the incoming scene's text (caught red-handed in `t0_boundary` at t=44.3s:
"A cloud workbench you talk to in plain language" ghosts through "opens on the cold start"). The
set is also **thematically narrow** — essentially every live demo is the same ADMET run, so
BioMate's largest domains (transcriptomics, genomics, variant calling, cryo-EM) are never shown.
None of this is fatal; the design language, color system, type, and copy are good. But the set
needs a composition pass before it should ship next to the flagship.

---

## 2. Strengths

- **Consistent design tokens.** All six share the same `:root` palette, IBM Plex Sans/Mono,
  verdict-badge system (ok/partial/gap/plain), and tag taxonomy. Brand rail, progress bar, and
  counter are consistent in structure.
- **Honesty is designed-in, not bolted on.** Every video carries verdict badges and a closing
  summary table that labels each capability demonstrated / available / partial / gap. The
  "findings withheld when outputs unreadable" scene (T3 s4; flagship s7) is a real
  trust-building UX pattern. This is a differentiator — keep it.
- **The flagship's live focal crops are excellent.** `dd_200` (ADMET completed) is the gold
  standard: centered, legible at distance, real values (hERG 0.003, DILI 0.855, oral-bioavail
  0.873, Download report), balanced whitespace. T1's results/Pareto and T3/T4's panels are also
  legible real UI.
- **Concept *cards* are well-styled in isolation** — good tile borders, semantic color accents
  (green `in-domain`, red `out-of-domain` in `t2_190`; green/red/amber quality verdicts in T4).
  The problem is slide-level composition, not the card component itself.
- **Copy and information scent are strong** — kickers, running examples, and "habit at a glance"
  closers give each video a clear spine.

---

## 3. Defects (with file / scene / frame references + severity)

### P1 — Concept scenes are composition-unbalanced (whitespace lakes); T0/T1/T2/T4
- **Where:** every `.concept` scene. Source: `.concept{justify-content:center}` +
  `.card.big{flex:initial}` in t0/t1/t2/t4 HTML. The flagship instead uses `.card.big{flex:1}`
  (fills the stage).
- **Rendered proof:** `t1_70` (T1 s2), `t1_150` (T1 s4), `t1_190` (T1 s6), `t2_190` (T2 s5).
  Each shows: caption ends ~y360 → **~200px empty band** → card floats ~y560–760 → verdict
  ~y845 → **entire bottom ~20% (y880–1080) empty.** The eye lands on a short card marooned in
  the lower-middle of an otherwise empty stage.
- **Why it matters:** this is the majority of the series' runtime (T1 has 5 such scenes, T2 has
  5, T4 has 5, T0 has 3). Next to the flagship's diagram-anchored scenes, it reads as unfinished.
- **Note on the "recent compaction fix":** it did make the cards tidy and content-sized, but it
  over-corrected — the card is now too small for the stage and nothing fills the vacated space.
  The committee's question "do they now look professional / any residual caption-to-card gap?":
  **the cards look professional in isolation, but the caption→card gap and bottom dead-zone are
  large and remain the single biggest visual weakness.**

### P1 — T0 and T3 transition = visible text-on-text double-exposure
- **Where:** `t0-...html` and `t3-...html` use `.scene{transition:opacity .6s ease, transform
  .6s ease}` with `.scene.active{opacity:1}` and **no `transition:none` on deactivate.** T1/T2/T4
  and the flagship use the fixed pattern (`transition:none` inactive, `.18s` active). The
  flagship's own CSS comment documents this exact fix ("Deactivate instantly … so two scenes'
  text never overlap mid-dissolve").
- **Rendered proof:** `t0_boundary` (t=44.3s) — the outgoing "The idea · what BioMate is /
  A cloud workbench you talk to in plain language …" body text is clearly legible **behind** the
  incoming "Every new conversation opens on the cold start" heading and caption. Looks like a
  rendering glitch / broken slide.
- **Severity:** P1 for these two videos — it happens at **every** scene change (~8–9 times each),
  for ~0.6s each, and reads as broken. Trivial fix (copy the T1 transition rule).

### P2 — T0–T4 concept scenes carry zero bespoke diagrams; flagship carries seven
- Flagship concept scenes are two-column (diagram + card) — see `dd_55` (DBTL loop) and
  `dd_200`-adjacent concept scenes. T0–T4 concept scenes are **all** the same single-card +
  tile-grid template. The result is both the whitespace above (P1) **and** visual monotony:
  T1 runs five near-identical card-grid layouts back to back. High-value concepts that the
  flagship *proves* render beautifully as diagrams — closed loop, applicability domain
  (`t2_190`), Pareto front, provenance/lineage (T4 s6), quality verdicts (T4 s5) — are taught
  with text tiles only.

### P2 — T3 live scenes use a different layout than the rest of the series
- T3 uses `.shotcol` (flex 1.55, screenshot left) + `.teachcol` (bullets right); the other four
  live videos use the centered `.scene.live` focal-crop stack. So T3 is the odd one out.
- It also has its own whitespace bug: `t3_110` — the tall left frame is `object-fit:contain;
  object-position:center top`, so the screenshot pins to the top and leaves a **large empty white
  band in the bottom ~20% of the frame** (y820–1015), plus matching empty space under the
  right-column bullets.

### P2 — ADMET "completed" state contradicts itself across videos
- Flagship s7 (`dd_200`): ADMET on aspirin/caffeine/ibuprofen → **Completed with findings shown**
  (hERG 0.003, DILI 0.855, oral-bioavail 0.873, Download report).
- T3 s4 (`t3-...html`, `assets/live/t3-completed-withheld.png`): the **same workflow, same three
  molecules** → **Completed with findings WITHHELD** ("outputs could not be read").
- A viewer who watches both sees the identical running example end two opposite ways. Even if each
  is a real run, presenting them under the same "aspirin/caffeine/ibuprofen" example is a
  continuity break. Pick one canonical outcome or annotate the difference.

### P2 — T0 cold-start crop omits the composer it narrates
- `t0_60`: the caption and figcaption both promise "the **composer** — the message box — at the
  **foot**", but the screenshot is cropped so the composer is **not in frame** (bottom cut at the
  "Recent Tools" sidebar row). Caption/visual mismatch on the first product screenshot new users
  see.

### P2 — T1 live form crop has a sliced text line at the top
- `t1_230` (T1 s7): the form screenshot's top edge cuts a line of body text in half
  ("Generation is only useful when constrained … shown before the run starts.") and the bottom
  is also mid-cut. Reads as a careless mid-scroll capture rather than a clean focal crop.

### P3 — Chrome / token drift across videos
- **Rail counter wording:** flagship says "Slide X / 17" and shows a live Concept/Live-UI pill in
  the rail; T0–T4 say "Stage X / N" and have **no** rail kind-pill. Pick one.
- **Type scale drift:** T0 `h2` 38px / caption 19px; T3 `h2` 34px; others 36px / 18px. Live-scene
  `max-height` 51vh (flagship) vs 52vh (T1/T2/T4). Caption `max-width` 64ch (T0) vs 66ch (others).
  Small, but a skeptical eye catches it.
- **T0 default `object-fit:cover`** on `.shot img` risks cropping screenshots; only scenes with an
  inline `contain` override escape it. Inconsistent within T0.

---

## 4. Coverage / consistency gaps vs the v2 spec (modules 00–14)

Mapped to `data_centroid_design_v2/spec`:
- **Well covered:** 00 cold start (T0), 02 data analysis (T3), 03 models (T2), 04 dataset object
  (T4), 05 design & generate (T1), 07 workflow panel (T3 + flagship).
- **Partial:** 01 search & evidence (only T0's JAK1 aside; no dedicated worked-examples), 06
  composer (shown but cropped, see P2), 11 all-modalities (T1 names peptide/protein as "form
  only" but doesn't show them).
- **Not covered — UX-relevant gaps:**
  - **13 Run cards by domain** — the **single biggest gap.** Every live demo in the entire set is
    ADMET (flagship + T3) or a drug-discovery module (T1/T2). BioMate's largest catalog domains —
    transcriptomics (1,695 wf), genomics (756), variant calling (181), cryo-EM — are **never shown
    running.** A new user never sees an RNA-seq or variant-calling run card. The series reads as a
    drug-discovery product, not the general bioinformatics engine the catalog describes.
  - **08 Full step view** — the deep per-step input/output view is never a dedicated scene (T3's
    Outputs tab is the closest).
  - **12 Reports as editable files** — T3 mentions "RUN ORIGINAL / edits saved alongside" in copy,
    but the **act of editing a report** is never shown live.
  - **14 Panes & output previews** — type-specific previews (image thumbnail, HTML table, FASTA /
    VCF code block) are described but never demonstrated.
  - 09/10 Worked examples, plus the CRO-compliance and IND-report flows from the product's own UX
    standard — absent.
- **Language parity:** EN + ZH narration present for all six (good). I did not audit ZH prose
  quality (writer/translation lane).

---

## 5. Prioritized recommendations for the remaining work

1. **(P1, trivial, do first) Fix the T0 + T3 transition.** Replace their `.scene`/`.scene.active`
   rules with the T1/T2/T4 pattern (`transition:none` inactive, `.18s` active). Kills the
   double-exposure at every scene change.
2. **(P1, highest visual ROI) Rebalance every concept scene.** Two options, not mutually
   exclusive: (a) quick — set `.card.big{flex:1}` so the card fills the stage (closes the
   top-gap and bottom dead-zone immediately); (b) proper — adopt the flagship's two-column
   diagram+card pattern for the high-value concepts (closed loop, applicability domain, Pareto,
   provenance, quality verdicts). The flagship SVGs are directly reusable. This is what closes
   the quality gap to the flagship.
3. **(P2) Normalize T3's live layout** to the centered `.scene.live` focal-crop pattern used by
   the other four, and fix the `object-position` bottom whitespace.
4. **(P2) Reconcile the ADMET completed state** across flagship and T3 — choose one canonical
   outcome (findings-present or withheld) for the shared aspirin/caffeine/ibuprofen example, or
   label them as two distinct runs on screen.
5. **(P2) Re-capture two screenshots:** T0 cold-start to include the composer it narrates; T1
   form so the top line isn't sliced.
6. **(P2, coverage) Add at least one non-drug-discovery live demo** — an RNA-seq or
   variant-calling run card — so the series represents BioMate's largest domains (addresses spec
   13). Ideally also one step-deep-view (08) and one output-preview-by-type scene (14).
7. **(P3) One chrome pass:** unify the rail counter wording + kind-pill, align `h2`/caption sizes
   and live `max-height`/`max-width` across all six, and remove the risky default
   `object-fit:cover` in T0.

**Audit discipline note:** I judged rendered frames, not the MP4s themselves, and did not edit any
tutorial/video files. Every defect above is traceable to a cited HTML rule or a cited frame
timestamp, so each is independently verifiable.
