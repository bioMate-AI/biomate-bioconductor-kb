# BioMate User Tutorials — index

Layman-friendly, task-first tutorials for BioMate. Every tutorial is **grounded in the shipped
code** (not the design prototype) and is **honest about what is not yet built** — each has an
"Honest limits" section. Figures are marked with `<!-- CAPTURE ... -->` comments + *(Figure to add)*
lines for a later screenshot pass against live dev.

Authoring standard: `docs/20261001_TUTORIAL_USER_PANEL_REVIEW.md` (10-point checklist).
Full coverage map (design spec 00–14 → tutorial → built/backlog): `docs/20261002_TUTORIAL_COVERAGE_MATRIX.md`.

---

## Start here — the core journey

| # | Tutorial | What it covers |
|---|----------|----------------|
| T0 | [Getting started](T0-getting-started.md) | First question, the composer, how BioMate answers |
| T1 | [Design & generate](T1-design-and-generate.md) | The Design & Generate module (small-molecule) + closed loop |
| T2 | [Models & the closed loop](T2-models-and-the-closed-loop.md) | Using models; the predict→run→learn loop |
| T3 | [Running a workflow & reading the report](T3-running-a-workflow-and-reading-the-report.md) | The end-to-end run + three-tab report |
| T4 | [Bringing your own data](T4-bringing-your-own-data.md) | Uploading a file; data quality gates |
| T5 | [Viewing your results](T5-viewing-your-results.md) | Output viewers (image/table/FASTA/VCF/3-D) |
| T6 | [Connecting instruments](T6-connecting-instruments.md) | Registering a lab/hospital instrument (the registry) |
| T7 | [Projects & collaboration](T7-projects-and-collaboration.md) | Projects, standing instructions, sharing, roles |
| T8 | [Reports — edit & export](T8-reports-edit-and-export.md) | Editing a report, saving versions, exporting |
| T9 | [Connecting data & tools](T9-connecting-data-and-tools.md) | Databases, MCP servers (the Connectors dialog) |
| T10 | [Exploring your datasets](T10-exploring-your-datasets.md) | A dataset's metadata, preview, lineage, versioning, scope |

## The cold-start function modules

| Module | Tutorial |
|--------|----------|
| Search & evidence | [M1](M1-search-and-evidence.md) |
| Data analysis | [M2](M2-data-analysis.md) |
| Design & generate | see **T1** |
| Models | see **T2** |

## Navigation & the workflow panel

| Surface | Tutorial |
|---------|----------|
| Every sidebar function | [S1 — Sidebar navigation](S1-sidebar-navigation.md) |
| Workflow panel (before/during a run) | [W1 — Workflow panel tabs](W1-workflow-panel-tabs.md) |
| After-run panel (Summary · Outputs · Reproducibility) | [W2 — After-run panel](W2-after-run-panel.md) |
| Full step view & provenance | [W3 — Full step view](W3-full-step-view.md) |

## Per-instrument — the analysis each instrument's data drives

These teach the **science/workflow** an instrument feeds (not the connector plumbing — that's T6).

| Instrument | Analysis it drives | Tutorial | Evidence |
|-----------|--------------------|----------|----------|
| Illumina BaseSpace | WGS germline (GATK) / RNA-seq | [basespace-sequencing](instruments/basespace-sequencing.md) | **Validated on real data** |
| Thermo EPU / cryo-EM | Single-particle reconstruction (`cryosparc_standard_spa`) | [cryoem-reconstruction](instruments/cryoem-reconstruction.md) | **Validated on real data** |
| qPCR | ΔΔCt relative quantification (NormqPCR) | [qpcr-quantification](instruments/qpcr-quantification.md) | Available, untested E2E |
| Flow cytometer | Immunophenotyping / gating | [flow-cytometry-gating](instruments/flow-cytometry-gating.md) | Available, untested E2E |
| LC-MS | Proteomics (DDA/DIA) / metabolomics | [lcms-proteomics-metabolomics](instruments/lcms-proteomics-metabolomics.md) | Available, untested E2E |
| Plate reader | Dose–response / HTS hit-calling | [plate-reader-assays](instruments/plate-reader-assays.md) | Available, untested E2E |
| Nanopore MinKNOW | Long-read basecalling (nf-core/nanoseq) | [nanopore-minknow](instruments/nanopore-minknow.md) | Available, untested E2E |
| Benchling ELN/LIMS | ADMET prediction / CRO campaign | [benchling-eln-lims](instruments/benchling-eln-lims.md) | Available; `mock_mode` w/o API key |
| Opentrons OT-2/Flex | Protocol execution (no analysis by design) | [opentrons-liquid-handling](instruments/opentrons-liquid-handling.md) | Prep only — no analysis mapping |
| SiLA2 device | Device-dependent | [sila2-devices](instruments/sila2-devices.md) | Conditional — no fixed workflow |

> **Routing caveat (verified 2026-10-02):** connector `workflow_id` strings are *symbolic routing
> labels*, not catalog IDs — most do not resolve verbatim, and `get_workflow_spec` is a fuzzy
> resolver that always returns a nearest match. Each instrument tutorial teaches the *real* catalog
> workflow its data maps to. See `docs/20261002_TUTORIAL_COVERAGE_MATRIX.md`.

---

## Consolidated honest map — what is NOT yet built (do not teach as working)

Surfaced by grounding every tutorial against shipped code. These are documented in each tutorial's
Honest-limits section rather than claimed as features:

| Surface | Not built / not wired today |
|---------|------------------------------|
| **Dataset object (T10)** | Version **compare & restore** (a "version" is an annotation, not a byte-copy); access **scope is enforced but not displayed** (no promote-to-shared switch); full typed viewers live on the run Outputs surface, not the object |
| **Reports (T8)** | **Ask-to-edit propose-diff** not built (hand-edit + Save-version only); only **4 real export formats** (Markdown, JSON, ZIP, plain-text) — DOCX only in the disabled IND flow; PDF/HTML not built; report lives in its run/session, not the Files tree |
| **Connectors (T9)** | No **skill/expert add-flow** (Skills tab deliberately removed); public-DB checkboxes + scope selector are display-only and **enforce nothing**; directory index-in-place is design-only |
| **Projects (T7)** | Product ships **3 roles (Viewer/Editor/Owner)**, not the design's 4 (no Reviewer); run-panel permissions card is a static placeholder; expert toggles are per-chat, not a per-project switch |
| **Workflow panel (W1)** | Auto-loop QC **remediation panel disabled** (`autoloopLocked`); Skip phase/step, cost-estimate badge, live % bar, "View phase outputs" all commented out |
| **Full step view (W3)** | **"Re-run from here", number→source jump, in-place param edit** scaffolded but not mounted; rendered⇄raw views + read-only resolved-params *do* work |
| **Disabled product-wide** | Billing, IND Report, CRO Library, Runs dashboard, biologics/peptide generators (design marks NOT-BUILT) |

## Stale developer docs to refresh (flagged during grounding)

- `CLAUDE.md` "Sidebar" checklist — lists Runs/dashboard, CRO Library, Starred Workflows, Billing that are no longer in the shipped sidebar
- `docs/user-manual/modules/I04` — said owner-transfer UI missing; it now exists
- `docs/user-manual/modules/I09` — agrees ask-to-edit not built (OK) but verify format list
- `docs/user-manual/modules/I12` — says Connectors dialog has 2 tabs; shipped code has 4

## Still pending

- **Screenshot capture pass** against live dev for every `<!-- CAPTURE -->` marker
- **Chinese (zh/)** translations for T6–T10, M1–M2, S1, W1–W3, and the 10 instrument tutorials (EN ships first, per the review cadence)
