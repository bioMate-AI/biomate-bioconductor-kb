# Committee review: bioinformatics / genomics + lab-instruments lens (2026-10-04)

Scope: 6 produced videos (T0-T4, drug-dev), 10 instrument written tutorials, 18 platform written tutorials, priority Excel (20260715), instrument inventory (0920), sample-data coverage (0921), domain validation (0923), series catalog. Audit only; no files edited.

## 1. Verdict

**Not covered.** For this lens the video set is effectively 0% of the instrument-analysis surface and about 0% of the omics surface.

- The six produced videos are platform and drug-development tutorials. T0-T4 teach the UI, the dataset object and the ADMET report. The only run shown is a 3-SMILES ADMET job whose findings were *withheld*, so no omics or instrument analysis is demonstrated anywhere. A grep of the narration for RNA-seq, variant, proteomics, cryo-EM, methylation and Foldseek finds only one-line mentions (T0 card names, T2 "Genomic" model domain).
- Written coverage is good for instruments: 10 tutorials, each ~1.7-2.1k words, and they cover the analysis, not just connector plumbing. The exceptions are Opentrons, SiLA2 and Benchling, which have no analysis by design and say so honestly.
- There is no written or video tutorial for the core omics domains as such: methylation, single-cell, epigenomics (ChIP/ATAC), count-matrix DE as a stand-alone, Foldseek/MMseqs2/FPSim2 large-DB search, or large WGS cohorts. RNA-seq and WGS exist only as sub-sections of `basespace-sequencing.md`.
- The series catalog (`series/catalog.json`) is explicitly "in production, not released". Only `admet-evidence`, `result-downloads` and `reproducibility-record` have episode folders. Even the catalog's 28 chapters + 42 episodes contain no omics-domain or search-DB entries (it maps the existing tutorial docs, which do not cover them). The catalog's own coverageNote concedes this.
- M1 and M2 (search and data analysis) are **BLOCKED** by the series' own audit, because the cold-start dashboard does not mount. M1 is the only place large-DB search would live, and it must not be filmed yet.

## 2. Instrument coverage table

Video = a produced walkthrough video; Tutorial = written .md. The pipeline-validation column comes from each tutorial's own §6, 0920 and 0921.

| Instrument (priority basis) | Analysis it drives | Video? | Written tutorial? (analysis covered?) | Execution evidence | Gaps |
|---|---|---|---|---|---|
| Illumina via BaseSpace (P1 genomics core; RNA-seq P1, WGS P1) | nf-core/rnaseq to DE; Wgs Germline Gatk | No | basespace-sequencing.md; yes, RNA-seq + WGS | RNA-seq validated on real GEO. WGS: 0921 says "dispatch blocked (fetchngs S3 bug)", while the tutorial calls WGS "validated". **Conflict.** | No video. No scRNA, ChIP/ATAC or methylation branch. No cohort/joint-genotyping content despite the P1 "large WGS cohorts" row. |
| Cryo-EM (P1 flagship, $200-2000/run) | cryosparc_standard_spa: motion, CTF, picking, 2D, refinement, FSC | No | cryoem-reconstruction.md; yes | Real run evidence claimed | No video despite being the top-priced P1. Does not show the P1 chain "ensemble to pocket to screen". |
| LC-MS (proteomics/metabolomics) | proteomicslfq (DDA), dia_proteomics_analysis (DIA-NN), xcms/metaMS | No | lcms-proteomics-metabolomics.md; yes | Weakest. 0921: execution blocked (B3 raw to mzML). 0923: metabolomics failed on 4 successive bugs. | No video. Tutorial routes DIA to DIA-NN; internal memory flags DIA-NN as not license-clean (OpenSWATH/PyProphet is the clean path). No metabolite-ID or confidence-level discussion. |
| qPCR | normqpcr ΔΔCq | No | qpcr-quantification.md; yes, best-written | 0921: runs end-to-end on bundled NormqPCR example. The tutorial says "no recorded real run" and is **stale**. | No video, though it is the cheapest to film (small table, minute-scale run, sample data bundled, Tier-1). Absolute/standard-curve and melt-curve QC are gaps. |
| Flow cytometry | Analyze Flow Cytometry Immunophenotyping | No | flow-cytometry-gating.md; yes | Unverified. No fixture (0921). | No video. Gating is described as a "gating strategy text field", not interactive gates. |
| Nanopore (MinKNOW) | nanopore_basecalling to nf-core/nanoseq | No | nanopore-minknow.md; yes | "Not verified end-to-end". Needs GPU basecalling. | No video. Basecalling (GPU, Dorado) is not explained as a cost driver. |
| Plate reader | Dose Response, HTS plate QC, hit calling | No | plate-reader-assays.md; yes | Synthetic 96-well runs (0921) | No video. Z'/QC framing not checked here. |
| Opentrons | None (protocol execution only) | No | opentrons-liquid-handling.md; honest "no analysis" | n/a | Fine, but a "run it, then analyse the plate-reader output" chain is unwritten. |
| SiLA2 devices | None (control) | No | sila2-devices.md; honest | n/a | The same missing chain. |
| Benchling ELN/LIMS | ADMET on registry data | No | benchling-eln-lims.md | hERG gate "not proven live" | Drug-dev flavoured, not an omics instrument. |
| Immunopeptidomics MS, Bioanalyzer/RIN, NanoDrop, cell counter, imaging/WSI (inventory 0920) | mhcquant; B8 QC parsers; WSI | No | **None** | QC parsers synthetic. Imaging blocked (B1). | The inventory lists hospital instruments with **no tutorial at all**: RIN/Bioanalyzer, NanoDrop, cell-counter QC, imaging/WSI, immunopeptidomics. These are the likeliest first-day user files. |

Summary: 0 of 10 instruments have a video. 7 of the 10 written tutorials describe a real analysis. Only qPCR and the 4 synthetic QC parsers are provably runnable today (plus RNA-seq and cryo-EM, which are claimed validated).

## 3. Omics-domain coverage vs the priority Excel

| Priority row | Video | Written | Note |
|---|---|---|---|
| P1 Cryo-EM SPA (Heavy GPU) | no | yes (instrument) | Top-revenue row, unfilmed |
| P1 Large WGS cohorts (sarek/GATK joint) | no | partial (single-genome WGS in basespace) | Cohort/joint-genotyping not taught. Execution reported blocked (0921). |
| P1 Bulk RNA-seq nf-core/rnaseq | no | partial (basespace 2a) | Video-ready: validated, GSE52778 sample data on cold-start |
| P1 Count-matrix DE (DESeq2/edgeR/limma), Tier-1 front door | no | M2 touches ad-hoc compute only | **Highest-leverage gap.** The freemium wedge has no tutorial |
| P1 Methylation from IDAT | no | **none** (P2 in Excel, but named in the P1 wet-lab segment) | |
| P1 Foldseek / AlphaFold-Multimer / structure search | no | **none** | Implemented. Foldseek, MMseqs2, FPSim2 and the lookup cache are all P1 and absent from every tutorial |
| P1 GWAS to scRNA to eQTL target-ID chain | no | none | "Proposed", not shippable |
| P2 Single-cell atlas / cellranger | no | none | T0-T4 never mention scRNA. 0923 title says single-cell + metabolomics blocked |
| P3 ChIP/ATAC | no | none | Low priority |
| Large DB search (Foldseek 214M AFDB, MMseqs2 nr/UniRef, ChEMBL FPSim2, gnomAD/ClinVar lookups) | no | **none** (grep of M1/M2/T9/T10 finds no Foldseek/MMseqs/BLAST) | M1 is the natural home but is blocked |

The priority Excel's own P1 list is dominated by cryo-EM, WGS cohorts, DE, Foldseek and large-DB search. The tutorial plan is dominated by platform UI and ADMET. The two are misaligned.

## 4. Accuracy findings

Produced videos (narration):
- No omics scientific claims to check. T3 states the run's findings were withheld because the outputs were unreadable. That is honest, but it makes T3 weak as a "how to read a result" demo, because the viewer never sees a real finding. T4 states that the profiler reads delimited tables, VCF and FASTQ and reports a Phred mean ("below twenty, consider trimming"); this is accurate and conventional (Q20).
- Risk: the only run demonstrated is ADMET with an unreadable-output failure. Presenting it as the model "run and report" flow without a finished omics example overstates readiness for the hospital/core-facility buyer (P1).

Written instrument tutorials:
- **qPCR §6 is stale.** It says "no recorded real run" and "untested", but 0921 shows the workflow now runs end-to-end on the NormqPCR bundled example. Correct the tutorial, then film it.
- **qPCR "1 cycle = 2-fold"** assumes ~100% amplification efficiency. The efficiency-aware workflows are named in the tutorial, but the assumption should be stated where the rule of thumb is given. ΔΔCt is also described as using "the average ΔCt of control", which is correct, though geometric-mean multi-HKG averaging is the usual practice.
- **basespace-sequencing.md** calls the WGS pipeline "validated" while 0921 reports dispatch blocked by a fetchngs S3 bug. This is a direct internal conflict and must be reconciled before any WGS narration.
- **LC-MS** recommends DIA-NN as the default DIA engine. By the project's own license memory this is not license-clean for a hosted commercial product; OpenSWATH/PyProphet or an open engine is. It is also scientifically thin on FDR at the protein level and on metabolite identification confidence (Schymanski levels). The metabolomics path is documented as failing in 0923.
- **Cryo-EM**: "FSC 0.143, gold-standard (Henderson 2012)" is correct. The rule "below 3 Å you can often see side chains; 4-6 Å secondary structure" is acceptable. It omits the half-map independence caveat and local-resolution/over-fit pitfalls; add one honest line. It also does not mention CryoSPARC licensing.
- **Flow**: the compensation explanation is correct. It never mentions transformation (logicle/biexponential) or the live/dead gate before population percentages, and pre-gating is only implied. Percentages of "live cells" depend on this.
- **Nanopore**: the pod5/fast5 and basecalling description is correct. It does not state that high-accuracy basecalling needs GPU, or that Q-score thresholds are model-dependent.

## 5. Prioritized recommendations (grounded in the priority Excel)

1. **Fix the evidence first, cheaply.** Reconcile WGS validated/blocked, update the qPCR §6 status, and decide DIA-NN vs an open engine. Do not film any episode whose pipeline is blocked (WGS, proteomics, metabolomics, imaging). That follows the series' own rule and the 0921 principle.
2. **Produce first (runnable now, high priority):**
   a. **Count-matrix DE (DESeq2) on GSE52778** from the cold-start chip: P1, Tier-1 front door, validated, sample data in place. Include QC, volcano and MA plot, padj vs log2FC, and replicate caveats.
   b. **Bulk RNA-seq from FASTQ via nf-core/rnaseq**: P1, validated on real GEO.
   c. **qPCR ΔΔCt**: runs on the bundled example in minutes, so it makes the best instrument demo.
   d. **Cryo-EM SPA** (P1, highest price). Film only with the documented real S3 run plus the screenshot audit.
3. **Write, then film, the missing P1 tutorials:** large-DB search (Foldseek on AFDB, MMseqs2, FPSim2 and the reference-lookup cache), as an M1 child once the cold-start dashboard bug is fixed. Then methylation (IDAT), and WGS cohort calling after the fetchngs bug is closed.
4. **Add short written tutorials for the unmapped inventory instruments:** Bioanalyzer/RIN, NanoDrop, cell-counter, and imaging. They are the likeliest first-day hospital files, and 0921 shows their synthetic QC parsers already run.
5. **Make T3/T4 stronger:** re-record a completed run that has real findings (RNA-seq or qPCR) so "reading the report" shows an actual result, not a withheld one.
6. **Defer** the P2/P3 rows (single-cell atlas, ChIP/ATAC, metagenomics) and the "Proposed" complex chains until execution evidence exists. Add them to `catalog.json`, since the catalog currently contains no omics-domain or search entries.
7. **Add an instrument-chain episode:** Opentrons or SiLA2 followed by plate reader followed by dose-response. It is the only way the control-only connectors show an analysis.
