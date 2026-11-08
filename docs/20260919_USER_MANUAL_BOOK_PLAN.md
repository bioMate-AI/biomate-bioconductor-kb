# BioMate User Manual — Plan for a Structured, Indexed Book (+ system audit-and-fix)

**Date:** 2026-09-19
**Why now:** the current manual (`docs/20260403_BIOMATE_USER_MANUAL.md` / `.docx`) is one long, text-heavy
document covering only 5 domains — general, statistics-forward, unstyled. Users report they can't
understand it. We will replace it with a **structured, indexed book**: overview → general function
modules → function areas by domain → databases & retrieval → appendices — page-styled to look like a
high-end company, use-case-first, and **interpretation over statistics**.

**Second purpose (equally important):** writing the book is a **structured audit of the whole system**.
As we document each module and use case, we exercise it on dev, detect errors, and fix them — so the
manual is *true*. **We honor the content in the manual for users: nothing is documented that doesn't
actually work.** Anything unverified or coverage-gapped is either fixed or clearly marked "not yet
supported" — never over-promised.

**Reference:** the book's module taxonomy mirrors `reference/claude_design/data_centroid_design_v2/`
(spec sections 00–14 + `dataui/` components). Page styling reuses the polished HTML exemplars under
`reference/claude_design/tutorials-work/` (IND Report, Research Agent UI, cryo_tutorial) and a design
system (`data_centroid_design_v2` / `webpage_design_v2` / `biomate`) + brand assets (logo, flyer).

---

## 1. Design principles (how this manual differs from the old one)

1. **Use-case-first, not feature-first.** Every domain chapter opens with a researcher's goal
   ("differential expression, treated vs control"), then shows the path — not a parameter glossary.
2. **Interpretation over statistics.** The old manual dumped stats; users want "what does this number
   mean and what do I do next." Every result section explains the artifact (DEG table, VCF, docked
   pose, IC50, map+resolution) and the QC-gate thresholds *with citations*, not raw metrics.
   (This is the fix the tutorial-demo plan already mandates: terminate at a gold-standard-comparable
   artifact, not a process tree — `docs/20260619_TUTORIAL_DEMO_PLAN.md`.)
3. **Indexed & hierarchical (a book).** Overview → general modules → function areas → domains →
   databases/retrieval → appendices, with a real table of contents, cross-references, and per-page
   anchors. A reader lands on exactly the page they need.
4. **Page-styled / high-end.** Rendered as styled HTML book pages (Claude-design polish), consistent
   brand, figures/screenshots, callout cards (tips, pitfalls, QC gates), not a wall of markdown.
5. **Per-persona doorways.** Wet-lab PI (no compute), bioinformatician, drug-discovery/regulatory,
   core-facility admin — each finds their entry path in the overview.
6. **Honest coverage.** A capability appears only if verified on dev. Coverage gaps / smoke-test-gated
   items are listed in an appendix as "roadmap," never sold as present.

---

## 2. The book structure (index / table of contents)

Mirrors design v2. Each **General module** chapter maps to a design v2 spec section (kept in sync so
the manual and the product describe the same object model).

### Part 0 — Overview & orientation
- 0.1 What BioMate is — the conversational execution engine; the two lanes (**Instant** = seconds,
  in-conversation; **Cloud** = validated pipeline, minutes–hours). *(design v2 §00)*
- 0.2 The object model in one page — everything is a live, referenceable object (dataset, run, output,
  report, model, plan) that opens the same everywhere.
- 0.3 Who it's for — persona doorways (PI / bioinformatician / drug-discovery+regulatory / core admin).
- 0.4 A 5-minute first analysis (one worked path, end to end).

### Part I — General function modules (the cross-domain platform)
One chapter each; the spine of the book.
- I.1 Getting started & the cold start — entry, projects, the router/lanes. *(§00)*
- I.2 Talking to BioMate — the composer: attaching data, @-refs, skills & experts, lane override. *(§06)*
- I.3 Search & evidence — literature answers, retrieval transparency ("how this was searched"),
  citations, conflicts, boundary, save-to-project. *(§01, §09)*  ← **newly shipped CitationPanel**
- I.4 Projects, instructions & collaboration — standing instructions vs notes, plans/hypotheses,
  team roles & rights. *(§00 ProjectSetup)*  ← **newly shipped Notes/Instructions + plans**
- I.5 Files & the dataset object — upload/ingest, quality profiling, versions, lineage, one-object-
  everywhere. *(§04)*
- I.6 Running an analysis — the workflow panel: pre-run restate, inputs-mapped, params, QC gates,
  auto-loop remediation, confirm & run, live SSE. *(§07)*
- I.7 The full step view & provenance — step-as-object: params it actually ran with, rendered⇄raw. *(§08)*
- I.8 Outputs, viewers & interactive panels — in-app viewers by evidence type (image/table/structure/
  density/sequence/VCF/single-cell), and when to use RStudio/Jupyter/CellxGene. *(§14)*  ← **newly
  shipped single-cell panel + interactive-tool honesty gate**
- I.9 Reports as editable files & reproducibility — the after-run report, versioning, the
  reproducibility record (checksums, software, citations), download/export. *(§12)*  ← **newly shipped**
- I.10 Models — model objects, reuse-by-reference, model use cases. *(§03, §10)*
- I.11 Design & generate — generating new sequences/molecules/etc. across modalities. *(§05, §11)*
- I.12 Connectors & skills — workspace connections, per-project skills/experts.
- I.13 Billing, quotas & the two-lane cost model — what's free/instant vs billed/cloud.

### Part II — Databases & retrieval supports (the knowledge backbone)
- II.1 The workflow catalog — how routing picks a workflow; searching the catalog.
- II.2 Public datasets & accession resolver — GEO/SRA/PDB/EMPIAR/PRIDE/… fetch by accession.
- II.3 Literature & evidence retrieval — sources queried, filtering, recency, the benchmark DB.
- II.4 Reference data & indexes — genomes/annotations, structure indexes (AlphaFold DB/Foldseek),
  chemical/target databases (DepMap/GTEx/ChEMBL/FAERS where present).
- II.5 Memory & project knowledge — what persists, what the agent reads.

### Part III — Function areas by domain (the use-case chapters)
One chapter per priority domain (ranked in §3). Every domain chapter uses the **same page template**
(§4) so the book is consistent.

### Appendices
- A. Glossary (plain-language). B. File formats accepted (by domain). C. QC-gate reference (thresholds
  + citations by sample type). D. Troubleshooting & common routing pitfalls. E. **Coverage & roadmap**
  (honest list of what's *not* yet supported / smoke-test-gated). F. Keyboard/CLI/API quick reference.

---

## 3. Domain list — ranked (what gets a chapter, in what order)

From the priority synthesis (`docs/20260715_WORKFLOW_USECASE_PRIORITIZATION.xlsx`, flagship/tutorial/
strategy docs). Build order maximizes (priority × existing-reuse).

**Flagship (hero chapter):**
- **Drug discovery → IND** — ADMET (hERG/DILI/Ames/CYP/Ro5) → **auto-loop remediation** → PBPK →
  IND §2.6 assembly. The "moat" demo. Richest existing drafts (IND Report, Research Agent UI R04–R13).

**P1 (first wave):**
1. **Transcriptomics (bulk RNA-seq)** — freemium front door. DE (count-matrix) + FASTQ→DE→GSEA.
2. **Cryo-EM** — core-facility flywheel; most-polished existing tutorial (`cyro_tutorial/`).
3. **Single-cell** — #1 conference demand; new in-app panel just shipped.
4. **Variant calling / genomics** — germline (sarek/GATK/DeepVariant); somatic (mark gaps).
5. **Structural biology** — AlphaFold3/Boltz-2, docking (Vina/DiffDock), MD, Foldseek. *(largest NEW
   writing effort — no existing draft; several parts smoke-test-gated → verify hard.)*
6. **Pharmacology / clinical** — PBPK, PopPK, BOIN dose-finding, PGx. (FAERS = gap.)
7. **Multi-omics / systems biology** — GWAS→scRNA→eQTL target-ID; MOFA2 vs SNF. *(verify chain runs.)*

**P2 (second wave):** Epigenomics (ChIP-seq/ATAC-seq), Proteomics (DIA), Metabolomics (LC-MS),
Metagenomics (profiling + MAG). All have gold-standard demos wired.

**Cross-domain chapter:** CRO / regulatory reporting (IND §2.6, 21 CFR 11 audit trail).

**Long-tail / roadmap (NOT chapters — appendix E only):** imaging, population genetics, immune
repertoire, synthetic biology, ag-genomics, glycoengineering, aspirational clinical Dx — no built
tutorials; documenting them would over-promise.

---

## 4. The per-domain chapter template (every domain page looks the same)

1. **What this is for** — one paragraph, plain language; who uses it.
2. **Use cases** — 2–5 researcher goals. Each: *goal → the workflow(s) → inputs → outputs (the
   artifact) → typical runtime lane*. (Tables from the synthesis; e.g. RNA-seq: nf-core/rnaseq →
   differentialabundance → clusterProfiler.)
3. **How to ask** — example prompts that route correctly (+ the disambiguation to avoid, e.g.
   germline vs somatic; bulk vs single-cell).
4. **Tools & workflows** — the real indexed workflows/tools behind the chapter (DB-backed).
5. **QC gates & how to read them** — thresholds *with citations*, what a fail means, what auto-loop does.
6. **A worked example** — one end-to-end run on a gold-standard dataset, with the real output artifact
   and its interpretation (reuse `evaluation/tutorial_demos/gold_standards.yaml`).
7. **Outputs & visualization** — which in-app viewer renders each output; when to go interactive.
8. **Pitfalls & tips** — the callout cards (the tip-card grammar from `docs/20260615_TIER0_..._REQUIREMENT.md`).
9. **What's not covered** — honest scope note linking appendix E.

---

## 5. Page style & Claude-design polish

- **Format:** styled HTML book pages (left-nav index + content pane), matching the doc-page style in
  `data_centroid_design_v2/spec/doc-page.js` + `spec.css`, and the polished tutorial pages in
  `tutorials-work/` (IND Report `ind/styles-ind.css`, Research Agent UI). Consistent brand (logo,
  palette, typography) → "high-end company."
- **Components:** TOC/left-nav, callout cards (tip / pitfall / QC-gate / license), figure blocks with
  captions, real screenshots, prompt→result mini-panels, evidence/citation blocks.
- **Two-phase process:**
  - **Phase A — content draft (verified):** we write each chapter to the template §4, *verifying each
    claim on dev as we go* (see §6). Output = structured markdown + a JSON page-model.
  - **Phase B — Claude-design polish:** hand the verified content to Claude design to lay it out as
    branded book pages (reusing the design system + exemplars). Design never invents capability — it
    styles the verified content.

---

## 6. The audit-and-fix loop (honor the content) — non-negotiable

For **every** module chapter (Part I/II) and **every** use case (Part III), before it is written as
"supported":
1. **Exercise it on dev** (`https://dev-public.biomate.ai`, fixture `lifeifei163361@163.com`) — the real
   flow the manual will describe (send the prompt, run the workflow / open the panel / view the output).
2. **Compare to the drafted claim.** Screenshot/log the actual behavior.
3. **On mismatch → fix the system** (root cause, per CLAUDE.md), not the manual. Re-verify. If it can't
   be fixed now, the manual says "not yet supported" and it goes to appendix E — never a false claim.
4. **Record** each check in a coverage ledger (`docs/user-manual/coverage-ledger.md`): module/use case →
   verified? → evidence → any bug filed/fixed. The book ships only content that is green in the ledger.

This turns the manual effort into a full-system QA pass — the structured way to find and fix the
details, exactly as intended.

---

## 7. Reuse map (don't start from scratch)

- **Skeleton prose:** `docs/20260422_BIOMATE_USER_TUTORIALS.md` (6 use cases + 7 feature guides + tips).
- **Polished pages to emulate/extend:** `tutorials-work/` cryo_tutorial, IND Report, Research Agent UI.
- **Verified use cases + datasets:** `evaluation/tutorial_demos/gold_standards.yaml` (7 domains) +
  `Tutorial Demo Scenarios 7-domain.md` (real chains, QC gates).
- **Module truth source:** design v2 spec 00–14 (+ our just-shipped features: CitationPanel retrieval,
  Notes/Instructions split, plans, single-cell panel, interactive-tool gate, versioned reports).
- **Design requirement specs:** TIER0 (shared template), SC, multi-omics, MG-stratification.

---

## 8. Deliverables & sequencing

- **D0 (now):** this plan + the coverage-ledger scaffold + the book skeleton (index + empty chapter
  stubs) + the chapter template.
- **D1 — Flagship chapter (Drug discovery → IND), verified.** Draft to template §4 + run the audit loop
  on dev (ADMET auto-loop, PBPK, IND §2.6). This proves the whole pipeline (content → verify → polish).
- **D2 — Claude-design polish of the flagship** → the reference "look" for the whole book.
- **D3 — P1 wave** (transcriptomics, cryo-EM, single-cell, variant calling), each content→verify→polish.
- **D4 — General modules (Part I)** written+verified (many already exercised by the flagship/P1 runs).
- **D5 — Databases & retrieval (Part II)**, then **P2 domains**, then structural/multi-omics (most new
  writing + hardest verification), then appendices.

Each D-step lands as verified content in the ledger before it's styled — so the book only ever contains
things that are true.

---

## 9. Open choices for you
- **Design system for the book:** `data_centroid_design_v2` doc-page style (consistent with the app) vs
  `webpage_design_v2` (more marketing-polished) — recommend the doc-page style for a manual.
- **Output home:** a `/manual` route in-app vs a standalone static book site. Recommend in-app `/manual`
  (same brand, deep-linkable from features).
- **Start point:** recommend **D1 = the flagship Drug-discovery→IND chapter** (richest reuse, proves the
  content→verify→polish loop end to end).
