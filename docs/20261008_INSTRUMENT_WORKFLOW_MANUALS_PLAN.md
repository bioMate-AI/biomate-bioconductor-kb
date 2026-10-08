# Instrument → Workflow User-Manual Completion Plan

**Date:** 2026-10-08
**Workstream owner doc (living — update each step).**
**Trigger:** user finding — *"the user manuals of instructions are not complete — we have a list of instruments from hospital, we also have mapped abilities in BioMate; the manuals are not complete."* Then clarified: *"I am not asking you to connect to the instrument. I am asking you to write user manuals for the workflows or other functions needed for each instrument"* and *"your connector does not work, it is just make up — you don't know the real instruments and drive. We will adapt them later."*

## Ground truth (what is real vs not)

- **REAL — the instrument list + instrument→workflow mapping:** `docs/20260920_HOSPITAL_INSTRUMENT_RESOURCE_INVENTORY.md`, sourced from the client's actual *"Hospital Core Facility — Instrument Inventory, Data Outputs, and BioMate Coverage.docx"* (Sep 17 2026; new 公共科研服务平台, 科教楼 Building 9, opening late Oct 2026). Each instrument is mapped to a **path-verified** BioMate workflow with an honest status, from live-tested audits (`20260918_HOSPITAL_CORE_FACILITY_COVERAGE_TEST.md`, `20260918_FACILITY_WORKFLOW_AUDIT_AND_UPGRADES.md`).
- **REAL — the workflows themselves:** the BioMate catalog (validated subset) + the `.nf` files under `backend/biomni_workflows/`. Manuals must ground every claim in the actual `.nf` (params, steps, outputs) or, for nf-core pipelines not stubbed locally (mcmicro, mhcquant), in the nf-core pipeline docs.
- **NOT REAL — the connectors / drivers / auto-routing:** `backend/lib/integrations/*_connector.py`, the `service/main.py` routing_map, instrument auto-detect. Made-up / to be adapted later. **Manuals must NOT document, depend on, or imply any connector/driver/auto-ingest.** Connection is out of scope; where a manual needs to say how data arrives, it defers to T6 generically ("once your files are in BioMate") — exactly as the existing instrument tutorials already do.

## Manual shape (template = the existing instrument tutorials)

The existing `docs/user-manual/tutorials/instruments/*.md` (e.g. `lcms-proteomics-metabolomics.md`) are already the correct shape — **workflow-focused**, connection deferred to T6:
1. **Who this is for / time / where it fits** (one blockquote; "T6 explains connecting; THIS explains the analysis").
2. **§1 What this instrument produces** — real data + real vendor file formats.
3. **§2 The BioMate analysis it drives (and why)** — the real workflow(s), by name + `.nf` path, the sub-analyses, when to pick which.
4. **§3 How to run it in BioMate** — upload data → ask in chat / pick the workflow card → confirm & run → read outputs. No connector.
5. **§4 Reading the outputs** — the real output files + interpretation.
6. **§5 BioMate also offers** — breadth: related real workflows/tools/databases the facility could also use (we are selling BioMate — knowledge + tool use).
7. **Honest status note** — ✅ validated / 🟡 registered-unverified / 🛑 gap, mirroring the inventory; if ingestion is blocked (B-items) say so plainly.
- **Bilingual:** EN in `tutorials/instruments/`, natural (non-calque) Chinese mirror in `tutorials/zh/instruments/*.zh.md`.

## Coverage gap (hospital data-generating instruments → manual)

| Instrument | Real BioMate workflow | Status | Existing manual? |
|---|---|---|---|
| Sequencer NGS RNA | Bulk RNA-seq DE (rnaseq→DESeq2) | ✅ | ✅ basespace-sequencing.md |
| Sequencer NGS DNA/WGS | WGS Germline GATK | ✅ (U1 caveat) | ✅ basespace-sequencing.md |
| **Sequencer somatic/tumor** | nf-core/sarek (Mutect2) | 🟡 | ❌ **MISSING** |
| **Sequencer Sanger (.ab1)** | — none (B5) | 🛑 | ❌ gap — document as not-yet-supported |
| Sequencer Nanopore | nf-core/nanoseq | 🔧 | ✅ nanopore-minknow.md |
| Mass spec — DIA / DDA / metabolomics | diaproteomics / proteomicslfq / metaboigniter | ✅/🟡 | ✅ lcms-proteomics-metabolomics.md |
| **Mass spec — TMT** | isobar/msstatstmt | 🔧 | ❌ **MISSING** |
| **Mass spec — PTM/phospho** | isobar/ptm_localization | 🔧 | ❌ **MISSING** |
| **Mass spec — immunopeptidomics** | mhcquant+epitopeprediction+hlatyping (nf-core) | ✅ | ❌ **MISSING** |
| Flow cytometer (.fcs) | flow immunophenotyping (flowCore/FlowSOM) | 🟡 | ✅ flow-cytometry-gating.md |
| qPCR (.eds/.pcrd) | normqpcr ΔΔCq | 🟡 | ✅ qpcr-quantification.md |
| Plate reader | HTS Plate QC + Hit Calling (Z′/4PL) | 🟡 | ✅ plate-reader-assays.md |
| **Digital slide scanner (WSI)** | nf-core/mcmicro | 🟡 / 🛑B1 | ❌ **MISSING** (ingestion-blocked — say so) |
| **Confocal microscope** | segment_cells_with_deep_learning | 🟡 / 🛑B1 | ❌ **MISSING** |
| **Fluorescence microscope** | segment-cells / imaging segmentation | 🟡 | ❌ **MISSING** |
| **Bioanalyzer / RIN** | lab_automation/rin_bioanalyzer_qc | 🆕 (pending DB reg) | ❌ **MISSING** |
| **NanoDrop** | lab_automation/nanodrop_purity_qc | 🆕 | ❌ **MISSING** |
| **Cell counter** | lab_automation/cell_counter_viability_qc | 🆕 | ❌ **MISSING** |
| **Gel & blot imager** | Western densitometry | 🔧 | ❌ **MISSING** |

(Support/sample-prep instruments — centrifuge, incubators, freezers, water system, gradient PCR, electrophoresis — produce no analyzable data → no manual, per inventory §3.)

## Plan — 4 parallel drafting agents (each: EN + zh, template above, inventory-grounded, no connector fiction, verify against real `.nf`)

- **A. Advanced proteomics mass-spec** — TMT (msstatstmt), PTM/phospho (ptm_localization), immunopeptidomics (mhcquant nf-core). Complements lcms (link, don't duplicate DIA/DDA/metabolomics).
- **B. Imaging & microscopy** — digital slide scanner→WSI (mcmicro, note .svs/.kfb B1 ingestion gap honestly), confocal + fluorescence microscopy → cell segmentation (segment_cells_with_deep_learning, note .czi/.lif B1 gap).
- **C. Sample-QC instruments** — Bioanalyzer/RIN, NanoDrop, cell counter, gel/blot imager (lab_automation QC parsers; note B8 pending dev DB registration so routing is not yet live).
- **D. Somatic/tumor sequencing** — nf-core/sarek somatic manual + a short honest "Sanger .ab1 not yet supported (roadmap)" note.

## Status log
- 2026-10-08: ground truth located (inventory doc), gap table built, template fixed, 4 agents to launch.
- 2026-10-08: **all 4 manuals written (EN + natural-Chinese mirror), honesty-audited clean** (zero connector-fiction leaks; every workflow claim grounded in a real `.nf` or labeled nf-core; each has a §Honest-limits section):
  - `instruments/somatic-tumor-sequencing.md` (+zh) — nf-core/sarek Mutect2; flags somatic unvalidated, ASCAT/PURPLE=U13 upgrade, Sanger `.ab1`=B5 gap.
  - `instruments/microscopy-pathology-imaging.md` (+zh) — slide scanner (nf-core/mcmicro) + confocal/fluorescence (segment_cells_with_deep_learning); states runnable-today (2D TIFF/OME-TIFF) vs B1 vendor-format roadmap; `wsi_he_nuclei_segmentation` `.svs` path flagged roadmap (not DB-registered/validated).
  - `instruments/sample-qc-instruments.md` (+zh) — RIN/NanoDrop/cell-counter (lab_automation QC, pending dev DB registration) + Western densitometry (manual ROIs; gel = in-silico sim only, B9).
  - `instruments/advanced-proteomics-mass-spec.md` (+zh) — TMT (msstatstmt 🔧) + PTM/phospho (isobar 🔧) + immunopeptidomics (nf-core/mhcquant, instrument-gated); complements lcms, doesn't duplicate.
- **Covers all 9 previously-missing data-generating hospital instruments.** Remaining (optional): refresh the 6 existing manuals if any connector references linger; add these 4 to the user-manual index/TOC.
- **Open product gaps surfaced by the manuals** (for the real-instrument adaptation later): B1 vendor-format readers (.svs/.kfb/.czi/.lif), B3 .raw→mzML, B8 QC-parser DB registration, somatic gold-chain validation, mhcquant not stubbed locally.
