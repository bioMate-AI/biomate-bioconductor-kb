# Hospital Core Facility — Instrument → BioMate Resource Inventory

**Date:** 2026-09-20
**Client source:** `Hospital Core Facility — Instrument Inventory, Data Outputs, and BioMate Coverage.docx` (Sep 17, 2026 notice — new 公共科研服务平台, 科教楼 Building 9 floors 5–6, opening late Oct 2026).
**Method basis:** the live-tested audits `20260918_HOSPITAL_CORE_FACILITY_COVERAGE_TEST.md` (per-output routing probe) and `20260918_FACILITY_WORKFLOW_AUDIT_AND_UPGRADES.md` (4 cluster auditors, ~130 search + ~70 spec probes on dev). Workflow paths below verified present in `backend/biomni_workflows/…`.
**Purpose:** the deliverable requested — a resource inventory mapping every instrument to the BioMate workflow/tool aligned to it, with an honest status (validated / registered-unverified / gap) and the upgrade/build item that closes each gap.

**Status legend**
- ✅ **Validated** — well-trodden path, run end-to-end.
- 🟡 **Registered** — a real workflow routes with a real param spec, but end-to-end runnability on this data type is unverified.
- 🔧 **Upgrade** — a workflow exists but is not best-in-class → see U# in `20260918_FACILITY_UPGRADE_BUILD_PLAN.md`.
- 🛑 **Gap / build** — no real workflow → see B#.

---

## 1. Data-generating instruments (produce analyzable files)

These six categories are the ones the notice itself flags as producing "substantial data files for computational analysis."

| Instrument (中文) | Output format | Aligned BioMate resource | Path / domain | Status |
|---|---|---|---|---|
| **Sequencer — NGS RNA** (测序仪) | BCL→FASTQ | *Bulk RNA-seq Differential Expression* (nf-core/rnaseq → DESeq2 chain) | transcriptomics | ✅ Validated |
| **Sequencer — NGS DNA/WGS** | BCL→FASTQ | *WGS Germline GATK* | `nextflow_nfcore/subworkflows/genomics/wgs_germline_gatk/main.nf` | ✅ Validated · 🔧 **U1** (flip default to DeepVariant; Clair3 for ONT — *not yet landed*) |
| **Sequencer — somatic/tumor** | FASTQ (T/N) | nf-core/sarek (Mutect2; ASCAT/PURPLE for purity) | genomics | 🟡 Registered · 🔧 **U13** ASCAT/PURPLE routing · WS1 **A6** (no somatic chain/gold yet) |
| **Sequencer — Sanger** | `.ab1` chromatogram | — none — | — | 🛑 **B5** (Tracy: trim→consensus/contig) |
| **Sequencer — Nanopore** | POD5/FAST5 | nf-core/nanoseq (indirect) | genomics | 🔧 **U5** (Guppy→dorado, EOL) · 🛑 **B6** (standalone POD5→dorado) |
| **Mass spec — proteomics DIA** (质谱仪) | `.raw/.wiff/.d`→mzML | nf-core/diaproteomics (DIA-NN) | proteomics | ✅ Validated · 🔧 **U2** (pin DIA-NN 2.x; timsTOF `.d`) |
| **Mass spec — proteomics DDA-LFQ** | →mzML | nf-core/proteomicslfq (MSGF+/Comet) | proteomics | 🟡 Registered · 🔧 **U8** (add FragPipe/MSFragger) |
| **Mass spec — TMT** | →mzML | isobar/msstatstmt/qPLEXanalyzer (thin) | proteomics | 🔧 **U9** (adopt nf-core/quantms umbrella) |
| **Mass spec — PTM/phospho** | →mzML | isobar/ptm_localization (PhosphoRS) | proteomics | 🔧 **U12** (PTMShepherd/FragPipe) |
| **Mass spec — metabolomics** | →mzML | *LC-MS Metabolomics → Multi-Method* (metaboigniter) | metabolomics | ✅ Validated (QC gate added, commit 08113a3) · 🔧 **U7** (SIRIUS 6 + MetaboAnalyst 6) |
| **Mass spec — immunopeptidomics** | →mzML | mhcquant + epitopeprediction + hlatyping + antigen_resolution | proteomics | ✅ **Best-in-class & complete** (gated on Orbitrap/timsTOF-class instrument — facility unknown) |
| **Flow cytometer** (流式细胞仪) | `.fcs` | *Analyze Flow Cytometry Immunophenotyping* (flowCore/FlowSOM) | `nextflow/subworkflows/cell_biology/analyze_flow_cytometry_immunophenotyping.nf` | 🟡 Registered (validation unverified) · 🔧 **U6** (flowClean→PeacoQC/flowAI), **U10** (CATALYST DA) |
| **qPCR instrument** (荧光定量PCR仪) | `.eds/.pcrd`→CSV; Ct | *normqpcr ΔΔCq normalization* | `nextflow_nfcore/subworkflows/bioconductor/normqpcr/delta_delta_cq_normalization.nf` | 🟡 Registered (best-in-class stack: NormqPCR/ddCt/qpcrNorm) |
| **Multimode plate reader** (多功能酶标仪) | CSV/Excel (Abs/FL/Lum) | *HTS Plate QC + Hit Calling* (Z′/4PL) | `nextflow_nfcore/subworkflows/drug_discovery/hts_plate_qc_hit_calling/main.nf` | 🟡 Registered · 🔧 **U11 / B9** (real drc 4PL dose-response *landed* df7b1664c; ELISA/CCK-8/luciferase modules still thin) |
| **Digital slide scanner** (数字化切片扫描仪) | WSI: `.svs/.ndpi/.mrxs/.kfb/.sdpc` | nf-core/mcmicro (multiplex; requires OME-TIFF) | imaging (DB-registered) | 🟡 Registered *but* 🛑 **B1** (no reader for `.kfb/.sdpc/.svs`) + 🛑 **B2/B4** (no pathology FM / QuPath) |
| **Confocal microscope** (共聚焦显微镜) | `.czi/.lif/.nd2/.oir` z-stacks | *Segment Cells With Deep Learning* | `nextflow/subworkflows/microbiology/segment_cells_with_deep_learning.nf` | 🟡 Registered *but* 🛑 **B1** (no `.czi/.lif/.nd2/.oir` reader) · 🔧 **U12seg** (Cellpose3/StarDist/Mesmer) |
| **Fluorescence microscope** (荧光显微镜) | 2D TIFF/JPG | segment-cells / imaging segmentation | microbiology/imaging | 🟡 Registered (TIFF opens; vendor formats need B1) |

---

## 2. Sample-QC & assay instruments (tabular/image output, mostly small parsers)

| Instrument (中文) | Output | Aligned BioMate resource | Status |
|---|---|---|---|
| **Bioanalyzer / RIN** (生物分析仪) | electropherogram, RIN (PDF/CSV) | — none — | 🛑 **B8** (bioanalyzeR RIN parser) |
| **Microvolume spectrophotometer / NanoDrop** (微量分光光度计) | A260/280, A260/230 | — none — | 🛑 **B8** (NanoDrop purity parser) |
| **Automated cell counter** (自动细胞计数仪) | count, viability % | — none — | 🛑 **B8** (cell-count/viability parser) |
| **Gel & blot imager** (多功能凝胶蛋白成像仪) | band TIFF + densitometry | Western densitometry (real); gel = in-silico sim only | 🔧/🛑 **B9** (real Fiji/ImageJ lane-profile densitometry) |
| **Protein electrophoresis + transfer** (蛋白电泳系统/全能转印仪) | gel → membrane (physical) | feeds gel/blot imager above | n/a (physical product) |
| **Gradient PCR** (梯度PCR仪) | amplified DNA (physical) | — | n/a (no data file) |

---

## 3. Support / sample-prep instruments (no analyzable data)

No BioMate resource applies — these feed the instruments above: vacuum nucleic-acid extractor (负压核酸提取仪), high-speed refrigerated centrifuge (高速冷冻离心机), tri-gas & CO₂ incubators (三气/水套式培养箱), monodisperse microsphere generator (单分散微球制造仪), ultra-low freezer (超低温冰箱), ultrapure water system (超纯水仪), ice maker (制冰机).

**Pathology sample-prep chain** (石蜡包埋机 / 石蜡切片机 / 冰冻切片机 / 生物显微镜): produces FFPE blocks and stained slides — physical products. Only the **digital slide scanner** downstream produces analyzable data (row 1, blocked on B1/B2). Notice has **no tissue processor / autostainer** → IHC & multiplex-IF throughput may be limited.

---

## 4. The genuine gaps — where the work is (not "no workflow exists")

Live testing showed a real workflow routes for **every** data-producing instrument. The true gaps cluster at two edges:

1. **Ingestion edge — vendor format readers (highest leverage).**
   - 🛑 **B1** imaging: `.kfb/.sdpc` (Chinese scanners), `.czi/.lif/.nd2/.oir` (confocal), even OpenSlide `.svs/.ndpi` → OME-TIFF. Unblocks **all** facility imaging.
   - 🛑 **B4** MS: `.raw/.wiff/.d` → mzML (msConvert/ThermoRawFileParser). Unblocks every MS pipeline on this facility's raw files.
2. **Frontier — pathology foundation models.**
   - 🛑 **B2** UNI/CONCH/Virchow2/Prov-GigaPath (tile+slide encoders). Upstream of the antigen programme: tumor-content QC (Gate A), IHC/antigen validation, organoid histology. BioMate's FM surface is entirely transcriptomic today.

**Facility unknowns that gate value (not BioMate gaps):** mass-spec class (Orbitrap/timsTOF vs triple-quad — decides immunopeptidomics), sequencer model (Illumina/MGI/Sanger/Nanopore — decides which pipelines apply), slide-scanner vendor (decides B1 converter effort), and access terms for external collaborators. **No single-cell/spatial platform** (10x/Visium) on the list.

---

## 5. Recommended sequencing (facility deliverables)

1. **Ship the cheap upgrades** the facility touches: **U1** DeepVariant default (not yet landed), **U2** DIA-NN 2.x pin, **U6** flowClean→PeacoQC, **U7** SIRIUS 6 — plus **B8** QC parsers (RIN/NanoDrop/cell-count) which are trivial and genuinely missing.
2. **Highest-leverage builds first:** **B4** MS raw→mzML, then **B1** imaging converters — they gate whole instrument axes.
3. **Strategic build (own track):** **B2** pathology FMs + **B4/QuPath** for the antigen programme's tissue-QC / antigen-validation upstream.
4. **Send the facility the four open questions** (MS model, sequencer model, scanner vendor, access/data-egress terms) — they determine effort more than any code change.
