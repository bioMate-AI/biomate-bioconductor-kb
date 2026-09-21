# Facility-driven workflow upgrade & build plan (detailed)

**Date:** 2026-09-18
**Basis:** the live audit in `20260918_FACILITY_WORKFLOW_AUDIT_AND_UPGRADES.md` (4 cluster auditors, ~130 search + ~70 spec probes). This doc turns that audit's U-list (upgrade existing workflows to better tools) and B-list (build missing capabilities) into concrete, sequenced work items with file, change, effort, risk, and verification.

**Definitions.**
- **Upgrade (U)** = a *working* BioMate workflow exists but isn't 2026 best-in-class → swap in the better tool / flip a default / pin a version. In-place, low-risk, fast.
- **Build (B)** = *no real workflow* exists for a capability the facility needs → new workflow/module. Larger.

**Verification method (all items).** (1) `POST /api/workflows/search` still routes the intent to the right workflow; (2) `GET /api/workflows/spec` shows the new tool/param; (3) where feasible, one real run on public data (converts "registered" → "validated"). Same read-only recipe used in the audit.

---

## Wave 1 — Upgrade wins (in-place, low-risk, ship first)

Effort: S = <½ day, M = ~1 day. Risk: workflow-def edit only unless noted.

| # | Workflow (path) | Current | Change | Effort | Risk | Verify |
|---|---|---|---|---|---|---|
| **U1** | WGS germline `.../genomics/wgs_germline_gatk/main.nf` | GATK HaplotypeCaller default | flip default `caller=deepvariant` (Clair3 for ONT); keep GATK as option | S | low (param default) | spec shows deepvariant default; a small germline run calls DeepVariant |
| **U2** | DIA proteomics `nfcore/dia_proteomics_analysis/main.nf` | DIA-NN, version unpinned | pin **DIA-NN 2.x** container + expose version; note MBR/FDR/timsTOF `.d` | S | low | spec shows pinned 2.x |
| **U3** | dose-response `.../biochemistry/dose_response/main.nf` | scalar curve *plotter* (x/ic50/hill) | real **`drc` `LL.4()`** fit of raw well data → IC50/EC50/Hill/GoF; add data-file input | M | med (behavior change) | spec has data input; run on public dose-response CSV |
| **U4** | ChIP-seq `.../genomics/perform_chipseq_peak_calling_with_macs2/main.nf` | bare 2-param MACS2 | route intent to full **nf-core/chipseq** (align→peaks→consensus→diffbind→QC) | S | low (routing/alias) | search "ChIP-seq" → nf-core/chipseq |
| **U5** | Nanopore `nfcore/nanoseq/main.nf` | Guppy basecaller (EOL) | ensure **dorado** basecaller (+ Clair3 variants); if module still calls Guppy, swap | M | med | spec/module references dorado |
| **U6** | Flow QC `.../bioconductor/flowclean/main.nf` | flowClean | route flow-QC intent to **PeacoQC / flowAI** (add module if absent) | M | low | search "flow QC" → PeacoQC |
| **U7** | Metabolite ID (metaboigniter downstream) | MS2Query only | add **SIRIUS 6** (CSI:FingerID) annotation + **MetaboAnalyst 6** enrichment | M | low (additive) | spec adds SIRIUS/MetaboAnalyst step |
| **U8** | DDA-LFQ `nfcore/proteomicslfq/main.nf` | MSGF+/Comet | add **FragPipe/MSFragger** search option (10–100× faster; also enables open/PTM search) | M | med | spec exposes msfragger engine |
| **U9** | TMT (isobar/msstatstmt/qPLEXanalyzer thin wrappers) | fragmented | adopt **nf-core/quantms** umbrella (DDA/DIA/TMT under OpenMS+MSstats) | M | med (new pipeline) | search "TMT proteomics" → quantms |
| **U10** | CNV/purity `.../cancer_biology/analyze_copy_number…/main.nf` | CNVkit approximation | prefer sarek's **ASCAT/PURPLE** for paired T/N purity/ploidy | S | low (routing) | search "tumor purity" → sarek ASCAT |
| **U11** | Cell segmentation `.../microbiology/segment_cells_with_deep_learning`, CRImage | generic/legacy | **Cellpose 3 / StarDist / Mesmer** modules (generalist, denoise, crowded nuclei) | M | low (additive) | search "nuclei segmentation" → Cellpose3/StarDist |
| **U12** | PTM `.../bioconductor/isobar/ptm_localization…` | PhosphoRS | **PTMShepherd / FragPipe** localization + open-search PTM | M | low | spec shows PTMShepherd |

*In flight (agent A):* **U1, U2, U3.**

> **CORRECTION (2026-09-20) — U1 and U2 are mis-scoped; only U3 shipped.**
> - **U3** ✅ landed (real `drc` 4PL fitter, commit df7b1664c).
> - **U1 is NOT a default flip.** In `wgs_germline_gatk/main.nf`, `params.caller` is *defined* (line 55)
>   but **never read** — there is no DeepVariant process anywhere in the workflow. Flipping the default
>   to `deepvariant` would silently still run GATK (a mislabel — the exact workaround CLAUDE.md forbids).
>   Worse, `nextflow_schema.json` advertises `deepvariant`, so the code↔schema is **drift** (should be
>   caught by the C2 drift test). **Correct scope:** a real BUILD — add a DeepVariant process gated on
>   `params.caller == 'deepvariant'` (container + GLnexus joint-genotyping), keep GATK the default until a
>   deliberate Batch germline run validates it. Not shipped this session (needs Batch; no speculative deploy).
> - **U2 is a DB/container change, not a file edit.** There is no local DIA-NN `.nf`; the DIA proteomics
>   workflow is registered only in the gitignored `galaxy_ai_tools.db` (lives on dev + S3). Pinning DIA-NN 2.x
>   is a dev-side container/DB update, done there — not editable from this checkout.

---

## Wave 2 — Build items (missing capability, prioritized by leverage)

Priority = how many instrument axes it unblocks. **P0 unblocks an entire instrument axis.**

| # | Gap | Build | Tooling | Effort | Priority |
|---|---|---|---|---|---|
| **B1** | **Imaging format ingestion** | converter workflow: any vendor image → OME-TIFF | **BioFormats/`bfconvert`, OpenSlide/libvips**; vendor **KFB→TIFF, SDPC→TIFF** (KFBio/SQRAY); `czi/lif/nd2/oir` readers (aicsimageio/readlif/nd2reader) | L | **P0** — unblocks ALL facility imaging (WSI + confocal); today every file must be pre-converted externally |
| **B2** | **Pathology foundation models** | tile + slide encoders | **UNI, CONCH, Virchow2, Prov-GigaPath / GigaPath** — embeddings, few-shot subtyping, tumor-content QC | L | **P0** — the antigen programme's upstream (tissue QC + IHC antigen validation); zero image FMs today |
| **B3** | **MS raw→mzML converter** | conversion workflow | ProteoWizard **msConvert** + **ThermoRawFileParser** | M | **P0** — unblocks `.wiff`/`.raw`/`.d` ingestion into every MS pipeline |
| **B4** | **QuPath digital pathology** | H&E/IHC WSI analysis | **QuPath** (annotation, IHC positivity, tumor detect) + **HistomicsTK** + Macenko/Vahadane stain norm | L | P1 (needs B1 first) |
| **B5** | **Sanger `.ab1` assembly** | trace → consensus/contig | **Tracy** (phred/mott trim → consensus) | M | P1 — hospital Sanger-confirmation staple; no workflow today |
| **B6** | **POD5 → dorado basecalling** | standalone raw-signal front end | **dorado** (+ modified-base models) | M | P1 — Nanopore raw output entry |
| **B7** | **CyTOF / mass cytometry** | norm/debarcode/DA | **CATALYST** (+ Cydar) | M | P1 — biggest cytometry hole |
| **B8** | **Instrument QC parsers** | small QC modules | RIN/Bioanalyzer (**bioanalyzeR**), NanoDrop 260/280·260/230, cell-count/viability | S each | P2 — trivial, genuinely missing |
| **B9** | **Bench-assay gaps** | modules | luciferase reporter (ratio+norm); CCK-8/MTT viability (`drc`); real gel densitometry (**Fiji/ImageJ** lane profile); generic 4PL ELISA (`drc`) | S–M | P2 |
| **B10** | **MS niche** | modules | **Skyline** PRM/SRM quant; **lipidomics ID** (MS-DIAL 5); **Casanovo** de-novo | M | P2 |

---

## Sequencing

1. **Wave 1 upgrades** ship independently and immediately (mostly workflow-def edits). Batch by domain to minimize deploys: [U1,U2,U3] (in flight), then [U4,U8,U9,U12] proteomics/genomics, then [U6,U7,U11] cytometry/imaging.
2. **B3 (msConvert)** and **B1 (imaging converters)** are the highest-leverage builds — do them before B4/B10 (they gate everything downstream on those axes).
3. **B2 (pathology FMs)** is the strategic build tied to the antigen programme; larger, own track.
4. **B8/B9** QC/assay parsers are cheap fillers between larger items.

## Open dependencies / caveats
- **Instrument-model unknowns gate value, not BioMate:** immunopeptidomics needs Orbitrap/Astral-class MS; the scanner vendor decides B1 converter effort; the sequencer model decides which pipelines apply. These are facility questions.
- **DB vs file:** some workflow defaults live in `backend/database/galaxy_ai_tools.db` (binary) rather than `.nf` files — those upgrades are SQL updates, documented per-item by the implementing agent, not binary edits.
- **Validation gap:** the audit proved *registration/routing*, not end-to-end runnability for the thin workflows. Each Wave-1 upgrade should include one real public-data run to validate, budget permitting.

---

## This session's parallel execution (the three threads okayed)

- **Thread A — Wave-1 upgrades U1/U2/U3** (backend workflow defs). *In flight.*
- **Thread B — L1c/L1d** output-resolution cleanup (frontend/server; owns `routes.ts` output region + `output-access.ts`).
- **Thread C — publication-flow objects** #22 report versioning + #24 plan object (isolated git worktree, since it also touches `routes.ts`; merged after).

File ownership is disjoint (A=backend, B=`routes.ts`+output-access, C=isolated worktree) so the three run without collision.
