# Supplementary Table S1 — Process Name Routing Table
**Paper:** BioMate: Evidence-graded QC governance for reproducible multi-omics analysis at scale
**Source:** `backend/lib/galaxy/jobs/qc_trace_monitor.py` — `_calculate_qc_metrics()` method

All matching is case-insensitive substring match on `process_name.upper()`. When multiple keywords are listed, any match routes to the corresponding parser.

---

| Domain | Process name keywords | Parser method | Output files read |
|---|---|---|---|
| **Cryo-EM** | `MOTION_CORRECTION` | `_parse_motion_correction_metrics` | `*.log`, `*_motion.txt` |
| Cryo-EM | `CTF_ESTIMATION`, `CTF_ESTIMATE` | `_parse_ctf_metrics` | `micrographs_ctf.cs`, `ctf_report.json`, `*.txt`, `*_ctf.log` |
| Cryo-EM | `PARTICLE_PICKING`, `PICKING` | `_parse_picking_metrics` | `*.star`, `*.box`, `*.coords` |
| Cryo-EM | `CLASSIFY_2D`, `CLASS_2D`, `2D_CLASSIFICATION`, `2DCLASSIFICATION` | `_parse_2d_classification_metrics` | `class2d_report.json`, `class2d_r{1,2}_report.json`, `class2d_metrics.json` |
| Cryo-EM | `HOMOGENEOUS_REFINEMENT`, `NONUNIFORM_REFINEMENT`, `HETEROGENEOUS_REFINEMENT`, `VALIDATION_FSC`, `LOCAL_CTF_REFINEMENT`, `AB_INITIO` | `_parse_refinement_metrics` | `*_results.json`, `job.json`, `*.json`, `*fsc*.txt` |
| Cryo-EM | `SHARPEN`, `CTF_REFINE_SHARPEN`, `POSTPROCESS`, `POSTPROCESSING` | `_parse_sharpening_metrics` | `sharpening_report.json`, `sharpening_results.json`, `postprocessing_results.json` |
| Cryo-EM | `MOLPROBITY`, `EMRINGER`, `MODEL_QUALITY`, `MODEL_VALIDATION`, `ALPHAFOLD_FIT` | `_parse_model_quality_metrics` | `*molprobity*.txt`, `*_model_quality*.json` |
| Cryo-EM | `LOCAL_RESOLUTION`, `LOCALRES`, `MONORES`, `RESMAP` | `_parse_local_resolution_metrics` | `local_resolution_report.json`, `local_resolution_results.json`, `localres_*.json` |
| **General QC** | `FASTQC`, `MULTIQC` | `_parse_fastqc_metrics` | `*fastqc_data.txt`, `fastqc_data.txt` |
| **RNA-seq** | `FASTP`, `TRIMGALORE`, `TRIMMOMATIC`, `BBDUK` | `_parse_trimming_metrics` | `*.json` (fastp), `*.log` (TrimGalore/Trimmomatic), `*.txt` |
| RNA-seq | `STAR_ALIGN`, `STAR_GENOME`, `HISAT2_ALIGN`, `HISAT2`, `BOWTIE2_ALIGN`, `BOWTIE2` | `_parse_alignment_metrics` | `*Log.final.out`, `*.log`, `*.txt` (flagstat) |
| RNA-seq | `FEATURECOUNTS`, `SUBREAD`, `HTSEQ` | `_parse_featurecounts_metrics` | `*.summary` |
| RNA-seq | `SALMON_QUANT`, `SALMON`, `KALLISTO` | `_parse_salmon_metrics` | `aux_info/meta_info.json`, `aux_info/alevin_meta_info.json`, `*.json` |
| **DNA-seq** | `FLAGSTAT`, `SAMTOOLS_FLAGSTAT`, `SAMTOOLS_STATS` | `_parse_flagstat_metrics` | `*.flagstat`, `*.txt` |
| DNA-seq | `MARKDUPLICATES`, `PICARD_MARKDUP`, `MARKDUP`, `GATK_MARKDUP` | `_parse_picard_dup_metrics` | `*.metrics`, `*.dup_metrics`, `*.txt` |
| DNA-seq | `BWA_MEM`, `BWA_MEM2`, `BWAMEM` | `_parse_alignment_metrics` | (same as RNA-seq alignment) |
| DNA-seq | `MOSDEPTH`, `SAMTOOLS_COVERAGE`, `GATK_COVERAGE`, `PICARD_WGS` | `_parse_coverage_metrics` | `*.mosdepth.summary.txt`, `*summary.txt`, `*.wgs_metrics`, `*wgs_metrics.txt` |
| **CRISPR** | `MAGECK_COUNT`, `MAGECK_MLE`, `MAGECK_TEST`, `CRISPRRESSO`, `GUIDE_ASSIGN`, `PERTURB_SEQ` | `_parse_guide_library_metrics` | `*.count_normalized.txt`, `*guide_summary*`, `*.log` |
| **scRNA-seq** | `CELLRANGER_COUNT`, `CELLRANGER`, `STARSOLO`, `ALEVIN` | `_parse_singlecell_metrics` | `metrics_summary.csv`, `outs/metrics_summary.csv`, `Summary.csv` |
| **ChIP/ATAC** | `MACS2`, `MACS3`, `CALLPEAK` | `_parse_peakcalling_metrics` | `*_peaks.narrowPeak`, `*_peaks.broadPeak`, `*_summits.bed`, `*.log`, `*frip*` |
| ChIP/ATAC | `ATAC_QC`, `TSS_ENRICH`, `ATAC_PEAK`, `DEEPTOOLS_PLOTFINGERPRINT`, `PLOTFINGERPRINT` | `_parse_atac_metrics` | `tss_enrich.txt`, `*.tss.txt`, `*.pbc.txt`, `*frip_score*` |
| **Metagenomics** | `KRAKEN2`, `KRAKEN`, `BRACKEN`, `METAPHLAN`, `KAIJU` | `_parse_metagenomics_metrics` | `*.report`, `*kraken*`, `*.k2report` |
| **Proteomics** | `MAXQUANT`, `MAXQUANT_SEARCH`, `MAXQUANT_ANDROMEDA` | `_parse_maxquant_metrics` | `peptides.txt`, `proteinGroups.txt`, `summary.txt` |
| Proteomics | `DIANN`, `DIANN_CONVERT`, `SPECTRONAUT`, `DIANN_SEARCH` | `_parse_diann_metrics` | `report.tsv`, `report.pg_matrix.tsv`, `*.tsv` |
| Proteomics | `PULLDOWN_QC`, `CHEMOPROTEOMICS_PULLDOWN`, `ABPP_PULLDOWN`, `ABPP`, `PULLDOWN` | `_parse_pulldown_metrics` | `pulldown_summary.json`, `enrichment_ratios.tsv` |
| **Cheminformatics** | `SMILES_QC`, `COMPOUND_QC`, `STRUCTURE_QC`, `ADMET_PRECHECK`, `DOCKING_PRECHECK` | `_parse_smiles_metrics` | `smiles_qc_report.json`, `compound_qc_summary.json` |
| **Drug safety** | `ADMET_TOXICITY`, `HERG_SCREEN`, `DILI_SCREEN`, `TOXICITY_SCREEN`, `ADMET_PRED`, `PREDICT_ADMET`, `ADMET_SAFETY` | `_parse_admet_toxicity_metrics` | `admet_results.json`, `toxicity_predictions.json` |
| **Pharmacogenomics** | `PGX_COVERAGE`, `CYP_COVERAGE`, `PHARMACOGENOMICS_QC`, `PGX_QC` | `_parse_pgx_coverage_metrics` | `pgx_coverage_summary.json` |
| **PK/PD — NCA** | `NCA_PKNCA`, `NCA_ANALYSIS`, `NONCOMPARTMENTAL`, `PKNCA` | `_parse_nca_results` | `nca_results.json`, `nca_summary.tsv` |
| **PK/PD — Pop PK** | `NLMIXR2`, `POPULATION_PK`, `POP_PK`, `POPPK`, `POPK` | `_parse_nlmixr2_results` | `nlmixr2_results.json`, `model_fit_summary.json` |
| **IVIVE** | `IVIVE`, `HEPATIC_CLEARANCE`, `IVIVE_HEPATIC`, `CLEARANCE_SCALING` | `_parse_ivive_results` | `ivive_results.json` |
| **Docking** | `MOLECULAR_DOCKING`, `DOCKING`, `AUTODOCK`, `VINA`, `GLIDE` | `_parse_docking_results` | `docking_autodock_vina_results.json` |
| **QSAR** | `QSAR_RF_MODEL`, `QSAR_MODEL`, `QSAR`, `CHEMPROP`, `DEEPCHEM` | `_parse_qsar_results` | `qsar_results.json` |

---

**Total parsers: 29**
**Total process-name keyword groups: 33**

Keywords are matched as substrings using `keyword in process_name.upper()`. The routing table is evaluated top-to-bottom; the first match wins. Processes not matching any keyword return `None` and no QC gate is applied.
