# TRAIN task: parameter_extraction  (2,273 instances)

## [0] source=multitask_sft_big

**USER:** Set up quasr_rna_seq_analysis using the sample manifest located at '/data/project/samples_rna_paired.txt'.

**ASSISTANT:** I will configure the 'quasr_rna_seq_analysis' workflow with the provided parameter:
- `samples_rna_paired.txt`: "/data/project/samples_rna_paired.txt" (sample sheet listing paired FASTQ files).

---

## [1] source=multitask_sft_big

**USER:** When providing an unpaired file alongside interleaved paired-end files to khmer: Normalize By Median, what positioning rule must be followed?

**ASSISTANT:** The unpaired file must be included so that it is processed last.

---

## [2] source=multitask_sft_big

**USER:** Set up the inputs for metacca. I have full genome summary stats in 'cohortA_all_snps.tsv' and 'cohortB_all_snps.tsv', and target variant summaries in 'cohortA_candidates.tsv' and 'cohortB_candidates.tsv'.

**ASSISTANT:** Here is the parameter mapping for the `metacca` workflow based on your files:

```json
{
  "S_XY_full_study1": "cohortA_all_snps.tsv",
  "S_XY_full_study2": "cohortB_all_snps.tsv",
  "S_XY_study1": "cohortA_candidates.tsv",
  "S_XY_study2": "cohortB_candidates.tsv"
}
```

---

## [3] source=multitask_sft_big

**USER:** I am running Trim otutable on my 16S amplicon data. I want any OTU count whose frequency relative to the total sample size is under 0.005 to be set to zero. What parameter value should I set?

**ASSISTANT:** You should set the minimum frequency parameter to 0.005. Trim otutable defines minimum frequency as the count divided by total sample size, and counts smaller than this threshold will be set to zero.

---

## [4] source=multitask_sft_big

**USER:** What sample input files are specified in the parameter definitions for `dexseq_python_htseq_preprocessed_workflow`?

**ASSISTANT:** The workflow parameter definitions specify data inputs such as `treated1fb.txt`, along with descriptions referencing `treated1fb.txt`, `treated2fb.txt`, `treated3fb.txt`, and untreated sample files.

---

## [5] source=multitask_sft_big

**USER:** I am configuring 'bioconductor-msnbase smooth mz' for noise reduction in my metabolomics mass spectrometry spectra. Which smoothing methods does the tool provide?

**ASSISTANT:** The 'bioconductor-msnbase smooth mz' tool supports two smoothing methods: 'Savitzky-Golay' and 'Moving Average'.

---

## [6] source=multitask_sft_big

**USER:** I am setting up Appendfdr for my peptide identification search results where my decoy entries start with 'DECOY_'. Can Appendfdr handle this prefix?

**ASSISTANT:** Yes. Appendfdr natively supports decoy identification based on prefixes such as 'DECOY_' (or 'REV_') to compute the false discovery rate.

---

## [7] source=multitask_sft_big

**USER:** I have my raw spike-in count matrix 'MET.CTL.countDat' formatted with 'Sample_Rep' columns, and I also compiled the sequencing depths into 'MET.CTL.totalReads'. Please parse these for the erccdashboard workflow.

**ASSISTANT:** Extracted inputs for erccdashboard:
- `MET.CTL.countDat`: RNA-Seq count table with 'Sample_Rep' column names (required count table)
- `MET.CTL.totalReads`: Vector of total reads per replicate (optional read depth vector)

---

## [8] source=multitask_sft_big

**USER:** Set up the ribodipa pipeline using our four Ribo-seq replicate alignments: 'rep1.bam', 'rep2.bam', 'rep3.bam', and 'rep4.bam'.

**ASSISTANT:** Extracted parameter configuration for **ribodipa_step_by_step_pipeline**:

- **bam_path**: `["rep1.bam", "rep2.bam", "rep3.bam", "rep4.bam"]` (Ribo-seq BAM alignment files 1 through 4)

---

## [9] source=multitask_sft_big

**USER:** From this request: 'Please take my DNA sequence seq_GFP_v1.fasta and optimize it for heterologous expression in Pichia pastoris', what are the primary inputs for Biomni: Optimize Codons For Heterologous Expression?

**ASSISTANT:** The extracted parameters are:
- **Input Sequence**: `seq_GFP_v1.fasta` (DNA)
- **Host Organism**: `Pichia pastoris`
- **Target Task**: Codon optimization for heterologous expression.

---

## [10] source=multitask_sft_big

**USER:** Does the brew3r_r workflow require any configurable parameters beyond the count_data input?

**ASSISTANT:** No, the `brew3r_r` workflow has no additional parameters defined in its configuration (`parameters: []`). It only requires the `count_data` input.

---

## [11] source=multitask_sft_big

**USER:** What required data inputs are expected by the 'saturn' workflow?

**ASSISTANT:** The `saturn` workflow requires two non-optional inputs:
1. `Tasic_counts_vignette`: A transcript expression count matrix.
2. `Tasic_metadata_vignette`: A sample or cell metadata dataframe.

---

## [12] source=multitask_sft_big

**USER:** If I have an ASCII quality character Q = 'I' in a SAM record, what formula does the Read Quality tool use to compute its numeric score?

**ASSISTANT:** It uses the formula: Phred Quality Score = ord(Q) - 33.

---

## [13] source=multitask_sft_big

**USER:** I am setting up a Canu assembly run for Oxford Nanopore reads. What is the standard parameter setting for the allowed difference in overlap between corrected reads?

**ASSISTANT:** The default parameter setting for Nanopore reads in Canu assembler is 0.144.

---

## [14] source=multitask_sft_big

**USER:** We want to configure in_vivo_base_edit_design for a project aimed at gene_correction using an ABE editor delivered via ex vivo HSC. What parameters can be identified?

**ASSISTANT:** Based on your request, the extracted parameters for in_vivo_base_edit_design are:
- Edit goal: gene_correction
- Editor class: ABE
- Delivery strategy: ex vivo HSC

---

## [15] source=multitask_sft_big

**USER:** I need to run Sequenzautils Gcwiggle using my reference genome 'hg38.fasta' with a window size of 50 base pairs. Can you extract the necessary execution parameters from my request?

**ASSISTANT:** Based on your request, the parameters for Sequenza-utils gc_wiggle are:
- **fasta**: `hg38.fasta`
- **window size**: `50`

---

## [16] source=multitask_sft_big

**USER:** What input slots and underlying packages are included in the flowSpecs workflow?

**ASSISTANT:** The `flowSpecs` workflow declares an optional data input slot named `count_data`. It utilizes the Bioconductor packages `bioconductor/flowspecs` and `bioconductor/flowcore`.

---

## [17] source=multitask_sft_big

**USER:** By default, how many initial bases does EstimateLibraryComplexity sort reads by when examining duplicates?

**ASSISTANT:** EstimateLibraryComplexity sorts reads by the first 5 bases (N = 5) by default.

---

## [18] source=multitask_sft_big

**USER:** Run Tomogram Reconstruction using SIRT with 25 iterations on my aligned tilt series. Set the tomogram thickness to 180 nm and binning factor to 2.

**ASSISTANT:** Extracted workflow parameters for Tomogram Reconstruction:
- reconstruction_method: "SIRT"
- sirt_iterations: 25
- tomogram_thickness_nm: 180
- binning_factor: 2

---

## [19] source=multitask_sft_big

**USER:** Please configure our QSP virtual patient simulation with the baseline covariate matrix 'covars.csv', mechanistic model 'pkpd_model.xml', 2000 patients, 30% biomarker prevalence (0.30), 1:1 allocation ratio (1.0), analysis mode 'stratified_response', and random seed 42.

**ASSISTANT:** Here are the extracted parameters mapped to the Qsp Virtual Population workflow inputs:
- covariate_file: covars.csv
- model_file: pkpd_model.xml
- analysis: stratified_response
- n_patients: 2000
- biomarker_prevalence: 0.30
- allocation_ratio: 1.0
- seed_base: 42

---

## [20] source=multitask_sft_big

**USER:** I am configuring ITRAQAnalyzer for a proteomics run and want to enable the ID pool feature. What flag controls this and what setting points it to the default ID pool file?

**ASSISTANT:** In ITRAQAnalyzer, the relevant flag is `-id_pool`. It is disabled by default. To point it to the default file (`/home/ubuntu/miniconda3/envs/py2test/share/OpenMS/IDPool/IDPool.txt`), set the flag to `'main'`.

---

## [21] source=multitask_sft_big

**USER:** What role does precursor mass tolerance play in ERPairFinder?

**ASSISTANT:** The precursor mass tolerance parameter is used for pair finding and matching the given pair m/z values to the detected mass spectrometry features.

---

## [22] source=multitask_sft_big

**USER:** I need to build a profile HMM from my alignment file 'input_alignment.msa' and save the resulting model as 'output_profile.hmm' using hmmbuild. What are the input and output arguments?

**ASSISTANT:** For hmmbuild, the input multiple sequence alignment argument <msafile> is 'input_alignment.msa', and the output profile HMM argument <hmmfile out> is 'output_profile.hmm'.

---

## [23] source=multitask_sft_big

**USER:** Fetch the metadata record for protocols.io entry ID 48291.

**ASSISTANT:** Extracted parameter:
- `protocol_id`: 48291 for the **Get Protocol Details** tool.

---

## [24] source=multitask_sft_big

**USER:** I want to supply my raw FCS files to the cytofqc_manual_step_by_step_qc workflow. Which input parameter corresponds to this data?

**ASSISTANT:** You can pass your raw FCS files using the `raw_cytof.fcs` data input parameter (described as raw CyTOF data in FCS format) or via `input_files`.

---

## [25] source=multitask_sft_big

**USER:** I want to add a method to my subsampling results. Here are my inputs: raw count matrix `hammer.counts`, previous result object `subsamples`, and treatment vector `hammer.design$protocol`. Please extract the workflow parameters.

**ASSISTANT:** The parameters for `subseq_add_methods_or_depths` have been extracted:
- `hammer.counts`: "hammer.counts" (raw RNA-seq counts matrix)
- `subsamples`: "subsamples" (subsamples object from previous run)
- `hammer.design$protocol`: "hammer.design$protocol" (vector of treatment groups)

---

## [26] source=multitask_sft_big

**USER:** I have my expression matrix loaded as `gene_expr_mat` and sample-to-batch mapping in `sample_batch_df`. How should these be assigned to the harmonizr workflow?

**ASSISTANT:** Map `gene_expr_mat` to the required parameter `df` and `sample_batch_df` to `des`. The workflow will process these inputs and output `de_table`.

---

## [27] source=multitask_sft_big

**USER:** I want to run `bedtools genomecov` to get a per-base report instead of the standard histogram. Which option should I specify?

**ASSISTANT:** To generate a per-base report in `bedtools genomecov`, you should use the `-d` parameter.

---

## [28] source=multitask_sft_big

**USER:** Please set up the DIFFBIND_COUNT step for our human genome (hg38) analysis using input 'samples.csv'. I want an FDR threshold of 0.05, a fold change cutoff of 1.5, min_overlap set to 2, and use the blacklist 'hg38-blacklist.bed'. Limit resources to 8 CPUs and 32GB memory.

**ASSISTANT:** Here are the extracted parameters for `DIFFBIND_COUNT`:
- `input`: "samples.csv"
- `genome`: "hg38"
- `fdr_threshold`: 0.05
- `fold_change`: 1.5
- `min_overlap`: 2
- `blacklist`: "hg38-blacklist.bed"
- `max_cpus`: 8
- `max_memory`: "32GB"

---

## [29] source=multitask_sft_big

**USER:** I want to run parody outlier detection on my numeric feature matrix called 'feature_matrix.tsv'. How should this be supplied?

**ASSISTANT:** Supply 'feature_matrix.tsv' as the `tcost` input parameter, which expects a multivariate data frame or matrix of numeric features.

---

## [30] source=multitask_sft_big

**USER:** I want to retrieve gene reports for BRCA1 under human (taxon 9606) using its NCBI gene symbol.

**ASSISTANT:** From your request, the parameters identified for NCBI Datasets Gene are: identifier type set to gene symbol ('BRCA1'), taxon specified as '9606' (human), and target data product designated as gene reports.

---

## [31] source=multitask_sft_big

**USER:** I am configuring ENSEMBL variant effect predictor for a run. My input reads are from mouse tissue. Can you identify the species parameter value from this request?

**ASSISTANT:** Extracted parameter:
- species: 'mouse' (Ensembl alias) or the corresponding Latin name 'Mus musculus'.

---

## [32] source=multitask_sft_big

**USER:** What output file types does the matter_image_processing_and_alignment workflow produce?

**ASSISTANT:** The workflow outputs results in three formats: `table/csv`, `plot/pdf`, and `object/rds`.

---

## [33] source=multitask_sft_big

**USER:** I am configuring Phylodeep modeldeep for phylodynamic model selection. I prefer using a feed-forward neural network trained on summary statistics rather than the default convolutional network. Which parameter option should I set?

**ASSISTANT:** You should set the tree representation and neural network option to `FFNN_SUMSTATS` (FFNN trained on summary statistics), which replaces the default `CNN_FULL_TREE`.

---

## [34] source=multitask_sft_big

**USER:** I am configuring iPHoP predict for bacteriophage host prediction from metagenomic contigs. I want to achieve an estimated false discovery rate (FDR) of roughly 5%. What minimum confidence score should I provide?

**ASSISTANT:** For an estimated overall FDR of roughly 5% in iPHoP predict, you should set the minimum confidence score to 95 (the default score of 90 corresponds to approximately 10% FDR).

---

## [35] source=multitask_sft_big

**USER:** What specific file and column fields are required as input for the stringdb workflow?

**ASSISTANT:** The workflow requires `gene_expression_data.csv`, which must be a table containing gene symbols, p-values, and log fold changes from a differential expression experiment.

---

## [36] source=multitask_sft_big

**USER:** Please pull the expression dataset GSE154569 from the Gene Expression Omnibus repository using Geoquery Getgeo.

**ASSISTANT:** Extracted parameter for Geoquery Getgeo:
- GEO Accession ID: GSE154569

---

## [37] source=multitask_sft_big

**USER:** What input datasets and parameters are required to run the aldex2_sensitivity_analysis workflow?

**ASSISTANT:** The `aldex2_sensitivity_analysis` workflow requires two mandatory data inputs:
1. `Y`: A count matrix of features by samples (type: matrix).
2. `conds`: A vector defining group conditions for the samples.

---

## [38] source=multitask_sft_big

**USER:** Please run FROGSSTAT Phyloseq Composition Visualisation on my dataset. I only want to keep taxa belonging to Bacteria at the Kingdom rank, and I want the aggregated composition plot generated at the Phylum level.

**ASSISTANT:** Extracted configuration for FROGSSTAT Phyloseq Composition Visualisation:
- Taxa subset filter: `Bacteria` at taxonomic level `Kingdom`
- Aggregation rank: `Phylum`

---

## [39] source=multitask_sft_big

**USER:** What outputs are generated when I execute the genebreak_dataframe_input_pipeline?

**ASSISTANT:** The workflow produces two main outputs: 'copy_number_segments' and 'visualizations'.

---

## [40] source=multitask_sft_big

**USER:** What outputs are generated when `harman_methylation_m_values` finishes processing?

**ASSISTANT:** The `harman_methylation_m_values` workflow produces three output formats: `table/csv`, `plot/pdf`, and `object/rds`.

---

## [41] source=multitask_sft_big

**USER:** I want to split an MGF dataset using Split file. Please put 2500 spectra in each chunk.

**ASSISTANT:** Extracted parameter for 'Split file':
- chunk size (number of records per file): 2500

Note: 'Number of new files' will be ignored by the tool.

---

## [42] source=multitask_sft_big

**USER:** Please configure FASTQ Masker to mask all bases with a Phred score below 20 using a less-than comparison.

**ASSISTANT:** Parameters extracted for FASTQ Masker:
- Quality score value: 20
- Comparison method: less-than (<)

---

## [43] source=multitask_sft_big

**USER:** What output file formats are generated by the chicago_peak_enrichment_analysis workflow?

**ASSISTANT:** The chicago_peak_enrichment_analysis workflow generates outputs in table/csv, plot/pdf, and object/rds formats.

---

## [44] source=multitask_sft_big

**USER:** When running `parallel_pick_otus_blast`, what is the default parameter setting for the minimum percentage of the query sequence that must align to consider a hit?

**ASSISTANT:** The default setting for the minimum percent of query sequence that can be aligned to consider a hit in `parallel_pick_otus_blast` is 0.5 (50%).

---

## [45] source=multitask_sft_big

**USER:** I am running Get.rabund for microbial community analysis. Can I change the arrangement of OTUs in the output so the most prevalent ones appear first?

**ASSISTANT:** Yes. While `Get.rabund` defaults to the same order as the input OTUs, it provides an option to select sorting by abundance.

---

## [46] source=multitask_sft_big

**USER:** What input files and output formats are defined for shortread_fastq_filtering_and_trimming?

**ASSISTANT:** The workflow takes `a.fastq.gz (input FASTQ file)` as its defined input (with `data_inputs` referencing `file.fastq` and `input_files`), and it generates `visualizations` as the final output.

---

## [47] source=multitask_sft_big

**USER:** What does increasing the 'ipoints' parameter do in RNAheat?

**ASSISTANT:** In RNAheat, the program fits a parabola to 2*ipoints+1 data points to calculate second derivatives. Increasing the 'ipoints' parameter produces a smoother specific heat curve.

---

## [48] source=multitask_sft_big

**USER:** What are the declared outputs of the `spatialdecon_custom_profile_matrix_generation` workflow?

**ASSISTANT:** The declared outputs of the workflow are `seurat_object` and `counts_matrix`.

---

## [49] source=multitask_sft_big

**USER:** I am configuring bacon_adjustment_with_95_ci. I have prepared an input matrix of replicated z-scores called 'rep_z_matrix.rds' and need to get the consensus score output.

**ASSISTANT:** For the `bacon_adjustment_with_95_ci` workflow, the required input parameter is:
- `zs`: set to `'rep_z_matrix.rds'` (matrix of replicated z-scores)

Upon completion, the workflow will generate the `consensus_score` output.

---

## [50] source=multitask_sft_big

**USER:** Does the cummeRbund workflow take any required input datasets, and how is the input parameter defined?

**ASSISTANT:** Yes, the cummeRbund workflow defines an input named 'input_files' of type 'data', which is marked as non-optional (optional: false) and is actively read by the workflow (read_by_workflow: true).

---

## [51] source=multitask_sft_big

**USER:** I prepared my normalized matrices for scRNA-seq, scATAC-seq, and 10x Multiome into a list named `pbmc_mosaic_matrices`. Can you extract the configuration needed for the `stabmap_indirect_mosaic_integration` workflow?

**ASSISTANT:** Here is the extracted parameter configuration for `stabmap_indirect_mosaic_integration`:

```json
{
  "assay_list_indirect": "pbmc_mosaic_matrices"
}
```

---

## [52] source=multitask_sft_big

**USER:** I am configuring Scater DetectOutlier for my single-cell RNA-seq QC. What are the allowed options for specifying which tail to look for outliers in?

**ASSISTANT:** The parameter is a character scalar choice with three options: 'both' (which is the default to look for outliers at both tails), 'lower' (to detect outliers only at the lower end), or 'higher' (to detect outliers only at the higher end).

---

## [53] source=multitask_sft_big

**USER:** What output files and results does the `meskit_ith_measurement` workflow generate upon completion?

**ASSISTANT:** The workflow produces three outputs: `mutational_signatures`, `phylogenetic_tree`, and `visualizations`.

---

## [54] source=multitask_sft_big

**USER:** Here is my input configuration for my differential expression run: I have my zero-inflated count matrix stored at 'counts_zinb.matrix' that should serve as zimData. Please map this to the bayseq_generic_zinb_analysis parameters.

**ASSISTANT:** Here is the parameter mapping for `bayseq_generic_zinb_analysis`:

- `zimData`: 'counts_zinb.matrix' (matrix of zero-inflated counts, read_by_workflow: true)

---

## [55] source=multitask_sft_big

**USER:** What constraints must be met for the plot title in 'Heatmap with extra color options'?

**ASSISTANT:** The title for 'Heatmap with extra color options' must not be blank, must be under 45 characters in length so that it fits on the plot, and cannot contain parentheses, brackets, '@', '%', or single quotes ('). The special characters '^', '!', '?', and '*' are permitted.

---

## [56] source=multitask_sft_big

**USER:** Please set up missmethyl_diff_var_rnaseq using 'rnaseq_raw_counts.tsv' as my count matrix, 'gencode_annotations.df' for annotations, and the vector 'sample_genders.rds'.

**ASSISTANT:** The parameters are extracted as follows:
- counts: "rnaseq_raw_counts.tsv"
- annot: "gencode_annotations.df"
- gender: "sample_genders.rds"

---

## [57] source=multitask_sft_big

**USER:** We have serology profiles for our SLE cohort in 'sle_serology_2024.csv'. We want to apply a non-IgG cutoff of 0.20, an IgG4 cutoff of 0.15, and set baff_april_high to true. How should we set up the Autoantibody Isotype Stratification workflow parameters?

**ASSISTANT:** Here is the parameter assignment for the `Autoantibody Isotype Stratification` workflow:
- `serology_file`: "sle_serology_2024.csv"
- `cohort`: "SLE"
- `non_igg_threshold`: 0.20
- `igg4_threshold`: 0.15
- `baff_april_high`: true

---

## [58] source=multitask_sft_big

**USER:** Please set up mpranalyze_comparative_analysis with my inputs located at: DNA matrix '/data/counts_dna.tsv', RNA matrix '/data/counts_rna.tsv', annotations '/meta/samples.tsv', and control vector '/meta/ctrl_enhancers.txt'.

**ASSISTANT:** Here are the extracted input parameters for 'mpranalyze_comparative_analysis':
- dna_counts.tsv: '/data/counts_dna.tsv'
- rna_counts.tsv: '/data/counts_rna.tsv'
- col_annotations.tsv: '/meta/samples.tsv'
- controls.txt: '/meta/ctrl_enhancers.txt'

---

## [59] source=multitask_sft_big

**USER:** Does 'Samtools coverage' support computing depth across multiple BAM files simultaneously, and how does it handle them?

**ASSISTANT:** Yes, 'Samtools coverage' supports multi-sample designs. If you select the option to pool the BAM files, it calculates coverage combined across all the specified files.

---

## [60] source=multitask_sft_big

**USER:** Which alignment and reference configuration parameters are available in the `nf-core/cageseq` pipeline?

**ASSISTANT:** Relevant configurable tools/parameters supported by `nf-core/cageseq` include `aligner`, `min_aln_length`, `genome`, `fasta`, `igenomes_base`, and `igenomes_ignore`, as well as options like `bigwig`, `outdir`, and `email`.

---

## [61] source=multitask_sft_big

**USER:** I am configuring Validate Variants for whole exome sequencing quality control. Please configure it so that if it encounters errors, it issues warnings instead of halting execution.

**ASSISTANT:** Based on your requirement, the parameter has been configured:
- `warnOnErrors`: `true` (emits warnings on errors instead of terminating the run).

---

## [62] source=multitask_sft_big

**USER:** Configure panomir for my experiment. The expression matrix is at 'counts_normalized.csv' and the sample phenotype sheet is at 'sample_covariates.csv'.

**ASSISTANT:** The parameters for the `panomir` workflow have been set:
- `gene_expression.csv`: `counts_normalized.csv` (gene expression matrix with genes as rows and samples as columns)
- `covariates.csv`: `sample_covariates.csv` (sample metadata table containing experimental conditions and covariates)

The workflow will generate summary tables (`table/csv`), visual plots (`plot/pdf`), and serialized PanomiR results (`object/rds`).

---

## [63] source=multitask_sft_big

**USER:** Which parameters can be used to set the reference sequences for parallel_assign_taxonomy_blast?

**ASSISTANT:** To provide reference sequences to blast against in parallel_assign_taxonomy_blast, you must specify either '--blast_db' or '--reference_seqs_db'.

---

## [64] source=multitask_sft_big

**USER:** Which input files are required to run the GPA workflow?

**ASSISTANT:** The GPA workflow requires the data input slot `input_files` (marked as mandatory, `optional: false`, and read by the workflow).

---

## [65] source=multitask_sft_big

**USER:** In the InputReader tool, which parameter flag do I use to specify the SD-property containing the training set activity data?

**ASSISTANT:** You can specify the name of the SD-property containing the activity data (response values) using the `-act` option.

---

## [66] source=multitask_sft_big

**USER:** In the Column join tool, what occurs if the header lines setting is set to 0?

**ASSISTANT:** If it is set to 0, a header line is added where the identifier column is named '#KEY', and the other columns are named according to the input dataset names/columns.

---

## [67] source=multitask_sft_big

**USER:** Please set up raer_bulk_differential_editing with alignments stored at 'sample_cohort.bam', genome reference 'hg38.fasta', and editing coordinates 'chr_18_editing_sites.gr'.

**ASSISTANT:** Extracted workflow parameters:
- `bam_files.bam`: "sample_cohort.bam"
- `fafn.fasta`: "hg38.fasta"
- `chr_18_editing_sites.gr`: "chr_18_editing_sites.gr"

---

## [68] source=multitask_sft_big

**USER:** In Plot Tools (Astronomy), how should I set the weight_col parameter if my table doesn't have a weights column versus when weights are in the 3rd column?

**ASSISTANT:** For Plot Tools, if your data does not contain weights, set `weight_col` to an empty string (`""`). If weights are in column 3, you can set `weight_col` to `c3` (using the `cXX` format where XX >= 1) or provide the exact column name.

---

## [69] source=multitask_sft_big

**USER:** I have my initial split forward FASTQ file named 'sample_chunk1_R1.fastq'. Which input parameter in rfastp_fastq_concatenation should this file be assigned to, and is it required?

**ASSISTANT:** Your file should be mapped to the parameter 'pe001_read1' (described as 'Split forward FASTQ file 1'). This parameter is optional.

---

## [70] source=multitask_sft_big

**USER:** I want to run the discordant workflow. Here is my dataset configuration: I have raw gene count tables stored at '/data/counts/rnaseq_matrix.tsv' for disease vs control cohorts. Please extract the workflow input settings.

**ASSISTANT:** Here are the extracted parameters for the discordant workflow:
- input_files: "/data/counts/rnaseq_matrix.tsv" (count_data)

---

## [71] source=multitask_sft_big

**USER:** What inputs does hicTADClassifier take, and what format is recommended according to its design specifications?

**ASSISTANT:** `hicTADClassifier` accepts a single Hi-C matrix, ideally in cooler format, to predict and output TAD boundary positions in a BED file.

---

## [72] source=multitask_sft_big

**USER:** I am configuring inputs for `mia_community_diversity_and_ordination`. What are the exact expected filename, file format, and primary output generated by this workflow?

**ASSISTANT:** The expected input file is `GlobalPatterns.RDS` with type `rds_se` (a TreeSummarizedExperiment containing raw counts and sample metadata). The workflow produces `phylogenetic_tree` as an output.

---

## [73] source=multitask_sft_big

**USER:** Configure Local Refinement using CryoSPARC with focus mask 'ribosome_head.mask', symmetry 'C1', initial lowpass filtered at 15 Å, and capped at 30 iterations.

**ASSISTANT:** Here are the extracted parameters for the Local Refinement workflow:
- focus_mask: "ribosome_head.mask"
- symmetry: "C1"
- initial_lowpass: 15
- max_iterations: 30
- use_cryosparc: true

---

## [74] source=multitask_sft_big

**USER:** I am configuring parameters for the `rlmm` workflow. Which internal reference and configuration files are registered as data inputs?

**ASSISTANT:** The registered data inputs for `rlmm` include 'Xba.CQV' (internal normalization file) and 'Xba.regions' (internal classification regions file), alongside the SNP list ('snps.lst') and ASCII-converted CEL files ('.raw files').

---

## [75] source=multitask_sft_big

**USER:** Please set up `scannotatr_train_basic_classifier` with my input dataset file located at `/data/annotated_zilionis_sce.rds`.

**ASSISTANT:** I have extracted the necessary parameter for `scannotatr_train_basic_classifier`:

- `zilionis`: `/data/annotated_zilionis_sce.rds` (SingleCellExperiment object, format `rds_sce`)

This fulfills the mandatory data input requirement to run the workflow.

---

## [76] source=multitask_sft_big

**USER:** In the `kissde_custom_table_analysis` workflow, is `table_counts_alt_splicing.txt` marked as optional?

**ASSISTANT:** No, `table_counts_alt_splicing.txt` is not optional (`optional: false`). It is a required data input that must be read by the workflow.

---

## [77] source=multitask_sft_big

**USER:** What input files are required to run the `rbwa_bwa_mem_long_reads` workflow?

**ASSISTANT:** Based on the workflow specification, the required inputs are:
- `reference.fa`: Reference genome FASTA file (`type: fasta`, required)
- `reads.fastq`: Input sequencing reads (`type: fastq`)

---

## [78] source=multitask_sft_big

**USER:** I am running assemblystats on my new de novo genome assembly, but I only received the summary file 'Assembly Statistics'. I need to see all possible detailed output files. How should I configure the tool?

**ASSISTANT:** Enable the option to display all output files (check the corresponding checkbox). If unchecked, the tool defaults to outputting only the 'Assembly Statistics' file; checking it ensures all output files are generated and displayed.

---

## [79] source=multitask_sft_big

**USER:** I have forward and reverse read files: `sampleA_R1.fastq.gz` and `sampleA_R2.fastq.gz`. Map these to the input parameters for `rfastp_paired_end_qc_and_merging`.

**ASSISTANT:** Here is the parameter mapping for `rfastp_paired_end_qc_and_merging`:
- `pe_read1`: `sampleA_R1.fastq.gz` (Forward paired-end FASTQ file)
- `pe_read2`: `sampleA_R2.fastq.gz` (Reverse paired-end FASTQ file)

---

## [80] source=multitask_sft_big

**USER:** In our rDock docking post-processing step, I want to filter the docking poses and ensure all records across the entire output file are sorted together after filtering, rather than sorting locally per name field block.

**ASSISTANT:** Extracted parameter for rDock docking post-filtering sorting:
- Sort all records in file after filtering: true

---

## [81] source=multitask_sft_big

**USER:** What output formats are produced by the raer_novel_editing_detection workflow?

**ASSISTANT:** The `raer_novel_editing_detection` workflow produces three output formats: `table/csv`, `plot/pdf`, and `object/rds`.

---

## [82] source=multitask_sft_big

**USER:** From the following request, identify the primary omics areas and suitable experimental designs for the CFSAN SNP Pipeline filter SNP Regions tool: 'We are conducting SNP-based phylogenetic analysis and bacterial outbreak strain typing on metagenomic samples.'

**ASSISTANT:** Based on the tool's supported design:
- Primary omics: genomics, metagenomics, bacterial genomics
- Suitable experimental designs: SNP-based phylogenetic analysis, Outbreak investigation and strain typing, Comparative genomics

---

## [83] source=multitask_sft_big

**USER:** I want to run `lea_predictive_ecological_genomics_genetic_gap`. My current data files are `snps_matrix.rds` (genotypes), `bioclim_current.rds` (current climate variables), and `bioclim_2050_ssp585.rds` (future climate projections). Please extract and map these to the workflow inputs.

**ASSISTANT:** Here is the mapped parameter assignment for `lea_predictive_ecological_genomics_genetic_gap`:
- `Y`: `snps_matrix.rds` (Genotype matrix)
- `X`: `bioclim_current.rds` (Current environmental variables matrix)
- `X.pred`: `bioclim_2050_ssp585.rds` (Predicted future environmental variables matrix)

---

## [84] source=multitask_sft_big

**USER:** Please set up the crisprseek_allele_specific_grna_design workflow using rs362331C.fa as the sequence for allele 1 and rs362331T.fa for allele 2.

**ASSISTANT:** I have configured the inputs for 'crisprseek_allele_specific_grna_design':
- rs362331C.fa: FASTA file for allele 1
- rs362331T.fa: FASTA file for allele 2

---

## [85] source=multitask_sft_big

**USER:** What inputs are mandatory to run the `viper` workflow, and what are their expected formats?

**ASSISTANT:** The `viper` workflow requires two inputs:
1. `dset`: An ExpressionSet or numeric matrix of gene expression data (`matrix` type, mandatory).
2. `bcellaracne.adj`: An ARACNe network adjacency file.

---

## [86] source=multitask_sft_big

**USER:** Prepare the input parameter mapping for tronco_pathway_level_visualization using my file 'cohort_binary_genotypes.rds'.

**ASSISTANT:** Here is the parameter mapping:
- `dataset.RData`: cohort_binary_genotypes.rds (Type: rds, TRONCO dataset object containing binary genotype data)

---

## [87] source=multitask_sft_big

**USER:** I ran principal coordinates analysis and obtained two files: 'pcoa_run1.txt' and 'pcoa_run2.txt'. How should I pass these to compare_3d_plots?

**ASSISTANT:** You should provide them as a comma-separated list of paths: 'pcoa_run1.txt,pcoa_run2.txt'.

---

## [88] source=multitask_sft_big

**USER:** What are the data input specifications and types for ledpred_all_in_one_ledpred?

**ASSISTANT:** The workflow defines one data input:
- Name: `crm.features`
- Type: `matrix`
- Optional: `false`
- Read by workflow: `true`
- Description: Pre-built feature matrix or loaded via `data(crm.features)`.

---

## [89] source=multitask_sft_big

**USER:** How does the energy threshold filtering parameter work in miRanda, and what kind of values does it require?

**ASSISTANT:** In miRanda, only alignments with an energy value less than or equal to the specified threshold are retained for downstream analysis. A negative value is required for filtering to take effect.

---

## [90] source=multitask_sft_big

**USER:** What are the minimal settings required to run RAxML?

**ASSISTANT:** The minimal settings required for RAxML are the input file and the substitution model.

---

## [91] source=multitask_sft_big

**USER:** In the Phylo.diversity tool, I set the parameter value to 25. How will the tool interpret this?

**ASSISTANT:** Since the value is between 0 and 100, the tool interprets 25 as the percentage of sequences to sample.

---

## [92] source=multitask_sft_big

**USER:** What exact input files and formats must I supply to the fedup workflow?

**ASSISTANT:** You need to provide two data inputs:
1. gene_list.rds: A named list containing a 'background' character vector and one or more test set character vectors.
2. pathways.gmt: Pathway annotations in GMT format.

---

## [93] source=multitask_sft_big

**USER:** Which input files and formats are required by the 'piano' microarray workflow?

**ASSISTANT:** The `piano` workflow requires two mandatory input files:
1. `norm_data.txt.gz`: pre-normalized expression values.
2. `setup.txt`: a tab-delimited experimental setup file mapping samples to experimental conditions.

---

## [94] source=multitask_sft_big

**USER:** Can you list the input file specifications documented for `chemminer_large_file_streaming`?

**ASSISTANT:** Based on the workflow configuration, the input specification is: `test.sdf` with type `data`, `optional: false`, `read_by_workflow: true`, and described as a 'Large SD file containing millions of molecules'.

---

## [95] source=multitask_sft_big

**USER:** I am configuring the quasr_smrna_seq_analysis pipeline. My miRNA sample sheet is located at '/data/project/sample_list_mirna.fasta.txt'. Can you map this to the workflow input?

**ASSISTANT:** Here is the mapped parameter for the workflow:
- `samples_mirna.txt`: "/data/project/sample_list_mirna.fasta.txt"

---

## [96] source=multitask_sft_big

**USER:** I am configuring CytoExport. Please map the parameters from my notes: 'Data table: protein_quant.csv; custom configuration: table_import_settings.cfg'.

**ASSISTANT:** Based on your inputs, the extracted parameters for CytoExport are:
- **Input CSV file**: `protein_quant.csv`
- **Alternative TableImport configuration file**: `table_import_settings.cfg`

---

## [97] source=multitask_sft_big

**USER:** I want to run the globalancova_sum_of_squares_decomposition workflow. Here are my files: expression_matrix.csv (normalized gene expression matrix) and phenotype_data.csv (clinical annotations with multi-level factors). Could you extract and confirm the required data inputs?

**ASSISTANT:** The workflow `globalancova_sum_of_squares_decomposition` requires the following non-optional data inputs:
- `expression_matrix.csv`: normalized gene expression matrix (type: matrix)
- `phenotype_data.csv`: sample clinical annotations with multi-level factors (type: data)

Both inputs are accounted for and will be read by the workflow to generate `de_table` and `visualizations`.

---

## [98] source=multitask_sft_big

**USER:** In the Deletion Profile tool, I have alignments with CIGAR strings like '101M', '68M140N33M', and '53M1D48M'. What value should I provide for the required read alignment length parameter?

**ASSISTANT:** You should set the required read alignment length parameter to 101. For the Deletion Profile tool, this parameter is set to the original read length, and CIGAR strings such as '101M', '68M140N33M', and '53M1D48M' all correspond to an alignment read length of 101.

---

## [99] source=multitask_sft_big

**USER:** Please set up epidecoder with my epitranscriptomic peaks in 'NOMO-1_ref_peaks.bed' and differential expression results from 'FTOi.txt'.

**ASSISTANT:** I have mapped your inputs for the `epidecoder` workflow:
- `NOMO-1_ref_peaks.bed`: BED file of modification event coordinates
- `FTOi.txt`: Tab-delimited differential gene expression data (containing ID, log2FC, and P-value columns)

The workflow will process these inputs using `bioconductor/epidecoder` and output the resulting `de_table`.

---

## [100] source=multitask_sft_big

**USER:** Configure the Simcyp Pbpk workflow for Ibuprofen (SMILES: CC(C)Cc1ccc(cc1)C(C)C(=O)O), MW 206.29 Da, logP 3.5, pKa 4.4, fu_plasma 0.01, blood_plasma_ratio 0.6, single oral dose of 400 mg in 20 Healthy subjects aged 18-65.

**ASSISTANT:** Extracted parameters for `Simcyp Pbpk`:
- `compound_name`: "Ibuprofen"
- `smiles`: "CC(C)Cc1ccc(cc1)C(C)C(=O)O"
- `mw_da`: 206.29
- `logP`: 3.5
- `pKa`: 4.4
- `fu_plasma`: 0.01
- `blood_plasma_ratio`: 0.6
- `dose_mg`: 400
- `route`: "oral"
- `population`: "Healthy"
- `n_subjects`: 20
- `age_range_years`: "18-65"

---

## [101] source=multitask_sft_big

**USER:** I am setting up the `regsplice_rna_seq_step_by_step` workflow. What mandatory data inputs do I need to prepare?

**ASSISTANT:** To execute `regsplice_rna_seq_step_by_step`, you must provide the following four inputs:
- `counts`: A matrix or data frame of RNA-seq read counts.
- `gene_IDs`: A vector containing the gene identifiers.
- `n_exons`: A vector specifying the number of exon bins per gene.
- `condition`: A vector defining the experimental conditions.

---

## [102] source=multitask_sft_big

**USER:** I ran deepTools bamCoverage with: bamCoverage -b treated_sample.bam -o treated_coverage.bw --outFileFormat bigwig. Which alignment file and output format were specified?

**ASSISTANT:** From the command, the input alignment file is `treated_sample.bam` (passed via `-b`) and the selected output format is `bigwig` (`treated_coverage.bw` passed via `-o` and `--outFileFormat`).

---

## [103] source=multitask_sft_big

**USER:** Extract the clustering threshold configuration from this command: Cluster.fragments input.fasta --percent 2 --diffs 3

**ASSISTANT:** The extracted parameter configurations for sequence difference thresholds are:
- `percent`: 2 (allows clustering if differences are ≤ 2% of the fragment length)
- `diffs`: 3

---

## [104] source=multitask_sft_big

**USER:** Please set up the rqc_advanced_qc_analysis workflow for these sequencing runs: '/data/sample1.fastq.gz' and '/data/sample2.fastq.gz'.

**ASSISTANT:** The input parameters for `rqc_advanced_qc_analysis` are configured as follows:
- `files`: ["/data/sample1.fastq.gz", "/data/sample2.fastq.gz"]

---

## [105] source=multitask_sft_big

**USER:** What is the default output format generated by ExtractSubBipNetwork, and what columns does it contain?

**ASSISTANT:** By default, ExtractSubBipNetwork exports a tabulated edge list with the format: 'source id edge type target id'.

---

## [106] source=multitask_sft_big

**USER:** I am configuring `Classify.otu` for my microbial community analysis. What is the functional difference between setting the output format to 'detail' versus 'simple'?

**ASSISTANT:** In `Classify.otu`, the `detail` format outputs taxonomic totals at each taxonomic level, whereas the `simple` format outputs only the highest taxonomic level classification.

---

## [107] source=multitask_sft_big

**USER:** What is the function of the side compounds file in ScopeNetwork?

**ASSISTANT:** In ScopeNetwork, the side compounds file is an optional parameter containing a list of ubiquitous side compounds that are considered available by default but are ignored during network expansion.

---

## [108] source=multitask_sft_big

**USER:** Set up a power calculation simulation for our trial: target power is 0.80, alpha is 0.025, endpoint is binary, expected treatment effect is 0.15, control rate is 0.20. We want 2 interim analyses, 1000 simulations, CV for heterogeneity is 0.3, enrichment fraction 0.4 with an enrichment multiplier of 1.2. We also have 50 historical patients with a historical rate of 0.18.

**ASSISTANT:** Extracted the following parameters for the `Rare Disease Power Calculator` workflow:
- `endpoint_type`: "binary"
- `treatment_effect`: 0.15
- `control_rate`: 0.20
- `alpha`: 0.025
- `power_target`: 0.80
- `n_interim_analyses`: 2
- `historical_n`: 50
- `historical_rate`: 0.18
- `heterogeneity_cv`: 0.3
- `enrichment_fraction`: 0.4
- `enrichment_effect_multiplier`: 1.2
- `n_simulations`: 1000

---

## [109] source=multitask_sft_big

**USER:** What mandatory inputs and parameters are declared for the `mygene` workflow?

**ASSISTANT:** The `mygene` workflow requires one mandatory data input slot named `input_files` (which expects count data). It does not declare any additional configurable parameters.

---

## [110] source=multitask_sft_big

**USER:** What are the input parameter requirements for the ucell_single_cell_experiment_workflow?

**ASSISTANT:** The workflow requires a mandatory input parameter named `sce` of type `rds_sce`, which corresponds to a SingleCellExperiment object containing single-cell expression data.

---

## [111] source=multitask_sft_big

**USER:** I want to export my subnetworks from ExtractSubBipNetwork as a JSON-based structure instead of the default edge list. What output format option should I select?

**ASSISTANT:** You should select the `JsonGraph` export format option.

---

## [112] source=multitask_sft_big

**USER:** Here is my configuration for running the epinem workflow:
`binary_effects_matrix.csv`: `./data/signaling_perturbation_matrix.csv`

Can you parse the inputs and specify what this file must contain?

**ASSISTANT:** Extracted parameter:
- `binary_effects_matrix.csv`: `./data/signaling_perturbation_matrix.csv`

Prerequisite specifications:
- Data type: binary matrix (CSV format)
- Matrix layout: Effect reporters must be rows, and single/double perturbations must be columns.
- Requirement: Mandatory (`optional: false`).

---

## [113] source=multitask_sft_big

**USER:** I want to perform association testing using the openstats workflow. My continuous phenotypic data is in `/experiments/cohort_continuous_measurements.csv`, which includes genotype, sex, batch, and weight columns. Please extract the input configuration.

**ASSISTANT:** The extracted input parameter for the `openstats` workflow is:
- `test_continuous.csv`: `/experiments/cohort_continuous_measurements.csv` (CSV file containing continuous phenotypic measurements, genotype, sex, batch, and weight columns).

---

## [114] source=multitask_sft_big

**USER:** We are setting up nf-core/crisprseq on our cluster. What are the expected input parameters and output files for this pipeline?

**ASSISTANT:** Inputs required by `nf-core/crisprseq` are:
- `reference_fasta`: The reference genome FASTA file.
- `analysis`: The analysis mode or configuration (e.g., targeted mode).

Key outputs generated include:
- `tsv_editing`: Tabular metrics detailing editing efficiency and indels.
- `bam`: Aligned sequence reads.
- `multiqc_report`: An aggregated quality control report.

---

## [115] source=multitask_sft_big

**USER:** Please set up the mdp workflow with my files: raw matrix 'expression_data.csv' and clinical annotations 'phenotype_data.csv'.

**ASSISTANT:** The parameters for the `mdp` workflow have been extracted:
- `expression_data.csv`: "expression_data.csv" (matrix of omic expression data with genes in rows)
- `phenotype_data.csv`: "phenotype_data.csv" (sample metadata containing 'Sample' and 'Class' columns)

---

## [116] source=multitask_sft_big

**USER:** I need to fix erroneous taxonomies in my QIIME 2 workflow. I want to change all instances of 'Bacteria;Proteobacteria' to 'Bacteria;Pseudomonadota' and 'Bacteria;Firmicutes' to 'Bacteria;Bacillota'. How do these map to qiime2 rescript edit-taxonomy arguments?

**ASSISTANT:** For `qiime2 rescript edit-taxonomy`, the parameters map as follows:
- `search-strings`: ['Bacteria;Proteobacteria', 'Bacteria;Firmicutes']
- `replacement-strings`: ['Bacteria;Pseudomonadota', 'Bacteria;Bacillota']

---

## [117] source=multitask_sft_big

**USER:** Inspect the following oligos configuration for Sffinfo and extract the defined components:
# Metagenomic Run A
forward GTGCCAGCMGCCGCGGTAA
reverse GGACTACHVGGGTWTCTAAT
barcode ACGTAGCT sample_01

**ASSISTANT:** Here are the extracted components from your oligos file:
- Ignored comment: `# Metagenomic Run A`
- Forward primer: `GTGCCAGCMGCCGCGGTAA`
- Reverse primer: `GGACTACHVGGGTWTCTAAT`
- Barcode sequence: `ACGTAGCT` (Sample identifier: `sample_01`)

---

## [118] source=multitask_sft_big

**USER:** Please extract the relevant workflow inputs from this protocol: starting dose of 15 mg, target DLT rate of 0.20, clearance of 3.2 L/h, volume of distribution of 50 L, and absorption rate constant of 1.1 /h.

**ASSISTANT:** Based on the Clinical Trial Simulation workflow parameters, the extracted inputs are:
- starting_dose_mg: 15
- DLT_rate_target: 0.20
- pk_CL_L_h: 3.2
- pk_Vd_L: 50
- pk_ka_h: 1.1

---

## [119] source=multitask_sft_big

**USER:** I am configuring Blobtools view for my metagenomic assembly. What options can I pass to the taxrule parameter, and what is selected by default?

**ASSISTANT:** For `Blobtools view`, the supported values for the `taxrule` parameter are `"bestsum"` and `"bestsumorder"`. The default value is `bestsum`.

---

## [120] source=multitask_sft_big

**USER:** Please set up `geneoverlap_self_comparison_overlap` using my gene set file 'pathway_genes.rds' and assume a genomic background size of 20,000 genes.

**ASSISTANT:** Extracted parameters for `geneoverlap_self_comparison_overlap`:
- `set1.rds`: 'pathway_genes.rds'
- `background_size`: 20000

---

## [121] source=multitask_sft_big

**USER:** How does `bed_window` modify the coordinates of an input interval given a windowsize?

**ASSISTANT:** `bed_window` calculates the middle point of each input genomic interval and then extends outward by `windowsize / 2` base pairs in both directions (upstream and downstream), creating a centered window of length equal to `windowsize`.

---

## [122] source=multitask_sft_big

**USER:** I am preparing inputs for karyoploter. Which tools and output files will be involved when I provide the gains and losses tables?

**ASSISTANT:** The workflow uses bioconductor/karyoploter, bioconductor/knitr, bioconductor/magrittr, and bioconductor/regioner. Upon processing your gains and losses inputs, it produces 'copy_number_segments' and 'visualizations'.

---

## [123] source=multitask_sft_big

**USER:** Can I supply multi-class labels (e.g., classes 0, 1, and 2) to the trainClass parameter in the iterativebma workflow?

**ASSISTANT:** No. The `trainClass` parameter specifically requires a vector of binary class labels (0/1) corresponding to the training samples, as the workflow is designed for binary classification.

---

## [124] source=multitask_sft_big

**USER:** What input slots and underlying tool dependencies are specified for the SEtools Nextflow workflow?

**ASSISTANT:** The SEtools workflow defines a required data input slot named 'input_files' (accepting count_data). Its underlying Bioconductor tool dependencies are 'bioconductor/setools' and 'bioconductor/summarizedexperiment'.

---

## [125] source=multitask_sft_big

**USER:** Extract the input requirements from this instruction: 'Process alignment_sample.maf using mafAddIRows ensuring it contains only the single reference target sequence.'

**ASSISTANT:** - **Tool**: mafAddIRows
- **Input file**: `alignment_sample.maf`
- **Format**: MAF (Multiple Alignment Format)
- **Prerequisite constraint**: Single target sequence only

---

## [126] source=multitask_sft_big

**USER:** Configure epialleler_long_read_methylation_reporting with our sequenced file located at /data/ont_run/sample_cpg_calls.bam.

**ASSISTANT:** Extracted parameter configuration:
- `longread.bam`: "/data/ont_run/sample_cpg_calls.bam"

---

## [127] source=multitask_sft_big

**USER:** Run reverse complement on this sequence: 5'-ATGCGATCG-3'. What parameters does Biomni: Reverse Complement require?

**ASSISTANT:** The tool `Biomni: Reverse Complement` requires a single parameter: the input DNA sequence (in this case, `ATGCGATCG`).

---

## [128] source=multitask_sft_big

**USER:** In the magar_methqtl_comparison workflow, is the data input 'reduced_methQTL' required or optional?

**ASSISTANT:** Based on the workflow parameter specifications, 'reduced_methQTL' is an optional data input defined as the 'first methQTL input dataset'.

---

## [129] source=multitask_sft_big

**USER:** Here is my R setup: `all_ids <- c('GAPDH', 'TP53', 'ACTB', 'EGFR')` and `sig_ids <- c('TP53', 'EGFR')`. Map these to the expected input parameters for the goseq workflow.

**ASSISTANT:** The inputs map as follows:
- `assayed.genes`: `c('GAPDH', 'TP53', 'ACTB', 'EGFR')` (character vector of all genes assayed)
- `de.genes`: `c('TP53', 'EGFR')` (character vector of differentially expressed genes)

---

## [130] source=multitask_sft_big

**USER:** I am configuring the single_cell/multiome_rna_atac workflow. I want to set the ATAC QC cutoffs to 1000 minimum fragments and a TSS enrichment of 5, while enabling peak-to-gene linkage. Which parameters map to these options?

**ASSISTANT:** Based on the workflow schema, set `min_atac_fragments` to 1000, `tss_enrichment_min` to 5, and set `link_peaks_to_genes` to true (or enable it).

---

## [131] source=multitask_sft_big

**USER:** I have an artifact named `dist.qza` and want to run `qiime2 stats wilcoxon-srt-facet`. Which input field should I assign it to?

**ASSISTANT:** You should set the `distribution` parameter to your artifact `dist.qza` and then execute the tool.

---

## [132] source=multitask_sft_big

**USER:** I have prepared three matrices: `gene1_snps.csv` for the SNPs in Gene 1, `gene2_snps.csv` for the SNPs in Gene 2, and `phenotype.csv` indicating case vs. control status. How do these map to the inputs of the genegeneinter workflow?

**ASSISTANT:** The parameters map directly to the inputs of `genegeneinter` as follows:
- `gene1_snps.csv`: `gene1_snps.csv` (genotype matrix for SNPs in Gene 1)
- `gene2_snps.csv`: `gene2_snps.csv` (genotype matrix for SNPs in Gene 2)
- `phenotype.csv`: `phenotype.csv` (case-control status vector)

---

## [133] source=multitask_sft_big

**USER:** I am configuring the Nextflow workflow 'drugTargetInteractions'. What inputs and parameters does it accept?

**ASSISTANT:** The 'drugTargetInteractions' workflow declares one mandatory data input slot named 'input_files' (which accepts count_data). It does not declare additional configurable workflow parameters ('parameters': []).

---

## [134] source=multitask_sft_big

**USER:** Which tools and output file formats are defined in the rbowtie workflow?

**ASSISTANT:** The rbowtie workflow utilizes the tools 'bioconductor/rbowtie' and 'bioconductor/biocmanager'. Its generated outputs are provided in 'table/csv', 'plot/pdf', and 'object/rds' formats.

---

## [135] source=multitask_sft_big

**USER:** What are the outputs and underlying tools specified for the kmcut_batch_cox_regression workflow?

**ASSISTANT:** The output of `kmcut_batch_cox_regression` is `enrichment_results`. The workflow has no external tools specified (`tools: None`).

---

## [136] source=multitask_sft_big

**USER:** In ExternalCalibration, how should I specify scan levels if I want scans with other levels to remain unchanged?

**ASSISTANT:** Provide them as a space-separated list. If any of the list items contain spaces, be sure to enclose them in single quotes.

---

## [137] source=multitask_sft_big

**USER:** Which input parameters are defined for the snprelate_identity_by_state_clustering workflow?

**ASSISTANT:** The workflow defines two data inputs: 'genofile' (an open GDS file handle, mandatory) and 'pop_code' (population code data).

---

## [138] source=multitask_sft_big

**USER:** Configure the PMIDs to PubTator tool for my literature dataset. I only care about pulling out chemical names and associated diseases from the abstracts.

**ASSISTANT:** Based on your request, configure `PMIDs to PubTator` with the selected term categories:
- Selected categories: `["Chemical", "Disease"]`
- Excluded categories: `["Gene", "Mutation", "Species"]`

---

## [139] source=multitask_sft_big

**USER:** Please run the experimental edge overlay workflow for the p53 pathway hsa04115 using data from the PC3 prostate cancer line and the HA1E cell line.

**ASSISTANT:** Extracted parameters for `kegglincs_overlay_experimental_edge_data`:
- KEGG pathway ID string: `"hsa04115"`
- Cell line 1: `"PC3"`
- Cell line 2: `"HA1E"`

These will generate the specified pathway results and visualizations.

---

## [140] source=multitask_sft_big

**USER:** I am configuring gatk4 Mutect2, but my downstream filtering tool cannot read compressed files. Should I select the gzipped output option?

**ASSISTANT:** No, you should leave the gzipped output option unchecked. While gzipped output is generally preferable, uncompressed output is necessary when your downstream tool cannot handle gzipped files.

---

## [141] source=multitask_sft_big

**USER:** I have sample log files generated during Rbec execution that I might pass to rbec_detect_contaminants. Is there an input parameter for these logs, and is it mandatory?

**ASSISTANT:** Yes, the parameter is 'log_path', which accepts paths to log files generated by Rbec for each sample. It is an optional data input ('optional': true).

---

## [142] source=multitask_sft_big

**USER:** Please set up the wppi workflow using my target list: TP53, BRCA1, and CHEK2.

**ASSISTANT:** I have configured the input for the wppi workflow:
- `genes_interest`: c("TP53", "BRCA1", "CHEK2")

---

## [143] source=multitask_sft_big

**USER:** What is the constraint on the maximum matrix size parameter when configuring 'Cell types - Downsample Cells (RNA)'?

**ASSISTANT:** The tool documentation provides an explicit warning regarding the maximum matrix size parameter: do not exceed the default value.

---

## [144] source=multitask_sft_big

**USER:** Run opencyto_interactive_gating on my processed file located at '/experiments/flow/sample_comp_trans.rds'.

**ASSISTANT:** Parameter extracted for opencyto_interactive_gating:
- gs: /experiments/flow/sample_comp_trans.rds (pre-compensated and transformed GatingSet RDS object).

---

## [145] source=multitask_sft_big

**USER:** When running Classify.seqs in my metagenomics pipeline, I want the summary output to report relative abundances instead of raw counts. Which option should I enable?

**ASSISTANT:** You should set the `relabund` parameter. In `Classify.seqs`, specifying `relabund` indicates that you want the summary files to report relative abundances rather than raw abundances.

---

## [146] source=multitask_sft_big

**USER:** I am configuring the nextclade data manager to download custom datasets not present in the default dropdown. Please download sars-cov-2 and hmpv.

**ASSISTANT:** Identified the following custom dataset names for download via the nextclade data manager:
- Dataset names: `sars-cov-2, hmpv`

These will be passed as a comma-separated list into the dataset name parameter.

---

## [147] source=multitask_sft_big

**USER:** I am configuring aurora_fastqc for an RNA-seq run. Here is my setup: custom adapters list located at `/data/adapters/custom_truseq.tsv`, reads from sample A1. Please extract the adapter file parameter requirements.

**ASSISTANT:** Based on the specification for `aurora_fastqc`:
- Adapter File: `/data/adapters/custom_truseq.tsv`
- File Structure Requirement: Must contain tab-delimited named adapter pairs (`name[tab]sequence`), with optional `#` comment lines.

---

## [148] source=multitask_sft_big

**USER:** I am configuring the netsam_id_mapping_to_symbols workflow. My inputs are a gene ID file named exampleGeneList.txt and an edge-list network file exampleNetwork_nonsymbol.txt. Do these satisfy the data inputs?

**ASSISTANT:** Yes. 'exampleGeneList.txt' matches the required input slot for the gene ID list, and 'exampleNetwork_nonsymbol.txt' matches the required input slot for the non-symbol network edge-list.

---

## [149] source=multitask_sft_big

**USER:** What are the input channels, output channels, and underlying tools for nf-core/bed_scatter_bedtools?

**ASSISTANT:** For nf-core/bed_scatter_bedtools:
- Input channel: ch_bed
- Output channel: scattered_beds
- Underlying tool: bedtools/split

---

## [150] source=multitask_sft_big

**USER:** Please set up katdetectr_non_standard_genome_kataegis_detection with my input file: /data/samples/variants_scaffolds.rds.

**ASSISTANT:** The input parameter has been extracted for `katdetectr_non_standard_genome_kataegis_detection`:

```json
{
  "data_inputs": [
    {
      "name": "genomic_variants.rds",
      "value": "/data/samples/variants_scaffolds.rds"
    }
  ]
}
```

---

## [151] source=multitask_sft_big

**USER:** Please configure the Snakemake tool to run my analysis using the file `rules/Snakefile` located in my project directory.

**ASSISTANT:** Here is the configuration based on your input:

- **Tool**: Snakemake (`workflow_mode`)
- **Input Snakefile**: `rules/Snakefile`

---

## [152] source=multitask_sft_big

**USER:** I am running Validate Variants on my WGS VCF file. I want the execution to log any formatting and genotype inconsistencies as warnings rather than crashing the pipeline. Which parameter should I set?

**ASSISTANT:** Set the parameter `warnOnErrors` to `true`. This instructs Validate Variants to emit warnings upon encountering validation errors instead of terminating the run.

---

## [153] source=multitask_sft_big

**USER:** How should I configure the hamming distance parameter in STR detection (Next Gen Mappers) if I only want simple STRs returned?

**ASSISTANT:** To return only simple STRs, set the hamming distance to zero (0). Setting a hamming distance greater than zero will detect both simple and interrupted STRs.

---

## [154] source=multitask_sft_big

**USER:** What file format is expected for the query input in chipseeker_peak_overlap_significance_and_geo_mining under the `files` parameter?

**ASSISTANT:** The `files` parameter expects a Query BED file (e.g., `files[[5]]`).

---

## [155] source=multitask_sft_big

**USER:** I need to fetch common MS contaminants for my proteomics experiment using Protein Database Downloader. Which source should I select?

**ASSISTANT:** For downloading common mass spectrometry contaminants, set the database source parameter to `cRAP`.

---

## [156] source=multitask_sft_big

**USER:** I have two files for my LC-MS alignment run: `cohort_a_peaks.tsv` and `cohort_b_peaks.tsv`. Both contain m/z, RT, and intensity values. How should these be mapped into the metabcombiner workflow inputs?

**ASSISTANT:** Map the inputs as follows:
- `dataset1.txt`: `cohort_a_peaks.tsv` (tab-delimited text file containing m/z, RT, and sample abundance columns for dataset X)
- `dataset2.txt`: `cohort_b_peaks.tsv` (tab-delimited text file containing m/z, RT, and sample abundance columns for dataset Y)

---

## [157] source=multitask_sft_big

**USER:** I'm running CD-HIT-EST on metagenomic assembled contigs at 0.95 sequence similarity threshold. Which word size parameter setting is suggested based on the guidelines?

**ASSISTANT:** For sequence identity thresholds between 0.90 and 1.0 (such as your target of 0.95), the recommended word size is 8, 9, or 10.

---

## [158] source=multitask_sft_big

**USER:** Please set up the vsn pipeline for my study. For the inputs, use my unnormalised microarray dataset 'kidney_unnorm_eset.RData' as kidney and 'lymphoma_singlecolor_eset.RData' as lymphoma.

**ASSISTANT:** I have mapped your data inputs for the 'vsn' workflow:
- `kidney`: kidney_unnorm_eset.RData (ExpressionSet containing unnormalised microarray data)
- `lymphoma`: lymphoma_singlecolor_eset.RData (ExpressionSet containing multi-array single-colour data)

This will produce the normalized_data output using the Bioconductor vsn suite.

---

## [159] source=multitask_sft_big

**USER:** I want to run the hummingbird workflow. What exact data inputs does it take?

**ASSISTANT:** The `hummingbird` workflow requires five inputs:
- `normM`: matrix of methylated reads for the control group
- `normUM`: matrix of unmethylated reads for the control group
- `abnormM`: matrix of methylated reads for the case group
- `abnormUM`: matrix of unmethylated reads for the case group
- `pos`: vector of genomic positions of CpGs

---

## [160] source=multitask_sft_big

**USER:** Please fetch the ARCHS4 RNA-seq information for the gene BRCA1 using the Biomni tool.

**ASSISTANT:** Extracted parameter for Biomni: Get Rna Seq Archs4:
- gene name: "BRCA1"

---

## [161] source=multitask_sft_big

**USER:** What input file is expected by the fella workflow, and which underlying Bioconductor/R packages does it rely on?

**ASSISTANT:** The workflow requires 'list_of_compounds.txt' (a character vector of affected KEGG compound IDs) as its data input. The underlying packages used are bioconductor/fella, bioconductor/keggrest, bioconductor/igraph, and bioconductor/magrittr.

---

## [162] source=multitask_sft_big

**USER:** Please set up the csar workflow using sample_reads.tsv containing our treatment ChIP-seq reads, control_reads.tsv for the mock control, and genes.gff for our annotation.

**ASSISTANT:** I have extracted the following inputs for the 'csar' workflow:
- sample_reads.tsv: 'sample_reads.tsv'
- control_reads.tsv: 'control_reads.tsv'
- genes.gff: 'genes.gff'

These will be processed by bioconductor/csar to generate the expected visualizations.

---

## [163] source=multitask_sft_big

**USER:** I want to set up the mitch workflow. Could you list the required input files and the Bioconductor packages it relies on?

**ASSISTANT:** For the `mitch` workflow, the inputs are:
- `ReactomePathways.gmt`: A gene sets file in GMT format.
- `rna`: Differential expression data frame generated from edgeR.
- `k9a`: Another differential expression data frame generated from edgeR.

The workflow relies on the following Bioconductor tools: `bioconductor/mitch`, `bioconductor/hgnchelper`, and `bioconductor/stringi`.

---

## [164] source=multitask_sft_big

**USER:** Set up rbowtie_spliced_alignment_splicemap with reference genome directory 'ref_genome/' and read file 'sample_reads.fastq' (reads are 100bp).

**ASSISTANT:** The inputs for `rbowtie_spliced_alignment_splicemap` are mapped as follows:
- `refDir`: `ref_genome/` (FASTA reference genome directory/file)
- `readsFiles`: `sample_reads.fastq` (FASTQ/FASTA short read files, meeting the >= 50bp requirement)

The workflow outputs will include `table/csv`, `plot/pdf`, and `object/rds`.

---

## [165] source=multitask_sft_big

**USER:** Which tools and data inputs are configured for the `omicsprint` workflow?

**ASSISTANT:** The `omicsprint` workflow utilizes `bioconductor/omicsprint`, `bioconductor/geoquery`, and `bioconductor/summarizedexperiment`.

Its data inputs include:
- `x`: Genotype matrix of the first omic dataset (rows are SNPs, columns are samples; required).
- `y`: Optional genotype matrix of a second omic dataset (rows are SNPs, columns are samples).
- `relations`: Optional data frame of expected relationships.

---

## [166] source=multitask_sft_big

**USER:** I want to supply my gene count file `expression_data.csv` to cemitool_diagnostic_and_troubleshooting_analysis. What outputs will be generated?

**ASSISTANT:** Upon processing `expression_data.csv`, the workflow will generate two primary outputs:
1. `network_graph`
2. `visualizations`

---

## [167] source=multitask_sft_big

**USER:** What input databases do I need to supply to run `Mmseqs Createtsv`?

**ASSISTANT:** You need to provide three databases:
1. A query database
2. A target database
3. A result database

---

## [168] source=multitask_sft_big

**USER:** I need to configure gffread to map sequence identifiers. What format does the chr_replace parameter expect?

**ASSISTANT:** The `chr_replace` parameter requires a 2-column tab-delimited file containing a reference (genomic) sequence replacement table.

---

## [169] source=multitask_sft_big

**USER:** Please set up rcistarget with my candidate set at `/data/differentially_expressed_genes.txt` and the motif database at `/databases/hg38_motif_rankings.db`.

**ASSISTANT:** Here are the extracted parameters and inputs for the `rcistarget` workflow:
- `gene_list.txt`: `/data/differentially_expressed_genes.txt`
- `motif_rankings.db`: `/databases/hg38_motif_rankings.db`

---

## [170] source=multitask_sft_big

**USER:** I am working with Constructive Solid Geometry and need to create a sphere primitive using the 'Create shape' tool. What parameter option should I specify?

**ASSISTANT:** Set the primitive shape parameter to 'Sphere'. The 'Create shape' tool allows you to select from Box, Cone, Cylinder, and Sphere.

---

## [171] source=multitask_sft_big

**USER:** Please set up the scale4c workflow with my Basic4Cseq table file located at '/data/raw_fragments.csv' and my viewpoint coordinates file at '/data/viewpoint_coords.tsv'.

**ASSISTANT:** Here are the extracted parameters and input mappings for the `scale4c` workflow:

- `liverData.csv`: `/data/raw_fragments.csv`
- `vp.txt`: `/data/viewpoint_coords.tsv`

---

## [172] source=multitask_sft_big

**USER:** I have t-statistics for my differentially expressed genes with gene symbols as identifiers. How should I supply this to ctrap_predict_targeting_drugs_and_descriptors?

**ASSISTANT:** You should pass this dataset to the required input parameter `diffExprStat`. It must be structured as a named numeric vector of t-statistics from your differential expression analysis, where the vector names correspond to gene symbols.

---

## [173] source=multitask_sft_big

**USER:** I have two files ready for integrative analysis: 'cohort_mcsea_gsea.rds' (output from mCSEATest) and 'counts_normalized.tsv' containing expression values where rows represent genes and columns represent samples. How do these map to mcsea_methylation_expression_integration?

**ASSISTANT:** They map to the workflow's input parameters as follows:
- `mCSEATest_results.rds`: cohort_mcsea_gsea.rds (GSEA results list from mCSEATest)
- `gene_expression.matrix`: counts_normalized.tsv (Matrix of gene expression values with genes as rows and samples as columns)

---

## [174] source=multitask_sft_big

**USER:** I am configuring Tab2Sbml. How do I prevent it from collapsing all my metabolites into just a single default compartment?

**ASSISTANT:** You must activate the option "Create compartment from metabolite suffixes". When deactivated, Tab2Sbml creates only one single default compartment.

---

## [175] source=multitask_sft_big

**USER:** I have runParameters.xml from an RTA sequencing run. Can basecallqc_basecall_qc_analysis accept this file, and is it a required input?

**ASSISTANT:** Yes, `basecallqc_basecall_qc_analysis` accepts `runParameters.xml` as a data input for RTA run parameters. It is an optional input (`optional: true`), so the workflow can execute even if it is not provided.

---

## [176] source=multitask_sft_big

**USER:** Please set up rnaseqsamplesize_user_prior_data_estimation with my file 'pilot_counts_matrix.tsv', which contains raw counts with genes along rows and samples in columns.

**ASSISTANT:** I have mapped your input parameters for `rnaseqsamplesize_user_prior_data_estimation`:
- `dataMatrix`: "pilot_counts_matrix.tsv"

---

## [177] source=multitask_sft_big

**USER:** We are preparing to run cqn_edger_differential_expression. Here are our files: raw read counts in 'count_matrix.tsv', transcript lengths in 'gene_lengths.tsv', GC percentage values in 'gc_content.tsv', library sizes in 'size_factors.tsv', and condition metadata in 'sample_groups.tsv'. Could you confirm how these map to the required workflow inputs?

**ASSISTANT:** All required input files for `cqn_edger_differential_expression` are correctly matched:
- `count_matrix.tsv`: raw count matrix
- `gene_lengths.tsv`: vector of gene lengths
- `gc_content.tsv`: vector of GC content values
- `size_factors.tsv`: vector of sample sequencing depths
- `sample_groups.tsv`: experimental design grouping

---

## [178] source=multitask_sft_big

**USER:** Set up the inputs for scmet_differential_methylation_analysis using 'donor1_meth.csv' for Group A, 'donor2_meth.csv' for Group B, and include 'donor1_cov.csv' for Group A covariates.

**ASSISTANT:** Here are the extracted input parameters for `scmet_differential_methylation_analysis`:
- `group_A_methylation.csv`: donor1_meth.csv
- `group_B_methylation.csv`: donor2_meth.csv
- `group_A_covariates.csv`: donor1_cov.csv
- `group_B_covariates.csv`: None (not provided)

---

## [179] source=multitask_sft_big

**USER:** From the following request: 'Run tvtb with variants chr15.phase3_integrated.vcf.gz and sample metadata integrated_samples.txt', identify the required input parameters.

**ASSISTANT:** The extracted input parameters are:
- VCF input: `chr15.phase3_integrated.vcf.gz` (VCF file containing genetic variants)
- Sample phenotype input: `integrated_samples.txt` (Tab-delimited text file containing sample phenotypes)

---

## [180] source=multitask_sft_big

**USER:** What mandatory inputs are required to run the genemeta workflow?

**ASSISTANT:** The `genemeta` workflow requires four inputs:
- `Split1`: ExpressionSet for study 1
- `Split2`: ExpressionSet for study 2
- `Split1.ER`: Binary phenotype vector for study 1
- `Split2.ER`: Binary phenotype vector for study 2

---

## [181] source=multitask_sft_big

**USER:** I want to feed my file 'sample_spatial.rds' into spanorm_seurat_workflow. How should the input parameter be specified?

**ASSISTANT:** The workflow expects an input named `Seurat` with file type `rds`. The file must be a Seurat object containing raw counts and spatial coordinates in its metadata.

---

## [182] source=multitask_sft_big

**USER:** I want to run the mzML Schema Validator on my metabolomics MS runs and make sure they conform to either the 1.1.0 or 1.1.1 schema specifications. What setting does the tool require for this validation logic?

**ASSISTANT:** The tool allows you to select the XML schema definition (XSD) versions to validate against. By selecting both schema versions, the tool will evaluate the file such that it is considered valid if it matches against any of the selected versions.

---

## [183] source=multitask_sft_big

**USER:** I have prepared 'estimates.csv' containing log-fold changes and 'standard_errors.csv' with the corresponding errors. Can you confirm if these match the inputs expected by `lapmix`?

**ASSISTANT:** Yes, those match the required inputs. The `lapmix` workflow expects `estimates.csv` (type: matrix/vector of contrast estimates/log-fold changes) and `standard_errors.csv` (type: matrix/vector of standard errors), both of which are required to run the Laplace mixture model.

---

## [184] source=multitask_sft_big

**USER:** I have an R data object `de_res_air`. What specific columns or vectors from `de_res_air` must be supplied to run `opweight_decomposed_opw`?

**ASSISTANT:** The `opweight_decomposed_opw` workflow requires two vectors from `de_res_air`:
1. `de_res_air$pvalue`: a vector of p-values from differential expression analysis.
2. `de_res_air$baseMean`: a vector of base mean expression values used as filter statistics.

---

## [185] source=multitask_sft_big

**USER:** What input and output data types are supported by the mrna_therapeutic_design pipeline?

**ASSISTANT:** The `mrna_therapeutic_design` workflow takes a `string` (representing a Protein AA sequence or ORF) as input and outputs results in `json`, `csv`, and `txt` formats.

---

## [186] source=multitask_sft_big

**USER:** Which configuration option is required to set the random seed when using Fq Subsample?

**ASSISTANT:** For Fq Subsample, you must specify the seed using the `--seed` argument within `ext.args`.

---

## [187] source=multitask_sft_big

**USER:** How should my input files be formatted before feeding them into the `massir` workflow?

**ASSISTANT:** The `massir` workflow expects two mandatory CSV files:
1. `expression_data.csv`: Normalized and log-transformed probe values with samples as columns and probes as rows.
2. `y_probes.csv`: Y chromosome probe identifiers listed as row names.

---

## [188] source=multitask_sft_big

**USER:** I am switching LocARNA Pairwise Aligner into local alignment mode. Are there any specific heuristic settings I need to adjust?

**ASSISTANT:** Yes. When running LocARNA Pairwise Aligner in local alignment mode, you usually need to turn off the 'max-diff' heuristic, which controls the maximal difference for alignment traces.

---

## [189] source=multitask_sft_big

**USER:** I have prepared my normalized log2 expression matrix saved in `olf.data` and the accompanying sample annotation data frame with Treatment and Batch variables stored as `olf.info`. Can you extract the parameters needed to initialize the harman workflow?

**ASSISTANT:** Here are the extracted parameters for the harman workflow:
- `olf.data`: `olf.data` (matrix of normalized log2 expression values)
- `olf.info`: `olf.info` (data.frame containing Treatment and Batch factors)

Both required inputs are present and properly formatted to proceed with batch correction and downstream visualization.

---

## [190] source=multitask_sft_big

**USER:** I want to run tilt alignment on my tilt series. Please configure it to use AreTomo2 with patch alignment enabled, and set the tilt axis angle to 85.5 degrees.

**ASSISTANT:** Here are the extracted parameters for the Tilt Alignment workflow:
- `alignment_method`: AreTomo2
- `patch_alignment`: true
- `tilt_axis_angle`: 85.5

---

## [191] source=multitask_sft_big

**USER:** What input file and specific parameters are required to run the sizepower workflow?

**ASSISTANT:** The `sizepower` workflow requires the input file `pilot_parameters.txt`, which contains estimated parameters: `G0`, `ER0`, `power`, `absMu1`, `sigmad`, and `n`.

---

## [192] source=multitask_sft_big

**USER:** I am configuring toolfactory to build a tool. Can I name my Toolshed repository 'My-RNASeq-Tool'?

**ASSISTANT:** No. The Toolshed repository name in toolfactory must consist strictly of lowercase letters, digits, and underscores. Uppercase letters and hyphens are not permitted, and you should choose the name carefully to prevent namespace clashes with other tool authors.

---

## [193] source=multitask_sft_big

**USER:** What mandatory input parameter is required by the scrapper_modular_sc_rna_seq_analysis workflow, and what format must it have?

**ASSISTANT:** The mandatory input is `sce.z`, which must be a `SingleCellExperiment` object containing raw count data stored in RDS format (`type: rds_sce`).

---

## [194] source=multitask_sft_big

**USER:** What inputs are required to run the enmix_downstream_analysis workflow?

**ASSISTANT:** The `enmix_downstream_analysis` workflow requires the following data inputs:
- `beta`: A preprocessed beta value matrix (type: matrix, mandatory).
- `mdat`: Data input for methylation analysis.

---

## [195] source=multitask_sft_big

**USER:** Run the fast feature selection pipeline on my single-cell matrix located at 'matrix_counts.rds' assuming 8 distinct cell types.

**ASSISTANT:** Here are the extracted parameters for `feast_fast_feature_selection`:

```json
{
  "data_inputs": {
    "Y": "matrix_counts.rds",
    "k": 8
  }
}
```

---

## [196] source=multitask_sft_big

**USER:** What inputs, tools, and outputs are defined for the raids workflow?

**ASSISTANT:** The raids workflow requires three inputs: 'ex1.vcf.gz' (gzipped donor VCF with GT, AD, and DP fields), 'ex1_good_small_1KG.gds' (Population Reference GDS file), and 'ex1_good_small_1KG_Annot.gds' (Population Reference SNV Annotation GDS file). It utilizes bioconductor/raids, bioconductor/snprelate, bioconductor/gdsfmt, and bioconductor/knitr, and outputs 'table/csv', 'plot/pdf', and 'object/rds'.

---

## [197] source=multitask_sft_big

**USER:** Configure the inputs for nipalsmcia_out_of_sample_prediction using these files:
- Training blocks: train_blocks.rds
- Test blocks: test_blocks.rds
- Training annotations: train_meta.tsv
- Test annotations: test_meta.tsv

**ASSISTANT:** Here is the parameter mapping for `nipalsmcia_out_of_sample_prediction`:
- `data_blocks_train`: train_blocks.rds
- `data_blocks_test`: test_blocks.rds
- `metadata_train`: train_meta.tsv
- `metadata_test`: test_meta.tsv

---

## [198] source=multitask_sft_big

**USER:** I am configuring a run using my normalized expression matrix 'counts_norm.mat' (genes in rows, samples in columns) and sample table 'metadata_samples.csv' with columns for batch, tissue, and donor IDs. How do these map to the randrotation_mixed_model_batch_correction inputs and what output will be produced?

**ASSISTANT:** The files map directly to the workflow inputs as follows:
- `edata`: 'counts_norm.mat' (matrix of gene expression data with features as rows and samples as columns)
- `pdata`: 'metadata_samples.csv' (dataframe containing batch, tissue, and individual/replicate identifiers)

The workflow will output `de_table`, which contains the differential expression analysis results.

---

## [199] source=multitask_sft_big

**USER:** What output file formats does `fcrn_antibody_pk` produce once it completes simulation?

**ASSISTANT:** The `fcrn_antibody_pk` workflow generates outputs across five distinct formats:
- `sdf`
- `csv_scores`
- `tsv_admet`
- `tsv_pk`
- `pdf_report`

---

## [200] source=multitask_sft_big

**USER:** I need to set up the MERFISH Spatial Analysis workflow. I have my images in './raw_images', transcript spots in 'transcripts.csv', segmentation boundaries in 'cells.csv', on the 'MERFISH' platform with 'watershed' segmentation, expecting 5000 cells across 250 genes. Can you extract these into the workflow inputs?

**ASSISTANT:** Here are the extracted input parameters for `single_cell/merfish_spatial_analysis`:
- `image_dir`: './raw_images'
- `detected_transcripts`: 'transcripts.csv'
- `cell_boundaries_csv`: 'cells.csv'
- `platform`: 'MERFISH'
- `n_genes`: 250
- `n_cells_expected`: 5000
- `segmentation_method`: 'watershed'

---

## [201] source=multitask_sft_big

**USER:** I have a single-cell dataset stored in 'pbmc_control.h5ad' and I want to simulate the response after knocking out 'TP53' using state_perturbation_prediction. Please extract the inputs for this pipeline.

**ASSISTANT:** Here are the extracted workflow inputs for `state_perturbation_prediction`:
- Input file: `pbmc_control.h5ad` (format: h5ad)
- Perturbation name: `TP53`

The workflow will run STATE and produce predicted expression profiles and DEGs in h5ad, csv, and json formats.

---

## [202] source=multitask_sft_big

**USER:** I am preparing the inputs for the `motifstack_ggplot2_motif_plotting` workflow. What mandatory data input matrix does it require, and what format should it be in?

**ASSISTANT:** According to the workflow specifications, it requires `bin_SOLEXA.pcm`, which is a non-optional matrix input described as a Position Count Matrix text file (`type: matrix`, `optional: false`).

---

## [203] source=multitask_sft_big

**USER:** Here is my docking configuration: receptor_pdb_file='protein.pdb', smiles_list=['CC(=O)Oc1ccccc1C(=O)O'], box_center=[10.5, 12.0, -4.2], box_size=[20.0, 20.0, 20.0], ncpu=8, exhaustiveness=16, n_poses=9, reference_ligand_smiles='CC(=O)O', randomSeed=42. Please map these to the inputs for docking_autodock_vina.

**ASSISTANT:** The parameters map directly to the inputs for the `docking_autodock_vina` workflow:
- `receptor_pdb_file`: 'protein.pdb'
- `smiles_list`: ['CC(=O)Oc1ccccc1C(=O)O']
- `box_center`: [10.5, 12.0, -4.2]
- `box_size`: [20.0, 20.0, 20.0]
- `ncpu`: 8
- `exhaustiveness`: 16
- `n_poses`: 9
- `reference_ligand_smiles`: 'CC(=O)O'
- `randomSeed`: 42
Output: `pdbqt`.

---

## [204] source=multitask_sft_big

**USER:** What are the required input datasets for executing the derfinder workflow?

**ASSISTANT:** The required data inputs are:
1. `files`: BAM or BigWig files containing raw coverage data.
2. `brainspanPheno`: A phenotype table containing sample covariates.

---

## [205] source=multitask_sft_big

**USER:** What output files will be generated by the `flowcore_gatingset_hierarchical_analysis` pipeline?

**ASSISTANT:** The workflow outputs three types of files: `table/csv`, `plot/pdf`, and `object/rds`.

---

## [206] source=multitask_sft_big

**USER:** What output files can I expect after executing `gostats_association_unsupported_organism`?

**ASSISTANT:** The workflow produces three outputs: `de_table`, `enrichment_results`, and `pathway_results`.

---

## [207] source=multitask_sft_big

**USER:** In the Collect.shared tool, what is the default sampling setting and how do I specify a 10% sampling frequency?

**ASSISTANT:** By default, Collect.shared is set to 100. To specify a 10% sampling frequency, set freq=0.10 (where freq represents a percentage of the number of sequences).

---

## [208] source=multitask_sft_big

**USER:** Please set up wpm_eset_msnset_to_plate_map using my file sample_expression_msnset.rds.

**ASSISTANT:** The parameter configuration for wpm_eset_msnset_to_plate_map is:
- my_MSnSet_object: "sample_expression_msnset.rds"

---

## [209] source=multitask_sft_big

**USER:** Is the 'sogin.fasta' sequence input mandatory when executing the otubase_taxonomic_classification_analysis workflow?

**ASSISTANT:** No, 'sogin.fasta' is marked as optional (`optional: true`) in the workflow inputs.

---

## [210] source=multitask_sft_big

**USER:** What are the default cutoff values for ignoring pairwise distances in Cluster.classic across different clustering methods?

**ASSISTANT:** In Cluster.classic, the default cutoff distance to ignore pairwise distances is 0.03 for the 'opti', 'agc', and 'dgc' methods, and 0.15 for all other clustering methods.

---

## [211] source=multitask_sft_big

**USER:** We want to run pcamethods_pca_diagnostics_validation. We have an incomplete matrix file 'imputed_metabolites_missing.tsv' and our reference complete matrix 'metabolites_reference_full.tsv'. Please set up the input mapping.

**ASSISTANT:** Here is the parameter assignment for `pcamethods_pca_diagnostics_validation`:

```json
{
  "metaboliteData": "imputed_metabolites_missing.tsv",
  "metaboliteDataComplete": "metabolites_reference_full.tsv"
}
```
- `metaboliteData`: Incomplete matrix for validation.
- `metaboliteDataComplete`: Reference complete matrix.

---

## [212] source=multitask_sft_big

**USER:** What are the required input files and expected output formats for the synapsis workflow?

**ASSISTANT:** The inputs for the synapsis workflow are 'foci_channel.tif' (an immunofluorescence image of foci, e.g., MLH3) and 'sc_channel.tif' (an immunofluorescence image of the synaptonemal complex, e.g., SYCP3). The workflow produces outputs in 'table/csv', 'plot/pdf', and 'object/rds' formats.

---

## [213] source=multitask_sft_big

**USER:** In the 'Segmentation and calling' tool, what options are available for the number of calling levels?

**ASSISTANT:** The 'Segmentation and calling' tool supports three options for the number of calling levels:
- 3: calls loss, normal, and gain
- 4: includes amplifications
- 5: includes double deletions

---

## [214] source=multitask_sft_big

**USER:** Here are the outputs from my limma analysis: an F-test p-value vector across all genes and individual contrast p-value matrices. How do these map to the inputs of the stager workflow?

**ASSISTANT:** They map to the two required data inputs of the 'stager' workflow:
- 'pScreen': The vector of gene-level screening p-values (e.g., from your limma F-test).
- 'pConfirmation': The matrix of contrast-level confirmation p-values (e.g., from your individual limma contrasts).

---

## [215] source=multitask_sft_big

**USER:** What output file types does the mirage workflow produce upon completion?

**ASSISTANT:** The `mirage` workflow produces three output types: a CSV table (`table/csv`), a PDF plot (`plot/pdf`), and an RDS object (`object/rds`).

---

## [216] source=multitask_sft_big

**USER:** Please run Filter - Max on input_scan.png using a filter size of 5.

**ASSISTANT:** Extracted parameter for Filter - Max:
- size: 5

---

## [217] source=multitask_sft_big

**USER:** What are the required input parameters and data slots to execute the OGRE workflow?

**ASSISTANT:** The OGRE workflow requires a mandatory data input slot named `input_files` (type: data, read_by_workflow: true, categorized under count_data). It does not require any additional declared parameters.

---

## [218] source=multitask_sft_big

**USER:** I want to run Seurat's ScaleData on my seurat_obj to eliminate technical noise. Please set it up to regress out the percentage of mitochondrial reads stored in 'percent.mt' and the total UMI counts in 'nCount_RNA'.

**ASSISTANT:** To regress out these confounding variables in Seurat `ScaleData`, configure the `vars.to.regress` parameter as follows:

```R
seurat_obj <- ScaleData(seurat_obj, vars.to.regress = c("percent.mt", "nCount_RNA"))
```

This mitigates the technical influence of library size (`nCount_RNA`) and cell stress/mitochondrial content (`percent.mt`) on subsequent dimensionality reduction.

---

## [219] source=multitask_sft_big

**USER:** How do I format the list of genes when passing them to the gene.iobio visualisation tool?

**ASSISTANT:** You should provide the genes as a comma-separated line. Alternatively, this line can be left empty if you plan to select genes interactively in gene.iobio.

---

## [220] source=multitask_sft_big

**USER:** Could you list the required data inputs and output artifacts for the scgps_subpopulation_relationship_prediction workflow?

**ASSISTANT:** The workflow parameters and artifacts are:
- **Inputs:**
  - `mixedpop1` (type: RDS): scGPS object for population 1.
  - `mixedpop2` (type: RDS): scGPS object for population 2.
  - `genes`: Vector of selected gene markers.
- **Outputs:**
  - `visualizations` (specifically producing a Sankey network of the transition and relationship scores).

---

## [221] source=multitask_sft_big

**USER:** I have prepared an expression matrix with 4 columns (human gene lengths, human counts, mouse gene lengths, mouse counts) stored as 'cross_sp_matrix' and an index array 'conserved_indices = c(1, 4, 12, 18)' for conserved orthologs. Please map these to the meb_sfmeb_bulk_different_species workflow inputs.

**ASSISTANT:** The inputs are mapped as follows:
- countsTable: 'cross_sp_matrix' (matrix with 4 columns: species 1 gene lengths, species 1 counts, species 2 gene lengths, species 2 counts)
- train_id: 'conserved_indices' (vector of row indices representing conserved genes)

---

## [222] source=multitask_sft_big

**USER:** We want to simulate an adaptive clinical trial testing 3 experimental arms against 1 control arm. The expected arm response rates are 0.35, 0.45, and 0.50, with a control rate of 0.20. We will conduct 2 interim analyses using MAMS design, enrolling 40 patients per stage across 1000 simulations. One-sided alpha is 0.025 and target power is 0.80. Futility boundary should be set to 0.1.

**ASSISTANT:** Here are the extracted parameters for the `Adaptive Trial Design` workflow:

- `n_arms`: 3
- `arm_response_rates`: [0.35, 0.45, 0.50]
- `control_response_rate`: 0.20
- `n_interim_analyses`: 2
- `design_type`: "MAMS"
- `n_patients_per_stage`: 40
- `n_simulations`: 1000
- `alpha_one_sided`: 0.025
- `power`: 0.80
- `futility_boundary`: 0.1

---

## [223] source=multitask_sft_big

**USER:** I want to convert my genomic alignment coordinates to GFF3 format based on the hg38 genome using 'coordinates to sequence'. Here is my coordinate file: mapped_positions.txt.

**ASSISTANT:** Extracted parameters for the 'coordinates to sequence' tool:
- Input coordinate file: 'mapped_positions.txt'
- Genome: 'hg38'
- Output format: 'GFF3'

---

## [224] source=multitask_sft_big

**USER:** I want to run `nf-core/genomeannotator` with my assembly file `genome_assembly.fasta` and write outputs to `./annotations/`. How do these map to the workflow parameters?

**ASSISTANT:** Based on the workflow's configured parameters, the inputs map as follows:
- Input assembly: `assembly` = `genome_assembly.fasta`
- Output directory: `outdir` = `./annotations/`

---

## [225] source=multitask_sft_big

**USER:** I have the following configuration entry for IEDB: 'HLA-A*03:01,8,9,10'. Can you extract the allele identifier and the requested peptide lengths?

**ASSISTANT:** From the entry 'HLA-A*03:01,8,9,10', the allele is 'HLA-A*03:01' and the specified peptide lengths are 8, 9, and 10.

---

## [226] source=multitask_sft_big

**USER:** Could you list all the output datasets generated by the graphite workflow, as well as the underlying Bioconductor tools it integrates?

**ASSISTANT:** The graphite workflow generates the following outputs:
- `de_table`
- `enrichment_results`
- `pathway_results`

It integrates the following Bioconductor tools:
- `bioconductor/graphite`
- `bioconductor/spia`
- `bioconductor/graph`
- `bioconductor/topologygsa`

---

## [227] source=multitask_sft_big

**USER:** I want to run Profile2CAMI on my taxonomic profiling results, but I only want to see genus and species in the output file instead of all default levels.

**ASSISTANT:** I will configure Profile2CAMI with your selected ranks:
- ranks: `["genus", "species"]`

(Note: The default ranks are `["superkingdom", "phylum", "class", "order", "family", "genus", "species", "strain"]`.)

---

## [228] source=multitask_sft_big

**USER:** What inputs do I need to supply when configuring the Admet Pred workflow?

**ASSISTANT:** The required inputs for the `Admet Pred` workflow are `smiles` (the molecular structures to screen) and `biomate_version`.

---

## [229] source=multitask_sft_big

**USER:** I am configuring tximeta_mixed_reference_import. My Oarfish quantification data file is located at 'experiment_rep1.quant.gz'. Please map this input parameter.

**ASSISTANT:** The input parameter is set as follows:
- `experiment_rep1.quant.gz`: 'experiment_rep1.quant.gz' (required data input for the Oarfish quantification file).

---

## [230] source=multitask_sft_big

**USER:** What data inputs are required for the mastr_multi_dataset_signature_aggregation workflow?

**ASSISTANT:** The workflow requires two RData inputs:
1. 'user_dataset_list.RData': A list of ExpressionSet or DGEList objects representing different transcriptomics datasets.
2. 'user_markers_pool.RData': A GeneSet or vector of gene IDs representing the initial markers pool.

---

## [231] source=multitask_sft_big

**USER:** What outputs and underlying software packages are associated with the polystest workflow?

**ASSISTANT:** The 'polystest' workflow produces three primary outputs: 'de_table', 'differential_abundance', and a 'summarizedexperiment' object. It utilizes the Bioconductor packages 'bioconductor/polystest' and 'bioconductor/summarizedexperiment'.

---

## [232] source=multitask_sft_big

**USER:** We are setting up hiReadsProcessor for genomic LM-PCR reads. The configuration is stored in 'experiment_metadata.xlsx' containing the sample barcodes and trimming coordinates. Please identify the metadata parameter file.

**ASSISTANT:** The metadata parameter file extracted for hiReadsProcessor is `experiment_metadata.xlsx`.

---

## [233] source=multitask_sft_big

**USER:** Please prepare the parameters for hpaanalyze_retrieve_parse_xml to query the gene ENSG00000141510.

**ASSISTANT:** Here is the extracted parameter for the workflow:

```json
{
  "ensembl_id": "ENSG00000141510"
}
```

---

## [234] source=multitask_sft_big

**USER:** I am analyzing a repeated-measures microbiome cohort and want to plot volatility control charts in QIIME 2 using the column 'sampling_week' to follow time progression. Which parameter specifies this time variable?

**ASSISTANT:** In `qiime2 longitudinal volatility`, the time axis is defined by the `state_column` parameter. Based on your description, you should set `state_column='sampling_week'`.

---

## [235] source=multitask_sft_big

**USER:** In 'WGCNA: construct network (RNA)', how should I set the height cut parameter if my sample clustering plot shows no outlier samples?

**ASSISTANT:** If there are no outliers observed in your sample clustering plot, you should leave the height cut field blank.

---

## [236] source=multitask_sft_big

**USER:** Does the 'msnid_peptide_modification_mapping' workflow accept an mzIdentML file specifically for modification data, and is it mandatory?

**ASSISTANT:** Yes, the workflow lists an optional data input named 'phospho.mzid.gz' with type 'data', described as an 'mzIdentML file containing modification data' (optional: true).

---

## [237] source=multitask_sft_big

**USER:** Set up AutoDock Vina docking for ligand list ['CC(=O)Oc1ccccc1C(=O)O'] against receptor 'target_protein.pdb'. Place the grid box center at (15.2, 22.0, -8.5), box size (20, 20, 20), using 8 CPUs, exhaustiveness 16, and generate 9 poses with random seed 42.

**ASSISTANT:** I have extracted the following parameters for the `Docking Autodock Vina` workflow:
- `smiles_list`: ['CC(=O)Oc1ccccc1C(=O)O']
- `receptor_pdb_file`: 'target_protein.pdb'
- `box_center`: [15.2, 22.0, -8.5]
- `box_size`: [20, 20, 20]
- `ncpu`: 8
- `exhaustiveness`: 16
- `n_poses`: 9
- `randomSeed`: 42

---

## [238] source=multitask_sft_big

**USER:** What are all the input slots and parameters required to execute the 'Integration Benchmark' workflow?

**ASSISTANT:** The 'Integration Benchmark' workflow accepts the following inputs:
- `embedding_file`
- `method_name`
- `k`
- `batch_weight`
- `good_threshold`

---

## [239] source=multitask_sft_big

**USER:** Here are my files for CDI clustering evaluation: raw counts at 'counts.raw.mtx', batch vector in 'batch_ids.rds', and candidate clustering solutions in 'candidate_labels.df.csv'. I do not have reference cell types. How do these map to `cdi_multi_batch_cdi`?

**ASSISTANT:** Based on your provided files, the mapping to `cdi_multi_batch_cdi` inputs is:
- `two_batch_matrix`: 'counts.raw.mtx'
- `two_batch_matrix_batch`: 'batch_ids.rds'
- `two_batch_matrix_label_df`: 'candidate_labels.df.csv'
- `two_batch_matrix_celltype`: Not provided (this parameter is optional and can be omitted).

---

## [240] source=multitask_sft_big

**USER:** Please run batch correction using batchelor on batch 1 at 'experiments/batch1.rds' and batch 2 at 'experiments/batch2.rds'.

**ASSISTANT:** Extracted parameters for the `batchelor` workflow:
- `sce1`: "experiments/batch1.rds"
- `sce2`: "experiments/batch2.rds"

---

## [241] source=multitask_sft_big

**USER:** What outputs and data dependencies are defined for panomir_custom_mirna_pathway_enrichment?

**ASSISTANT:** The workflow produces two main outputs: 'enrichment_results' and 'visualizations'. For data dependencies, it requires 'mirna_targets.RData' (miRNA target sets, e.g., TargetScan) along with the user-supplied 'expressed_genes.txt' and 'selected_mirnas.txt'.

---

## [242] source=multitask_sft_big

**USER:** Configure the inputs for running the venndetail workflow using my dataset: I have `deg_sets.rds` which contains the character vectors of differentially expressed genes across conditions, and `gene_annotations.rds` containing functional details for these genes.

**ASSISTANT:** Here are the extracted parameters for the `venndetail` workflow:
- `list_of_vectors`: `deg_sets.rds` (a list of character or numeric vectors representing the datasets to compare)
- `annotation_list`: `gene_annotations.rds` (a list of data frames containing additional annotations for the elements in the datasets)

---

## [243] source=multitask_sft_big

**USER:** I need to run logistic regression and inspect multicollinearity diagnostics on my sequence metadata. Does 'Perform Logistic Regression with vif' report regression coefficients as well as collinearity diagnostics?

**ASSISTANT:** Yes. The tool fits logistic regression via R's `glm` and outputs a single file containing summary statistics of the regression, while also computing VIF (Variance Inflation Factor) values via `vif`.

---

## [244] source=multitask_sft_big

**USER:** What are the required input data parameters for the gothic workflow?

**ASSISTANT:** The input data parameters for `gothic` are `fileName1` (aligned reads file 1, e.g., Bowtie Table format) and `fileName2` (aligned reads file 2).

---

## [245] source=multitask_sft_big

**USER:** I am preparing my data for bert_covariate_batch_correction. If my file contains gene counts, a batch identifier column, and two biological factors named 'Treatment' and 'Tissue', how should the covariate columns be formatted?

**ASSISTANT:** To comply with `bert_covariate_batch_correction`, the batch column must be named `'Batch'`, and the biological covariate columns must be prefixed with `'Cov_'` (for example, `'Cov_Treatment'` and `'Cov_Tissue'`).

---

## [246] source=multitask_sft_big

**USER:** I want to launch rawdiag_shiny_application to inspect LC-MS runs. My instrument data is located in '/storage/mass_spec/raw_files'. Which parameter should I populate?

**ASSISTANT:** You should set the 'directory_path' parameter to '/storage/mass_spec/raw_files'. This parameter is designated for specifying the path to a directory containing .raw files.

---

## [247] source=multitask_sft_big

**USER:** I need to query ChEMBL for molecules containing the benzene ring substructure represented by 'c1ccccc1'. Please set up the input for the Search ChEMBL database tool.

**ASSISTANT:** Extracted parameter for 'Search ChEMBL database':
- SMILES input: 'c1ccccc1'
- Search mode: Substructure search

---

## [248] source=multitask_sft_big

**USER:** What input datasets and metadata are expected by the 'diffbind_multi_factor_analysis' workflow?

**ASSISTANT:** The workflow requires: 1) a sample sheet with multiple metadata columns (e.g., 'tamoxifen.csv'), 2) aligned BAM files (such as 'reads/Chr18_BT474_ER_1.bam'), and 3) peak caller output files (such as 'peaks/BT474_ER_1.bed.gz'). Its output is 'visualizations'.

---

## [249] source=multitask_sft_big

**USER:** What is the default script path configured for parallel_assign_taxonomy_rdp when setting up taxonomy assignment?

**ASSISTANT:** The default path is set to `/usr/local/lib/python2.6/site-packages/scripts/assign_taxonomy.py`.

---

## [250] source=multitask_sft_big

**USER:** What are the expected output artifacts produced by the gofuncr_go_graph_exploration_and_utilities workflow?

**ASSISTANT:** The workflow produces two outputs:
1. `enrichment_results`: Refined GO enrichment analyses.
2. `cluster_assignments`: Resulting cluster assignments derived from the GO graph exploration.

---

## [251] source=multitask_sft_big

**USER:** What outputs are generated by the `safe` pathway analysis workflow?

**ASSISTANT:** The `safe` workflow produces three outputs: `enrichment_results`, `pathway_results`, and `visualizations`.

---

## [252] source=multitask_sft_big

**USER:** I want to run drug_discovery/survival_analysis_km. Which input parameters do I need to supply?

**ASSISTANT:** The workflow accepts the following inputs:
- `mode`
- `endpoint`
- `distribution`
- `median_control_mo`
- `hazard_ratio`
- `alpha`
- `power`
- `dropout_rate`
- `accrual_months`
- `followup_months`
- `n_arms`
- `n_interim`
- `rmst_tau`
- `weibull_shape`
- `indication`
It produces an output in `json` format.

---

## [253] source=multitask_sft_big

**USER:** What are the required input datasets and expected output targets for the linnorm_cell_subpopulation_clustering workflow?

**ASSISTANT:** The workflow requires one non-optional input: `Islam2011` (a matrix of expression values). The generated outputs are `de_table`, `cluster_assignments`, and `normalized_data`.

---

## [254] source=multitask_sft_big

**USER:** How are custom cache download parameters passed to the Ensemblvep Download tool in a Nextflow/nf-core module?

**ASSISTANT:** Options for downloading the Ensembl Variant Effect Predictor (VEP) cache in `Ensemblvep Download` are passed and controlled through `task.ext.args`.

---

## [255] source=multitask_sft_big

**USER:** Optimize an LNP formulation for delivering mRNA to the spleen. I'm using ionizable lipid 'CCCCC(CCC)CCN(CC)CC' and helper lipid 'CCCCCCCCCCCCCCCC(=O)OCC'. Please also perform a grid search sweep across molar ratios.

**ASSISTANT:** Here are the extracted parameters for the `drug_discovery/lnp_formulation_optimization` workflow:

- `ionizable_lipid_SMILES`: "CCCCC(CCC)CCN(CC)CC"
- `helper_lipid_SMILES`: "CCCCCCCCCCCCCCCC(=O)OCC"
- `cargo_type`: "mRNA"
- `target_tissue`: "spleen"
- `run_ratio_sweep`: true

---

## [256] source=multitask_sft_big

**USER:** Can you list the data inputs and parameters declared for the RSeqAn workflow?

**ASSISTANT:** The RSeqAn workflow declares one data input: `count_data` (type: data, optional: true, read_by_workflow: false). It defines no additional execution parameters.

---

## [257] source=multitask_sft_big

**USER:** Which option flag in `bcftools view` is designated for excluding sites based on specific expressions or criteria?

**ASSISTANT:** The documented parameter flag for exclusion in `bcftools view` is `-e`.

---

## [258] source=multitask_sft_big

**USER:** What mandatory data input file is specified for the semdist_evaluate_predictions_ru_mi workflow?

**ASSISTANT:** The workflow requires the mandatory data input file 'MFO_LABELS_TEST.txt' (optional: false), which is described as a tab-delimited true annotations file.

---

## [259] source=multitask_sft_big

**USER:** What are the declared inputs, outputs, and parameters for the immunology workflow 'ipdDb'?

**ASSISTANT:** For the 'ipdDb' workflow:
- Inputs: `plot_object`
- Data inputs: `input_files` (type: data, optional: false, declared .nf input slot)
- Parameters: none (`[]`)
- Outputs: none (`[]`)
- Underlying tool: `bioconductor/ipddb`.

---

## [260] source=multitask_sft_big

**USER:** Configure BioTransformer for my metabolomics run. I have an input SDF molecule list and I want it to predict biotransformation products rather than running identification.

**ASSISTANT:** Based on your request, the parameters extracted for BioTransformer are:
- Omics domain: Metabolomics
- Task mode: Prediction (generate biotransformation products for the input molecules)

---

## [261] source=multitask_sft_big

**USER:** What mandatory input datasets do I need to prepare before executing the viper_single_sample_viper workflow?

**ASSISTANT:** The `viper_single_sample_viper` workflow requires two mandatory data inputs:
1. `dset`: An ExpressionSet or matrix containing gene expression data.
2. `regulon`: A regulon class object.

---

## [262] source=multitask_sft_big

**USER:** I am configuring MAnorm for ChIP-seq data. My average fragment length from paired-end sequencing is 300 bp. What value should I use for the 3' read shift?

**ASSISTANT:** You should set the 3' read shift value to 150 bp. In MAnorm, this parameter is defined as half of the fragment length to determine the precise binding site.

---

## [263] source=multitask_sft_big

**USER:** I am configuring NCBI Accession Download for a single reference sequence and want to subset the region between nucleotide 500 and 1500. How can I format this parameter?

**ASSISTANT:** In NCBI Accession Download, the region parameter for a single accession accepts start and end coordinates separated by ':', '..', or '.'. You can specify this subset as '500:1500', '500..1500', or '500.1500'. Note that region subsetting is only supported for a single accession.

---

## [264] source=multitask_sft_big

**USER:** I ran TRUST4 and produced a contig annotation file. Can I pass this to the screpertoire workflow, and if so, under which input?

**ASSISTANT:** Yes, `screpertoire` accepts formats like TRUST4 and WAT3R in addition to 10x Cell Ranger VDJ. You should supply it to the `filtered_contig_annotations.csv` input.

---

## [265] source=multitask_sft_big

**USER:** In the SC3 Prepare tool for RNA analysis, which parameter defines the lower limit of eigenvectors used in k-means clustering relative to cell numbers?

**ASSISTANT:** The parameter is 'Minimum number of eigenvectors used for kmeans clustering as a fraction of the total number of cells'.

---

## [266] source=multitask_sft_big

**USER:** Run the compepitools heatmap workflow. My genomic regions GRanges object is at '/data/regions/peaks.RData' and the significance values matrix is at '/data/stats/pvals_matrix.txt'.

**ASSISTANT:** Extracted parameters for `compepitools_epigenomic_heatmap_visualization`:
- `user_regions.RData`: '/data/regions/peaks.RData'
- `pvalues.txt`: '/data/stats/pvals_matrix.txt'

---

## [267] source=multitask_sft_big

**USER:** Configure the `Cutandtag Alignment Spikein` workflow with Bowtie2 index 'hg38/bowtie2', spike-in index 'ecoli/bowtie2', mapq cutoff 30, max fragment size 700, and bin size 10.

**ASSISTANT:** Here are the extracted parameters for `Cutandtag Alignment Spikein`:
- `bowtie2_index`: "hg38/bowtie2"
- `spikein_index`: "ecoli/bowtie2"
- `min_mapq`: 30
- `max_fragment_size`: 700
- `binsize`: 10

---

## [268] source=multitask_sft_big

**USER:** How do I specify which columns to group by when using Datamash, and what happens if I do not specify any?

**ASSISTANT:** You specify fields as a comma-separated list of column indices (for example, `1,5`). If no columns are specified, each operation is performed across the entire input file.

---

## [269] source=multitask_sft_big

**USER:** I am setting up Beagle 4.0 for my GWAS study. I want to use my phased panel located at `/data/panels/1000G_phased.vcf.gz` to impute missing markers. Extract the relevant parameter.

**ASSISTANT:** Based on Beagle 4.0 syntax, the extracted parameter is:
- `ref=/data/panels/1000G_phased.vcf.gz`

---

## [270] source=multitask_sft_big

**USER:** What input file does the frenchfish workflow accept, and what tool does it execute?

**ASSISTANT:** The frenchfish workflow accepts 'SampleFISH.jpg_data.csv', which is a CSV file containing automated FISH probe counts and nuclear area from FISHalyseR. It executes the tool 'bioconductor/frenchfish'.

---

## [271] source=multitask_sft_big

**USER:** What are the required input parameters and data slots declared for the gemma_r workflow?

**ASSISTANT:** The gemma_r workflow requires a mandatory data input slot named 'input_files' (accepting count_data). There are no additional declared configurable parameters.

---

## [272] source=multitask_sft_big

**USER:** Please set up the flowmerge workflow using my file 'sample.fcs', which contains the cell marker measurements represented as a flowFrame.

**ASSISTANT:** I have extracted the required parameter for the 'flowmerge' workflow:
- `sample.fcs`: flow cytometry data file containing cell marker measurements (represented as a flowFrame).

The workflow will use `bioconductor/flowmerge` and `bioconductor/rgraphviz` to fit mixture models, merge components, and produce `cluster_assignments` and `visualizations`.

---

## [273] source=multitask_sft_big

**USER:** What is the mandatory input dataset for the mbpcr_direct_vector_profile_estimation workflow?

**ASSISTANT:** The required non-optional input is 'jekoChr11Array250Knsp', a dataset containing raw log2 ratios and physical positions.

---

## [274] source=multitask_sft_big

**USER:** I want to initialize the flowgate_batch_gating_strategy_pipeline. I have an existing compensated GatingSet saved as an RDS file at 'data/compensated_gs.rds'. Please set up the input parameter.

**ASSISTANT:** I have mapped your input file to the workflow parameter:

```json
{
  "gs": "data/compensated_gs.rds"
}
```

This supplies your existing, compensated GatingSet object to the pipeline.

---

## [275] source=multitask_sft_big

**USER:** What outputs are produced when running the wpm workflow on a sample metadata CSV?

**ASSISTANT:** The wpm workflow produces 'visualizations' representing the randomized well-plate layout generated from your input metadata.

---

## [276] source=multitask_sft_big

**USER:** I want to set up hdtd_covariance_structure_analysis using my file `raw_counts_stacked.csv`. Extract the required input configuration.

**ASSISTANT:** Based on the workflow schema, the input configuration is:
- `user_data.csv`: Set to `raw_counts_stacked.csv` (type: matrix, dimensions `row_vars x (col_vars * N)` representing column-wise stacked subject matrices).

---

## [277] source=multitask_sft_big

**USER:** Configure the GC content constraints in Workflow-2 Parameters Maystro so that minimum GC is 0.3, maximum GC is 0.7, and the analysis window size is 100 bp.

**ASSISTANT:** The extracted parameters for Enforce GC Content Constraints are:
- mini: 0.3
- maxi: 0.7
- window: 100

---

## [278] source=multitask_sft_big

**USER:** I need to run bedtools random to generate 2,000 background intervals of 250 base pairs each. What command-line options should I supply?

**ASSISTANT:** Use the `-n` parameter to specify the number of intervals and `-l` to set the interval length: set `-n 2000` and `-l 250`.

---

## [279] source=multitask_sft_big

**USER:** I am modeling T-cell expansion with an initial count N0 of 1000 cells, carrying capacity K = 1e6, growth rate r = 0.05, and evaluating over time t = 48 hours. Which parameters does the Biomni Logistic Growth tool require?

**ASSISTANT:** The Biomni Logistic Growth model parameters map directly to your values:
- Initial population (N0): 1000
- Carrying capacity (K): 1e6
- Growth rate (r): 0.05
- Time (t): 48

---

## [280] source=multitask_sft_big

**USER:** What inputs does the tidySpatialExperiment workflow take, and is the count data input mandatory?

**ASSISTANT:** The workflow declares one data input slot: `count_data` (type: data). It is marked as optional (`optional: true`), meaning the workflow can run without a mandatory external count data file if self-contained data is provided.

---

## [281] source=multitask_sft_big

**USER:** What specific parameter does 'PAQmiR Create miRNA/Precursors reference files (RNA)' require to filter out the sequences for my target organism from the mature and hairpin files?

**ASSISTANT:** The tool requires the 'species code' parameter, which it uses to identify and extract the sequences belonging to your target reference species from the input mature and hairpin miRNA files.

---

## [282] source=multitask_sft_big

**USER:** I have my files ready: exposome_data.rds containing our ExposomeSet, transcript_counts.rds as an ExpressionSet, and protein_levels.rds as another ExpressionSet. How do these map to the inputs of omicrexposome_integration_analysis?

**ASSISTANT:** The mapping for omicrexposome_integration_analysis is:
- `brge_expo`: exposome_data.rds (ExposomeSet object containing exposure data)
- `brge_gexp`: transcript_counts.rds (ExpressionSet containing transcriptome data)
- `brge_prot`: protein_levels.rds (ExpressionSet containing proteome data)

---

## [283] source=multitask_sft_big

**USER:** Please set up the santa workflow with my files: protein_interactome.gml containing our network graph and gwas_hits.csv containing gene scores.

**ASSISTANT:** Here are the extracted parameters for the `santa` workflow:
- `network.gml`: `protein_interactome.gml` (igraph-compatible network file)
- `phenotype_weights.csv`: `gwas_hits.csv` (table containing gene names and continuous weights or binary indicators)

Running this will generate `cluster_assignments` quantifying the phenotype clustering across the graph.

---

## [284] source=multitask_sft_big

**USER:** I am using the Pivot Table tool to aggregate expression counts. Please set the replacement value for missing values after aggregation to '0'.

**ASSISTANT:** Parameter extracted:
- Value to replace missing values with: '0' (overriding the default empty field).

---

## [285] source=multitask_sft_big

**USER:** Set up the zfpkm workflow using my dataset stored at '/data/experiments/se_counts_fpkm.rds'.

**ASSISTANT:** Here is the extracted parameter configuration for the zfpkm workflow:

```json
{
  "workflow": "zfpkm",
  "data_inputs": [
    {
      "name": "SummarizedExperiment",
      "type": "rds_se",
      "value": "/data/experiments/se_counts_fpkm.rds"
    }
  ]
}
```

---

## [286] source=multitask_sft_big

**USER:** Can I run the clusterprofiler_biological_theme_comparison workflow without providing gene_clusters.csv?

**ASSISTANT:** No. The parameter definition specifies that `gene_clusters.csv` has `optional: false` and `read_by_workflow: true`. It is a required input table mapping genes to their clusters or experimental conditions.

---

## [287] source=multitask_sft_big

**USER:** Please set up the Exposure Response Modeling workflow with the following parameters: patient dataset file is 'cohort_pkpd.csv', exposure metric to test is 'Cmin', keep Emax unfixed, set Hill bounds between 0.5 and 3.5, use 500 bootstrap replicates, and name the compound 'BM-402'.

**ASSISTANT:** Here are the extracted parameters for the Exposure Response Modeling workflow:
- `patient_data_csv`: "cohort_pkpd.csv"
- `exposure_metric`: "Cmin"
- `emax_fixed`: false
- `hill_bounds`: [0.5, 3.5]
- `bootstrap_n`: 500
- `compound_name`: "BM-402"

---

## [288] source=multitask_sft_big

**USER:** I am configuring a pipeline run with an expression matrix file 'vdx_norm.tsv' having Entrez IDs, a validation matrix 'mainz_norm.tsv', and signature weights 'sig_weights.rds'. How should these be mapped to dart_wrapper_dart inputs?

**ASSISTANT:** The files map to the `dart_wrapper_dart` inputs as follows:
- `vdx.data`: 'vdx_norm.tsv' (normalized gene expression matrix with Entrez Gene IDs as rownames)
- `mainz.data`: 'mainz_norm.tsv' (independent normalized gene expression matrix with Entrez Gene IDs as rownames)
- `modelSig`: 'sig_weights.rds' (named vector of model signature gene weights/directions)

---

## [289] source=multitask_sft_big

**USER:** I have unindexed BAM files from a bulk RNA-seq run and a GTF file. Can metagene2_rnaseq_metagene_analysis accept these directly as parameters?

**ASSISTANT:** No. The workflow specifically requires 'bam_files' to be indexed BAM files of RNA-seq alignments and 'regions' to be structured as a GRangesList of exons grouped by gene/transcript. You must index your BAM files and prepare the regions input as a GRangesList before executing this workflow.

---

## [290] source=multitask_sft_big

**USER:** What configurable parameters and underlying tools are registered for the 'timecourse' workflow?

**ASSISTANT:** The 'timecourse' workflow wraps the 'bioconductor/timecourse' tool. It requires the 'input_files' data input (type: data, mandatory) and defines no additional configurable parameters in its workflow specification.

---

## [291] source=multitask_sft_big

**USER:** What input file and format are required for the tricycle_discrete_stage_inference workflow?

**ASSISTANT:** The workflow requires a mandatory input named `sce_normalized.rds`, which must be a `SingleCellExperiment` (type `rds_sce`) object containing normalized logcounts.

---

## [292] source=multitask_sft_big

**USER:** Configure the inputs for `rnaseqsamplesize_visualization_and_optimization` using my parameters: sample size range 3 to 20, sequencing depth from 10M to 50M reads, and FDR thresholds of 0.01, 0.05, and 0.10.

**ASSISTANT:** Extracted parameter configuration for `rnaseqsamplesize_visualization_and_optimization`:
- `User` (numeric parameters and ranges): Sample size range [3, 20], read depth range [10M, 50M], FDR thresholds [0.01, 0.05, 0.10].

---

## [293] source=multitask_sft_big

**USER:** What types of output files does the ccpromise_probe_pair_level_ccpromise workflow generate?

**ASSISTANT:** The workflow produces outputs in three formats: 'table/csv', 'plot/pdf', and 'object/rds'.

---

## [294] source=multitask_sft_big

**USER:** What is the default variant frequency threshold used by the Drug Resistance Mutations tool to report mutations?

**ASSISTANT:** The Drug Resistance Mutations tool uses a default reporting threshold of 1% to report detected drug-resistant mutations.

---

## [295] source=multitask_sft_big

**USER:** I want to run Table to GeoJSON on my data table, but I only want to include specific fields while omitting sensitive ones. Does the tool support this?

**ASSISTANT:** Yes, `Table to GeoJSON` allows you to configure column selection by either including or excluding specific columns; otherwise, all columns are included in the properties field by default.

---

## [296] source=multitask_sft_big

**USER:** Is the DCCFiles input marked as required or optional in geomxtools_protein_geomx_workflow?

**ASSISTANT:** The `DCCFiles` input is marked as optional (`optional: true`) and has `read_by_workflow: false` in the workflow specifications.

---

## [297] source=multitask_sft_big

**USER:** Here is my setup: raw count table is `gene_counts_df`, gene-level GC percentages are in `gene_gc_vec`, and sample tissues are stored in `metadata$tissue_type`. How do these map to the qsmooth GC-content normalization inputs?

**ASSISTANT:** The inputs map as follows:
- `counts1`: `gene_counts_df` (matrix/data frame of raw expression counts)
- `gcContent`: `gene_gc_vec` (numeric vector of GC-content values)
- `pd1$organ`: `metadata$tissue_type` (vector or factor representing biological groups)

Running the workflow with these will output `expression_matrix` and `normalized_data`.

---

## [298] source=multitask_sft_big

**USER:** I want to run ctat_analyze_differential_expression on my edgeR results. I need a minimum fold-change cutoff of 4 and an FDR significance threshold of 0.05. How should I set the tool parameters?

**ASSISTANT:** You should set:
- Minimum fold change (C-value): `4` (the tool will log2-transform this value before applying the threshold)
- Required significance (P-value): `0.05` (applied after false discovery rate correction for pairwise comparisons)

---

## [299] source=multitask_sft_big

**USER:** I am working on mass spectrometry-based metabolomics data and want to query HMDB using 'KMD HMDB Data Plot'. I have an observed m/z ratio of 285.05 and want to look up matching compounds using a tolerance window of 0.01 Da. What query parameter values does the tool expect?

**ASSISTANT:** Based on the specification for 'KMD HMDB Data Plot', the relevant parameters are:
- `m/zRatio`: 285.05
- `MassTolerance`: 0.01

The tool queries the database for all compounds satisfying the condition `m/z = m/zRatio ± MassTolerance` and plots the resulting matches.

---

## [300] source=multitask_sft_big

**USER:** I'm setting up the Advanced NG-CHM Generator heatmap and want to highlight specifically TP53, EGFR, and BRCA1 on the full summary heatmap rows. How should that be specified?

**ASSISTANT:** To label those rows in the full summary heat map using Advanced NG-CHM Generator, provide them as a comma-delimited list:
`TP53,EGFR,BRCA1`

---

## [301] source=multitask_sft_big

**USER:** When should I select the 'No packaged matrix output' option in Scanpy RunUMAP?

**ASSISTANT:** You should choose 'No packaged matrix output' in cases where auxiliary files are generated (such as marker genes). However, do not use this option when there are no other output files generated.

---

## [302] source=multitask_sft_big

**USER:** When adding a new taxon using 'Update PlantTribes scaffold', how does the tool position the new species in the tree rooting structure?

**ASSISTANT:** The new species is positioned immediately after a specified species code in the rooting order configuration file.

---

## [303] source=multitask_sft_big

**USER:** In the `rnamodr_multi_sample_comparison_and_visualization` workflow, is there an optional example GFF3 annotation file specified in the parameters?

**ASSISTANT:** Yes, the workflow defines an optional data input parameter named `RNAmodR.Data.example.AAS.gff3`, described as `RNAmodR.Data.example.AAS.gff3() (GFF3 annotation)`.

---

## [304] source=multitask_sft_big

**USER:** Based on the error from `bionet_exact_module_detection`:
`Error in match.arg(type) : 'arg' should be one of “table”, “XGMML”, “sif”, “tab”, “tgf”, “net” Calls: saveNetwork -> match.arg`
What are the permitted values for the network export type parameter?

**ASSISTANT:** The valid parameter values accepted by `type` in `saveNetwork` are:
- `table`
- `XGMML`
- `sif`
- `tab`
- `tgf`
- `net`

---

## [305] source=multitask_sft_big

**USER:** I want to assemble inputs for compcoder_phylogenetic_rnaseq_comparison. I have species_raw_counts.tsv for count.matrix, sample_meta.csv for sample.annotations, vertebrate_tree.nwk for tree, and gene_lengths.tsv for length.matrix. How should these map?

**ASSISTANT:** The inputs map to the `compcoder_phylogenetic_rnaseq_comparison` workflow parameters as follows:
- `count.matrix`: `species_raw_counts.tsv` (matrix of raw counts)
- `sample.annotations`: `sample_meta.csv` (data frame containing sample annotations and species IDs)
- `tree`: `vertebrate_tree.nwk` (phylogenetic tree in ape phylo format)
- `length.matrix`: `gene_lengths.tsv` (matrix of orthologous gene lengths)

---

## [306] source=multitask_sft_big

**USER:** What are the data input requirements specified for the flagme_correlation_based_alignment workflow?

**ASSISTANT:** The workflow specifies `cdfFiles` (raw GC-MS data in NetCDF format, marked as optional) and `input_files` as data inputs.

---

## [307] source=multitask_sft_big

**USER:** What is the default setting and behavior for the grouping parameter in the Chimera.perseus tool?

**ASSISTANT:** In Chimera.perseus, the parameter defaults to false (`default=false`). When set to false, if any one group determines a sequence to be chimeric, then all groups classify that sequence as chimeric.

---

## [308] source=multitask_sft_big

**USER:** Please set up EDIRquery to search the TP53 gene for repeats of length 20 to 50 bp, separated by at least 100 bp but at most 500 bp, allowing a single base-pair mismatch.

**ASSISTANT:** Based on your request, the parameters for `EDIRquery` are extracted as follows:
- **Gene of interest (required)**: TP53
- **Repeat sequence lengths**: 20–50 bp
- **Minimum distance**: 100 bp
- **Maximum distance**: 500 bp
- **Allow 1-bp mismatch**: true

---

## [309] source=multitask_sft_big

**USER:** I am configuring the 'table rename columns via regex' tool. Can you explain what the regular expression pattern parameter is used for?

**ASSISTANT:** The regular expression pattern parameter specifies the regex pattern to search for within the table's column names. It identifies the specific parts or substrings of the column headers that should be targeted for replacement.

---

## [310] source=multitask_sft_big

**USER:** Please set up Centrifuge on our metagenomics sample reads 'sample_R1.fastq' and reference index 'p_compressed+h+v'.

**ASSISTANT:** Here are the extracted parameters for Centrifuge:
- Input FASTQ: `sample_R1.fastq`
- Database / Index: `p_compressed+h+v`

---

## [311] source=multitask_sft_big

**USER:** Which input file type and reference sources are involved in running the proportional venn tool?

**ASSISTANT:** The tool takes a VAR-file as input and utilizes data from three reference sources: 1000G, dbSNP, and COSMIC.

---

## [312] source=multitask_sft_big

**USER:** Please run get differential expression on my dataset. Set the magnification factor for normalization using fixed size sliding windows in reference regions to 2.5.

**ASSISTANT:** Extracted parameter:
- Magnification factor for sliding window normalization in reference regions: 2.5

---

## [313] source=multitask_sft_big

**USER:** Configure Scater Normalise to compute log-transformed expression values using the cpm slot from my SingleCellExperiment dataset.

**ASSISTANT:** Extracted parameter for Scater Normalise:
- assayData slot: "cpm"

---

## [314] source=multitask_sft_big

**USER:** What input parameters and files are required by biosigner_summarized_experiment_analysis?

**ASSISTANT:** The workflow requires one non-optional input parameter: `dia.se`, which must be an RDS file of type `rds_se` containing a SummarizedExperiment object with assay data and corresponding sample and feature metadata.

---

## [315] source=multitask_sft_big

**USER:** I am configuring pySelectMotifsFromGTF to extract motifs. What setting must I pay special attention to regarding k-mer length?

**ASSISTANT:** You must set the Kmer Length parameter. Note that the length must be at least as long as your k-mer sequence, otherwise the program will not run correctly.

---

## [316] source=multitask_sft_big

**USER:** What parameter is used in meta-velvetg to specify the expected coverage of unique regions, and what should it be set to for metagenomics?

**ASSISTANT:** In meta-velvetg, the parameter for expected coverage of unique regions is `-exp_cov`. It takes a float or "auto", and for metagenomic analysis, it is set to "auto".

---

## [317] source=multitask_sft_big

**USER:** I am configuring PhaBOX phaGCN for my metagenomic viral contigs. I already ran external gene prediction and have my own predicted protein sequences ready to upload.

**ASSISTANT:** Acknowledged. PhaBOX phaGCN allows you to optionally provide your own predicted protein sequences as input, bypassing the default prediction pipeline that uses Prodigal and DIAMOND blastp.

---

## [318] source=multitask_sft_big

**USER:** I want to extract annotations from ChEBI across our metabolic model by pointing to its identifiers.org URI. How does ExtractAnnotations expect this database reference to be specified?

**ASSISTANT:** ExtractAnnotations expects the name of the referenced database to export annotations from to be specified as listed in the model notes or formatted as an identifiers.org base URI.

---

## [319] source=multitask_sft_big

**USER:** What data inputs are required by the riboSeqR workflow?

**ASSISTANT:** The riboSeqR workflow requires a single non-optional data input named `input_files`, which takes the count data for the analysis.

---

## [320] source=multitask_sft_big

**USER:** Please set up protrek_protein_search with the following inputs: query sequence file 'kinase_target.fasta', structure file 'kinase_target.pdb', search against the 'uniprot_sprot' database, query type set to 'structure', and return the top 20 hits.

**ASSISTANT:** Here are the extracted parameters for the protrek_protein_search workflow:
- query: "kinase_target.fasta"
- query_type: "structure"
- top_k: 20
- databases: ["uniprot_sprot"]
- input_fasta: "kinase_target.fasta"
- input_pdb: "kinase_target.pdb"

---

## [321] source=multitask_sft_big

**USER:** I want to regress out both batch effects and mitochondrial percentage using SCCAF multiple regress out. How should I provide these keys to the tool?

**ASSISTANT:** You should supply them as a comma-separated list of keys (e.g., `batch,percent_mito`), ensuring each key corresponds exactly to a column in the observations (`obs`) dataframe of your AnnData object.

---

## [322] source=multitask_sft_big

**USER:** I want to update alignments.bam using the header from reference_header.bam using Samtools reheader. Which file is the target and which is the source?

**ASSISTANT:** In Samtools reheader, 'alignments.bam' is the target dataset (which provides the alignment records) and 'reference_header.bam' is the source dataset (which provides the new header).

---

## [323] source=multitask_sft_big

**USER:** I need to configure a job for Expansionhunterdenovo Profile. What genomic data format and target variant type does this tool process?

**ASSISTANT:** Expansionhunterdenovo Profile processes genome alignment data in BAM format to analyze short tandem repeats (STRs).

---

## [324] source=multitask_sft_big

**USER:** I want to set up `tapseq_primer_design_and_evaluation`. My files are `exons_chr11.rds` containing exon annotations, `k562_reads.bam` for polyA site inference, and `hg38.fasta` for the reference sequence. How do these map to the workflow inputs?

**ASSISTANT:** Here is the parameter mapping for your input files:
- `chr11_genes`: `exons_chr11.rds` (rds_granges containing annotated exons per gene)
- `chr11_k562_dropseq.bam`: `k562_reads.bam` (BAM file to infer polyA sites)
- `hg38`: `hg38.fasta` (reference genome sequence)

---

## [325] source=multitask_sft_big

**USER:** Set up a grid calculation with GridBuilder using my docked file 'active_site_ligand.sdf'.

**ASSISTANT:** I have extracted the following parameters for **GridBuilder**:
- **Reference ligand file**: `active_site_ligand.sdf`
- **Reference ligand format**: `sdf`

---

## [326] source=multitask_sft_big

**USER:** What are the designated inputs and outputs for the bioconductor/normalyzerde pipeline in the normalyzerde workflow?

**ASSISTANT:** The inputs are:
- `tiny_data.tsv`: raw expression matrix with annotations (matrix type, mandatory).
- `tiny_design.tsv`: design matrix mapping samples to experimental groups.

The resulting output is:
- `normalized_data`: the normalized expression results alongside normalization performance plots.

---

## [327] source=multitask_sft_big

**USER:** What are the outputs and Bioconductor tools used by the `degraph` workflow?

**ASSISTANT:** The `degraph` workflow utilizes the tools `bioconductor/degraph`, `bioconductor/kegggraph`, `bioconductor/rbgl`, `bioconductor/rgraphviz`, `bioconductor/corpcor`, and `bioconductor/fields`. It produces three outputs: `de_table`, `pathway_results`, and `visualizations`.

---

## [328] source=multitask_sft_big

**USER:** What format options are available for the exported graph in ExtractSubNetwork besides the default edge list?

**ASSISTANT:** In addition to the default tabulated edge list, ExtractSubNetwork can export graphs in GML, JsonGraph, or as a tabulated node list structured as 'label node id node type'.

---

## [329] source=multitask_sft_big

**USER:** What is the expected output of the osat_paired_sample_assignment workflow?

**ASSISTANT:** The expected output of the osat_paired_sample_assignment workflow is 'visualizations'.

---

## [330] source=multitask_sft_big

**USER:** What is the default value of k for the k-nearest-neighbors algorithm in 'qiime2 sample-classifier classify-samples-from-dist'?

**ASSISTANT:** The default value of k is 1.

---

## [331] source=multitask_sft_big

**USER:** Can I omit the 'classes' input when running clustersignificance_pca_downstream_analysis if I only supply the expression matrix?

**ASSISTANT:** No, the `classes` parameter is not optional. You must provide both the `expression` matrix (samples as rows, genes as columns) and the `classes` character vector defining the class labels.

---

## [332] source=multitask_sft_big

**USER:** I want to run CNVkit Call on my segmented file 'sample.cns' using a static list of threshold log2 cutoffs instead of tumor purity rescaling. How should I specify that parameter?

**ASSISTANT:** You should specify the method parameter as `-m threshold` along with your input `.cns` file.

---

## [333] source=multitask_sft_big

**USER:** I am configuring a run to project my evaluation dataset into a reference embedding. My reference matrix file is 'pbmc_reference_counts.mtx' and my query matrix file is 'pbmc_replicate2_counts.mtx'. How do these map to the `snifter_project_new_data` inputs?

**ASSISTANT:** Based on your files, the parameters for `snifter_project_new_data` map as follows:
- `train_mat`: 'pbmc_reference_counts.mtx'
- `test_mat`: 'pbmc_replicate2_counts.mtx'

---

## [334] source=multitask_sft_big

**USER:** What structure is expected for the input object in the `msfeatures` proteomics workflow, and which underlying tools are utilized?

**ASSISTANT:** The workflow expects a `SummarizedExperiment` object where feature abundances are stored in the assay and retention times are stored in `rowData`. The workflow utilizes `bioconductor/msfeatures`, `bioconductor/summarizedexperiment`, and `bioconductor/pheatmap`.

---

## [335] source=multitask_sft_big

**USER:** When is it appropriate to select the 'No packaged matrix output' option in Scanpy RunFDG?

**ASSISTANT:** Choosing 'No packaged matrix output' is useful when auxiliary files are generated (such as in marker genes). However, do not use it when there are no other output files.

---

## [336] source=multitask_sft_big

**USER:** Here are my files for single-cell enrichment: a count matrix saved as sc_data.rds (SingleCellExperiment format) and gene_sets.rds containing our GeneSetCollection. Map these to the escape workflow inputs.

**ASSISTANT:** The inputs are mapped as follows:
- `sc_data.rds`: Assigned to `sc_data.rds` (type: `rds_sce`, raw single-cell counts)
- `gene_sets.rds`: Assigned to `gene_sets.rds` (type: list of gene sets / GSEABase GeneSetCollection object)

---

## [337] source=multitask_sft_big

**USER:** I want to run celaref_scrna_seq_query_vs_microarray_ref. My query counts matrix file is stored at '/scratch/data/sc_counts_clustered.tsv'. Please set up the required input.

**ASSISTANT:** Here is the extracted parameter for the workflow:

```json
{
  "counts_filepath.query": "/scratch/data/sc_counts_clustered.tsv"
}
```

---

## [338] source=multitask_sft_big

**USER:** I have a CSV file of species abundance counts from an environmental survey with headers on the first line. I want to calculate geometric means. How should the tool parameters be configured?

**ASSISTANT:** For the Geometric means tool, configure the parameters as follows:
- Input: Species abundance table/CSV file
- Separator: `comma`
- Header: `true` (indicates your data has a header)

---

## [339] source=multitask_sft_big

**USER:** Here are my microscope parameters for our Cryo-ET import run: tilt movies are at '/data/ts_01.mrc', metadata at '/data/ts_01.mdoc', acquired at 300 kV, pixel size 1.35 Å, Cs 2.7 mm, total cumulative dose 120 e/Å², ranging from -60 to +60 degrees with 3-degree steps. Please extract the workflow inputs.

**ASSISTANT:** Here are the extracted parameters for the 'Import Tiltseries' workflow:
- tiltseries_path: "/data/ts_01.mrc"
- mdoc_path: "/data/ts_01.mdoc"
- pixel_size: 1.35
- voltage: 300
- spherical_aberration: 2.7
- total_dose: 120
- tilt_range_min: -60
- tilt_range_max: 60
- tilt_increment: 3

---

## [340] source=multitask_sft_big

**USER:** In configuring output attributes for peptide taxonomic identification in Unipept, which fields correspond to the most specific classification before the lineage list?

**ASSISTANT:** The fields to extract or include are `taxon_rank`, `taxon_id`, and `taxon_name`.

---

## [341] source=multitask_sft_big

**USER:** I have deconvolution proportions saved in 'cell_proportions.tsv', sample clinical covariates in 'metadata.csv', and total counts stored in 'sample_totals.rds'. Map these to the speckle_propeller_on_precalculated_proportions input arguments.

**ASSISTANT:** Here is the parameter mapping for `speckle_propeller_on_precalculated_proportions`:
- `pbmc.props`: 'cell_proportions.tsv' (matrix or data frame of cell type proportions)
- `pbmc.sample.info`: 'metadata.csv' (data frame of sample metadata)
- `tot.cells`: 'sample_totals.rds' (vector of total cell counts per sample)

---

## [342] source=multitask_sft_big

**USER:** I am configuring ritan_induced_subnetwork_extraction. My gene list is in candidate_genes.txt and I want to use BIOGRID-ORGANISM-Mus_musculus-3.4.136.symbols.sif.gz as the reference network.

**ASSISTANT:** Here are the extracted input parameters for `ritan_induced_subnetwork_extraction`:
- `my_genes.txt`: `candidate_genes.txt` (required vector of gene symbols)
- `BIOGRID`: `BIOGRID-ORGANISM-Mus_musculus-3.4.136.symbols.sif.gz` (optional user-defined network SIF file)

---

## [343] source=multitask_sft_big

**USER:** Set up the `fpsim2_chemical_similarity` workflow for query 'CC(=O)Oc1ccccc1C(=O)O,c1ccccc1' against the staged database file '/data/fpsim2/chembl_29.h5'.

**ASSISTANT:** Here are the extracted parameters for `fpsim2_chemical_similarity`:
- `query_smiles`: "CC(=O)Oc1ccccc1C(=O)O,c1ccccc1"
- `fpsim2_db`: "/data/fpsim2/chembl_29.h5"

---

## [344] source=multitask_sft_big

**USER:** What outputs does the metaseqr2 workflow produce?

**ASSISTANT:** The metaseqr2 workflow outputs 'counts_matrix' and 'normalized_data'.

---

## [345] source=multitask_sft_big

**USER:** I want to set up the Scfv Antibody Design workflow. Please configure it with 'input_scfv.pdb', create 100 designs at a temperature of 0.7, enable structure prediction, and set top N predictions to 10.

**ASSISTANT:** Here are the extracted parameters for the `scfv_antibody_design` workflow:
- `antibody_pdb`: "input_scfv.pdb"
- `num_designs`: 100
- `temperature`: 0.7
- `predict_structure`: true
- `top_n_predict`: 10

---

## [346] source=multitask_sft_big

**USER:** For my nucleosome calling step in NucleR, set the length of the reads centered around the dyad to 147 bp.

**ASSISTANT:** Extracted parameter for NucleR:
- Read length around dyad center: 147

---

## [347] source=multitask_sft_big

**USER:** I am preparing my script for `safe_covariate_adjusted_safe_analysis`. Here are my variables: gene matrix is `e3.upp`, category matrix is `C.mat`, target status is `p3.upp$p53`, and the confounder to adjust for is `p3.upp$er`. What will the workflow output once executed?

**ASSISTANT:** Based on the inputs provided for `safe_covariate_adjusted_safe_analysis`, the workflow will generate two outputs:
1. `enrichment_results`
2. `pathway_results`

---

## [348] source=multitask_sft_big

**USER:** Configure the CryoSPARC Import Particles workflow to import my RELION stack from 'particles.star' with a pixel size of 0.824 Å, acceleration voltage of 300 kV, and a box size of 256 pixels.

**ASSISTANT:** Here is the parameter configuration for the Import Particles workflow:

```json
{
  "workflow": "Import Particles",
  "input_format": "STAR",
  "particle_star": "particles.star",
  "pixel_size": 0.824,
  "voltage": 300,
  "box_size": 256,
  "use_cryosparc": true
}
```

---

## [349] source=multitask_sft_big

**USER:** Here are my requirements for nf-core/callingcards: set the minimum mapping quality to 20, use barcode pattern 'NNNNTG' for read 1, and set datatype to mammal. Which parameters correspond to these settings?

**ASSISTANT:** Based on the pipeline parameters, the corresponding settings are:
- `min_mapq`: 20
- `r1_bc_pattern`: "NNNNTG"
- `datatype`: "mammal"

---

## [350] source=multitask_sft_big

**USER:** In csvtk-cut, how should I format the input if I want to extract the first and second columns?

**ASSISTANT:** You can specify column indices separated by a comma. For the first and second columns, provide '1,2'.

---

## [351] source=multitask_sft_big

**USER:** What are the inputs, parameters, and underlying tools for the fastqcleaner workflow?

**ASSISTANT:** The `fastqcleaner` workflow has the following specifications:
- **Data Inputs / Parameters:** `input.fastq.gz` (optional: true, described as a compressed FASTQ file containing raw sequencing reads; example input: `example_fastq.gz`).
- **Underlying Tools:** `bioconductor/fastqcleaner`, `bioconductor/biostrings`, and `bioconductor/shortread`.

---

## [352] source=multitask_sft_big

**USER:** What input data slot is declared for the MutationalPatterns workflow, and what data type does it expect?

**ASSISTANT:** The workflow expects the input slot 'input_files' with a data type of 'count_data' (required/non-optional).

---

## [353] source=multitask_sft_big

**USER:** In MITObim, which options are used when supplying a FASTA sequence versus a MAF alignment?

**ASSISTANT:** If a FASTA sequence is provided, MITObim uses it as a bait via the `--quick` option. If a MAF alignment is provided, the reference is extracted from the alignment using the `--maf` option.

---

## [354] source=multitask_sft_big

**USER:** I want to set up the DrugVsDisease workflow for my transcriptomic study. What input data files does it require?

**ASSISTANT:** The DrugVsDisease workflow requires the 'input_files' parameter, which accepts data inputs of type 'count_data' (such as local CEL files or downloaded datasets from ArrayExpress or GEO).

---

## [355] source=multitask_sft_big

**USER:** Here are my inputs for scdesign3: raw count matrix raw_counts.rds and cell pseudotime values cell_traj_times.tsv. Please extract them for the workflow parameters.

**ASSISTANT:** Here are the extracted parameters for the scdesign3 workflow:
- `example_count`: raw_counts.rds (matrix of raw counts)
- `pseudotime`: cell_traj_times.tsv (vector of pseudotime values for cells)

---

## [356] source=multitask_sft_big

**USER:** I want to supply a custom adapter file to 'Fastqc report'. How must the adapter sequences be formatted inside this file?

**ASSISTANT:** The non-default adapter file must contain sets of named adapters structured as `name[tab]sequence`. Any lines prefixed with a hash (`#`) will be ignored as comments.

---

## [357] source=multitask_sft_big

**USER:** Which input files and matrices are required or accepted by the normalyzerde_differential_expression workflow?

**ASSISTANT:** The workflow accepts:
- `CycLoess-normalized.txt`: Selected normalized expression matrix (`CycLoess`, type: matrix, optional: true)
- `tiny_design.tsv`: Design matrix mapping samples to experimental groups.

---

## [358] source=multitask_sft_big

**USER:** We are setting up the mumosa workflow for multi-modal single-cell data. Can you clarify the required data inputs and format specifications?

**ASSISTANT:** The `mumosa` workflow requires a single mandatory input parameter:
- `sce2` (type: `rds_sce`, optional: `false`): A `SingleCellExperiment` object containing RNA-seq data alongside an alternative experiment with ADT/protein data, where both modalities are preprocessed with PCA.

---

## [359] source=multitask_sft_big

**USER:** What is the mandatory input file and format required by the survcomp_performance_comparison_meta_analysis workflow?

**ASSISTANT:** The workflow requires a mandatory input named `Concordance` with the file type `rds`. This RDS file must contain the concordance index objects computed for multiple genes across multiple datasets.

---

## [360] source=multitask_sft_big

**USER:** Run the random landscape simulation for 5 genes using a ruggedness constant c of 0.8.

**ASSISTANT:** The extracted parameters for oncosimulr_random_landscape_predictability are:
- integer (number of genes): 5
- numeric (ruggedness constant c): 0.8

---

## [361] source=multitask_sft_big

**USER:** What are the input data parameters and potential output formats for `regioner_local_zscore_analysis`?

**ASSISTANT:** The workflow accepts two peak data inputs:
- `Rad21.gz` (ChIP-seq peak file for Rad21, optional: true)
- `Ctcf.gz` (ChIP-seq peak file for CTCF, optional: true)

It generates the following outputs:
- `table/csv`
- `plot/pdf`
- `object/rds`

---

## [362] source=multitask_sft_big

**USER:** In SeedListGenerator, what is the default m/z position behavior, and what option can be configured when providing idXML input?

**ASSISTANT:** By default, `SeedListGenerator` uses the precursor m/z for the m/z position. However, for idXML input only, you can configure it to use the monoisotopic mass of the best peptide hit instead.

---

## [363] source=multitask_sft_big

**USER:** I want to configure the Polyaminer Bulk workflow with a mouse reference. Set min reads per site to 15, usage change threshold to 0.15, FDR cutoff to 0.05, strand to forward, memory limit to 32GB, and request 8 CPUs for 12 hours.

**ASSISTANT:** Here are the extracted parameters for the Polyaminer Bulk workflow:
- `min_reads_per_site`: 15
- `min_usage_change`: 0.15
- `fdr_threshold`: 0.05
- `strand`: "forward"
- `max_memory`: "32GB"
- `max_cpus`: 8
- `max_time`: "12h"

---

## [364] source=multitask_sft_big

**USER:** What input file is required for the multirnaflow workflow and how should the columns be formatted?

**ASSISTANT:** The required input is `raw_counts.csv`, which is a CSV file containing raw RNA-seq counts with genes in rows and samples in columns. The column names must be formatted with underscore-separated metadata, such as `Condition_Time_Replicate`.

---

## [365] source=multitask_sft_big

**USER:** Configure gsri_multiple_gene_sets_analysis using my expression matrix 'norm_expr.RData', sample metadata 'metadata_classes.csv', and gene signatures 'c2_pathways.gmt'.

**ASSISTANT:** Here are the extracted parameters for `gsri_multiple_gene_sets_analysis`:
- `expression_data.RData`: "norm_expr.RData"
- `phenotypes.csv`: "metadata_classes.csv"
- `gene_sets.gmt`: "c2_pathways.gmt"

---

## [366] source=multitask_sft_big

**USER:** What input formats and data inputs are accepted by the `katdetectr` workflow?

**ASSISTANT:** The `katdetectr` workflow accepts three input options:
- `pathToVCF` (or `genomic_variants.vcf`): a VCF file containing genomic variants
- `pathToMAF`: a MAF file containing genomic variants from single or multiple samples
- `syntheticData`: a `VRanges` object containing genomic variants.

---

## [367] source=multitask_sft_big

**USER:** In Decoupler pseudo-bulk, how should I specify grouping fields if I want to merge 'donor' with 'cell_type', and also merge 'treatment' with 'time_point'?

**ASSISTANT:** In Decoupler pseudo-bulk, fields within each group are merged using comma separation, and multiple groups are separated by a colon (:). To merge 'donor' and 'cell_type' as one grouping and 'treatment' and 'time_point' as a second, specify: donor,cell_type:treatment,time_point.

---

## [368] source=multitask_sft_big

**USER:** I am configuring the `gviz_gene_region_visualization` workflow. Can I skip supplying the `geneModels` table?

**ASSISTANT:** No, `geneModels` is a mandatory parameter (`optional: false`). You must provide a table containing gene model coordinates and identifiers for the workflow to generate visualizations.

---

## [369] source=multitask_sft_big

**USER:** I am configuring the tool 'Verify that two input SAM files are present' for standard BayesASE analysis without modifications. How should I set the alignment type parameter?

**ASSISTANT:** For BayesASE without modification, you should select 'Single End' for the alignment type parameter.

---

## [370] source=multitask_sft_big

**USER:** Under what exact atom-count condition does the Compound search tool output matching molecules?

**ASSISTANT:** The Compound search tool prints matching molecules only when the number of heavy atoms in the molecule equals the number of atoms specified in the SMARTS pattern.

---

## [371] source=multitask_sft_big

**USER:** I want to run the scfeatures workflow. What specific data inputs do I need to prepare beforehand?

**ASSISTANT:** You need two data inputs:
1. `expression_matrix.rds`: A normalized single-cell RNA-seq expression matrix (stored as an RDS file).
2. `metadata.csv`: Cell-level metadata containing sample identifiers and cell-type annotations.

---

## [372] source=multitask_sft_big

**USER:** I want to run `genestructuretools_dexseq_and_gtf_reannotation` to overlap my DEXSeq results with reannotated GTF features. What are the mandatory input files required?

**ASSISTANT:** The workflow requires three main data inputs:
1. `example_gtf.gtf`: A GTF annotation file for feature reannotation (UTRs and broad biotypes).
2. `dexseq_results_significant.txt`: A table containing significant DEXSeq results.
3. `gencode.vM14.dexseq.gtf`: The DEXSeq exonic parts GTF file used to overlap and identify exonic part types affected by differential usage.

---

## [373] source=multitask_sft_big

**USER:** Extract the parameters for running `Nanoparticle Pk Biodistribution` from this setup: We administered a 5 mg/kg dose of nanoparticles with a diameter of 50 nm, neutral surface chemistry, PEG molecular weight of 2000 Da, PEG density of 0.5 chains/nm2, and zeta potential of -12 mV into a 4T1 tumor model for a 48-hour simulation.

**ASSISTANT:** Here are the extracted parameters for `Nanoparticle Pk Biodistribution`:
- `particle_diameter_nm`: 50
- `surface_chemistry`: "neutral"
- `PEG_density_chains_nm2`: 0.5
- `PEG_MW_Da`: 2000
- `dose_mg_kg`: 5
- `tumor_model`: "4T1"
- `zeta_potential_mV`: -12
- `simulation_hours`: 48

---

## [374] source=multitask_sft_big

**USER:** I am configuring pram_step_by_step_pram_analysis for retrospective RNA-seq study. My inputs are /data/ref_annot.gtf and /alignments/sample1_sorted.bam. Map these to the workflow parameters.

**ASSISTANT:** The workflow input mapping is:
- `in_gtf`: /data/ref_annot.gtf (GTF file of existing gene annotations)
- `finbam`: /alignments/sample1_sorted.bam

---

## [375] source=multitask_sft_big

**USER:** I want to run range2tag on aligned_reads.sam using regions defined in target_intervals.txt, saving the output tags to extracted_tags.txt.

**ASSISTANT:** Extracted parameters for Duplex Sequencing Analysis: range2tag:
- SAM file: `aligned_reads.sam`
- TXT file (start/stop positions): `target_intervals.txt`
- Output file: `extracted_tags.txt`

---

## [376] source=multitask_sft_big

**USER:** Is the `curto.xml` parameter required to execute `sbmlr`, and how is it defined?

**ASSISTANT:** No, `curto.xml` is defined as an optional data input parameter (`optional: true`, `type: data`) representing an SBML model file, with `read_by_workflow: false`.

---

## [377] source=multitask_sft_big

**USER:** I am configuring `supersigs_partial_signature_adjustment`. Here are my inputs: my trinucleotide mutation matrix is stored in `sample_mut_matrix.tsv` and I have a trained signature object `sig_confounder.rds`. Please map these to the required inputs.

**ASSISTANT:** Here is the parameter mapping for `supersigs_partial_signature_adjustment`:
- `input_dt`: `sample_mut_matrix.tsv` (Trinucleotide mutation matrix data frame, type: matrix)
- `supersig`: `sig_confounder.rds` (Trained SuperSig object)

---

## [378] source=multitask_sft_big

**USER:** Can you check the parameter list for 'visium_voyager_spatial_esda' and tell me the required data input parameter for the Space Ranger directory?

**ASSISTANT:** The required parameter is 'spaceranger_dir'. It is a non-optional directory path pointing to the 10X Space Ranger output directory that contains 'outs/spatial/' and 'outs/filtered_feature_bc_matrix'.

---

## [379] source=multitask_sft_big

**USER:** Configure the fgnet workflow for my yeast analysis. My gene identifiers are in 'yeast_hits.txt' and I also have an optional expression vector file 'yeast_expr.rds'.

**ASSISTANT:** I have extracted the parameters for the fgnet workflow:
- genesYeast: 'yeast_hits.txt' (character vector of gene symbols/IDs, required)
- genesYeastExpr: 'yeast_expr.rds' (named numeric vector of gene expression values, optional)

---

## [380] source=multitask_sft_big

**USER:** I want to annotate my imputed variants using bcftools plugin impute-info. Will it work if my file only has genotype dosage (DS) tags but lacks GP tags?

**ASSISTANT:** No. `Bcftools Pluginimputeinfo` specifically requires `FORMAT/GP` tags to compute the IMPUTE2 INFO metric. If your file only has `DS` tags and lacks `FORMAT/GP`, the metric cannot be generated.

---

## [381] source=multitask_sft_big

**USER:** What inputs must I provide to run blma_network_based_integrative_analysis, and what outputs does it generate?

**ASSISTANT:** The workflow requires two mandatory data inputs:
- `dataList`: A list of expression matrices from multiple datasets.
- `groupList`: A list of group label vectors corresponding to those datasets.

It generates two outputs:
- `de_table`: The differential expression table across studies.
- `pathway_results`: Downstream network-based pathway analysis results.

---

## [382] source=multitask_sft_big

**USER:** Why shouldn't I just set the k-mer length in Salmon as high as possible?

**ASSISTANT:** While longer k-mers increase sequence distinctiveness, they reduce robustness to sequencing errors in reads. If a read contains errors, a longer k-mer is more likely to span a mismatch and fail to match the index.

---

## [383] source=multitask_sft_big

**USER:** I want OpenSwathChromatogramExtractor to extract signal spanning 15 milliseconds before and 15 milliseconds after my targeted retention time. What parameter value should I provide for the window size?

**ASSISTANT:** Because the window size in OpenSwathChromatogramExtractor represents the full window length (extracting half the value on either side), you should set the full window size parameter to 30 milliseconds (or 30 ms) to extract 15 milliseconds on either side.

---

## [384] source=multitask_sft_big

**USER:** Which DFTB+ parameter sets are supported in PyMuonSuite Phonons?

**ASSISTANT:** In **PyMuonSuite Phonons**, the currently supported DFTB+ parameter sets are `3ob-3-1` and `pbc-0-3`.

---

## [385] source=multitask_sft_big

**USER:** What read extension options does damidseq provide, and what is the default setting?

**ASSISTANT:** damidseq provides two options for read extension: 'Full', which extends all reads, and 'GATC', which extends reads to --len or to the next GATC site (whichever is shorter). 'GATC' is the default setting and increases peak resolution.

---

## [386] source=multitask_sft_big

**USER:** What value should I set for the insert size in hicBuildMatrixMicroC if I don't know the exact higher-end fragment size from an analyzer?

**ASSISTANT:** If the value is not known, you should use the default value of 1000. Note that this parameter represents the higher end of the fragment size distribution (typically between 800 to 1500 bp, as measured by instruments like a Fragment Analyzer) rather than the average fragment size.

---

## [387] source=multitask_sft_big

**USER:** In multiple_rarefactions_even_depth, does the tool automatically include taxonomic lineage metadata in the output rarefied OTU tables?

**ASSISTANT:** No. The option to include taxonomic (lineage) information for each OTU defaults to `False`. To include it, you must enable this setting, and the taxonomic information must already be present in the input OTU table.

---

## [388] source=multitask_sft_big

**USER:** What outputs can I expect to receive once the nadfinder_replicated_nad_seq workflow finishes processing?

**ASSISTANT:** The nadfinder_replicated_nad_seq workflow produces two main outputs: a differential enrichment table ('de_table') detailing the identified nucleolar-associated domains and associated graphical 'visualizations'.

---

## [389] source=multitask_sft_big

**USER:** What outputs does the mosbi workflow produce when it finishes running?

**ASSISTANT:** The `mosbi` workflow produces three outputs: `cluster_assignments`, `consensus_score`, and `normalized_data`.

---

## [390] source=multitask_sft_big

**USER:** What input data parameters does the DFplyr workflow accept?

**ASSISTANT:** The DFplyr workflow declares an optional input slot named `count_data` (type: data).

---

## [391] source=multitask_sft_big

**USER:** I need to configure oncoscanr_ascat_workflow. My input file is named 'tumor_segments.tsv', which contains chromosome numbers, start positions, and end positions. What input parameter does this satisfy?

**ASSISTANT:** This satisfies the mandatory data input 'ascat_example.txt', which expects an ASCAT output text file containing chr, startpos, and endpos.

---

## [392] source=multitask_sft_big

**USER:** What input files does the mogamun workflow accept, and what columns are expected in the differential expression file?

**ASSISTANT:** The mogamun workflow accepts the following inputs:
1. `Sample_DE.csv`: A comma-separated file containing gene names, FDR/PValue, and optionally logFC.
2. `Sample_NodesScore.csv`: An optional comma-separated file with pre-calculated node scores.
3. `NetworkLayersDir`: A directory of 2-column tab-separated network files, each starting with a unique character.

The resulting output is a differential expression table (`de_table`) representing active modules.

---

## [393] source=multitask_sft_big

**USER:** In the command line tool for `metaQuantome: visualize`, how are colors represented when customizing heatmaps or PCA plots?

**ASSISTANT:** In the command line interface of `metaQuantome: visualize`, the colors are coded as integers from 1 through 6.

---

## [394] source=multitask_sft_big

**USER:** I am configuring Scmap index clusters on my SingleCellExperiment object. Which parameter specifies the cell annotations, and what does it point to?

**ASSISTANT:** You need to specify the column name in the 'colData' slot of the SingleCellExperiment object that contains the cell classification information.

---

## [395] source=multitask_sft_big

**USER:** What outputs does the enrichmentbrowser workflow generate?

**ASSISTANT:** The enrichmentbrowser workflow outputs:
- `de_table`: The differential expression analysis table.
- `enrichment_results`: Results from set-based and network-based enrichment analyses.
- `consensus_score`: Combined consensus enrichment scores.

---

## [396] source=multitask_sft_big

**USER:** Please set up `edge_sva_de_analysis` with my files: `counts_kidney.mat` for expression values, `patient_sex.csv` for sex, and `patient_age.csv` for age.

**ASSISTANT:** Here is the parameter mapping for `edge_sva_de_analysis`:
- `kidexpr`: `counts_kidney.mat` (matrix of gene expression measurements)
- `sex`: `patient_sex.csv` (vector of sex covariates)
- `age`: `patient_age.csv` (vector of age covariates)

---

## [397] source=multitask_sft_big

**USER:** Here is my QC analysis plan: 'Please inspect sample_R1.fastq using Calculate sequence complexity to see the unique base pair distribution.' What are the target inputs?

**ASSISTANT:** The extracted tool and input are:
- Tool: Calculate sequence complexity
- Input: `sample_R1.fastq` (FastQ format)
- Metrics generated: Per-Read and Total Sequence Complexity.

---

## [398] source=multitask_sft_big

**USER:** I want to run Chai1 Structure Prediction for my protein fasta file 'target.fasta'. I want 3 trunk recycles, 200 diffusion timesteps, and random seed 42. Extract these into the workflow inputs.

**ASSISTANT:** Here are the extracted parameters for the `chai1_structure_prediction` workflow:
- `input_fasta`: "target.fasta"
- `num_trunk_recycles`: 3
- `num_diffusion_timesteps`: 200
- `seed`: 42

---

## [399] source=multitask_sft_big

**USER:** When PyMuonSuite Quantum Averaging generates displacements on a muonated structure, does it overwrite the original input file?

**ASSISTANT:** No, the original file is preserved when displacements are made to the muonated structure.

---

## [400] source=multitask_sft_big

**USER:** What inputs do I need to prepare to run gep2pep_condition_set_enrichment_analysis?

**ASSISTANT:** You need to provide two mandatory data inputs:
1. `rp`: a gep2pep repository containing PEPs.
2. `pgset`: a character vector of conditions or drugs of interest.

---

## [401] source=multitask_sft_big

**USER:** Here are my files for variant analysis:
- gwas_snps.csv (GWAS table with SNP IDs, p-values, chr, and positions)
- pathways.gmt (GMT collection containing Entrez IDs)
- snp_correlation.rds (symmetric LD correlation matrix)

Can you assign these to the `cpvsnp_vegas_analysis` workflow parameters?

**ASSISTANT:** Here is the parameter mapping for `cpvsnp_vegas_analysis`:
- `arrayData.csv`: `gwas_snps.csv`
- `gene_sets.gmt`: `pathways.gmt`
- `ld_matrix.rds`: `snp_correlation.rds`

---

## [402] source=multitask_sft_big

**USER:** I have preprocessed patient expression profiles in `patient_expr_matrix.tsv` and clinical outcomes in `patient_surv_censoring.csv`. Map these to the inputs for rcaspar_survival_prediction_with_cross_validation.

**ASSISTANT:** The inputs are mapped as follows:
- `geData`: `patient_expr_matrix.tsv` (matrix of covariates for all patients)
- `survData`: `patient_surv_censoring.csv` (data frame of survival times and censorship for all patients)

---

## [403] source=multitask_sft_big

**USER:** Please prepare a query for Retrieve an analysis report using accession id ERR1234567.

**ASSISTANT:** For the 'Retrieve an analysis report' tool, the extracted parameter is:
- Accession ID: ERR1234567

---

## [404] source=multitask_sft_big

**USER:** I am configuring ruvnormalize_iterative_ruv. My count data is in 'counts_transposed.csv' (samples as rows, genes as columns), my technical replicates are tracked in 'rep_matrix_padded.csv' (with -1 padding), and I have housekeepers in 'housekeeper_genes.txt'. Map these to the workflow inputs.

**ASSISTANT:** Here is the parameter mapping for the `ruvnormalize_iterative_ruv` workflow:
- `expression_matrix.csv`: `counts_transposed.csv`
- `negative_controls.txt`: `housekeeper_genes.txt`
- `replicates_mapping.csv`: `rep_matrix_padded.csv`

---

## [405] source=multitask_sft_big

**USER:** What outputs are generated when running `cytopipeline_flowai_json_preprocessing_pipeline` on flow cytometry data?

**ASSISTANT:** The `cytopipeline_flowai_json_preprocessing_pipeline` workflow produces three output types:
- `table/csv`: Tabular quality control and processing metrics.
- `plot/pdf`: Diagnostic and QC visualization plots.
- `object/rds`: Processed R data objects containing the preprocessed flow cytometry data.

---

## [406] source=multitask_sft_big

**USER:** Please set up the spsimseq workflow using my real count matrix file 'zhang.counts' and the sample grouping vector 'MYCN.status'.

**ASSISTANT:** Extracted parameters for the spsimseq workflow:
- `zhang.counts`: "zhang.counts" (matrix of real bulk RNA-seq counts)
- `MYCN.status`: "MYCN.status" (vector of grouping variables for the samples)

---

## [407] source=multitask_sft_big

**USER:** What example values and parameters are provided for enforcing GC content constraints in the Evaluate Manufacturability documentation?

**ASSISTANT:** The example provides the following constraint parameters: `mini=0.3`, `maxi=0.7`, and `window=100` under 'Enforce GC Content Constraints'.

---

## [408] source=multitask_sft_big

**USER:** Set up mbased execution with genomic coordinates from /experiments/sample1_snvs.bed and allele counts from /experiments/sample1_counts.tsv.

**ASSISTANT:** Extracted parameters for the `mbased` workflow:
- `snv_coordinates.bed`: `/experiments/sample1_snvs.bed` (genomic coordinates of SNVs with gene/aseID annotations)
- `rna_seq_counts.tsv`: `/experiments/sample1_counts.tsv` (allele-specific RNA-seq read counts for each SNV)

---

## [409] source=multitask_sft_big

**USER:** Extract the simulation and MM-GBSA parameters from this request: 'Run GROMACS Protein-Ligand MD with receptor target.pdb and ligand drug.mol2 at 310 K and 1.0 bar. For MM-GBSA, analyze from frame 50 to 500 with a step interval of 5.'

**ASSISTANT:** Extracted parameters:
- `receptor`: target.pdb
- `ligand`: drug.mol2
- `temperature`: 310
- `pressure`: 1.0
- `mmgbsa_startframe`: 50
- `mmgbsa_endframe`: 500
- `mmgbsa_interval`: 5

---

## [410] source=multitask_sft_big

**USER:** What input slots are configured for the pepXMLTab workflow?

**ASSISTANT:** The `pepxmltab` workflow lists `plot_object` in its workflow inputs and defines `input_files` (type: data, non-optional) as the declared Nextflow input slot.

---

## [411] source=multitask_sft_big

**USER:** What input file does the `kissde_snv_snp_analysis` workflow accept, and what is its expected format?

**ASSISTANT:** The workflow accepts `output_kissplice_SNV.fa`, which is a KisSplice FASTA output file containing single nucleotide variation (SNV) sequences.

---

## [412] source=multitask_sft_big

**USER:** I want to run the `scfa` workflow. What inputs must I prepare, and how should they be structured?

**ASSISTANT:** You need to provide two non-optional data inputs for the `scfa` workflow:
1. `dataList`: A list of matrices, each representing a molecular data type with samples as rows and features as columns.
2. `survival`: A data frame containing survival time and event status for the samples.

---

## [413] source=multitask_sft_big

**USER:** In Homova, how should I specify that I only want to analyze sets 'GroupA' and 'GroupB' from my design file?

**ASSISTANT:** In the `sets` parameter of Homova, enter the set names separated by dashes: `GroupA-GroupB`. If this parameter is left blank, the tool defaults to analyzing all sets found in your design file.

---

## [414] source=multitask_sft_big

**USER:** I have prepared `network.graph` as my igraph RDS object and `node_scores.csv` containing the initial scores. What specific outputs should I expect when the diffustats workflow finishes?

**ASSISTANT:** The `diffustats` workflow will produce three primary outputs:
1. `de_table`: The resulting candidate prioritization table with smoothed scores.
2. `network_graph`: The processed network structure.
3. `visualizations`: Visual plots representing the smoothed scores and network propagation results.

---

## [415] source=multitask_sft_big

**USER:** I want to run `vidger_edger_dge_visualization` on my stored file `counts_dge.rds`, which is an edgeR DGEList containing CPM and DGE statistics. How should this be specified in the workflow inputs?

**ASSISTANT:** You should supply your file to the required input parameter `df.edger`:
- `df.edger`: "counts_dge.rds" (type: rds, representing the edgeR DGEList or results object/data frame containing CPM and DGE statistics).

---

## [416] source=multitask_sft_big

**USER:** What is the default distance WindowBed adds upstream and downstream of features in file A?

**ASSISTANT:** bedtools WindowBed adds 1000 base pairs upstream and downstream of each feature in A by default.

---

## [417] source=multitask_sft_big

**USER:** I have prepared my dataset file at `data/gRNAs_and_targets.csv` containing 20bp spacer sequences for scoring CRISPR specificity. Please configure the workflow inputs for crisprscore_off_target_specificity_scoring.

**ASSISTANT:** The extracted parameter configuration is:
- `gRNAs_and_targets.csv`: `data/gRNAs_and_targets.csv`

This matches the non-optional data input required by the `crisprscore_off_target_specificity_scoring` workflow.

---

## [418] source=multitask_sft_big

**USER:** What options are available for the enzyme parameter in PercolatorAdapter?

**ASSISTANT:** In PercolatorAdapter, the available enzyme options are: 'no_enzyme', 'elastase', 'pepsin', 'proteinasek', 'thermolysin', 'chymotrypsin', 'lys-n', 'lys-c', 'arg-c', 'asp-n', 'glu-c', 'trypsin', and 'trypsinp'.

---

## [419] source=multitask_sft_big

**USER:** I have prepared two inputs for piuma: a normalized table named 'norm_counts.tsv' with metadata columns, and a SummarizedExperiment object called 'se_experiment.rds'. Map these to the workflow inputs.

**ASSISTANT:** Based on the piuma workflow specifications, the mapping is:
- `df_TDA`: 'norm_counts.tsv' (data.frame containing normalized expression values and metadata columns)
- `dataSE`: 'se_experiment.rds' (SummarizedExperiment object containing normalized assay data and colData metadata)

---

## [420] source=multitask_sft_big

**USER:** I am configuring the 'Identify clusters' tool in Epigenetics and want to use the Leiden algorithm for modularity optimization. Which numeric option should I choose?

**ASSISTANT:** You should select option 4. In the 'Identify clusters' tool, the 'Algorithm for modularity optimization' parameter maps option 4 to the Leiden algorithm.

---

## [421] source=multitask_sft_big

**USER:** I am configuring 'Save Sequence Data In DB'. Where should the database connection URI be passed if I use a JSON configuration file?

**ASSISTANT:** You should specify the database URI under the JSON key `'JSON_db_uri'`, formatted as `postgresql://container_name:password@host:port/path/to/database`.

---

## [422] source=multitask_sft_big

**USER:** I want to run PoseIndices2PDB to extract poses. The input reference structure is 'target_ref.pdb' and the transformations are stored in 'docking_poses.trans'. Please identify the required inputs.

**ASSISTANT:** For PoseIndices2PDB, the required inputs extracted from your request are:
- Reference PDB file: `target_ref.pdb`
- Transformation file containing pose indices: `docking_poses.trans`

The tool will use these to generate individual PDB files for each pose.

---

## [423] source=multitask_sft_big

**USER:** Please set up the input for the pcamethods_expressionset_pca_imputation workflow using my saved object at 'data/cohort_exprs.rds'.

**ASSISTANT:** Extracted parameter configuration for pcamethods_expressionset_pca_imputation:
- `sample.ExpressionSet`: "data/cohort_exprs.rds" (Type: rds, Bioconductor ExpressionSet object containing gene expression data).

---

## [424] source=multitask_sft_big

**USER:** I need to configure candidate_genes.tsv for the gofuncr workflow. What structure must this file have?

**ASSISTANT:** The `candidate_genes.tsv` input must be a tabular dataframe containing gene symbols alongside a binary candidate indicator column (e.g., specifying candidate vs. non-candidate/background genes).

---

## [425] source=multitask_sft_big

**USER:** What input data object and file format are required by the 'mimager_transformed_array_visualization' workflow?

**ASSISTANT:** The workflow requires 'raw_microarray_data.RData' (type: rds, non-optional), which must be an AffyBatch or FeatureSet object containing raw microarray intensities.

---

## [426] source=multitask_sft_big

**USER:** Set up the data inputs for the ptairms pipeline using raw data located at '/data/ptr_tof_runs/' and metadata at '/data/ptr_tof_runs/sampleMetadata.tsv'.

**ASSISTANT:** Configured inputs for the `ptairms` workflow:
- `directory`: '/data/ptr_tof_runs/'
- `sampleMetadata.tsv`: '/data/ptr_tof_runs/sampleMetadata.tsv'

---

## [427] source=multitask_sft_big

**USER:** In ProgenesisConverter for my label-free proteomics run, the 'Score' column contains mixed peptide search scores derived from both MSE and DDA acquisitions. Should I enable any specific option?

**ASSISTANT:** Yes, you should set the option in `ProgenesisConverter` designated for when scores in the 'Score' column come from two or more different schemes (e.g., MSE and DDA). This informs the converter to correctly handle and normalize heterogeneous scoring metrics.

---

## [428] source=multitask_sft_big

**USER:** What are all the required and optional input channels/parameters for running `nf-core/bam_dedup_umi`?

**ASSISTANT:** The input channels and parameters for `nf-core/bam_dedup_umi` are:
- `ch_genome_bam`
- `ch_fasta`
- `umi_dedup_tool`
- `umitools_dedup_stats`
- `bam_csi_index`
- `ch_transcriptome_bam`
- `ch_transcript_fasta`

---

## [429] source=multitask_sft_big

**USER:** I want to run Sample SNPs on our GWAS dataset to downsample the marker set to roughly 25,000 evenly spaced variants across the genome.

**ASSISTANT:** Extracted parameter for **Sample SNPs**:

- **Target number of SNPs**: `25000`

Note that the tool will sample variants approximately uniformly spaced relative to the reference genome, so the final count may slightly exceed 25,000.

---

## [430] source=multitask_sft_big

**USER:** What is the declared input parameter name required by the phenoTest workflow for supplying count data?

**ASSISTANT:** The phenoTest workflow specifies `input_files` as its declared input data slot (which takes `count_data`).

---

## [431] source=multitask_sft_big

**USER:** Extract the tools utilized and expected output formats for the gewist workflow.

**ASSISTANT:** For the `gewist` workflow:
- **Tools**: `bioconductor/gewist` and `bioconductor/car`
- **Outputs**: `table/csv`, `plot/pdf`, and `object/rds`

---

## [432] source=multitask_sft_big

**USER:** What input parameters or data slots does the iSEEde workflow accept?

**ASSISTANT:** The iSEEde workflow defines an optional input data slot named `count_data` (declared as an input slot, though not read directly by the workflow as it relies on precomputed differential expression data).

---

## [433] source=multitask_sft_big

**USER:** Here is my small-molecule input file 'lead_candidates.smiles'. Please prepare the metabolite_prediction_biotransformer pipeline to generate the results.

**ASSISTANT:** The parameters extracted for `metabolite_prediction_biotransformer` are:
- `smiles`: "lead_candidates.smiles"

The pipeline will process these structures using RDKit AllChem with BioTransformer 3.0-derived SMARTS rules and return output in `json` and `csv` formats.

---

## [434] source=multitask_sft_big

**USER:** If I execute spec2vec similarity without setting an explicit value for the intensity power, what value is used and how does it affect word weighting?

**ASSISTANT:** The default power value is 0. With this setting, word intensities are raised to the power of 0, meaning that no intensity-based weighting is performed when calculating the weighted sum of word vectors.

---

## [435] source=multitask_sft_big

**USER:** Can you list the required data inputs and execution parameters for the rpx workflow?

**ASSISTANT:** The `rpx` workflow has one required input slot: `input_files` (type: data, mandatory, declared .nf input slot reading count_data). It does not declare additional standalone execution parameters (`parameters: []`).

---

## [436] source=multitask_sft_big

**USER:** What are the required input formats for genotypes, phenotypes, and covariates in the hiergwas workflow?

**ASSISTANT:** The inputs required by the `hiergwas` workflow are:
- `genotype_matrix.txt`: An n x p matrix of numerically coded SNPs (0, 1, 2).
- `phenotype_vector.txt`: A vector of length n (binary or continuous).
- `covariates.txt`: An optional vector or matrix containing covariates.

---

## [437] source=multitask_sft_big

**USER:** What specific data inputs are required to execute the milor_da_glmm_random_effects workflow?

**ASSISTANT:** The workflow requires two data inputs: `pbmc.sce` (a SingleCellExperiment object in `rds_sce` format containing single-cell counts and reduced dimensions) and `pbmc.design` (a `data.frame` mapping samples to fixed and random effect covariates).

---

## [438] source=multitask_sft_big

**USER:** Can you list the tools and outputs generated by the qfeatures workflow?

**ASSISTANT:** The `qfeatures` workflow utilizes the following tools:
- `bioconductor/qfeatures`
- `bioconductor/complexheatmap`
- `bioconductor/dplyr`
- `bioconductor/ggplot2`
- `bioconductor/gplots`

Its outputs are:
- `normalized_data`
- `visualizations`

---

## [439] source=multitask_sft_big

**USER:** Here is my configuration for running sarks:
`sequences_data <- setNames(c('ATGCGCTA', 'CGTATCGA'), c('seq1', 'seq2'))`
`score_values <- setNames(c(3.4, -1.2), c('seq1', 'seq2'))`
How do these map to the sarks workflow parameters?

**ASSISTANT:** The inputs map to the sarks workflow parameters as follows:
- `simulatedSeqs`: `sequences_data` (mapped as the named character vector of sequences)
- `simulatedScores`: `score_values` (mapped as the named numeric vector of scores)

---

## [440] source=multitask_sft_big

**USER:** I'm passing single segmented and ground truth image files rather than zip archives to 'Compute image segmentation and object detection performance measures'. What configuration do I need to be careful of?

**ASSISTANT:** When using a pair of individual images instead of archives, you must turn off the 'Unzip' option.

---

## [441] source=multitask_sft_big

**USER:** What is the syntax to enforce GC content constraints between 30% and 70% across a 100 bp window in Workflow-0 Parameters Maystro?

**ASSISTANT:** In Workflow-0 Parameters Maystro, you can specify GC content constraints using the syntax:
`mini=0.3, maxi=0.7, window=100`

---

## [442] source=multitask_sft_big

**USER:** Does the `xmapbridge` workflow define any configurable parameters, and what tool does it execute?

**ASSISTANT:** The `xmapbridge` workflow executes the tool `bioconductor/xmapbridge`. It does not declare any configurable execution parameters beyond the mandatory data input `input_files`.

---

## [443] source=multitask_sft_big

**USER:** What input data files are listed as data inputs for the `normalyzerde_stepwise_processing` workflow?

**ASSISTANT:** The workflow defines `tiny_data.tsv` (matrix, raw expression matrix) and `tiny_design.tsv` as data inputs.

---

## [444] source=multitask_sft_big

**USER:** What are the declared input files for the busparse_transcript_to_gene_mapping workflow?

**ASSISTANT:** The declared data inputs for the 'busparse_transcript_to_gene_mapping' workflow are:
- 'fasta_test.fasta': transcriptome FASTA file (type: fasta, optional: true)
- 'gtf_test.gtf': gene annotation file (type: gtf, optional: true)

---

## [445] source=multitask_sft_big

**USER:** What data inputs are required to run `amountain_multi_layer_module_detection`?

**ASSISTANT:** The workflow requires two mandatory data inputs:
1. `W`: A matrix representing the shared edge weight matrix/network.
2. `listz`: A list containing node score vectors, with one vector corresponding to each network layer.

---

## [446] source=multitask_sft_big

**USER:** I have my sequencing tracks ready. What inputs does `seqsetvis_signal_profiling_and_clustering` require according to its definition?

**ASSISTANT:** The workflow requires `bw_files` (a named vector of file paths to BigWig files, marked as required with `optional: false`) and `olaps`.

---

## [447] source=multitask_sft_big

**USER:** Please set up the metabolite prediction biotransformer workflow for my molecules: 'CC(=O)NC1=CC=C(O)C=C1' and 'CC1=CC=C(C=C1)S(=O)(=O)N', simulating both phase I and phase II metabolism across up to 3 reaction cycles with a minimum confidence threshold of 0.65.

**ASSISTANT:** Here are the extracted parameters for the Metabolite Prediction Biotransformer workflow:
- `smiles_list`: ["CC(=O)NC1=CC=C(O)C=C1", "CC1=CC=C(C=C1)S(=O)(=O)N"]
- `metabolism_type`: "phase I and phase II"
- `max_cycles`: 3
- `min_confidence`: 0.65

---

## [448] source=multitask_sft_big

**USER:** When merging compartments in TopologicalPathwayAnalysis, when should I use names versus identifiers?

**ASSISTANT:** Use names if they are consistent and unambiguous across compartments. Alternatively, use identifiers if a compartment suffix is present in the format 'xxx_y' (with 'xxx' as the base identifier and 'y' as the compartment label).

---

## [449] source=multitask_sft_big

**USER:** What output does the cliprofiler_custom_window_profiling workflow generate once it processes the peaks.rds and custom_annotation.gff3 files?

**ASSISTANT:** The `cliprofiler_custom_window_profiling` workflow produces `visualizations` as its output.

---

## [450] source=multitask_sft_big

**USER:** I want to fine-map chromosome 4 from position 10000000 to 20000000 comparing case strains (NOD/ShiLtJ, NZO/HlLtJ) against control strains (C57BL/6J, 129S1/SvImJ) using mousefm. How does this map to the inputs?

**ASSISTANT:** The workflow input slot 'Genomic' will receive:
- Coordinates: chromosome 4, start: 10000000, end: 20000000
- Mouse strain groups: case strains (NOD/ShiLtJ, NZO/HlLtJ) vs. control strains (C57BL/6J, 129S1/SvImJ).

---

## [451] source=multitask_sft_big

**USER:** I am preparing to run `raresim_estimate_expected_variants_with_defaults`. Here is my input list: `inputs = {'mac_bins.csv': '/data/cohort/mac_bins.csv'}`. Extract the required parameters and outputs.

**ASSISTANT:** Extracted configuration for `raresim_estimate_expected_variants_with_defaults`:
- **Required Data Input**: `mac_bins.csv` (provided: `/data/cohort/mac_bins.csv`), defining the lower and upper boundaries of the MAC bins.
- **Output**: `burden_test_results`
- **Parameters**: Ancestry-specific default parameters are applied automatically by the workflow.

---

## [452] source=multitask_sft_big

**USER:** Run the oral absorption BCS pipeline for atorvastatin with SMILES CC(C)c1c(C(=O)Nc2ccccc2)c(-c2ccccc2)c(-c2ccc(F)cc2)n1CC[C@@H](O)C[C@@H](O)CC(=O)O at an oral dose of 20 mg.

**ASSISTANT:** Here are the extracted parameters for the `oral_absorption_bcs_model` workflow:
- `smiles`: "CC(C)c1c(C(=O)Nc2ccccc2)c(-c2ccccc2)c(-c2ccc(F)cc2)n1CC[C@@H](O)C[C@@H](O)CC(=O)O"
- `dose_mg`: 20

---

## [453] source=multitask_sft_big

**USER:** I have my pilot single-cell expression data saved as `pilot_data.rds`. If I feed this into the scdd_single_cell_simulation workflow, what output will be produced?

**ASSISTANT:** The workflow accepts `pilot_data.rds` (a SingleCellExperiment object) and generates a simulated dataset structured as a `singlecellexperiment` object containing the simulated differentially and equivalently distributed genes.

---

## [454] source=multitask_sft_big

**USER:** How do I specify which samples are cases and controls when using SnpSift CaseControl?

**ASSISTANT:** Case and control status is defined using a string composed of the characters '+', '-', and '0', where '+' represents a case, '-' represents a control, and '0' represents a neutral sample.

---

## [455] source=multitask_sft_big

**USER:** What export format options does Sbml2CarbonSkeletonNet offer for exporting metabolic network graphs?

**ASSISTANT:** Sbml2CarbonSkeletonNet supports the following graph export formats:
- Tabulated edge list (default: `source id edge type target id`)
- GML
- JsonGraph
- Tabulated node list (`label node id node type`)

---

## [456] source=multitask_sft_big

**USER:** Please set up the Helical Refinement workflow with a helical rise of 4.75 Angstroms, helical twist of 28.5 degrees, C1 symmetry, initial lowpass filter at 30 Angstroms, and enable helical parameter refinement in CryoSPARC.

**ASSISTANT:** The parameters have been extracted as follows:
- helical_rise_angstroms: 4.75
- helical_twist_deg: 28.5
- symmetry: "C1"
- initial_lowpass: 30
- refine_helical_params: true
- use_cryosparc: true

---

## [457] source=multitask_sft_big

**USER:** I need to perform anisotropic scaling on a 2-D RGB microscopy image to stretch it to twice its width while keeping the height unchanged. How should I specify the scaling factors in the Scale image tool?

**ASSISTANT:** In the **Scale image** tool, provide a comma-separated list of scaling factors: `2.0, 1.0`. For a 2-D RGB or single-channel image, the first value corresponds to image width (scaled by 2.0) and the second corresponds to image height (scaled by 1.0).

---

## [458] source=multitask_sft_big

**USER:** Extract the parameters to run `xcms plot eic` on file `sample_metabolites.mzML` targeting an m/z of 301.1412.

**ASSISTANT:** The extracted parameters for `xcms plot eic` are:
- Input file: `sample_metabolites.mzML`
- m/z: `301.1412`
- Default tolerance: `10 ppm`
- Default MS level: `1`

---

## [459] source=multitask_sft_big

**USER:** Here is our file list for the gene therapy barcode project: `barcodes_matrix.tsv` and `barcodes_metadata.tsv`. Which inputs correspond to the workflow parameters for isanalytics_custom_barcode_data_workflow?

**ASSISTANT:** For `isanalytics_custom_barcode_data_workflow`, the extracted parameters are:
- `barcodes_matrix.tsv`: Matched to the custom barcode matrix input.
- `barcodes_metadata.tsv`: Matched to the custom metadata sheet parameter (optional, `read_by_workflow: false`).

---

## [460] source=multitask_sft_big

**USER:** I want to execute `puma_pca_and_clustering_with_uncertainty`. What data input parameter is required, what format does it take, and what content does it expect?

**ASSISTANT:** The workflow requires the parameter `eset_estrogen_mmgmos`. It is a mandatory (non-optional) `rds` file containing an `ExpressionSet` object with expression levels and uncertainty estimates (such as those generated by mmgMOS on Affymetrix GeneChip data).

---

## [461] source=multitask_sft_big

**USER:** In mkyrobe genotype, what is the default percent coverage cutoff for reporting gene alleles?

**ASSISTANT:** The default percent coverage threshold in `mkyrobe genotype` is 100, which results in only the best alleles being reported.

---

## [462] source=multitask_sft_big

**USER:** I have standard calibration curve data in ref_calib.csv where column 'Concentration' is the known standard and 'PeakArea' is the measured signal. I want to quantify metabolite levels in experimental_samples.tsv using its 'Area' column with the table scipy interpolate tool. How should I map these inputs?

**ASSISTANT:** For the `table scipy interpolate` tool, map the inputs and parameters as follows:
- **Reference table**: `ref_calib.csv`
- **Reference X (source) column**: `PeakArea` (or signal metric to interpolate from)
- **Reference Y (target) column**: `Concentration` (the target calibrated value)
- **Query table**: `experimental_samples.tsv`
- **Query X (source) column**: `Area` (the column containing measured signals to calculate new Y values for)

---

## [463] source=multitask_sft_big

**USER:** Run kfetchdata and ensure the returned sequences are in emblxml-1.1 format.

**ASSISTANT:** Extracted parameter for kfetchdata:
- Output data format: 'emblxml-1.1'

---

## [464] source=multitask_sft_big

**USER:** What mandatory inputs are required to run the `topgo_score_based_expression_enrichment` workflow?

**ASSISTANT:** The workflow requires two mandatory inputs:
1. `ALL`: An ExpressionSet containing normalized microarray expression measurements.
2. `y`: An integer vector containing binary class labels for the samples.

---

## [465] source=multitask_sft_big

**USER:** How should my genotype data be formatted for the gwas_bayes workflow, and what analytical methods does it use?

**ASSISTANT:** The genotype data must be supplied in 'genotypes.csv' as a matrix of SNP genotypes coded as 0/1/2. The workflow performs Bayesian genome-wide association analysis using MCMC, MAP, or BIC methods to identify SNPs associated with the phenotype.

---

## [466] source=multitask_sft_big

**USER:** What are the required input data slots and parameters for executing the 'meshes' Nextflow workflow?

**ASSISTANT:** The 'meshes' workflow requires a mandatory input slot named `input_files` of type data (declared for count_data). It does not take any additional workflow parameters.

---

## [467] source=multitask_sft_big

**USER:** What are all the required input matrices and parameters for the snm workflow?

**ASSISTANT:** The `snm` workflow requires four primary inputs:
1. `raw.data`: Matrix of raw probe intensities.
2. `bio.var`: Model matrix of biological variables.
3. `adj.var`: Model matrix of probe-specific adjustment variables (e.g., batch, age).
4. `int.var`: Data frame of intensity-dependent array effects.

---

## [468] source=multitask_sft_big

**USER:** In the specl_swath_library_generation_no_irt workflow, is the peptideStd.sqlite file mandatory to run the pipeline?

**ASSISTANT:** No, according to the workflow parameters, 'peptideStd.sqlite' (the non-redundant BiblioSpec database) is marked with 'optional: true', so it is not strictly required to execute the workflow.

---

## [469] source=multitask_sft_big

**USER:** Configure nucler_mnase_bias_correction with nucleosomal_coverage.RData as my nucleosomal coverage RleList and naked_control_coverage.RData for the control RleList.

**ASSISTANT:** Extracted workflow inputs for nucler_mnase_bias_correction:
- nucleosomal_coverage.RData: nucleosomal_coverage.RData (RleList of nucleosomal DNA coverage)
- control_coverage.RData: naked_control_coverage.RData (RleList of control DNA coverage)

Expected workflow output: visualizations.

---

## [470] source=multitask_sft_big

**USER:** What input dataset is required to run the lrcell workflow, and what is its expected format?

**ASSISTANT:** The required input is `example_gene_pvals.RData`, which must be a named numeric vector containing bulk differential expression (DE) gene p-values.

---

## [471] source=multitask_sft_big

**USER:** I am aligning amplicon marker genes using align_seqs. I want to tighten the filtering so that sequences must match their closest blast hit with at least 85% sequence identity.

**ASSISTANT:** Extracted parameter for `align_seqs`:
- Minimum percent sequence identity to closest blast hit: `0.85` (overriding default `0.75`).

---

## [472] source=multitask_sft_big

**USER:** I am configuring my PepQuery2 proteomics pipeline: 'Please run competitive filtering with fast mode enabled to accelerate the execution time.' Which execution mode should be parsed from this request?

**ASSISTANT:** Based on your request, the specified setting is fast mode (enabled), which speeds up PepQuery2 by returning only one better match from the reference peptide-based competitive filtering steps.

---

## [473] source=multitask_sft_big

**USER:** Set up the cosia_cross_species_diversity_and_specificity workflow for my gene list c('BRCA1', 'TP53') using shared tissues c('Brain', 'Liver', 'Heart').

**ASSISTANT:** Here are the extracted parameters for `cosia_cross_species_diversity_and_specificity`:
- `gene_set`: c('BRCA1', 'TP53') (character vector of gene symbols or IDs)
- `map_tissues`: c('Brain', 'Liver', 'Heart') (character vector of shared tissues)

---

## [474] source=multitask_sft_big

**USER:** In the Mismatch Profile tool, my CIGAR strings are "68M140N33M" and "53M1D48M". What value should I provide for the required read alignment length?

**ASSISTANT:** You should set the required read alignment length to 101. Both CIGAR strings (68M + 33M = 101; 53M + 48M = 101) indicate an original read length of 101.

---

## [475] source=multitask_sft_big

**USER:** I want to extract genes from my model using GetGenesFromReactions. What inputs do I need to provide, and what will the output format look like?

**ASSISTANT:** You need to provide:
1. A list of reaction identifiers.
2. An SBML file containing GPR annotations.

The tool outputs a tab-separated file with one row per gene, featuring associated reaction identifiers from the input file in the first column and gene identifiers in the second column.

---

## [476] source=multitask_sft_big

**USER:** I want to run `miaviz_prevalence_plotting`. I have an RDS file named `gut_microbiome_tse.rds` containing a TreeSummarizedExperiment object. How should I configure the input?

**ASSISTANT:** Configure the workflow input as follows:
- `GlobalPatterns`: `gut_microbiome_tse.rds` (TreeSummarizedExperiment object containing taxonomic counts, type: `rds_se`).

---

## [477] source=multitask_sft_big

**USER:** What input data parameters does the iSEE workflow expect?

**ASSISTANT:** The `iSEE` workflow requires the input parameter `input_files`, which is a mandatory non-optional data input slot expecting `count_data` (such as data stored in SummarizedExperiment objects).

---

## [478] source=multitask_sft_big

**USER:** What is the default percent identity threshold reported by mashmap, and how should it be adjusted for noisy long-read datasets or human assembly comparisons?

**ASSISTANT:** By default, `mashmap` sets the identity threshold to 85 (reporting mappings with 85% or greater identity). For noisier long-read datasets, it can be lowered to 80, whereas for mapping a human genome assembly to a human reference, it can be set higher to 95.

---

## [479] source=multitask_sft_big

**USER:** Please set up the phenstat workflow using my file `phenotypic_data.csv`, which has Genotype, Sex, Batch, and body_weight recorded for each mouse.

**ASSISTANT:** I have extracted the required input for the phenstat workflow:
- `phenotypic_data.csv`: CSV file containing columns `Genotype`, `Sex`, `Batch`, and the quantitative variable `body_weight`.

The workflow will run a linear mixed model via `bioconductor/phenstat` testing for genotype effects while adjusting for batch and sex, and it will produce visual summary plots (`visualizations`).

---

## [480] source=multitask_sft_big

**USER:** I want to supply my own annotated gene sets to panomir_custom_pathway_table_generation. What is the parameter/input name and format?

**ASSISTANT:** The workflow accepts the optional data input 'pathways.gmt', which expects a GMT file containing your custom gene sets or pathways.

---

## [481] source=multitask_sft_big

**USER:** I'm setting up `pcaexplorer_gene_level_pca_and_profiling`. I have two files: `count_matrix.txt` containing my raw count matrix and `metadata.txt` containing sample covariates. Can you extract the required data inputs for this workflow?

**ASSISTANT:** Here are the extracted required data inputs for `pcaexplorer_gene_level_pca_and_profiling`:

- `count_matrix.txt`: raw count matrix (type: `matrix`, optional: `false`, read_by_workflow: `true`)
- `metadata.txt`: sample covariates (type: `data`, optional: `false`, read_by_workflow: `true`)

---

## [482] source=multitask_sft_big

**USER:** In Summary.tax, I want my summary output files to report relative proportions instead of raw counts. Which parameter should I set?

**ASSISTANT:** You should set the parameter 'relabund=t' (or TRUE). By default, 'relabund' is 'f', which generates raw abundances.

---

## [483] source=multitask_sft_big

**USER:** What input parameters and masks are accepted by the Focused Refinement Pipeline?

**ASSISTANT:** The pipeline accepts the following inputs: 'subtraction_mask', 'invert_mask', 'focus_mask', 'symmetry', 'initial_lowpass', 'max_iterations', and 'use_cryosparc'.

---

## [484] source=multitask_sft_big

**USER:** What is the default script path configured for parallel_alpha_diversity?

**ASSISTANT:** The default script path is `/usr/local/lib/python2.6/site-packages/scripts/alpha_diversity.py`.

---

## [485] source=multitask_sft_big

**USER:** Extract the mandatory data input parameters for the tidycoverage workflow from its specification.

**ASSISTANT:** The mandatory data input parameters for tidycoverage are:
- `tracks`: A list of BigWig files (`type: list`, `optional: false`)
- `locus`: Target genomic region (`type: rds_granges`)

---

## [486] source=multitask_sft_big

**USER:** Here are the parameters I intend to feed into the MERSCOPE segmentation pipeline:
--ch_input /data/merscope_run \
--json /configs/vpt_config.json \
--ch_images_regex 'mosaic_(?P<stain>[\w|-]+)_z(?P<z>[0-9]+).tif' \
--ch_custom_weights /models/custom_cellpose.pt

Please extract and map them to the input channels of `nf-core/tiff_segmentation_vpt`.

**ASSISTANT:** The extracted parameters mapped to the workflow inputs are:
- `ch_input`: `/data/merscope_run`
- `json`: `/configs/vpt_config.json`
- `ch_images_regex`: `'mosaic_(?P<stain>[\w|-]+)_z(?P<z>[0-9]+).tif'`
- `ch_custom_weights`: `/models/custom_cellpose.pt`

---

## [487] source=multitask_sft_big

**USER:** Please log an audit export for run_id 'RUN-88219' using workflow 'lead_optimization' version 'v2.1.0' under study 'ST-402'. The run was performed by Dr. Aris Thorne for off-target binding profiling. The inputs were 'compounds.sdf' and outputs were 'docking_scores.csv', using params in 'config.json'.

**ASSISTANT:** Here are the extracted parameters for `Run Audit Export`:
- `run_id`: "RUN-88219"
- `workflow_name`: "lead_optimization"
- `workflow_version`: "v2.1.0"
- `study_id`: "ST-402"
- `analyst_name`: "Dr. Aris Thorne"
- `purpose`: "off-target binding profiling"
- `input_files`: ["compounds.sdf"]
- `output_files`: ["docking_scores.csv"]
- `parameters_json`: "config.json"

---

## [488] source=multitask_sft_big

**USER:** Configure the alevinqc_interactive_shiny_app workflow for my output located at `/data/singlecell/sample1_alevin/`.

**ASSISTANT:** Based on your request, the parameters are extracted as follows:
- `baseDir`: `/data/singlecell/sample1_alevin/` (must contain `alevin/`, `aux_info/`, and `cmd_info.json`)
Output generated: `visualizations`.

---

## [489] source=multitask_sft_big

**USER:** When configuring coordinate offsets in the 'Get flanks' tool, how do positive and negative offset values behave?

**ASSISTANT:** In 'Get flanks', positive values offset coordinates in the direction of transcription, whereas negative values offset coordinates in the opposite direction.

---

## [490] source=multitask_sft_big

**USER:** I want to impute ungenotyped markers in Beagle using an external reference panel of phased haplotypes. Which argument should I pass to supply the reference panel?

**ASSISTANT:** In Beagle, you specify the reference panel of phased genotypes using the `ref` argument. Ungenotyped markers present in that reference panel can then be imputed into your target samples.

---

## [491] source=multitask_sft_big

**USER:** In the command syntax for hmmscan, what do the `<seqfile>` and `<hmmfile>` placeholders correspond to?

**ASSISTANT:** In `hmmscan`, `<seqfile>` represents the input file containing the query protein sequences, while `<hmmfile>` represents the target database or collection of protein profiles that the sequences are searched against.

---

## [492] source=multitask_sft_big

**USER:** I need to generate OTU-specific primers with Primer.design from my 16S alignment. Make sure the ambiguity cutoff is set to 95%.

**ASSISTANT:** Extracted parameter:
- `cutoff`: 95

This will ensure that ambiguous bases are only introduced at positions not supported by at least 95% of your target sequences.

---

## [493] source=multitask_sft_big

**USER:** I want to rotate my geometry by 45 degrees around the vector [0, 1, 0] using the Rotate shape tool. What are the key inputs?

**ASSISTANT:** The key inputs for the 'Rotate shape' tool are the rotation angle (45 degrees) and the arbitrary axis ([0, 1, 0]) about which the shape will be rotated.

---

## [494] source=multitask_sft_big

**USER:** What parameters are mentioned in scATAC-seq Preprocessing for filtering out low-quality cells?

**ASSISTANT:** The parameters mentioned are `min_counts` (to keep cells with at least a specified number of counts) and `min_features` (to keep cells with at least a specified number of genes expressed).

---

## [495] source=multitask_sft_big

**USER:** What input parameters and files are declared for the `rsbml` workflow?

**ASSISTANT:** The `rsbml` workflow defines one required input slot under `data_inputs`: `input_files` (type: `data`, optional: `false`, read_by_workflow: `true`, classified under workflow input slot `count_data`). It does not define any secondary optional parameters in its parameters list.

---

## [496] source=multitask_sft_big

**USER:** List the required inputs and outputs for the transcriptomics workflow dose_gene_set_enrichment_analysis.

**ASSISTANT:** Required input: `ranked_gene_list.txt` (a sorted, named numeric vector of fold changes with Entrez gene IDs as names).
Output: `enrichment_results`.

---

## [497] source=multitask_sft_big

**USER:** How can I specify multiple target columns when running `csvtk-split`?

**ASSISTANT:** You can provide multiple columns separated by a comma (`,`). You can also specify column numbers directly; for example, `'1,2'` will target columns 1 and 2.

---

## [498] source=multitask_sft_big

**USER:** How do I specify regions to analyze in sixpack, and what is an example format?

**ASSISTANT:** In `sixpack`, a set of regions is specified by pairs of positions consisting of integers separated by any non-alphanumeric character. For example, a valid region specification is `24-45`.

---

## [499] source=multitask_sft_big

**USER:** How should I specify genomic regions when running SHEAR-SV?

**ASSISTANT:** Regions in SHEAR-SV are defined using 1-based coordinates. You can specify a full chromosome (e.g., "chr1") or a specific interval including endpoints (e.g., "chr1:10000-15000").

---

## [500] source=multitask_sft_big

**USER:** In the Thermo proteomics tool, I want to include only MS2 and MS3 scan levels in the output.

**ASSISTANT:** Extracted parameter for the Thermo tool:
- MS levels: `2,3` (or interval `2-3`)

---

## [501] source=multitask_sft_big

**USER:** What are the required input files for running the `occugene` workflow, and what information must they contain?

**ASSISTANT:** The `occugene` workflow requires two mandatory data inputs:
- `annotation.csv`: A table containing ORF start and end coordinates.
- `insertions.csv`: A table containing genomic positions of transposon insertions.

---

## [502] source=multitask_sft_big

**USER:** Does the circseqaligntk_synthetic_read_simulation_and_evaluation workflow allow passing a circular genome reference, and is it mandatory?

**ASSISTANT:** Yes, it accepts a circular genome sequence in FASTA format via the 'FR851463.fa' input parameter, which is designated as an optional input (optional: true).

---

## [503] source=multitask_sft_big

**USER:** Which database sources can I query using the 'Get species occurrences data' tool?

**ASSISTANT:** You can query any combination of the following sources: `gbif`, `bison`, `inat`, `ebird`, `antweb`, `ala`, `idigbio`, `obis`, `ecoengine`, and `vertnet`.

---

## [504] source=multitask_sft_big

**USER:** Configure the Lc Ms Proteomics Metabolomics workflow using positive polarity mzML files at 'data/pos_meta.mzML', metadata at 'data/meta.tsv', HMDB database at 'ref/hmdb.db', proteomics table at 'data/prot_matrix.tsv', FDR threshold of 0.05, fold-change threshold of 2.0, correlation cutoff of 0.7, and enable joint pathway enrichment.

**ASSISTANT:** Here are the extracted parameters for the workflow:
- `polarity`: positive
- `metabolomics_mzml`: data/pos_meta.mzML
- `metabolomics_meta`: data/meta.tsv
- `hmdb_database`: ref/hmdb.db
- `proteomics_input`: data/prot_matrix.tsv
- `fdr_threshold`: 0.05
- `fc_threshold`: 2.0
- `correlation_cutoff`: 0.7
- `run_joint_enrichment`: true

---

## [505] source=multitask_sft_big

**USER:** Which Bioconductor packages and output targets are associated with the spotlight workflow?

**ASSISTANT:** The spotlight workflow utilizes the following Bioconductor tools: bioconductor/spotlight, bioconductor/nmf, bioconductor/singlecellexperiment, bioconductor/spatialexperiment, bioconductor/tenxvisiumdata, and bioconductor/tabulamurissenisdata.

Its defined workflow outputs are:
1. `normalized_data`
2. `visualizations`

---

## [506] source=multitask_sft_big

**USER:** I am configuring a calculation in MuDirac and want to rely on standard default properties for the element's nucleus without specifying a custom isotope mass. What value should I use?

**ASSISTANT:** You should use the default value `-1`. In MuDirac, `-1` specifies that the most common isotope for the element will be utilized.

---

## [507] source=multitask_sft_big

**USER:** Which input files and parameter settings are documented under `data_inputs` for the lea_ecological_association_lfmm_mcmc workflow?

**ASSISTANT:** The documented data inputs include:
- `genotypes.lfmm`: type `matrix`, optional `true`, read_by_workflow `false`, described as 'genotype matrix in LFMM format'.
- `gradients.env`: representing environmental gradient matrix inputs.

---

## [508] source=multitask_sft_big

**USER:** I am running MassCalculator for peptide identification and only need the m/z values exported in the final output. What parameter setting should I use?

**ASSISTANT:** You should set the output format parameter to `'mz_only'` (m/z values only).

---

## [509] source=multitask_sft_big

**USER:** I ran pepwheel with custom residue markup, but all residues except ACFGILMVWY disappeared from my annotations, and those ten became squares. What setting caused this?

**ASSISTANT:** This occurs because the setting that marks the residues `ACFGILMVWY` as squares was enabled. Setting this flag to true explicitly overrides any other residue markup you defined, leaving all residues other than A, C, F, G, I, L, M, V, W, and Y unmarked.

---

## [510] source=multitask_sft_big

**USER:** Configure the genomation workflow using my data: aligned_reads.bam contains our aligned CAGE reads and genomic_features.gtf contains our annotation set.

**ASSISTANT:** The input parameters for the genomation workflow are configured as follows:
- aligned_reads.bam: "aligned_reads.bam" (BAM file of aligned reads)
- genomic_features.gtf: "genomic_features.gtf" (GTF file of gene annotations)

These inputs will be processed to produce the requested visualizations.

---

## [511] source=multitask_sft_big

**USER:** I have an input matrix named 'cohort_trinuc_matrix.rds' and a pre-trained signatures list named 'pkg_supersig_list.rds'. How should these be assigned as inputs to 'supersigs_predict_supersig'?

**ASSISTANT:** Map the inputs as follows:
- 'input_dt': 'cohort_trinuc_matrix.rds' (Trinucleotide mutation matrix data frame)
- 'supersig_ls': 'pkg_supersig_list.rds' (Pre-trained SuperSigs list provided by the package)

---

## [512] source=multitask_sft_big

**USER:** I have a pipeline step using JQ where I need to extract the numeric 'foo' field from a list of records so each value prints on a separate line. What filter expression should be configured?

**ASSISTANT:** You should configure the filter expression as either `.[].foo` or `.[] | .foo`.

---

## [513] source=multitask_sft_big

**USER:** In Monocle3 top markers, what is the consequence of specifying the optional reference set of cells for marker significance testing?

**ASSISTANT:** Specifying a set of cells as reference accelerates the marker significance test, but does so at some cost in sensitivity.

---

## [514] source=multitask_sft_big

**USER:** Please set up the probamr workflow using my files: annotations in /data/gencode.v38.gtf, CDS in /data/cds.fa, proteins in /data/prot.fa, and the scoring table at /data/confident_psms.tsv.

**ASSISTANT:** Here is the parameter mapping for the probamr workflow data inputs:
- test.gtf: /data/gencode.v38.gtf
- coding_seq.fasta: /data/cds.fa
- pro_seq.fasta: /data/prot.fa
- passedPSM.tab: /data/confident_psms.tsv

---

## [515] source=multitask_sft_big

**USER:** Here are my input files for the genomicdistributions workflow: a primary query file 'vistaEnhancers.bed.gz' and a comparison set 'setB_100.bed.gz'. Please map these to the workflow inputs and required parameters.

**ASSISTANT:** The inputs map as follows:
- `queryFile.bed` (required data input): `vistaEnhancers.bed.gz`
- Additional comparison BED file: `setB_100.bed.gz`

The workflow will run `bioconductor/genomicdistributions` using these inputs to generate distribution visualizations.

---

## [516] source=multitask_sft_big

**USER:** What mandatory input parameters or data files must be provided to run the GOSemSim workflow?

**ASSISTANT:** The workflow requires a mandatory data input slot named `input_files`, which takes `count_data`.

---

## [517] source=multitask_sft_big

**USER:** Extract the settings for my Map small RNA run: the query sequence column is 'read_seq', reference miRNA is 'hsa-miR-21', allowing up to 1 mismatch, with 5' trimming of 2 bases and 3' addition of 1 base.

**ASSISTANT:** Here are the extracted parameters for Map small RNA:
- `seq`: read_seq
- `miRNA`: hsa-miR-21
- `mism`: 1
- `tr5`: 2
- `add`: 1

---

## [518] source=multitask_sft_big

**USER:** In GNPSExport, how do I set the tool to consider all peptide identifications rather than a restricted number of the most intense peptides per consensus element?

**ASSISTANT:** Set the parameter for the number of most intense peptides to consider per consensus element to '-1'.

---

## [519] source=multitask_sft_big

**USER:** Run mechanism-aware imputation on my file at '/metabolomics/cohort_se.rds'. What parameters are being passed?

**ASSISTANT:** The extracted parameter for the `mai_summarized_experiment_imputation` workflow is:

- `se`: `"/metabolomics/cohort_se.rds"` (type: rds_se, mandatory SummarizedExperiment object containing metabolomics abundance data with missing values in its assay).

---

## [520] source=multitask_sft_big

**USER:** I am configuring SortSam for my WGS BAM alignments and want to skip unnecessary decoding of read tags and qualities to speed up sorting. Which parameter setting should I apply?

**ASSISTANT:** You should set the stringency parameter to SILENT.

---

## [521] source=multitask_sft_big

**USER:** I am configuring Remove.lineage manually without a file. I want to exclude Bacteria;Firmicutes; and Bacteria;Actinobacteria;. How should I enter this parameter?

**ASSISTANT:** When no taxons are selected from a file, you should enter the lineages separated by dashes. For your selection, provide:
`Bacteria;Firmicutes;-Bacteria;Actinobacteria;`

---

## [522] source=multitask_sft_big

**USER:** Run qiime2 vsearch cluster-features-de-novo on my 16S feature table 'table.qza' and sequences 'rep-seqs.qza' clustering at 97% sequence identity.

**ASSISTANT:** The extracted parameters and inputs for `qiime2 vsearch cluster-features-de-novo` are:
- Feature table: `table.qza`
- Feature sequences: `rep-seqs.qza`
- Percent identity threshold: `0.97` (or 97%)

---

## [523] source=multitask_sft_big

**USER:** What input slots are required to run the VisiumIO Nextflow workflow?

**ASSISTANT:** The workflow requires a single mandatory input slot named `count_data`, which provides the spatial count data files (such as tar.gz, h5, or mtx).

---

## [524] source=multitask_sft_big

**USER:** What is the default scaling value in NetCDF xarray operations, and what output does the tool generate?

**ASSISTANT:** The default scaling factor is 1. The tool stores the resulting manipulated data into a new NetCDF file.

---

## [525] source=multitask_sft_big

**USER:** Extract the fields for 'Chado biomaterial add' from this description: 'Register LiverSample_01 from Provider Alpha Bio with Biosample SAMN0001, SRA SRR0001, Bioproject PRJNA0001, and custom attributes {"organ": "liver"}.'

**ASSISTANT:** Here are the extracted parameters:
- Description of the biomaterial: LiverSample_01
- Biomaterial Provider: Alpha Bio
- Biosample Accession: SAMN0001
- Sra Accession: SRR0001
- Bioproject Accession: PRJNA0001
- Attributes: {"organ": "liver"}

---

## [526] source=multitask_sft_big

**USER:** How does seed selection work in the Evaluation (Single Cell) tool if 'random' is specified in methods?

**ASSISTANT:** When 'random' is specified in methods, one random gene set is selected for each seed. If left empty, it selects one random set using a random seed.

---

## [527] source=multitask_sft_big

**USER:** I am configuring 'Create: Design, Wide, and Annotation datasets'. My quantitative sample measurements are in columns 2, 3, 4, and 5 of my wide dataset table. How should I specify this?

**ASSISTANT:** You should enter `2,3,4,5` (1-based column indices separated by commas, with no spaces). Columns that are not listed will be automatically treated as descriptor annotation columns.

---

## [528] source=multitask_sft_big

**USER:** Here are the files I have for my project: a normalized expression matrix named `expression_matrix.csv` and patient clinical annotations named `phenotype_data.csv`. What inputs does `globalancova_public_gene_set_testing` extract from these?

**ASSISTANT:** The workflow extracts the following required inputs:
- `expression_matrix.csv`: Normalized gene expression matrix (type: matrix)
- `phenotype_data.csv`: Sample clinical annotations (type: data)
Both files are mandatory to test gene sets against the phenotype labels.

---

## [529] source=multitask_sft_big

**USER:** I need to configure `tanggle_explicit_networks`. What are the expected inputs and what outputs will it generate?

**ASSISTANT:** For `tanggle_explicit_networks`, the required input is `network_text`, which can be provided as an Extended Newick format string or file representing a reticulated tree (optionally mapped via data input `network.nwk`). The workflow produces two outputs: `consensus_score` and `visualizations`.

---

## [530] source=multitask_sft_big

**USER:** What input slots and configurable parameters are defined for the tidySummarizedExperiment workflow?

**ASSISTANT:** The workflow defines:
- Data input: `count_data` (type: data, optional: true, declared .nf input slot).
- Parameters: None (`parameters: []`).

---

## [531] source=multitask_sft_big

**USER:** Please set up the OpenFE RBFE pipeline for my target 'receptor.pdb', with 'lig_a.sdf' and 'lig_b.sdf'. Run 15 lambda windows for 5.0 ns simulation time following 1.0 ns equilibration at 300 K and 1.0 bar, using a 2.0 fs timestep. Enable GPU acceleration.

**ASSISTANT:** I have extracted the following parameters for the OpenFE Relative Binding Free Energy (RBFE) workflow:
- receptor: "receptor.pdb"
- ligand_a: "lig_a.sdf"
- ligand_b: "lig_b.sdf"
- n_lambda_windows: 15
- simulation_time_ns: 5.0
- equilibration_ns: 1.0
- temperature: 300
- pressure: 1.0
- timestep_fs: 2.0
- gpu: true

---

## [532] source=multitask_sft_big

**USER:** Set up `cellmapper_custom_data_search` using my expression matrix file `custom_microarray_matrix.rds` (genes as rows, samples as columns) and my target probeset '1007_s_at'.

**ASSISTANT:** Here are the extracted parameters for `cellmapper_custom_data_search`:
- `ALL`: `custom_microarray_matrix.rds` (matrix/ExpressionSet with genes as rows and samples as columns)
- `query.genes`: '1007_s_at'

---

## [533] source=multitask_sft_big

**USER:** I have stored my AVA run files under '/workspace/data/AVA_Run_01/' which contains the Amplicons/ folder. Please configure the required data input parameter for the r453plus1toolbox workflow.

**ASSISTANT:** The extracted parameter for the `r453plus1toolbox` workflow is:
- `projectDir`: "/workspace/data/AVA_Run_01/"

Make sure the required tables (`sample.csv`, `amp.csv`, `reference.csv`, `variant.csv`, and `variantHits.csv`) are also provided as inputs.

---

## [534] source=multitask_sft_big

**USER:** What is the declared input slot for the SARC workflow?

**ASSISTANT:** The declared input slot in the SARC workflow is `count_data` (marked as optional data input in the Nextflow configuration).

---

## [535] source=multitask_sft_big

**USER:** I need to run the IMPC tool with the gene symbol Trp53 and MGI ID MGI:98834. How should these inputs be handled?

**ASSISTANT:** Both inputs are valid since the IMPC tool accepts mixed gene symbols and MGI IDs. You can input them into the query field separated by a delimiter, and select the desired query type from the tool's drop-down menu.

---

## [536] source=multitask_sft_big

**USER:** Configure the 3D Variability Pipeline with 3 components, filtered to 4.5 Angstroms, running 20 iterations, using cluster mode with 5 clusters, and without subsampling particles.

**ASSISTANT:** Here are the extracted parameters for the 3D Variability Pipeline:
- `num_components`: 3
- `filter_res_angstroms`: 4.5
- `num_iterations`: 20
- `cluster_mode`: true
- `num_clusters`: 5
- `subsample_particles`: false

---

## [537] source=multitask_sft_big

**USER:** What input files and output formats are associated with the difflogo workflow?

**ASSISTANT:** The `difflogo` workflow accepts two inputs: `pwm1.pwm` (First position weight matrix file) and `pwm2.pwm` (Second position weight matrix file). It generates outputs in `table/csv`, `plot/pdf`, and `object/rds` formats using tools including `bioconductor/difflogo`, `bioconductor/motifdb`, and `bioconductor/seqlogo`.

---

## [538] source=multitask_sft_big

**USER:** Please set up toast_complete_geometric_deconvolution using my bulk methylation matrix file 'data/beta_values.rds'. I don't have reference cell type profiles.

**ASSISTANT:** I have configured the parameters for `toast_complete_geometric_deconvolution`:

- `Ybeta`: "data/beta_values.rds"
- `ref_m`: null (omitted as it is optional)

This setup will perform reference-free geometric deconvolution using the Tsisal approach.

---

## [539] source=multitask_sft_big

**USER:** I am configuring the inpower workflow and have prepared an R matrix called 'data.rda' with MAF, Beta, SNP ID, and original study detection power. Can you extract the data input parameter?

**ASSISTANT:** From your request, the extracted input parameter is:
- **data_inputs**:
  - **name**: `data.rda`
  - **type**: `matrix` (or data frame)
  - **description**: User-provided matrix containing SNP ID, Minor Allele Frequency (MAF), Effect Size (Beta), and Power of detection in the original study.

---

## [540] source=multitask_sft_big

**USER:** What does the 'Column used as legend' setting do in the Phyloseq Richness tool?

**ASSISTANT:** In the Phyloseq Richness tool, the 'Column used as legend' parameter allows you to select a group from the metadata to fill color representing the group it belongs to.

---

## [541] source=multitask_sft_big

**USER:** Set up the inputs for rarevariantvis using my files: my_snvs.vcf.gz for SNVs and my_svs.vcf.gz for structural variants.

**ASSISTANT:** Here is the parameter mapping for `rarevariantvis`:
- `sample`: `my_snvs.vcf.gz` (VCF file of SNVs)
- `sv_sample`: `my_svs.vcf.gz` (VCF file of SVs)

These will generate the expected `visualizations` output.

---

## [542] source=multitask_sft_big

**USER:** What input format does the Create pseudo genome tool accept?

**ASSISTANT:** The `Create pseudo genome` tool takes a multi-contig FASTA file as its input.

---

## [543] source=multitask_sft_big

**USER:** I want to create an index group in GROMACS containing residue 34 and residue 50 using an OR operator. What selection syntax should I provide to Create GROMACS index files?

**ASSISTANT:** You should specify the selection as `r34 | r50`. The tool uses the prefix 'r' followed by the residue number (e.g., 'r34') and combines groups using the '|' (or) operator.

---

## [544] source=multitask_sft_big

**USER:** I need to configure `qiime2 feature-classifier vsearch-global` to limit the number of reported top matches per query sequence. Which parameter controls this limit?

**ASSISTANT:** The number of top matches returned per query sequence is controlled by the `maxaccepts` (or `maxhits`) parameter, which sets the maximum number of top hits (M) included in the report.

---

## [545] source=multitask_sft_big

**USER:** What input parameters or data files are defined for genega_custom_codon_weights_computation?

**ASSISTANT:** The workflow defines an optional input data file named `EGFP.fasta` of type `fasta`, which contains highly expressed gene sequences.

---

## [546] source=multitask_sft_big

**USER:** Please set up Glimmer long ORFs on my assembly genome.fna and set the minimum length cutoff for ORFs to 150 bp.

**ASSISTANT:** The extracted parameter and input for `Glimmer long ORFs` are:
- Input sequence file: `genome.fna`
- Minimum length threshold: `150` bp

---

## [547] source=multitask_sft_big

**USER:** What outputs and underlying software tools are involved in running the dss workflow?

**ASSISTANT:** The `dss` workflow produces two outputs: `de_table` and `normalized_data`. The tools utilized within the workflow are `bioconductor/dss`, `bioconductor/bsseq`, and `bioconductor/edger`.

---

## [548] source=multitask_sft_big

**USER:** What input datasets and files do I need to prepare before running RecParams?

**ASSISTANT:** To run `RecParams`, you need:
1. cfDNA sequencing data
2. Normal sample sequencing data
3. Preprocessed cfDNA reads files

---

## [549] source=multitask_sft_big

**USER:** What are the input requirements and expected output file formats produced by the plasmut workflow?

**ASSISTANT:** For the plasmut workflow:
- Input: user_mutation_data.csv containing sample/patient ID, gene/mutation, analyte type ("plasma" or "buffy coat"), mutant read count (y), and total read count (n).
- Outputs: table/csv, plot/pdf, and object/rds.

---

## [550] source=multitask_sft_big

**USER:** I am configuring the Periodicity sequence analysis tool for nucleosome mapping, but my target organism's chromosome sizes are missing from the dropdown menu. What does the tool require here?

**ASSISTANT:** The Periodicity tool requires you to select chromosome sizes for your reference genome. If your genome of interest is not listed in the preset options, you need to contact the Galaxy team to have it added.

---

## [551] source=multitask_sft_big

**USER:** Set up pgSnp to gd_snp to append my new variant calls from 'sampleB.pgsnp' into our existing 'master.gd_snp' file, and make sure any novel SNPs found only in sampleB are retained and backfilled with -1 for previous individuals.

**ASSISTANT:** Here is the extracted configuration for 'pgSnp to gd_snp':
- Target mode: Append to existing dataset
- Input pgSnp file: `sampleB.pgsnp`
- Existing gd_snp file: `master.gd_snp`
- Novel SNP handling: Backfill with "-1" (unknown) for previous individuals (do not skip novel SNPs)

---

## [552] source=multitask_sft_big

**USER:** Here are my files for aberrant splicing analysis: annotations in metadata_samples.tsv (includes sampleID, bamFile, and covariates) and aligned files sample1.bam and sample2.bam. Map these to the fraser workflow inputs.

**ASSISTANT:** Here is the parameter mapping for the 'fraser' workflow:
- `sampleTable.tsv`: metadata_samples.tsv
- `*.bam`: [sample1.bam, sample2.bam]

---

## [553] source=multitask_sft_big

**USER:** I am configuring 'Chado load InterProScan results' for my genome annotation pipeline and want to load predictions for 'polypeptide' features. What feature type parameter should be supplied?

**ASSISTANT:** The parameter is the feature type of the query, which must be a valid Sequence Ontology term. Based on your input, the feature type should be set to 'polypeptide'.

---

## [554] source=multitask_sft_big

**USER:** What output files or objects are generated by the cnvmetrics_log2_ratio_similarity workflow?

**ASSISTANT:** The workflow produces two main outputs: `copy_number_segments` and `visualizations`.

---

## [555] source=multitask_sft_big

**USER:** I have my single-cell reference saved at `ref_sce.rds` and spatial transcriptomics library at `tissue_spe.rds`. How do these map to the inputs of the spotlight_two_step_deconvolution workflow?

**ASSISTANT:** The files map to the workflow inputs as follows:
- `sce`: `ref_sce.rds` (SingleCellExperiment reference data)
- `spe`: `tissue_spe.rds` (SpatialExperiment spatial transcriptomics data)

---

## [556] source=multitask_sft_big

**USER:** Which parameters in nf-core/viralintegration control read support filters and the viral reference genome?

**ASSISTANT:** In nf-core/viralintegration, read filtering thresholds are managed by `min_reads` and `max_hits` (along with `remove_duplicates`), while the reference viral genome sequence is supplied via `viral_fasta`.

---

## [557] source=multitask_sft_big

**USER:** I have three files for cluster annotation: 'norm_counts.tsv' (normalized scRNA-seq expression), 'metadata_clusters.csv' (cell metadata with cluster assignments), and 'marker_reference.csv' (cell-type marker genes). How do these map to `clustifyr_marker_list_annotation`?

**ASSISTANT:** The files map to the workflow inputs as follows:
- `pbmc_matrix`: `norm_counts.tsv` (matrix of normalized single-cell RNA-seq counts)
- `pbmc_meta`: `metadata_clusters.csv` (metadata table containing cluster assignments)
- `cbmc_m`: `marker_reference.csv` (table of known marker genes for each cell type)

---

## [558] source=multitask_sft_big

**USER:** In the psmatch_fragment_ion_calculation_and_visualization workflow, is the raw mass spectrometry input file 'file.mzML.gz' mandatory?

**ASSISTANT:** No, the 'file.mzML.gz' input is marked with optional: true, so it is not strictly mandatory.

---

## [559] source=multitask_sft_big

**USER:** We completed differential methylation testing and saved the results as a named numeric vector of CpG p-values called `dm_cpg_pvalues`. Please configure the input for methylgsa_methylgometh_analysis.

**ASSISTANT:** The parameter configuration for `methylgsa_methylgometh_analysis` is:
- `cpg.pval`: `dm_cpg_pvalues`

---

## [560] source=multitask_sft_big

**USER:** I am looking at the pgxRpi workflow parameters. Does it require a mandatory count_data input?

**ASSISTANT:** No, the `count_data` input slot declared in the pgxRpi workflow is marked as optional (`optional: true`) and is not read by the workflow (`read_by_workflow: false`).

---

## [561] source=multitask_sft_big

**USER:** Run countandcluster.py with sample.bam, index sample.bam.bai, cluster file cluster_groups.txt, minimum proportion 0.15, gene output gene_summary.tsv, and cluster output cluster_summary.tsv.

**ASSISTANT:** Here is the extracted command structure for `countandcluster.py`:
`countandcluster.py -b sample.bam -i sample.bam.bai -c cluster_groups.txt -p 0.15 -g gene_summary.tsv -o cluster_summary.tsv`

Extracted parameters:
- `-b`: sample.bam
- `-i`: sample.bam.bai
- `-c`: cluster_groups.txt
- `-p`: 0.15
- `-g`: gene_summary.tsv
- `-o`: cluster_summary.tsv

---

## [562] source=multitask_sft_big

**USER:** We are setting up scBFA for gene detection analysis. We have cell-level covariates stored in cell_covars.mat and gene-level covariates in gene_covars.mat. Which parameters should these map to in scBFA?

**ASSISTANT:** In scBFA, the cell-level covariates `cell_covars.mat` should be passed to the cell-level covariate matrix parameter `X`, and the gene-level covariates `gene_covars.mat` should be passed to the gene-level covariate matrix parameter `Q`.

---

## [563] source=multitask_sft_big

**USER:** When configuring ClusterMassTracesByPrecursor, what is the typical recommended range for the maximum spectrum peak shift parameter?

**ASSISTANT:** A value between 1 and 3 spectra is usually sensible, though the exact number depends on your chromatographic setup.

---

## [564] source=multitask_sft_big

**USER:** Can you check if identifications.id.csv is optional in the isobar_ptm_localization_quant workflow configuration?

**ASSISTANT:** According to the workflow parameters for isobar_ptm_localization_quant, 'identifications.id.csv' has optional set to false, meaning it is a strictly required data input that must be read by the workflow.

---

## [565] source=multitask_sft_big

**USER:** What is the recommended input edge weight file setting in MetaboRank, and what does the tool do with these weights?

**ASSISTANT:** The parameter is the 'input edge weight file', which specifies the path to a file containing edges' weights. MetaboRank normalizes these weights as transition probabilities.

---

## [566] source=multitask_sft_big

**USER:** If I provide an interval to make-window with a specified windowsize, what logic does it use to define the new start and end coordinates?

**ASSISTANT:** It takes the middle point of the input interval and computes the new start and end coordinates by extending `windowsize/2` base pairs to both the left and right of that midpoint.

---

## [567] source=multitask_sft_big

**USER:** I want to run diffcyt using my cytometry raw file 'sample_flowset.rds', metadata table 'samples_meta.csv', and marker categories 'markers.tsv'. Can you map these to the workflow inputs?

**ASSISTANT:** Based on the `diffcyt` workflow definition, here is the mapped input configuration:
- `d_flowSet`: 'sample_flowset.rds' (RDS format flowSet object containing raw cytometry data)
- `experiment_info`: 'samples_meta.csv' (data frame of sample metadata)
- `marker_info`: 'markers.tsv' (data frame of marker classifications)

---

## [568] source=multitask_sft_big

**USER:** We are configuring an nf-core/clipseq run. Our design file is at 'samples.csv', the reference fasta is 'genome.fa', annotations are in 'genes.gtf', small RNA fasta is 'smrna.fa', and output should be directed to './clipseq_out'. Can you extract the parameters for this run?

**ASSISTANT:** Here are the extracted parameters for the `nf-core/clipseq` pipeline:

- `input`: "samples.csv"
- `fasta`: "genome.fa"
- `gtf`: "genes.gtf"
- `smrna_fasta`: "smrna.fa"
- `outdir`: "./clipseq_out"

---

## [569] source=multitask_sft_big

**USER:** In PLINK, how can I configure the chromosome filter if I want to keep only chromosomes 1 through 6 plus chromosome 8, excluding all other variants?

**ASSISTANT:** You can specify chromosomes to PLINK as a hyphenated range combined with a comma-separated list, such as `1-6,8`. PLINK will exclude all variants that are not on these listed chromosomes.

---

## [570] source=multitask_sft_big

**USER:** I generated gene trees using OrthoFinder and the gene IDs contain species prefixes like 'HUMAN_gene123'. How does the tool 'Chado load trees' handle these prefixes?

**ASSISTANT:** `Chado load trees` provides an option to specify a comma-separated list of prefixes to be stripped from identifiers, allowing clean mapping of OrthoFinder output to database features.

---

## [571] source=multitask_sft_big

**USER:** I want to run `normalyzerde_retention_time_normalization`. My raw LC-MS matrix with retention times is stored at `/data/lcms_raw.tsv` and my group assignments are in `/data/groups_design.tsv`. How should these be mapped to the workflow's data inputs?

**ASSISTANT:** You can map your files to the workflow's parameters as follows:
- `tiny_data.tsv`: `/data/lcms_raw.tsv` (raw expression matrix with retention times)
- `tiny_design.tsv`: `/data/groups_design.tsv` (design matrix mapping samples to groups)

Both inputs are required matrix files.

---

## [572] source=multitask_sft_big

**USER:** Run the Mean Line Projection cluster analysis workflow on my dataset matrix 'pca_scores_2d.tsv' with class assignment vector 'treatment_vs_control.rds'.

**ASSISTANT:** I have extracted the following parameters for the `clustersignificance_mlp_analysis` workflow:
- `mlpMatrix`: 'pca_scores_2d.tsv' (2D matrix with samples as rows and 2 dimensions as columns)
- `classes`: 'treatment_vs_control.rds' (character vector of 2 class labels)

---

## [573] source=multitask_sft_big

**USER:** What exact mandatory input datasets must I prepare to run the genvisr workflow?

**ASSISTANT:** You must provide two inputs: 'brcaMAF' (a data frame representing a MAF file) and 'clinical' (a data frame containing clinical data in long format).

---

## [574] source=multitask_sft_big

**USER:** What data input slot must be configured to run the DMRScan workflow?

**ASSISTANT:** The DMRScan workflow requires a non-optional data input slot named `input_files`, which accepts `count_data`.

---

## [575] source=multitask_sft_big

**USER:** What is the required data input for the 'sdams_matrix_based_analysis' workflow and what are its specifications?

**ASSISTANT:** The required data input is 'featureInfo'. It is a non-optional matrix containing non-negative expression values, such as TPM.

---

## [576] source=multitask_sft_big

**USER:** Here are my test objects in R: a vector of observed stats 'hedenfalk$stat' and a matrix of bootstrap-derived null stats 'hedenfalk$stat0'. How do these align with the inputs for qvalue_fdr_estimation_from_test_statistics?

**ASSISTANT:** The inputs map as follows:
- `hedenfalk$stat`: The vector of observed test statistics.
- `hedenfalk$stat0`: The matrix of empirical null statistics generated via permutation or bootstrap.

---

## [577] source=multitask_sft_big

**USER:** List the expected output files/data structures generated by the mcbiclust transcriptomics workflow.

**ASSISTANT:** The `mcbiclust` workflow produces two primary outputs: `enrichment_results` and `expression_matrix`.

---

## [578] source=multitask_sft_big

**USER:** What is the primary input required by arraymvout_direct_affybatch_outlier_detection?

**ASSISTANT:** The required input is `raw_arrays.CEL`, which is an RDS file representing raw Affymetrix CEL files loaded into an AffyBatch object (`optional: false`).

---

## [579] source=multitask_sft_big

**USER:** What input parameters and files are required to run the Proteome Selectivity Profiling workflow?

**ASSISTANT:** The workflow expects the following inputs:
- `smiles_list`: List of query compound SMILES strings
- `target_class`: Target panel class (e.g., kinase, GPCR, or nuclear receptor)
- `panel_size`: Size of the off-target panel (e.g., 468 for kinome)
- `IC50_threshold_nM`: Threshold in nM for activity determination
- `reference_smiles`: Reference compound SMILES

---

## [580] source=multitask_sft_big

**USER:** Please set up splatter_compare_and_diff_simulations using 'simulated_counts.rds' as my first dataset and 'reference_counts.rds' as the second dataset.

**ASSISTANT:** I have extracted the following parameters for splatter_compare_and_diff_simulations:
- sim1: "simulated_counts.rds"
- sim2: "reference_counts.rds"

---

## [581] source=multitask_sft_big

**USER:** Can Tabular Label Convert be configured to modify column headers instead of row labels in my numerical table?

**ASSISTANT:** Yes. Tabular Label Convert supports converting either the labels of the rows or the columns using an alias map.

---

## [582] source=multitask_sft_big

**USER:** Please set up the Covalent Warhead Design pipeline for SMILES 'CC(=O)C=C' and 'c1ccccc1NC(=O)C=C'. Set the warhead type to 'acrylamide', enable GSH half-life estimation, and turn off kinome selectivity profiling.

**ASSISTANT:** Here are the extracted parameters for the 'Covalent Warhead Design' workflow:
- `smiles_list`: ["CC(=O)C=C", "c1ccccc1NC(=O)C=C"]
- `warhead_type`: "acrylamide"
- `run_gsh`: true
- `run_kinome_selectivity`: false

---

## [583] source=multitask_sft_big

**USER:** Can I leave the 'sce' parameter empty or optional when calling scry_sce_null_residuals_pca?

**ASSISTANT:** No, the 'sce' parameter is not optional (`optional: false`). It must be provided as a SingleCellExperiment object containing raw UMI counts in the 'counts' assay.

---

## [584] source=multitask_sft_big

**USER:** What input data slot must be provided to run the scMultiSim Nextflow pipeline?

**ASSISTANT:** The scMultiSim workflow requires the mandatory data input parameter 'input_files' (expecting 'count_data'), which is read directly by the workflow.

---

## [585] source=multitask_sft_big

**USER:** I want to categorize my environmental 16S rRNA marker gene survey counts using Categorize. My hierarchy has 5 ranks, and I want to aggregate annotations at the penultimate rank. What level should I set?

**ASSISTANT:** You should set the hierarchy level to 4. In Categorize, level 1 is the highest rank, and higher numbers near the leaves; for a 5-level hierarchy, level 4 collapses the data exactly one level above being fully specified.

---

## [586] source=multitask_sft_big

**USER:** What are the default file extensions extracted by the Online data tool, and how should they be entered?

**ASSISTANT:** The default file extensions are sdf, mol, smi, and inchi. They must be specified with one extension per line.

---

## [587] source=multitask_sft_big

**USER:** I have MaxQuant output files named 'evidence.txt' and 'proteinGroups.txt', as well as an experiment design file 'study_design.csv'. How do these map to the msstatsconvert workflow inputs?

**ASSISTANT:** They map to the workflow inputs as follows:
- mq_ev.csv: evidence.txt (MaxQuant evidence file)
- mq_pg.csv: proteinGroups.txt (MaxQuant protein groups file)
- annotation.csv: study_design.csv (experimental design annotation file mapping runs to conditions/replicates).

---

## [588] source=multitask_sft_big

**USER:** Please configure spatialsimgp for my simulation using my coordinate file at '/data/tissue_pixel_coords.csv'.

**ASSISTANT:** I have configured the input for the spatialsimgp workflow:

- coords.csv: /data/tissue_pixel_coords.csv (spatial coordinate matrix containing spatial dimension columns)

---

## [589] source=multitask_sft_big

**USER:** I have a collection of high-dimensional cytometry count data files that I need to pass into tidytof. How is the input parameter defined for this workflow?

**ASSISTANT:** The workflow expects the parameter `input_files` (of type `data`), which receives your cytometry `count_data` files as declared in the workflow input specification.

---

## [590] source=multitask_sft_big

**USER:** Configure the 'Get VCF annotation statistics' tool to process 'cohort_variants.vcf' with a window interval of 5000 bp and prefix 'pop_stats'.

**ASSISTANT:** Here is the parameter mapping for `Get VCF annotation statistics`:
- **Input file**: `cohort_variants.vcf` (VCF file)
- **Step**: `5000` (Step in bp)
- **Output label**: `pop_stats` (Prefix for the output files)

---

## [591] source=multitask_sft_big

**USER:** What input datasets and formats does the hiccompare workflow require?

**ASSISTANT:** The `hiccompare` workflow requires two mandatory matrix inputs: `HMEC.chr22` and `NHEK.chr22`. Both must be provided as either a sparse upper triangular matrix file or an R data frame for chromosome 22. It outputs `normalized_data`.

---

## [592] source=multitask_sft_big

**USER:** I am configuring the Hyperparameter Search tool for a deep learning model. What option must be toggled to output the model skeleton and weights, and what outputs are generated?

**ASSISTANT:** You must check the boolean option located below the model input. Enabling this splits the outputs into two parts: the model skeleton and the trained weights.

---

## [593] source=multitask_sft_big

**USER:** Extract the input parameters required for the Ich S7A Safety Pharmacology workflow from this protocol note: 'Candidate molecule Aspirin (SMILES: CC(=O)OC1=CC=CC=C1C(=O)O) was tested for Pain at an oral dose of 10 mg/kg, reaching a Cmax of 150 ng/mL. The calculated safety margin is 30.'

**ASSISTANT:** Here are the extracted input parameters for the workflow:
- `compound_name`: "Aspirin"
- `smiles`: "CC(=O)OC1=CC=CC=C1C(=O)O"
- `indication`: "Pain"
- `dose_mg_kg`: 10
- `exposure_cmax_ng_mL`: 150
- `route`: "oral"
- `safety_margin`: 30

---

## [594] source=multitask_sft_big

**USER:** What input slots and data types are required by the factDesign workflow?

**ASSISTANT:** The workflow requires a mandatory input slot named `input_files` of type `data` representing `count_data` (`optional: false`, `read_by_workflow: true`).

---

## [595] source=multitask_sft_big

**USER:** I want to run the pharmacology/predict_admet_properties workflow on a list of SMILES using DeepPurpose MPNN models and a chunk size of 500. What inputs and parameters need to be configured?

**ASSISTANT:** Based on the workflow definition, configure the following inputs:
- `smiles_list`: your list of compound SMILES strings
- `ADMET_model_type`: MPNN (specifying DeepPurpose pretrained models)
- `admet_shard_size`: 500

---

## [596] source=multitask_sft_big

**USER:** I want to run phyloseq_bar_plot showing the top 20 taxa across my samples.

**ASSISTANT:** Extracted parameter for `phyloseq_bar_plot`:
- Number of taxa: 20 (valid positive integer within the supported range of 1 to 50).

---

## [597] source=multitask_sft_big

**USER:** I have an OTU count table `microbe_counts.tsv` with samples along rows and OTUs along columns, and a metadata sheet `sample_info.tsv` containing treatment and batch variables. How should these map to the inputs of the plsdabatch workflow?

**ASSISTANT:** These map to the required inputs of `plsdabatch` as follows:
- `ad.count`: `microbe_counts.tsv` (matrix containing raw OTU/microbial counts with samples in rows and OTUs in columns)
- `ad.metadata`: `sample_info.tsv` (metadata containing treatment and batch factor variables)

---

## [598] source=multitask_sft_big

**USER:** Here are my run inputs for production MD: GRO file is complex.gro, TOP file is system.top, CPT file is npt_equil.cpt, and parameter file is custom_prod.mdp.

**ASSISTANT:** Extracted inputs for GROMACS production simulation:
- GRO file: complex.gro
- TOP file: system.top
- CPT file: npt_equil.cpt (from NPT equilibration)
- MDP file: custom_prod.mdp

---

## [599] source=multitask_sft_big

**USER:** I am configuring VIRULIGN for FASTA sequences. I want the reference sequence to have gaps added whenever codon insertions are found in the target sequences. How should I set the insertion option?

**ASSISTANT:** You should set the insertion option to 'yes'. In VIRULIGN, selecting 'yes' inserts gaps into the reference sequence to accommodate the identification of codon insertions in the target sequences.

---

## [600] source=multitask_sft_big

**USER:** In chicPlotViewpoint, what happens if I do not choose to highlight significant regions in the visualization?

**ASSISTANT:** If the option to highlight significant regions is not set in `chicPlotViewpoint`, the significant file data is only used to update the p-values rather than visually highlighting those regions in the plot.

---

## [601] source=multitask_sft_big

**USER:** What outputs does the findips_survival_outcome_ip_detection pipeline generate?

**ASSISTANT:** The workflow produces two main outputs: `feature_selection` and `visualizations`.

---

## [602] source=multitask_sft_big

**USER:** I want to run the Hexamer frequency tool on my sequence set, but I also want 6mer frequency calculated for the reference genome and for mRNA sequences. Which options should I pass?

**ASSISTANT:** To calculate hexamer frequencies for those additional sets, pass:
- `-r`: specifies calculation for the reference genome
- `-g`: specifies calculation for the mRNA sequences

---

## [603] source=multitask_sft_big

**USER:** Run randrotation with my expression count table counts_matrix.tsv (genes along rows, samples along columns) and sample metadata in metadata_batch.csv.

**ASSISTANT:** I have extracted the following parameters for the `randrotation` workflow:
- `edata`: counts_matrix.tsv (matrix of gene expression data with features as rows and samples as columns)
- `pdata`: metadata_batch.csv (dataframe of phenotype and batch information for each sample)

---

## [604] source=multitask_sft_big

**USER:** I am running Vsearch Sort on my amplicon sequences. How do I sort the entries by sequence length instead of abundance?

**ASSISTANT:** To sort by sequence length, use the `--sortbylength` parameter. If you need to sort by decreasing abundance instead, you would use `--sortbysize`.

---

## [605] source=multitask_sft_big

**USER:** What are the declared input requirements for the Rsamtools workflow?

**ASSISTANT:** The Rsamtools workflow requires a non-optional data input named `input_files` mapped to the `count_data` input slot.

---

## [606] source=multitask_sft_big

**USER:** What input parameters and file formats are expected for peaks in `chipenrich_narrow_peak_enrichment_chipenrich`?

**ASSISTANT:** The workflow accepts the `peaks_E2F4` parameter, which can be provided as a data.frame or a file path pointing to a `.narrowPeak` or `.bed` file containing narrow peak calls.

---

## [607] source=multitask_sft_big

**USER:** Set up the inputs for the Helical SPA Pipeline: movies are in '/data/filaments/raw_movies', pixel size is 0.82 Å, acceleration voltage is 300 kV, spherical aberration is 2.7 mm, total dose is 45 e-/Å². Filament diameter is 120 Å, helical rise is 4.75 Å, twist is -166.5 degrees, overlap fraction is 0.6, and minimum filament length is 300 Å.

**ASSISTANT:** Extracted workflow parameters:
- `movies_path`: '/data/filaments/raw_movies'
- `pixel_size`: 0.82
- `voltage`: 300
- `cs`: 2.7
- `total_dose`: 45
- `filament_diameter_angstroms`: 120
- `helical_rise_angstroms`: 4.75
- `helical_twist_deg`: -166.5
- `overlap_fraction`: 0.6
- `min_filament_length_angstroms`: 300

---

## [608] source=multitask_sft_big

**USER:** I want to run the scmap workflow. I have my FPKM gene expression matrix saved as 'yan_counts.rds' and cell type annotations in 'annotations_df.csv'. Which workflow inputs do these map to?

**ASSISTANT:** These map to the following scmap workflow inputs:
- `yan`: `yan_counts.rds` (matrix of FPKM gene expression, non-optional)
- `ann`: `annotations_df.csv` (data frame containing cell type annotations, non-optional)

---

## [609] source=multitask_sft_big

**USER:** Here are the files I have for running reference gene selection in normqpcr: raw technical replicates file qPCR.techReps.txt and a TaqMan qPCR file example.txt. Please identify which input files correspond to the normqpcr workflow requirements.

**ASSISTANT:** Based on the normqpcr workflow specifications, the extracted inputs are:
- qPCR.techReps.txt: Raw qPCR data with technical replicates (required input)
- example.txt: TaqMan qPCR data (alternative/additional data input)

---

## [610] source=multitask_sft_big

**USER:** Which parameters in MSGFPlusAdapter are combined to determine the actual precursor mass tolerance?

**ASSISTANT:** The actual precursor mass tolerance is determined by combining the non-monoisotopic peak error consideration with the `precursor_mass_tolerance` and `precursor_error_units` parameters.

---

## [611] source=multitask_sft_big

**USER:** In the swfdr_science_wise_fdr_estimation workflow, what parameter or data input handles the literature p-values, and is it mandatory?

**ASSISTANT:** The data input is `journals_pVals` (described as a data frame containing published p-values and truncation status metadata). It is mandatory (`optional: false`) and read directly by the workflow.

---

## [612] source=multitask_sft_big

**USER:** I am setting up a molecular screening workflow and want a tighter, more specific definition of my molecule's features. How does the Pharmacophore tool handle this?

**ASSISTANT:** In the Pharmacophore tool, you can enable the flag that increases the number of pharmacophore points, which generates a more specific spatial and chemical description of the molecule.

---

## [613] source=multitask_sft_big

**USER:** I need to set up gdnax in R. My alignment file is at '/data/alignments/sample1.bam' and I want to use 'TxDb.Hsapiens.UCSC.hg38.knownGene' for gene annotations. Extract the parameters for the workflow.

**ASSISTANT:** Here are the extracted parameters for the `gdnax` workflow:
- `bamfiles`: `c("/data/alignments/sample1.bam")`
- `txdb`: `"TxDb.Hsapiens.UCSC.hg38.knownGene"`

---

## [614] source=multitask_sft_big

**USER:** How do I configure the `-I` parameter in BWA-MEM2 if my paired-end library has a mean insert size of 250 bp and standard deviation of 25 bp?

**ASSISTANT:** You can specify `-I 250,25`. In BWA-MEM2, only the mean is required (e.g., `250`), but providing mean and standard deviation as `250,25` is also valid. Note that skipping values with empty commas, such as `250,,10`, is invalid.

---

## [615] source=multitask_sft_big

**USER:** Please identify the clustering inclusion criterion described here: 'Filter clusters so that the minimum combined length of tandem repeat arrays within a single cluster meets the threshold for TAREAN analysis.'

**ASSISTANT:** The parameter/criterion is the 'minimum combined length of tandem repeat arrays within a single cluster', which determines whether a cluster is included in TAREAN analysis.

---

## [616] source=multitask_sft_big

**USER:** I am preparing my data for specond_stepwise_specond_analysis. What are the requirements for the input file?

**ASSISTANT:** The required input is `expression_matrix.txt`, which must be a matrix of log2 expression values with genes arranged as rows and experimental conditions arranged as columns.

---

## [617] source=multitask_sft_big

**USER:** Configure rtpca with my experiment files: 'tpp_data.RData' containing our ExpressionSets, 'ppi_annotations.csv' with our interaction network, and 'complex_annotations.csv' with the complex memberships.

**ASSISTANT:** The parameters for the `rtpca` workflow are mapped as follows:
- `tpp_data.RData`: `tpp_data.RData` (type: rds/RData list of ExpressionSets or matrices)
- `ppi_annotations.csv`: `ppi_annotations.csv` (data frame of known PPIs)
- `complex_annotations.csv`: `complex_annotations.csv` (data frame of protein complex memberships)

---

## [618] source=multitask_sft_big

**USER:** I want to set up edge_timecourse_de_analysis. Here are my files: expression_counts.tsv (matrix of gene expression measurements), group_status.tsv (vector of group covariates), sample_timepoints.tsv (vector of time points), and patient_ids.tsv (vector of individual IDs). How should these map to the workflow inputs?

**ASSISTANT:** The files map to the workflow inputs as follows:
- `kidexpr` (or `endoexpr`): `expression_counts.tsv` (matrix of gene expression measurements)
- `sex` (or `class`): `group_status.tsv` (vector of adjustment or group covariates)
- `age` (or `time`): `sample_timepoints.tsv` (vector of time points)
- `ind`: `patient_ids.tsv` (vector of individual IDs for longitudinal studies)

---

## [619] source=multitask_sft_big

**USER:** I need to run Cnvpytor Partition on my dataset with bin sizes 10000, 20000, and 50000. How should I supply the bin size parameter?

**ASSISTANT:** For Cnvpytor Partition, multiple bin sizes should be separated by a space. The extracted parameter value is:

- bin size: `10000 20000 50000`

---

## [620] source=multitask_sft_big

**USER:** In Stacks: genotypes, I want to restrict the export so that only loci present in at least 15 individuals of the population are included. Which parameter handles this?

**ASSISTANT:** You should use the `-r` option. The `-r` parameter allows you to specify the minimum number of population individuals in which a locus must exist to be exported (e.g., `-r 15`).

---

## [621] source=multitask_sft_big

**USER:** I want to perform genomic proximity enrichment with knowyourcg_genomic_proximity. My CpG probe ID list is stored in 'selected_probes.rds'. Please map this input.

**ASSISTANT:** The parameter mapping for 'knowyourcg_genomic_proximity' is:
- `character`: selected_probes.rds (character vector of CpG probe IDs)

---

## [622] source=multitask_sft_big

**USER:** In SMAP-design for genome editing, which specific genomic features must be present in the input GFF3 file?

**ASSISTANT:** The input GFF3 file must contain 'gene', 'CDS', and 'exon' features, with positions mapped relative to the accompanying FASTA file.

---

## [623] source=multitask_sft_big

**USER:** Does switchBox support decision rules like 'majority wins' for its feature pair classifiers?

**ASSISTANT:** Yes. According to the switchBox specifications, it employs classifiers based on comparisons of feature pairs (TSP) using decision rules such as the majority wins principle.

---

## [624] source=multitask_sft_big

**USER:** Here is my input dataset configuration for mutational signature extraction: `mutational_catalog.csv`, which is an unformatted text count matrix of samples across 96 trinucleotide mutation types. Does the `suitor` workflow accept this directly?

**ASSISTANT:** Yes. The `suitor` workflow requires a non-optional data input named `mutational_catalog.csv` of type matrix (a matrix or data frame of mutational counts where columns represent tumors/samples and rows represent mutation types, such as 96 trinucleotide categories), which is read by the workflow.

---

## [625] source=multitask_sft_big

**USER:** I am preparing inputs for atacseqqc_atacseq_downstream_analysis. Do I have to provide a shifted.bam file?

**ASSISTANT:** No, according to the workflow parameters, 'shifted.bam' is marked as optional ('optional': true).

---

## [626] source=multitask_sft_big

**USER:** What outputs can I expect from running the `geodiff` pipeline on my NanoString dataset?

**ASSISTANT:** The `geodiff` workflow generates two primary outputs: `de_table` (containing differential expression analysis results) and `normalized_data` (containing Poisson threshold normalized expression data).

---

## [627] source=multitask_sft_big

**USER:** I want to configure the Bagging Embeddings Processor to perform bagging specifically on my training and validation sets. How should I specify that?

**ASSISTANT:** You should configure the split parameter with the comma-separated value `'0,1'`, where 0 represents train and 1 represents val (with 2 representing test).

---

## [628] source=multitask_sft_big

**USER:** In adacgh2_directory_ff_forking, what is the format and role of the data input file `inputEx.txt`?

**ASSISTANT:** In the `adacgh2_directory_ff_forking` workflow, `inputEx.txt` is an optional large tab-separated text file containing array CGH (aCGH) data.

---

## [629] source=multitask_sft_big

**USER:** What exact input files are needed to run the drivernet workflow?

**ASSISTANT:** The drivernet workflow requires the following four inputs:
- 'samplePatientMutationMatrix.ext': a binary matrix of patient mutations
- 'samplePatientOutlierMatrix.ext': a binary matrix of patient expression outliers
- 'sampleInfluenceGraph.ext': a gene-gene interaction network
- 'sampleGeneNames.ext': a character vector of gene names for permutation

---

## [630] source=multitask_sft_big

**USER:** I am writing a mutation expression in csvtk-advanced-mutate. How should string literals be enclosed in expressions like comparing a name column?

**ASSISTANT:** String literals must be enclosed in double quotes (for example, `'$name=="abc"'`). The single quote character (`'`) is invalid and will be replaced by the tool.

---

## [631] source=multitask_sft_big

**USER:** Configure the tigre non-Affymetrix time series analysis workflow using our raw expression matrix file 'norm_counts.tsv', time points vector [0, 2, 4, 8, 12], and experiment replicates [1, 1, 2, 2, 3].

**ASSISTANT:** Here is the mapped input configuration for `tigre_non_affymetrix_time_series_analysis`:
- `data`: 'norm_counts.tsv' (matrix of raw expression values)
- `times`: [0, 2, 4, 8, 12] (vector of observation times)
- `experiments`: [1, 1, 2, 2, 3] (vector of experiment indices)

Upon execution, this workflow will generate outputs in table/csv, plot/pdf, and object/rds formats.

---

## [632] source=multitask_sft_big

**USER:** I am configuring Scanpy DiffusionMap for a single-cell RNA-seq run. When should I select the 'No packaged matrix output' option?

**ASSISTANT:** You should choose 'No packaged matrix output' when auxiliary files are generated (such as marker genes). Do not select this option if no other output files are being produced, as the tool will not yield meaningful outputs.

---

## [633] source=multitask_sft_big

**USER:** What data inputs are defined for the ResidualMatrix workflow?

**ASSISTANT:** The workflow defines one data input: `count_data`, which is an optional data input slot (`(declared .nf input slot)`).

---

## [634] source=multitask_sft_big

**USER:** Please set up EICExtractor for my LC-MS proteomics run. Enable automatic detection of injection RT peaks so I don't have to define them in the pos file.

**ASSISTANT:** Configuring EICExtractor:
- Feature: Automatic detection of injection RT peaks enabled (bypassing manual retention time definitions in the 'pos' input file)
- Target Omics: LC-MS/MS quantitative proteomics.

---

## [635] source=multitask_sft_big

**USER:** I have a file called simulation_RIVER.gz containing subject IDs, gene names, genomic features, expression Z-scores, and N2 pair identifiers. How does this map to the RIVER workflow's input parameters?

**ASSISTANT:** In the `river` workflow, this file maps to the `simulation_RIVER.gz` data input parameter, which expects a gzipped text file containing subject ID, gene name, genomic features, expression Z-scores, and N2 pair identifiers.

---

## [636] source=multitask_sft_big

**USER:** We want to configure the semaglutide validation model with a subcutaneous absorption rate ka of 0.035 1/h, central clearance of 35 mL/h, central volume of 5.5 L, a dose of 0.5 mg, and baseline body weight of 92 kg over 30 weeks. Can you extract the parameters for the workflow?

**ASSISTANT:** Here are the extracted parameters mapped to the `P0 PKPD Semaglutide Validation` workflow inputs:
- `pk_ka_h`: 0.035
- `pk_cl_ml_h`: 35
- `pk_v1_l`: 5.5
- `dose_mg`: 0.5
- `pd_baseline_wt_kg`: 92
- `n_weeks`: 30

---

## [637] source=multitask_sft_big

**USER:** I am preparing inputs for goseq_custom_category_analysis. I have a binary vector of DE status for assayed genes (`genes`), an Ensembl to Entrez mapping object (`org.Hs.egENSEMBL2EG`), and an Entrez to KEGG mapping object (`org.Hs.egPATH`). Please confirm if these match the workflow's expected data inputs.

**ASSISTANT:** Yes, these exactly match the required inputs for `goseq_custom_category_analysis`: 1) `genes` (named binary vector of assayed genes and DE status), 2) `org.Hs.egENSEMBL2EG` (Ensembl to Entrez mapping object), and 3) `org.Hs.egPATH` (Entrez to KEGG mapping object).

---

## [638] source=multitask_sft_big

**USER:** I have my Illumina DNA methylation array outputs: 'tumor_bisulfite_beta.tsv' for standard bisulfite conversion and 'tumor_ox_bisulfite_beta.tsv' for oxidative bisulfite conversion. How do I map these to enmix_oxbs_mle inputs?

**ASSISTANT:** You should assign your files to the `enmix_oxbs_mle` input parameters as follows:
- `beta.BS`: 'tumor_bisulfite_beta.tsv'
- `beta.oxBS`: 'tumor_ox_bisulfite_beta.tsv'

---

## [639] source=multitask_sft_big

**USER:** I want to generate a mesh from geology_layer.shp using the GMSH method with a target cellsize of 25.0 via OGSTools shp2msh.

**ASSISTANT:** The extracted parameters for OGSTools shp2msh are:
- Input shapefile: geology_layer.shp
- Meshing method: GMSH
- Cellsize: 25.0

---

## [640] source=multitask_sft_big

**USER:** I am configuring `qiime2 feature-classifier classify-consensus-blast`. I want to search against reference_reads, evaluate a maximum of 15 hits, and require that at least 60% of the hits agree on the assigned taxonomy. Which parameters should I set?

**ASSISTANT:** Set `maxaccepts` to 15 and `min_consensus` to 0.60, with your reference database passed to `reference_reads` and input sequences to `query`.

---

## [641] source=multitask_sft_big

**USER:** I am configuring 'table column transformations' for my metabolomics dataset. I need to transform the 'Metabolite_Intensity' and 'Standardized_Peak_Area' columns. Which parameter do I set?

**ASSISTANT:** You should supply 'Metabolite_Intensity' and 'Standardized_Peak_Area' to the 'Columns to Transform' parameter, which accepts one or more column header names from your dataset.

---

## [642] source=multitask_sft_big

**USER:** Please set up the snprelate_relatedness_and_ibd_analysis workflow using my open GDS file handle gds_handle and subset samples using sample_ids_yri.txt.

**ASSISTANT:** The parameters for `snprelate_relatedness_and_ibd_analysis` are mapped as follows:
- `genofile`: "gds_handle" (Open GDS file handle)
- `YRI.id`: "sample_ids_yri.txt"

---

## [643] source=multitask_sft_big

**USER:** What input files are required to run virAnnot Blast2tsv, and what is the recommended maximum evalue when using TBLASTX?

**ASSISTANT:** virAnnot Blast2tsv requires two input files: a BLAST file from blast annotation and a FASTA contig file. When using the TBLASTX blast type, the standard maximum evalue threshold is 0.001.

---

## [644] source=multitask_sft_big

**USER:** I want to run PAPAA for cell line prediction using the genes TP53, PTEN, and PIK3CA. How do I specify these pathway genes in the command?

**ASSISTANT:** You can supply the target pathway genes to PAPAA using the `--path_genes` parameter. Pass them either as a comma-separated string of HUGO symbols (e.g., `--path_genes TP53,PTEN,PIK3CA`) or point to a file containing them (e.g., `--path_genes path_genes.txt`).

---

## [645] source=multitask_sft_big

**USER:** I want to run ngsreports. Here are my raw inputs: fastqc.zip containing FastQC output archives, or alternatively fastqc_extracted_directory.

**ASSISTANT:** The input parameters identified for the ngsreports workflow are:
- `fastqc.zip`: FastQC output zip files (optional)
- `fastqc_extracted_directory`: extracted FastQC directories

---

## [646] source=multitask_sft_big

**USER:** Extract the relevant parameters for running the Transporter Ddi Pgp Bcrp assessment workflow from this experiment summary:
Compound: BM-402
SMILES: CC1=CC=C(C=C1)NC(=O)C2=CC=CC=C2
Molecular weight: 211.26 g/mol
Clinical dose: 150 mg
Total Cmax: 1250 ng/mL
Fraction unbound (plasma): 0.08
Fraction absorbed: 0.85
Transporter IC50 measurements: P-gp IC50 is 4.5 uM, BCRP IC50 is 12.0 uM, OATP1B1 IC50 is 35 uM, and MATE1 IC50 is 50 uM.
Efflux ratios: P-gp efflux ratio is 3.2, BCRP efflux ratio is 1.8.

**ASSISTANT:** Extracted parameters for `drug_discovery/transporter_ddi_pgp_bcrp`:
- `compound_name`: "BM-402"
- `smiles`: "CC1=CC=C(C=C1)NC(=O)C2=CC=CC=C2"
- `molecular_weight`: 211.26
- `dose_mg`: 150
- `cmax_total_ng_ml`: 1250
- `fu_p`: 0.08
- `fa`: 0.85
- `pgp_ic50_um`: 4.5
- `bcrp_ic50_um`: 12.0
- `oatp1b1_ic50_um`: 35.0
- `mate1_ic50_um`: 50.0
- `efflux_ratio_pgp`: 3.2
- `efflux_ratio_bcrp`: 1.8

---

## [647] source=multitask_sft_big

**USER:** What input file and format are required to run the esetvis workflow?

**ASSISTANT:** The esetvis workflow strictly requires 'expression_data.RData' (type: rds_se, read_by_workflow: true), which must be an ExpressionSet or SummarizedExperiment object containing expression values and sample/feature annotations.

---

## [648] source=multitask_sft_big

**USER:** I want to supply my data to the semisup workflow. I have a quantitative trait file 'trait_levels.tsv' as my response vector and genotype data 'snps.raw' for the genetic variants. How should these map to the workflow inputs?

**ASSISTANT:** The workflow inputs should be mapped as follows:
- `y`: 'trait_levels.tsv' (vector of quantitative trait observations, non-optional)
- `snp`: 'snps.raw' (vector or matrix of SNP genotypes)

---

## [649] source=multitask_sft_big

**USER:** In Snippy, how do I configure the reference setting if I want to perform self-mapping against an input file from my current session?

**ASSISTANT:** To perform self-mapping in Snippy, select `history` under the reference selection option, and then choose your input file from the history as the reference.

---

## [650] source=multitask_sft_big

**USER:** Please set up anf_multi_view_affinity_network_fusion with my multi-omic affinity list 'multi_view_matrices' and ground truth class labels vector 'sample_classes'.

**ASSISTANT:** I have mapped your parameters for the anf_multi_view_affinity_network_fusion workflow:
- Wall: multi_view_matrices
- project_ids: sample_classes

This will execute multi-view affinity network fusion and spectral clustering to generate the cluster_assignments output.

---

## [651] source=multitask_sft_big

**USER:** Run the Guppy basecaller wrapper with my ONT raw data collection located in fast5_collection: 'reads/fast5_set/' and config file: 'configs/guppy_dna.tar'.

**ASSISTANT:** Extracted inputs for Guppy basecaller wrapper:
- fast5 files input: `'reads/fast5_set/'` (collection of fast5 files)
- configuration input: `'configs/guppy_dna.tar'` (tar file)

---

## [652] source=multitask_sft_big

**USER:** What input data slot is required to run the CytoML workflow?

**ASSISTANT:** The CytoML workflow requires the mandatory input data slot named `plot_object`.

---

## [653] source=multitask_sft_big

**USER:** In chipqc_single_sample_qc, how is the sequence alignment input specified, and is it required?

**ASSISTANT:** The sequence alignment input is specified by the parameter `reads`, which expects a file of type `bam` (for example, `reads/SRR568129.bam`), and it is marked as `optional: true`.

---

## [654] source=multitask_sft_big

**USER:** Configure the ebseq_isoform_de_multi_conditions workflow with my files: raw counts matrix 'counts_matrix_isoforms.csv', sample condition mappings 'sample_conditions.csv', and isoform-to-gene mapping file 'isoform_to_gene.csv'.

**ASSISTANT:** Here is the parameter mapping for ebseq_isoform_de_multi_conditions:
- multi_condition_isoform_counts.csv: 'counts_matrix_isoforms.csv'
- isoform_annotations.csv: 'isoform_to_gene.csv'
- multi_conditions.csv: 'sample_conditions.csv'

---

## [655] source=multitask_sft_big

**USER:** What input does the collate_alpha tool expect in a metagenomics workflow?

**ASSISTANT:** The input to 'collate_alpha' is the log file generated by 'alpha_diversity'.

---

## [656] source=multitask_sft_big

**USER:** Check my input specification for running spatialde_spatial_experiment_workflow: spe_file='sample1_counts_coords.rds'. Does this fulfill all mandatory data inputs?

**ASSISTANT:** Yes. The workflow defines only one required data input: `spe` of type `rds` (a SpatialExperiment object containing spatial coordinates and raw count assays). Providing 'sample1_counts_coords.rds' satisfies this requirement.

---

## [657] source=multitask_sft_big

**USER:** We want to run generecommender. The expression data is loaded in an R matrix called 'norm_expr_matrix' and our query gene list is query_list <- c('ESR1', 'GATA3', 'FOXA1'). Please assign the workflow parameters.

**ASSISTANT:** The parameters for the `generecommender` workflow are extracted as follows:
- `geneData`: `norm_expr_matrix` (microarray expression matrix with genes as rows and experiments as columns)
- `my.query`: `c('ESR1', 'GATA3', 'FOXA1')` (character vector of query gene/probeset IDs)

---

## [658] source=multitask_sft_big

**USER:** What is the mandatory input required by the tomoseqr_detect_axial_peak_genes workflow?

**ASSISTANT:** The workflow requires the non-optional data input 'testx', which is a Tomo-seq expression data frame for a specific axis.

---

## [659] source=multitask_sft_big

**USER:** In ipaPy2 gibbs sampler, how is the burn-in period handled if I do not specify the number of iterations to ignore when calculating posterior probabilities?

**ASSISTANT:** If the parameter for the number of iterations to ignore is set to `None`, `ipaPy2 gibbs sampler` defaults to discarding the first 10% of the total iterations when computing posterior probabilities.

---

## [660] source=multitask_sft_big

**USER:** What mandatory inputs are required to run the `xcms_quality_based_feature_filtering` metabolomics workflow?

**ASSISTANT:** The workflow requires the input `faahko.rds`, which is a non-optional RDS file (`optional: false`) containing a preprocessed `XcmsExperiment` object that is read by the workflow.

---

## [661] source=multitask_sft_big

**USER:** What are the required input parameters and final outputs of the `orderedlist_compare_ordered_lists` workflow?

**ASSISTANT:** The workflow requires two mandatory data inputs:
- `list1`: Character vector of ordered gene identifiers.
- `list2`: Character vector of ordered gene identifiers.

Its output is:
- `visualizations`: Comparison visualizations of the ordered gene lists.

---

## [662] source=multitask_sft_big

**USER:** I am configuring SamToFastq to convert a BAM file back to FASTQ. Which parameter controls whether reverse-strand aligned reads are reverse-complemented back to their original read orientation?

**ASSISTANT:** The parameter that controls this behavior is RE_REVERSE. When set to True (which is the default setting), reads mapped to the reverse strand have their sequences reverse-complemented to restore the original orientation in the output FASTQ.

---

## [663] source=multitask_sft_big

**USER:** How can I define taxon-specific sequence length thresholds when using `qiime2 rescript filter-seqs-length-by-taxon`?

**ASSISTANT:** You can define individual length thresholds for specific taxonomic groups by using the 'labels' option. This allows you to apply filtering criteria to multiple taxonomic groups simultaneously while optionally setting global minimum and maximum lengths.

---

## [664] source=multitask_sft_big

**USER:** What input format specifications does the BED-to-GFF conversion tool require?

**ASSISTANT:** The tool expects input formatted specifically as a 12-column UCSC wiggle BED file to convert it into GFF3.

---

## [665] source=multitask_sft_big

**USER:** For the splicewiz coverage visualization run, please set up the input mapping with my dataset: I have my NxtSE object saved at `experiment_data.rds` and my differential analysis output at `differential_edgeR.tsv`.

**ASSISTANT:** The parameters extracted for the `splicewiz_coverage_visualization` workflow are:
- `se`: `experiment_data.rds` (type: rds, NxtSE object)
- `res_edgeR`: `differential_edgeR.tsv` (type: data)

---

## [666] source=multitask_sft_big

**USER:** I have a matrix of raw counts 'pdac_epi_counts' and clinical metadata in 'interestedVariables'. If I pass these into cogaps_distributed_sc_cogaps_workflow, what outputs should I expect?

**ASSISTANT:** The workflow accepts 'pdac_epi_counts' (matrix of raw single-cell counts) and 'interestedVariables' (metadata matrix/dataframe), and it will produce two outputs: 'enrichment_results' and 'visualizations'.

---

## [667] source=multitask_sft_big

**USER:** What outputs are produced when running the ontoproc workflow with hpca_sce and hpca.csv?

**ASSISTANT:** The `ontoproc` workflow outputs `cell_type_annotations` (formal ontology mappings) and a filtered `singlecellexperiment` object subsetted to descendants of the specified cell type.

---

## [668] source=multitask_sft_big

**USER:** What are the input requirements and underlying tools configured for the ndexr workflow?

**ASSISTANT:** The `ndexr` workflow requires a non-optional data input under the slot `input_files` (accepting count_data). The tools utilized in the workflow are `bioconductor/ndexr` and `bioconductor/knitr`.

---

## [669] source=multitask_sft_big

**USER:** What are the default GC content filter thresholds and window lengths evaluated in the sirna_design workflow?

**ASSISTANT:** The workflow scans all 19-, 20-, and 21-mer windows and applies a default GC content filter of 30–52%.

---

## [670] source=multitask_sft_big

**USER:** Here are the files for my variant comparison run: I have the sequencing VCF at 'patient_tumor_sample.vcf.gz' and the COSMIC export file 'CosmicCLP_MutantExport.tsv.gz'. How should these be mapped to the seqcat_cosmic_profile_comparison data inputs?

**ASSISTANT:** For the `seqcat_cosmic_profile_comparison` workflow, map your files as follows:
- `sample.vcf.gz`: 'patient_tumor_sample.vcf.gz' (VCF file of the HTS sample)
- `CosmicCLP_MutantExport.tsv.gz`: 'CosmicCLP_MutantExport.tsv.gz' (COSMIC Cell Lines Project mutant export dataset)

---

## [671] source=multitask_sft_big

**USER:** I have two files for survival analysis: 'tumor_expression.csv' which has continuous gene expression with genes as rows and samples as columns, and 'clinical_outcomes.csv' with survival times and censoring status for each sample. How do these map to the messina_survival_analysis_messina workflow inputs?

**ASSISTANT:** They map to the required inputs of `messina_survival_analysis_messina` as follows:
- `expression_matrix.csv`: 'tumor_expression.csv' (matrix of continuous gene expression values with genes as rows and samples as columns)
- `survival_data.csv`: 'clinical_outcomes.csv' (table containing survival times and censoring status for each sample)

---

## [672] source=multitask_sft_big

**USER:** What input format does `selectksigs` accept, and what columns are required in the mutation file?

**ASSISTANT:** The workflow accepts a tab-separated or gzipped text file in Mutation Position Format (`inputFile.txt` or an example like `esophageal.mp.txt.gz`). The file must contain columns for: sample, chromosome, coordinate, reference base, and alternate base.

---

## [673] source=multitask_sft_big

**USER:** I need to run differential stability testing on an atlas dataset stored at `/data/atlas_bench.rds` using Cepo with out-of-memory HDF5 parallel processing. How should I specify the input?

**ASSISTANT:** For the `cepo_out_of_memory_parallel_differential_stability` workflow, supply the SingleCellExperiment object to the following input parameter:
- `cellbench`: `"/data/atlas_bench.rds"` (an RDS file containing a `SingleCellExperiment` object with a `logcounts` assay and `celltype` in `colData`).

---

## [674] source=multitask_sft_big

**USER:** Here are my files for Ribo-seq differential pattern analysis: rep1.bam, rep2.bam, rep3.bam, rep4.bam, and annotation.gtf. Map them to ribodipa_step_by_step_pipeline.

**ASSISTANT:** The files map to the inputs of 'ribodipa_step_by_step_pipeline' as follows:
- bam_path[1]: rep1.bam (Ribo-seq alignment BAM file)
- bam_path[2]: rep2.bam (Ribo-seq alignment BAM file)
- bam_path[3]: rep3.bam (Ribo-seq alignment BAM file)
- bam_path[4]: rep4.bam (Ribo-seq alignment BAM file)
- bam_path[5]: annotation.gtf (Reference genome GTF file)

---

## [675] source=multitask_sft_big

**USER:** I want to trim my paired-end reads r1.fastq and r2.fastq to exactly 100 bp using fgbio TrimFastq. Please identify the inputs and parameters.

**ASSISTANT:** The extracted parameters and inputs are:
- Input FASTQ files: line-matched paired files `r1.fastq` and `r2.fastq`
- Target read length: 100 bp

---

## [676] source=multitask_sft_big

**USER:** Using 'Retrieve Ensembl features in BED format', download genomic annotations specifically for protein_coding and nonsense_mediated_decay transcripts.

**ASSISTANT:** Extracted parameter:
- biotypes: ["protein_coding", "nonsense_mediated_decay"]

---

## [677] source=multitask_sft_big

**USER:** I am configuring Salmon quant for paired-end RNA-seq. I need to ensure that orphan reads are completely ignored during quantification in quasi-mapping mode. Which option controls this?

**ASSISTANT:** You should enable the flag to discard orphan mappings in quasi-mapping mode. When this flag is supplied, Salmon will disregard orphan mappings and strictly use paired mappings for quantification estimates.

---

## [678] source=multitask_sft_big

**USER:** Please set up the beta_significance tool for my metagenomics dataset using the weighted UniFrac metric.

**ASSISTANT:** I have extracted the required parameter for beta_significance:
- significance test to use: 'weighted_unifrac'

---

## [679] source=multitask_sft_big

**USER:** Can I use 'Remove Selected Features or Samples' for proteomics or transcriptomics, or is it restricted strictly to metabolomics?

**ASSISTANT:** While primarily categorized under metabolomics, it also supports proteomics, transcriptomics, and any omics data presented in a wide format, as long as your design file is tab-separated and contains the required `sampleID` column.

---

## [680] source=multitask_sft_big

**USER:** Please set up the seqTools workflow to process our input sequencing data file located at '/data/runs/sample_R1.fastq.gz'.

**ASSISTANT:** I have extracted the input parameter for the seqTools workflow:
- `input_files`: '/data/runs/sample_R1.fastq.gz'

---

## [681] source=multitask_sft_big

**USER:** Prepare the data inputs for camera_isotope_validation using our files: raw run file 'sample_01.mzML' and input peaklist set 'xcms_peaks.RData'.

**ASSISTANT:** Based on the workflow parameter specifications, here are the extracted data inputs:
- `file.mzML`: "sample_01.mzML"
- `input_files`: "xcms_peaks.RData"

---

## [682] source=multitask_sft_big

**USER:** We are setting up the `biostatistics/gate3_interaction_test` workflow. Which input parameters must we supply?

**ASSISTANT:** The workflow requires the following input parameters:
- `trial_file`
- `analysis`
- `outcome_type`
- `biomarker_positive`
- `treatment_experimental`
- `default_treatment`
- `higher_is_better`
- `min_interaction`
- `alpha`

---

## [683] source=multitask_sft_big

**USER:** I am configuring a sequence search where both my query and target database are nucleotide sequences, but I need translation-level alignment. Does NCBI BLAST+ tblastx support translated nucleotide-to-translated nucleotide search?

**ASSISTANT:** Yes. NCBI BLAST+ tblastx is specifically built to search a translated nucleotide database using a translated nucleotide query via the command-line interface.

---

## [684] source=multitask_sft_big

**USER:** I want to configure the `dmrseq` workflow. I have `sample_bismark.cov.gz` containing coverage counts and `sample_metadata.csv` detailing sample groups. How are these read?

**ASSISTANT:** The workflow maps these files to the following required parameters:
- `sample_bismark.cov.gz`: Bismark coverage files containing methylated and total read counts.
- `sample_metadata.csv`: CSV file containing sample identifiers and condition covariates.
Both are mandatory inputs consumed by the workflow to compute DMR statistics.

---

## [685] source=multitask_sft_big

**USER:** Please set up the parameters for the Apply Vcog Grade workflow. We are evaluating canine subjects showing vomiting with a severity score of 3.

**ASSISTANT:** Extracted parameters for Apply Vcog Grade:
- species: canine
- symptom: vomiting
- severity_value: 3
- event_type: adverse event

---

## [686] source=multitask_sft_big

**USER:** What graph export formats are supported by ExtractSubReactionNetwork, and what is the default output format?

**ASSISTANT:** ExtractSubReactionNetwork exports a tabulated edge list (`source id edge type target id`) by default. Other available format options include GML, JsonGraph, and a tabulated node list (`label node id node type`).

---

## [687] source=multitask_sft_big

**USER:** I have a GenomicRatioSet named 'cohort_methy.RData' and an ExpressionSet named 'cohort_gexp.RData'. How should these be mapped to the meal_methylation_expression_integration inputs?

**ASSISTANT:** Map 'cohort_methy.RData' to the `brge_methy` input (GenomicRatioSet containing methylation data) and 'cohort_gexp.RData' to the `brge_gexp` input (ExpressionSet containing gene expression data).

---

## [688] source=multitask_sft_big

**USER:** Which flag in MUMmer tells it to report query coordinates for reverse complement matches relative to the forward strand?

**ASSISTANT:** The parameter is `-c`. It instructs MUMmer to report the query position of a reverse complement match relative to the forward strand of the query sequence.

---

## [689] source=multitask_sft_big

**USER:** We want to run spatial_multiomics_integration using anchor-based transfer with Seurat v5 and Tangram mapping on an input file named sample_visium.rds. Which tools and input formats are recognized by this workflow?

**ASSISTANT:** The workflow accepts input files in 'h5', 'h5ad', or 'rds' formats (such as your sample_visium.rds) and integrates tools including Seurat v5, Tangram, and cell2location for anchor-based transfer and spatial mapping.

---

## [690] source=multitask_sft_big

**USER:** I am preparing a command for `isocorcli` on Orbitrap metabolomics data with a 13C tracer. I need a resolution of 140000 at m/z 200, a tracer purity of 0.99, and the input file is `labeled_data.tsv`. Please extract the required CLI arguments.

**ASSISTANT:** Based on the `isocorcli` CLI syntax, the extracted arguments are:
- Tracer: `-t 13C` (or your specific tracer identifier)
- Mass spectrometer type: `-f orbitrap`
- Resolution: `-r 140000`
- m/z of resolution: `-m 200`
- Tracer purity: `-p 0.99`
- Input data: `labeled_data.tsv`

Command:
`isocorcli -t 13C -f orbitrap -r 140000 -m 200 -p 0.99 labeled_data.tsv`

---

## [691] source=multitask_sft_big

**USER:** Is the expression data input strictly required for scan_upc_rnaseq_upc_expression_probability, or is it optional?

**ASSISTANT:** According to the workflow parameters, the data input 'rna_seq_rpkm.txt' is marked as optional (`optional: true`).

---

## [692] source=multitask_sft_big

**USER:** What input and output formats are used by the `biomarker_patient_enrichment` workflow?

**ASSISTANT:** The `biomarker_patient_enrichment` workflow accepts inputs in `json` format and generates outputs in `json`, `txt`, and `csv` formats.

---

## [693] source=multitask_sft_big

**USER:** I want to run StrainDesign analyzing-model. I have my base model, biomass reaction, and ethanol production reaction ready. Can I also define a specific carbon substrate and media composition?

**ASSISTANT:** Yes. While the model, target reaction, and biomass reaction are the required inputs, StrainDesign analyzing-model allows you to optionally provide a carbon substrate, media composition, and an heterologous pathway to adapt the simulation to your experimental conditions.

---

## [694] source=multitask_sft_big

**USER:** Set up a Particle Subtraction run with mask 'domainA_mask.mrc', invert the mask set to true, and execute it through CryoSPARC.

**ASSISTANT:** Here are the extracted parameters for Particle Subtraction:
- `subtraction_mask`: domainA_mask.mrc
- `invert_mask`: true
- `use_cryosparc`: true

---

## [695] source=multitask_sft_big

**USER:** Please set up pgca using my two input datasets: runA_proteins.tsv and runB_proteins.tsv.

**ASSISTANT:** I have mapped your inputs to the `pgca` workflow parameters:
- `run1.txt`: runA_proteins.tsv
- `run2.txt`: runB_proteins.tsv

Both files will be ingested to generate the global protein group dictionary and workflow visualizations.

---

## [696] source=multitask_sft_big

**USER:** In QuantWiz-IQ, what is the default value for the reporter label maximum peak intensity threshold, and what parameter guides its adjustment?

**ASSISTANT:** In `QuantWiz-IQ`, the default reporter label maximum peak intensity threshold is 0. Setting this threshold depends on the signal-to-noise ratio (S/N) of your proteomics data.

---

## [697] source=multitask_sft_big

**USER:** When compiling a reference with CNVkit Reference, how can I ensure it calculates the GC content and repeat-masked proportion of each region?

**ASSISTANT:** You need to provide the reference genome FASTA file using the `-f` option. When `-f` is supplied, CNVkit Reference calculates the GC content and repeat-masked proportion across each target region.

---

## [698] source=multitask_sft_big

**USER:** What is the default limit for individual categories displayed in pie charts by plot_taxa_summary, and what happens to the remaining categories?

**ASSISTANT:** The default maximum number of individual categories in each pie chart is 20. All additional categories beyond this limit are grouped into an 'other' category.

---

## [699] source=multitask_sft_big

**USER:** I am configuring Panaroo. Which specific parameter category is provided for tuning graph correction settings across its modes?

**ASSISTANT:** The parameters used for fine-tuning Panaroo's modes are located in the 'Graph correction' section.

---

## [700] source=multitask_sft_big

**USER:** What is the mandatory input required by `mungesumstats_liftover_genome_build`?

**ASSISTANT:** The mandatory input is `sumstats_dt`, which must be a `data.table` containing formatted GWAS summary statistics (`optional: false`).

---

## [701] source=multitask_sft_big

**USER:** I want to perform self-mapping with my own reference sequence in snippy-core instead of using built-in indexes. How should I configure the reference setting?

**ASSISTANT:** To perform self-mapping, set the reference option to 'history' and select your input file as the reference.

---

## [702] source=multitask_sft_big

**USER:** In my metabolomics run, I want to screen for targeted compounds in my untargeted peak table. I want to allow an m/z error window of ±10 ppm and a retention time deviation of ±0.25 minutes. Which parameters are configured for this in MS Target Screening?

**ASSISTANT:** In `MS Target Screening`, you should configure: 1) the mass-to-charge ratio tolerance in ppm (set to 10 ppm), and 2) the retention time tolerance (set to 0.25 minutes). Both tolerances are applied symmetrically (±) around the target marker values.

---

## [703] source=multitask_sft_big

**USER:** Please set up the Metadata Harmonizer workflow for cohort_samples.tsv using snomed_terms.obo. Use a fuzzy threshold of 0.85, token threshold of 0.75, review threshold of 0.60, and an ambiguity margin of 0.05.

**ASSISTANT:** The extracted parameters for the `Metadata Harmonizer` workflow are:
- `metadata_file`: "cohort_samples.tsv"
- `ontology_file`: "snomed_terms.obo"
- `fuzzy_threshold`: 0.85
- `token_threshold`: 0.75
- `review_threshold`: 0.60
- `ambiguity_margin`: 0.05

---

## [704] source=multitask_sft_big

**USER:** I have finished quantification using simpleaf and saved the directory at '/data/scrna/simpleaf_output'. Configure the input for alevinqc_interactive_and_individual_plots.

**ASSISTANT:** You can configure the workflow input using the `baseDir` parameter:

```json
{
  "baseDir": "/data/scrna/simpleaf_output"
}
```
This points the workflow to the directory containing your quantification output files.

---

## [705] source=multitask_sft_big

**USER:** Does the 'Design primers to features (Variant Analysis)' tool offer any automated melting temperature prediction capability?

**ASSISTANT:** Yes. It can optionally predict reference and variant Tm by utilizing the uMelt web service provided by the University of Utah.

---

## [706] source=multitask_sft_big

**USER:** What input parameters does `tidycoverage_aggregated_coverage_profiling` accept according to its definition?

**ASSISTANT:** The workflow accepts two optional list parameters:
1. `tracks`: A list of BigWig files.
2. `features`: A list of genomic features.

---

## [707] source=multitask_sft_big

**USER:** Please set up sictools_indel_difference_detection using sampleA.bam as the first alignment file and sampleB.bam as the second alignment file.

**ASSISTANT:** Parameters extracted successfully for `sictools_indel_difference_detection`:
- `bam1.bam`: sampleA.bam
- `bam2.bam`: sampleB.bam

---

## [708] source=multitask_sft_big

**USER:** In kmernator, how do I configure it so that reads showing at least a partial hit to screen sequences are separated out?

**ASSISTANT:** To separate reads that have at least a partial hit to the screens, specify the `filter-output` option.

---

## [709] source=multitask_sft_big

**USER:** What data input slots are specified for the ExperimentSubset workflow, and are they mandatory?

**ASSISTANT:** The workflow specifies one declared input slot named "count_data" of type "data", which is marked as optional (optional: true).

---

## [710] source=multitask_sft_big

**USER:** What input and output file formats are associated with the screencounter_combinatorial_barcodes workflow?

**ASSISTANT:** The workflow accepts single-end FASTQ reads via the `combo.fq` data input (e.g., `combo.fastq`). Its generated outputs include tabular data (`table/csv`), visual plots (`plot/pdf`), and an R data object (`object/rds`).

---

## [711] source=multitask_sft_big

**USER:** I want to filter my reads with NanoFilt. Please set it to keep reads at least 500 bp long, quality score of at least 10, remove 15 bp from the start of each read, and trim 10 bp from the end.

**ASSISTANT:** Here are the extracted parameters for `NanoFilt` based on your criteria:
- Minimum length (`-l`): `500`
- Minimum quality (`-q`): `10`
- Head crop (`--headcrop`): `15`
- Tail crop (`--tailcrop`): `10`

Command syntax:
`NanoFilt -l 500 -q 10 --headcrop 15 --tailcrop 10`

---

## [712] source=multitask_sft_big

**USER:** Does seq.hotSPOT support custom panels for specific tissues, and what experimental design vignette is listed in its applicability?

**ASSISTANT:** Yes, seq.hotSPOT is designed to build custom panels for any tissue of interest using SNV datasets, and its suitable experimental design includes `hotSPOT-vignette`.

---

## [713] source=multitask_sft_big

**USER:** What hypothesis testing configurations and inputs does the 'T Test for Two Samples' tool accept?

**ASSISTANT:** The tool takes four inputs and allows you to set the alternative hypothesis as either two-sided or one-sided for the non-pooled two-sample t-test.

---

## [714] source=multitask_sft_big

**USER:** Which tools and inputs are specified in the plyranges workflow definition?

**ASSISTANT:** The workflow incorporates the tools `bioconductor/plyranges` and `bioconductor/ggplot2`. It accepts `count_data` through a mandatory input slot named `input_files`.

---

## [715] source=multitask_sft_big

**USER:** I want to extract particles from my cryo-EM micrographs using extract_particles with a box size of 256 pixels and downscale them using Fourier cropping to 128 pixels. What parameters are configured here?

**ASSISTANT:** Based on your request, the parameters configured for `extract_particles` are:
- Box size: 256 pixels
- Fourier cropping: enabled (cropped to 128 pixels)

---

## [716] source=multitask_sft_big

**USER:** Which input files are mandatory to run the quantsmooth workflow?

**ASSISTANT:** The `quantsmooth` workflow requires two data input files:
1. `copy_number_matrix.csv`: A matrix or vector containing copy number values.
2. `probe_positions.csv`: A vector containing the chromosomal positions for the probes.

---

## [717] source=multitask_sft_big

**USER:** I ran DNAclust on my metagenomics data and want to use cutClust to remove singleton clusters. What cut value should I set?

**ASSISTANT:** To remove singletons using `cutClust`, you should set the cutoff value to 2, which cuts off columns from the left to eliminate clusters with fewer than 2 reads.

---

## [718] source=multitask_sft_big

**USER:** What output files or data structures does the `gostag` workflow produce?

**ASSISTANT:** The `gostag` workflow generates three outputs: `de_table`, `enrichment_results`, and `cluster_assignments`.

---

## [719] source=multitask_sft_big

**USER:** For the tool 'Count intervals in one file overlapping intervals in another file', what are the accepted formats for the source and target files?

**ASSISTANT:** The source file must be in BAM or BED format, and the target file must be in BED format.

---

## [720] source=multitask_sft_big

**USER:** Please check the input configuration required for running the progeny workflow.

**ASSISTANT:** For the `progeny` workflow:
- **Input Slot**: `input_files` (representing the `count_data`).
- **Required**: Yes (`optional: false`).
- **Parameters**: None are explicitly required (`parameters: []`).
- **Supported Organisms**: Human and mouse.

---

## [721] source=multitask_sft_big

**USER:** Set up the nonmem_poppk workflow for compound 'DRG-402' administered at 100 mg. We have 50 subjects and 600 observations in 'data/pk_cohort.csv'. We want to include WT and CRCL as covariates, test model_type 'one_compartment', estimation_method 'FOCE-I', and run 500 bootstrap iterations.

**ASSISTANT:** Here are the extracted parameters for the 'drug_discovery/nonmem_poppk' workflow:

- `compound_name`: "DRG-402"
- `dose_mg`: 100
- `n_id`: 50
- `n_obs`: 600
- `pk_data_csv`: "data/pk_cohort.csv"
- `covariate_WT`: true
- `covariate_CRCL`: true
- `model_type`: "one_compartment"
- `estimation_method`: "FOCE-I"
- `n_bootstrap`: 500

---

## [722] source=multitask_sft_big

**USER:** What input data does the gg4way transcriptomics workflow require?

**ASSISTANT:** The gg4way workflow requires a single mandatory input named 'efit' (provided as an RDS file). This must be an MArrayLM object from limma containing differential expression results for multiple contrasts.

---

## [723] source=multitask_sft_big

**USER:** Configure the Cryosparc Standard Spa workflow for movie files in '/data/raw_movies/*.tiff'. The microscope voltage was 300 kV, pixel size is 0.824 A, spherical aberration is 2.7 mm, total dose is 45.0 e-/A2, particle box size is 384, and our complex has C1 symmetry.

**ASSISTANT:** Here are the extracted parameters for **Cryosparc Standard Spa**:

- **movies_path**: `"/data/raw_movies/*.tiff"`
- **voltage**: `300`
- **pixel_size**: `0.824`
- **spherical_aberration**: `2.7`
- **total_dose**: `45.0`
- **particle_box_size**: `384`
- **symmetry**: `"C1"`

---

## [724] source=multitask_sft_big

**USER:** In the Filter (Variant Analysis) tool, what parameter handles filtering variants below a specific quality score, and how does it update the record?

**ASSISTANT:** The relevant setting is the Quality option. When specified, it evaluates the variant quality score for each record; if a score is below the user-defined threshold, it populates the record's FILTER field with `Q[value]`.

---

## [725] source=multitask_sft_big

**USER:** In HyPhy-RELAX, what happens if I omit the optional label for the reference branch set?

**ASSISTANT:** If the optional reference branch set label is not provided in HyPhy-RELAX, all non-test branches are automatically used as the reference.

---

## [726] source=multitask_sft_big

**USER:** In Cluster Picker, what scoring type options are available for calculating genetic distance, and how do they handle gaps?

**ASSISTANT:** Cluster Picker provides several scoring types for genetic distance:
- 'gap': disregards sites containing -, ~, or n.
- 'abs': counts absolute character differences.
- 'valid': only counts differences for sites with standard nucleotides (a, c, t, g) present in both sequences.
- 'ambiguity': disregards sites with ambiguous/gap characters.

---

## [727] source=multitask_sft_big

**USER:** I want to launch nf-core/nanoseq for a multiplexed run. Here is my setup: samplesheet is at 'samples.csv', output should go to './results_nanoseq', barcode kit is 'SQK-NBD114-24', we need barcode trimming with barcoding on both ends, and I want to run on GPU device '0'. Please map these parameters.

**ASSISTANT:** Here are the extracted parameters mapped for nf-core/nanoseq:

- input: "samples.csv"
- outdir: "./results_nanoseq"
- barcode_kit: "SQK-NBD114-24"
- trim_barcodes: true
- barcode_both_ends: true
- gpu_device: "0"

---

## [728] source=multitask_sft_big

**USER:** I am configuring dominosignal and have prepared CellPhoneDB files (complex_input.csv, gene_input.csv, interaction_input.csv, protein_input.csv), SCENIC regulon and AUC matrices (scenic_regulon.csv, scenic_auc.csv), and my SingleCellExperiment object pbmc3k_sce.rds. Can you confirm which Bioconductor/R packages this workflow relies on to generate the output visualizations?

**ASSISTANT:** The workflow relies on the following packages to process the data and generate visualizations:
- `bioconductor/dominosignal`
- `bioconductor/complexheatmap`
- `bioconductor/singlecellexperiment`
- `bioconductor/circlize`
- `bioconductor/knitr`
- `bioconductor/plyr`

---

## [729] source=multitask_sft_big

**USER:** I want to filter my RAD-seq reads more stringently using process_radtags so that any read falling below an average sliding window score of 20 is dropped. How should I specify that?

**ASSISTANT:** You should specify `-s 20`. This overrides the default threshold of 10 and discards any read whose average sliding window quality score drops below 20.

---

## [730] source=multitask_sft_big

**USER:** I need to fetch the crystal structure for hemoglobin with PDB ID 1HHO into my working directory using Get PDB file.

**ASSISTANT:** Here is the parameter extracted for the **Get PDB file** tool:

```json
{
  "accession_code": "1HHO"
}
```

---

## [731] source=multitask_sft_big

**USER:** I am running geNomad on my metagenomic contigs and want to apply stricter filtering to minimize false positive virus and plasmid predictions as much as possible. Which preset should I specify?

**ASSISTANT:** You should specify the `--conservative` preset. This preset applies more aggressive filters to remove potential false positives, resulting in a more restricted and high-confidence set of plasmid and virus predictions.

---

## [732] source=multitask_sft_big

**USER:** Looking at this command error from my clevrvis execution, what parameters were supplied to createSeaObject?
"Error in createSeaObject(fracTable, parents, timepoints, timepointInterpolation = TRUE) : No valid input for fracTable provided."

**ASSISTANT:** Based on the function call, the parameters passed are:
- `fracTable`: fracTable (invalid/empty input)
- `parents`: parents
- `timepoints`: timepoints
- `timepointInterpolation`: TRUE

---

## [733] source=multitask_sft_big

**USER:** I am setting up `make_distance_histograms` for comparing beta diversity across sample groups. What format is required for the user-generated preferences file?

**ASSISTANT:** The user-generated preferences file for `make_distance_histograms` must contain a dictionary defining preferences for the analysis, and this dictionary must include a 'Fields' key that maps to a list of your desired fields (it defaults to ('NO', 'DEFAULT')).

---

## [734] source=multitask_sft_big

**USER:** I have an R data file containing my DNAbin alignment object ('alignment.rds') and an accompanying metadata table ('metadata.tsv'). Which workflow inputs in clstutils_reference_set_creation correspond to these files?

**ASSISTANT:** In `clstutils_reference_set_creation`, 'alignment.rds' maps to the `seqs` parameter (an RDS file containing a DNAbin alignment object), and 'metadata.tsv' maps to the `seqdat` parameter (a table input).

---

## [735] source=multitask_sft_big

**USER:** I am configuring a batch run for grouping reference metabolites using `metaboannotation_create_standard_mixes`. I have prepared `Standard_list_example.txt` containing compound names and chemical formulas. Please extract and format the input configuration.

**ASSISTANT:** Here is the extracted input parameter configuration for `metaboannotation_create_standard_mixes`:

```json
{
  "data_inputs": [
    {
      "name": "Standard_list_example.txt",
      "type": "data",
      "optional": false,
      "read_by_workflow": true,
      "description": "tab-delimited text file containing standard compound names and chemical formulas"
    }
  ]
}
```

---

## [736] source=multitask_sft_big

**USER:** I want to run Seurat FindVariableGenes on my single-cell RNA-seq dataset, but please partition the genes into 30 bins instead of the default.

**ASSISTANT:** Extracted parameter for Seurat `FindVariableGenes`:
- `num.bin`: `30` (default is 20)

---

## [737] source=multitask_sft_big

**USER:** What input files are defined for the workflow bsgenome_constant_width_dict_search, and are they mandatory?

**ASSISTANT:** The workflow defines an optional data input parameter named `ce2dict0.fa`, which is a FASTA file containing query patterns (truncated or prepared for dictionary search). It is marked as optional (`optional: true`).

---

## [738] source=multitask_sft_big

**USER:** What does the mega-reads pass parameter control in MaSuRCA, and what are its available options?

**ASSISTANT:** In MaSuRCA, this parameter controls the number of mega-reads passes during assembly. Setting it to 0 (the default) performs two passes of mega-reads for a slower but higher-quality assembly. Setting it to 1 performs fewer passes to speed up the process.

---

## [739] source=multitask_sft_big

**USER:** I am configuring `nf-core/seqsubmit`. What is the primary input argument used to determine the submission pathway?

**ASSISTANT:** The primary input argument is `mode`. The pipeline supports three submission modes, each routing to a dedicated workflow with its own specific samplesheet structure.

---

## [740] source=multitask_sft_big

**USER:** What input format does RepMatch accept, and how many datasets can it take?

**ASSISTANT:** RepMatch accepts two or more input datasets formatted in GFF (General Feature Format, specifically GFF3).

---

## [741] source=multitask_sft_big

**USER:** Here are my files for differential expression analysis: raw_endo.tsv, pos_controls.tsv, neg_controls.tsv, hk_genes.tsv, and sample_metadata.txt. Please assign them to nanostringdiff_matrix_input_workflow inputs.

**ASSISTANT:** The files map to the inputs of nanostringdiff_matrix_input_workflow as follows:
- endogenous: raw_endo.tsv
- positive: pos_controls.tsv
- negative: neg_controls.tsv
- housekeeping: hk_genes.tsv
- designs: sample_metadata.txt

---

## [742] source=multitask_sft_big

**USER:** Run the tool fetch_supplementary_info_from_doi for the publication with identifier 10.1038/s41586-020-2649-2.

**ASSISTANT:** Extracted parameter:
- DOI: 10.1038/s41586-020-2649-2

---

## [743] source=multitask_sft_big

**USER:** I am configuring SamToFastq to convert a BAM file to FASTQ. Does it default to un-reversing reverse-aligned reads, and what parameter controls that?

**ASSISTANT:** Yes, by default it un-reverses reverse-aligned reads using the parameter mode `RE_REVERSE=True`.

---

## [744] source=multitask_sft_big

**USER:** What input files and formats are required by the r4rna workflow?

**ASSISTANT:** The workflow requires two main inputs: 'predicted_structure.txt' (a predicted RNA structure in helix format) and 'known_structure.dbn' (a known RNA structure in dot-bracket/Vienna format).

---

## [745] source=multitask_sft_big

**USER:** Can you check the parameter specifications for the `Segmented` input in `ace_batch_post_analysis`?

**ASSISTANT:** Based on the workflow definition:
- Name: `Segmented`
- Type: `rds`
- Optional: `false` (mandatory)
- Read by workflow: `true`
- Description: Segmented QDNAseq object, models.tsv (tab-delimited file with sample information).

---

## [746] source=multitask_sft_big

**USER:** I need to run the Ssuis_serotypingPipeline.pl script. What command-line flags and input files are required to construct the execution command?

**ASSISTANT:** The execution syntax for `Ssuis_serotypingPipeline.pl` requires the following flags:
- `--fastq_directory`: Path to the directory containing input FASTQ files.
- `--scoreName`: Prefix or name for the score output.
- `--serotype_db`: Path to the serotype reference database (`serotype.fasta`).
- `--serotype_definitions`: Path to the serotype definitions file (`serotype_definitions.txt`).
- `--cps2K`: Path to the cps2K reference file (`cps2K.fasta`).

Example invocation:
`perl Ssuis_serotypingPipeline.pl --fastq_directory /path/to/fastq/directory --scoreName Scores_output_name --serotype_db serotype.fasta --serotype_definitions serotype_definitions.txt --cps2K cps2K.fasta`

---

## [747] source=multitask_sft_big

**USER:** What inputs and parameters need to be configured for the Topaz Train workflow, and what outputs does it generate?

**ASSISTANT:** Topaz Train accepts the following inputs and settings: `num_training_micrographs`, `expected_particles_per_micrograph`, `train_epochs`, `model_architecture`, and `use_cryosparc`. It outputs a `.pth` model file and a `.json` metadata file using the `TOPAZ_TRAIN` tool.

---

## [748] source=multitask_sft_big

**USER:** I am setting up 'ribotaper part 3: ribosome profiling' and need to configure the read lengths parameter for P-site calculation. How should this be formatted?

**ASSISTANT:** The read lengths parameter must be provided as comma-separated values, such as '26,28,29'. These values are used directly for P-site calculation.

---

## [749] source=multitask_sft_big

**USER:** What input matrices are required by the graphalignment_directed_binary_network_alignment workflow?

**ASSISTANT:** The workflow requires three input matrices: `ex$a` (the adjacency matrix of directed network A), `ex$b` (the adjacency matrix of directed network B), and `ex$r` (the node similarity matrix between network A and network B).

---

## [750] source=multitask_sft_big

**USER:** What files and reports does the nf-core/viralmetagenome pipeline output after processing sequencing reads?

**ASSISTANT:** Based on the pipeline definition, `nf-core/viralmetagenome` generates the following output files:
- `bam`: Aligned read records
- `bai`: Index file for the BAM alignment
- `fasta_assembly`: Assembled consensus genome in FASTA format
- `multiqc_report`: Quality control summary report aggregate

---

## [751] source=multitask_sft_big

**USER:** How does XFDR filter spectrum hits using the minimum delta score threshold?

**ASSISTANT:** XFDR applies a minimum delta score threshold such that hits are rejected if their delta score is greater than or equal to that threshold value.

---

## [752] source=multitask_sft_big

**USER:** Construct a NanoStat command to process 8 threads on a BAM file named 'sample.bam', specifying 1D reads and saving the output to 'stats_dir' with prefix 'sample1'.

**ASSISTANT:** Here is the command using the specified parameters:

`NanoStat -t 8 --bam sample.bam --readtype 1D -o stats_dir -p sample1`

---

## [753] source=multitask_sft_big

**USER:** What input files and output formats are associated with the proteodisco_splice_junctions_workflow?

**ASSISTANT:** The workflow accepts:
- Inputs: `spliceJunctions_pyQUILTS_chr22.bed` (BED file containing splice junctions), `validationSetSJ_hg19.txt` (custom text file containing splice junctions), and an optional data input `TxDb.Hsapiens.UCSC.hg19.knownGene` (transcript annotations).
- Outputs: `table/csv`, `plot/pdf`, and `object/rds`.

---

## [754] source=multitask_sft_big

**USER:** What are the required input files for running the tool `DCS mutations to SSCS stats`?

**ASSISTANT:** The `DCS mutations to SSCS stats` tool requires two main inputs:
1. A VCF file containing DCS (Duplex Consensus Sequence) mutations.
2. A BAM file containing aligned SSCS (Single Strand Consensus Sequence) reads.
Additionally, a user-specified output file path is required to write the results.

---

## [755] source=multitask_sft_big

**USER:** If my input BAM files lack @RG header lines with SM identifiers, how will Samtools mpileup separate the samples across three input BAM files?

**ASSISTANT:** When sample (SM) identifiers are absent in the @RG header lines, Samtools mpileup regards each input file as one individual sample, resulting in three samples corresponding to the three input files.

---

## [756] source=multitask_sft_big

**USER:** Here are my input datasets for our phylogenetics run: tree structure is stored in 'species_tree.nwk', PCA morphospace coordinates in 'coords_2d.csv', and secondary continuous phenotypic measurements in 'leaf_traits.csv'. Please assign these to ggtreespace_annotated_phylomorphospace_heatmap inputs.

**ASSISTANT:** Based on your files, the inputs for `ggtreespace_annotated_phylomorphospace_heatmap` are assigned as follows:
- `tree_file.nwk`: 'species_tree.nwk'
- `trait_coords.csv`: 'coords_2d.csv'
- `additional_traits.csv`: 'leaf_traits.csv'

---

## [757] source=multitask_sft_big

**USER:** Run the membrane permeability prediction for molecules 'CC(=O)NC1=CC=C(O)C=C1' and 'c1ccccc1'. We measured PAMPA permeability at 1.2e-6 cm/s, set the donor pH to 6.5, and we want to include P-gp efflux evaluation.

**ASSISTANT:** Here are the extracted parameters for the Membrane Permeability Prediction workflow:
- smiles_list: ["CC(=O)NC1=CC=C(O)C=C1", "c1ccccc1"]
- measured_PAMPA_cm_s: 1.2e-6
- pH_donor: 6.5
- include_Pgp: true

---

## [758] source=multitask_sft_big

**USER:** Please set up cardinal_unsupervised_analysis_and_segmentation with my dataset located at '/data/imaging/lung_tumor_processed.rds'.

**ASSISTANT:** I have configured the input parameter for `cardinal_unsupervised_analysis_and_segmentation`:

- `processed_msi.rds`: `/data/imaging/lung_tumor_processed.rds` (type: rds, MSImagingExperiment object).

---

## [759] source=multitask_sft_big

**USER:** I want to extract TMB and chromosomal instability using the purecn_biomarker_extraction workflow. What inputs must I prepare?

**ASSISTANT:** You need to provide two mandatory data inputs:
1. `Sample1_PureCN.rds`: A serialized PureCN output object (.rds).
2. `callable_status.bed`: A BED file defining callable regions (for example, output from GATK CallableLoci).

---

## [760] source=multitask_sft_big

**USER:** What input data does the pmp_signal_drift_and_batch_correction workflow require, and is it optional?

**ASSISTANT:** The `pmp_signal_drift_and_batch_correction` workflow requires an input named `MTBLS79`. It is a non-optional matrix input consisting of a SummarizedExperiment object containing the metabolomics peak matrix and sample metadata.

---

## [761] source=multitask_sft_big

**USER:** I need to run dRep compare with a secondary ANI threshold of 0.95, coverage threshold of 0.3, and using the ANImf algorithm. What arguments should I pass?

**ASSISTANT:** Based on the dRep compare command-line parameters, you should set:
- `--S_algorithm ANImf`
- `-sa 0.95`
- `-nc 0.3`

---

## [762] source=multitask_sft_big

**USER:** What output files and categories will I get after executing ggmanh_gds_variant_annotation_plotting on my gwas_alleles.csv file?

**ASSISTANT:** The workflow generates two main outputs: `gwas_summary_statistics` (annotated with gene and consequence information) and `visualizations` (the annotated Manhattan plot).

---

## [763] source=multitask_sft_big

**USER:** What is the default mean pairwise identity percentage that RNAz Select Seqs optimizes alignments for?

**ASSISTANT:** The default value for mean pairwise identity in `RNAz Select Seqs` is 80 percent.

---

## [764] source=multitask_sft_big

**USER:** I have sample IDs in 'samples_list.txt' (no .bam suffix), target intervals in 'exome_targets.bed', aligned reads in a directory called 'alignments/' containing .bam and .bai pairs, and no custom region filter. Map these to the inputs for badregionfinder.

**ASSISTANT:** Here is the mapping of your data to the badregionfinder workflow inputs:
- `SampleNames2.txt`: `samples_list.txt`
- `targetRegions2.bed`: `exome_targets.bed`
- `BAM/BAI files`: `alignments/`
- `regionsOfInterest`: omitted / left empty (this input is optional).

---

## [765] source=multitask_sft_big

**USER:** Run the association study report workflow using the file located at `/results/scfeatures_output_list.rds`.

**ASSISTANT:** Here is the extracted input parameter for `scfeatures_association_study_report`:

- `scfeatures_result.rds`: "/results/scfeatures_output_list.rds" (named list of feature dataframes generated by scFeatures)

---

## [766] source=multitask_sft_big

**USER:** I am configuring aurora_fastqc_site with a custom adapter file. How must the file be structured for the tool to parse it properly?

**ASSISTANT:** The custom adapter file for `aurora_fastqc_site` must meet the following formatting requirements:
- Each entry must contain named adapters formatted as `name[tab]sequence`.
- Any line starting with a hash symbol (`#`) is treated as a comment and ignored.

---

## [767] source=multitask_sft_big

**USER:** In hicDetectLoops, how is the size of the square around a peak calculated from the peakWidth parameter?

**ASSISTANT:** In hicDetectLoops, `peakWidth` defines the width of the peak region in bins. The square surrounding the peak encompasses `(2 * peakWidth)^2` bins.

---

## [768] source=multitask_sft_big

**USER:** I have my ChIP treatment mapped at `data/H3K4me3.sorted.bam` and background control at `data/Input.sorted.bam`. Both are coordinate-sorted and indexed. Map these to the normr workflow inputs.

**ASSISTANT:** The inputs for the `normr` workflow are mapped as follows:
- `ChIP.bam`: `data/H3K4me3.sorted.bam`
- `Control.bam`: `data/Input.sorted.bam`

---

## [769] source=multitask_sft_big

**USER:** Configure the tRNA feature comparison and visualization workflow using my saved object 'experiment_tRNA_grl.rds'.

**ASSISTANT:** Extracted parameter for `trna_feature_comparison_and_visualization`:
- `grl`: 'experiment_tRNA_grl.rds' (type: `rds_granges`, non-optional GRangesList containing tRNA datasets for feature comparison).

---

## [770] source=multitask_sft_big

**USER:** I need to configure `gsalightning_single_gene_testing`. I have my gene expression counts stored in `counts_matrix.csv` (genes across rows, samples across columns) and my phenotypes in `clinical_factors.csv` containing the condition factors. How should these map to the workflow inputs?

**ASSISTANT:** You should map your files to the workflow's input parameters as follows:
- `expression_matrix.csv`: `counts_matrix.csv` (gene expression matrix with genes as rows and samples as columns)
- `sample_metadata.csv`: `clinical_factors.csv` (sample annotations containing group/condition factor)

---

## [771] source=multitask_sft_big

**USER:** In the GWAS evaluation tool, what value should I pass if I want it to compute the r-squared distance?

**ASSISTANT:** You should pass `1`. A value of `1` indicates that the tool will compute the r-squared distance.

---

## [772] source=multitask_sft_big

**USER:** Does the hiAnnotator Nextflow workflow take an input slot called 'input_files', and is it required?

**ASSISTANT:** Yes. The hiAnnotator workflow specifies an input slot named 'input_files' of type data, which is required (optional: false) and read directly by the workflow.

---

## [773] source=multitask_sft_big

**USER:** What input files and output formats are defined for the 'rprimer' workflow?

**ASSISTANT:** The 'rprimer' workflow accepts 'example_alignment.txt', which is a multiple DNA sequence alignment in FASTA format (type: fasta). It generates outputs in 'table/csv', 'plot/pdf', and 'object/rds' formats.

---

## [774] source=multitask_sft_big

**USER:** Here are my input parameters for processing spatial transcriptomics data:
- Directory path: /data/instruments/CosMx_Run1
- Molecule coordinates file: /data/instruments/CosMx_Run1/moleculesDf.csv
How do these map to the moleculeexperiment workflow inputs?

**ASSISTANT:** They map to the 'moleculeexperiment' workflow inputs as follows:
- `repoDir`: "/data/instruments/CosMx_Run1" (the path to the directory containing vendor-specific output files)
- `moleculesDf.csv`: "/data/instruments/CosMx_Run1/moleculesDf.csv" (mandatory data frame input containing molecule coordinates and features)

---

## [775] source=multitask_sft_big

**USER:** I am configuring the 'gviz' workflow. Can you extract the data inputs and software dependencies involved?

**ASSISTANT:** The data inputs for the 'gviz' workflow are:
1. `twoGroups`: Type `rds_granges`, non-optional (GRanges object containing numeric metadata columns).
2. `bgFile.bedGraph`: Type bedGraph (genomic coordinates with a single numeric score column).

The underlying tools/packages used are `bioconductor/gviz`, `bioconductor/genomicfeatures`, `bioconductor/genomicranges`, `bioconductor/biomart`, `bioconductor/ensembldb`, and `bioconductor/knitr`.

---

## [776] source=multitask_sft_big

**USER:** What core criteria or unit must I specify to configure 'Get overlapping reads (RNA)'?

**ASSISTANT:** You must specify the target overlap length in nucleotides (nt) representing the overlap signature of interest, allowing the tool to identify and extract pairable reads into FASTA format.

---

## [777] source=multitask_sft_big

**USER:** What graph export formats are supported by Sbml2Graph beyond the default edge list?

**ASSISTANT:** Beyond the default tabulated edge list, Sbml2Graph supports GML, JsonGraph, and a tabulated node list (formatted as `label node id node type`).

---

## [778] source=multitask_sft_big

**USER:** I want to run Cooler zoomify on my Hi-C contact matrix starting at 1000 bp with binary progression steps. How should I specify the target resolutions parameter?

**ASSISTANT:** You should specify the target resolutions parameter as `1000B`. The suffix `B` indicates a binary progression (geometric steps with a factor of 2), which expands to 1000, 2000, 4000, 8000, and so on.

---

## [779] source=multitask_sft_big

**USER:** What input parameters does the `Dart Toxicity Prediction` workflow take?

**ASSISTANT:** The `Dart Toxicity Prediction` workflow accepts the following inputs:
- `smiles_list`: List of SMILES strings for the small molecules
- `indication_population`: Target population context for the prediction
- `run_placental_transfer`: Option to execute the physicochemical placental transfer model

---

## [780] source=multitask_sft_big

**USER:** In the qsutils_genotyping workflow, what is the 'Unknown' input parameter and is it strictly required?

**ASSISTANT:** In 'qsutils_genotyping', the 'Unknown' input corresponds to 'Unknown-Genotype.fna', which is a FASTA file containing the target haplotype to be genotyped. According to the workflow definition, it is marked as optional (optional: true).

---

## [781] source=multitask_sft_big

**USER:** Using getSequenceInfo tool, please extract all entries matching the keyword 'kinase' into a distinct file.

**ASSISTANT:** Extracted parameter for getSequenceInfo tool:
- keyword: "kinase"

Sequences with descriptions matching 'kinase' will be partitioned and downloaded into a separate file.

---

## [782] source=multitask_sft_big

**USER:** What input data parameters must be specified when setting up the shiny_gosling workflow?

**ASSISTANT:** The `shiny_gosling` workflow requires the non-optional data input parameter `input_files`, which supplies the workflow's input data (count data).

---

## [783] source=multitask_sft_big

**USER:** I am configuring Beacon2 VCF2BFF to generate a genomicVariations dataset. My input VCF was aligned against GRCh38/hg38. Which reference genome option should I set?

**ASSISTANT:** For Beacon2 VCF2BFF, you should specify `hg38` as the reference genome parameter to accurately annotate and generate the genomicVariations dataset (valid examples include hs37, hg37, and hg38).

---

## [784] source=multitask_sft_big

**USER:** How should I format the list of items to export in QCExporter if some of the target names contain whitespace?

**ASSISTANT:** In `QCExporter`, provide a space-separated list of items. In order to allow for spaces in list items, surround each item containing spaces with single quotes. If left empty, metrics from all items will be exported.

---

## [785] source=multitask_sft_big

**USER:** I want to run LASSO to evaluate performance across 5 folds instead of just fitting a single model. What evaluation parameter setting should I use?

**ASSISTANT:** Set the evaluation parameter to `1` to evaluate the tool, and provide `5` to the `folds` argument. Any value other than 1 will produce a fitted model instead of running fold-based evaluation.

---

## [786] source=multitask_sft_big

**USER:** I want to supply my data to the glmgampoi workflow. What is the required input parameter name and file format?

**ASSISTANT:** The required input parameter is `sce`, which must be an `rds_sce` file containing a SingleCellExperiment object with raw single-cell counts and cell-level metadata.

---

## [787] source=multitask_sft_big

**USER:** What input files are required to run the scruff workflow?

**ASSISTANT:** The `scruff` workflow requires the following input files:
- `read1Path.fastq.gz`: Read 1 FASTQ file containing cell barcodes and UMIs
- `read2Path.fastq.gz`: Read 2 FASTQ file containing transcript sequences
- `reference.fa`: Reference genome FASTA file
- `reference.gtf`: Reference annotation GTF file
- `barcode_list.tsv`: Predefined cell barcodes

---

## [788] source=multitask_sft_big

**USER:** Here are my input microscopy files for running the ebimage segmentation pipeline: I've got nuclei.tif containing the DAPI nuclear channel and cells.tif with the cytoplasmic cell body channel.

**ASSISTANT:** Extracted inputs for the `ebimage` workflow:
- `nuclei.tif`: Grayscale fluorescent microscopy image of nuclei
- `cells.tif`: Grayscale fluorescent microscopy image of cell bodies

Both inputs are mapped and ready to be processed by `bioconductor/ebimage` to generate segmented boundary visualizations.

---

## [789] source=multitask_sft_big

**USER:** I need to sort my FASTA file by decreasing sequence length using VSearch sorting, but I want to understand how ties are handled. What parameters control this?

**ASSISTANT:** VSearch sorting uses `--sortbylength` to sort entries by decreasing sequence length. When sequence lengths are tied, VSearch breaks ties by sorting by decreasing abundance first, followed by increasing alpha-numerical order of the sequence label.

---

## [790] source=multitask_sft_big

**USER:** Please assign my files to the 'sampleclassifier' workflow: 'reference_affy_norm.tsv' (normalized reference probe set matrix) and 'cohortB_test_norm.tsv' (normalized query microarray matrix).

**ASSISTANT:** The input mapping for the 'sampleclassifier' workflow is:
- `micro_refmat`: 'reference_affy_norm.tsv'
- `micro_testmat`: 'cohortB_test_norm.tsv'

---

## [791] source=multitask_sft_big

**USER:** What are the required and optional CLI parameters for ExtractClustersFromWardTree?

**ASSISTANT:** The parameters for `ExtractClustersFromWardTree` are:
- `-i`: Filename of the serialized cluster tree (input)
- `-o_out`: Output filename
- `-o_type`: Output type
- `-i_type`: (Optional) Switches between binary (default) and text file for the cluster tree input
- `-min_size`: Cluster size threshold parameter

---

## [792] source=multitask_sft_big

**USER:** How should I structure my input data for `geneselectmmd_data_matrix_workflow`?

**ASSISTANT:** The workflow requires a mandatory input parameter named `mat`, which must be a matrix of gene expression values where the rows correspond to genes and the columns correspond to samples.

---

## [793] source=multitask_sft_big

**USER:** What are the specific data input files defined for the acgh_sproc_import workflow?

**ASSISTANT:** The workflow defines data inputs for 'sproc' (individual Sproc files matching sproc*.txt) and 'human.clones.info.J' (clone information file).

---

## [794] source=multitask_sft_big

**USER:** I am configuring hicstuff full pipeline for a dual-digest experiment using DpnII and HinfI. What should the enzyme parameter string be?

**ASSISTANT:** The parameter value should be: `DpnII,HinfI` (comma-separated enzyme names, as supported by the hicstuff full pipeline).

---

## [795] source=multitask_sft_big

**USER:** What input slots and parameter requirements are declared for the GenomicScores Nextflow workflow?

**ASSISTANT:** The `GenomicScores` workflow declares one data input slot: `count_data` (type: data, which is marked as optional and not directly read by the workflow). There are no additional mandatory workflow-level parameters configured, and it is marked as self-contained.

---

## [796] source=multitask_sft_big

**USER:** Please set up the inputs for the roseq workflow. I have my cell groups saved in 'conditions.csv' and my raw single-cell read counts in 'sc_counts.csv'.

**ASSISTANT:** Here are the mapped inputs for the `roseq` workflow:
- `count_matrix.csv`: `sc_counts.csv`
- `cell_metadata.csv`: `conditions.csv`

---

## [797] source=multitask_sft_big

**USER:** Here are the files I have for transcription start site profiling: `mapcap_test_R1.fastq.gz` (forward multiplexed reads), `mapcap_test_R2.fastq.gz` (reverse multiplexed reads), and `reference_genome.fa` (FASTA reference). How do they map into the `icetea` workflow inputs?

**ASSISTANT:** The files map directly to the inputs of the `icetea` workflow as follows:
- `mapcap_test_R1.fastq.gz`: Forward multiplexed Read 1 FASTQ file
- `mapcap_test_R2.fastq.gz`: Raw multiplexed Read 2 FASTQ file
- `reference_genome.fa`: Reference genome FASTA file for indexing

The workflow utilizes `bioconductor/icetea`, `bioconductor/rsubread`, and `bioconductor/rtracklayer` to produce the `de_table` output.

---

## [798] source=multitask_sft_big

**USER:** Please check what primary omics data formats and study designs the tool 'Subset Wide Data and Design File' accommodates.

**ASSISTANT:** `Subset Wide Data and Design File` is primarily applicable to metabolomics, proteomics, transcriptomics, and any wide-format omics data. It is suitable for multi-group comparative study designs where specific sample groups or subsets need to be extracted.

---

## [799] source=multitask_sft_big

**USER:** What input format does BlastAlign require, and what output formats does it generate?

**ASSISTANT:** BlastAlign requires an input file containing nucleic sequences in FASTA format. It returns multiple alignments in Nexus and Phylip formats.

---

## [800] source=multitask_sft_big

**USER:** I need to run the medips_quality_control_analysis workflow on my human embryonic stem cell MeDIP replicate file located at '/seq/hESCs_rep1_medip.bam'. How should this be specified?

**ASSISTANT:** You can assign your file to the MeDIP BAM parameter as follows:

```json
{
  "bam.file.hESCs.Rep1.MeDIP": "/seq/hESCs_rep1_medip.bam"
}
```

---

## [801] source=multitask_sft_big

**USER:** Here are my files for DEGseq analysis: mapped reads are in 'sample.bed' and the transcript reference coordinates are in 'refFlat.txt'. How do these map to the workflow inputs?

**ASSISTANT:** The workflow inputs map as follows:
- `sample.bed`: 'sample.bed' (mapped reads for the sample)
- `refFlat.txt`: 'refFlat.txt' (gene annotation table)

---

## [802] source=multitask_sft_big

**USER:** Please set up the Assay Ingestion And Ranking workflow with file 'compound_screen.csv', evaluating BCR-ABL1 as potency (weight 0.7) and hERG as safety (weight 0.3), applying a hERG safe threshold of 10.0, and returning the top 50 hits.

**ASSISTANT:** Here are the extracted parameters for the `Assay Ingestion And Ranking` workflow:
- `assay_csv`: "compound_screen.csv"
- `potency_assay`: "BCR-ABL1"
- `safety_assay`: "hERG"
- `potency_weight`: 0.7
- `safety_weight`: 0.3
- `herg_safe_threshold`: 10.0
- `top_n`: 50

---

## [803] source=multitask_sft_big

**USER:** What input channels are required to execute the nf-core/fastq_trim_fastp_fastqc workflow?

**ASSISTANT:** The workflow requires two input channels:
1. 'ch_reads': the raw FASTQ read files.
2. 'ch_adapter_fasta': FASTA file containing adapter sequences for trimming.

---

## [804] source=multitask_sft_big

**USER:** Please set up the hepatic clearance extrapolation workflow for compound SMILES 'CC(=O)Nc1ccc(O)cc1'. The assay was done in human hepatocytes with a measured in vitro Clint of 18.5 uL/min/10^6 cells, fu_plasma of 0.85, fu_inc of 0.90, and we want to apply the well-stirred scaling model.

**ASSISTANT:** Here are the extracted parameters mapped to the 'Ivive Hepatic Clearance' workflow inputs:
- `smiles`: "CC(=O)Nc1ccc(O)cc1"
- `assay_type`: "hepatocyte"
- `clint_in_vitro`: 18.5
- `species`: "human"
- `fu_plasma`: 0.85
- `fu_inc`: 0.90
- `scaling_model`: "well-stirred"

---

## [805] source=multitask_sft_big

**USER:** I have the following files prepared for integration: gut_microbiome_counts.rds (phyloseq object), serum_metabolites.tsv (matrix), and patient_covariates.csv (data frame of metadata). How should these map to combi_constrained_integration inputs?

**ASSISTANT:** Map gut_microbiome_counts.rds to zhangMicrobio, serum_metabolites.tsv to zhangMetabo, and patient_covariates.csv to zhangMetavars.

---

## [806] source=multitask_sft_big

**USER:** Which underlying tools and parameters are utilized by the 'eds' workflow?

**ASSISTANT:** The workflow utilizes the tools `bioconductor/eds` and `bioconductor/tximportdata`. It accepts the data input `input_files` and takes no additional configurable parameters (`parameters: []`).

---

## [807] source=multitask_sft_big

**USER:** I want to run `destiny_gene_relevance` using my processed dataset saved at `data/hvg_sce.rds`. Please set up the input mapping.

**ASSISTANT:** I have mapped your dataset to the workflow's required input parameter:
- `allen_hvg`: `data/hvg_sce.rds` (SingleCellExperiment object, type `rds_sce`).

---

## [808] source=multitask_sft_big

**USER:** I have my pooled single-cell data ready. The raw HTO matrix is in 'hto_raw_counts.tsv' (cells x HTOs) and my vector of detected gene counts per cell is 'cell_gene_counts.rds'. How should these be mapped to the demuxmix inputs?

**ASSISTANT:** Map the inputs as follows:
- 'hto': Provide the matrix of raw HTO counts (HTOs x cells) sourced from 'hto_raw_counts.tsv'.
- 'rna': Provide the vector containing the number of detected genes per droplet sourced from 'cell_gene_counts.rds'.

---

## [809] source=multitask_sft_big

**USER:** I am preparing my metabolomics imaging run on MSI mz images with my Cardinal MSImageSet saved in sample_dataset.RData.

**ASSISTANT:** I have identified your input format and upload type for 'MSI mz images':
- Input format: Cardinal MSImageSet saved as RData
- Upload method: regular upload
- File: sample_dataset.RData

---

## [810] source=multitask_sft_big

**USER:** How do I specify the input tree when running Newick Display, and can it accept input from standard input?

**ASSISTANT:** For `Newick Display`, the input argument is either the path to a file containing one or more Newick trees, or `-` to read the tree directly from standard input (stdin).

---

## [811] source=multitask_sft_big

**USER:** I want to run seqvartools_variant_iteration using our cohort file located at '/data/cohort_variants.gds'. Please set up the input.

**ASSISTANT:** The workflow input parameter is mapped as follows:
- `gdsfile.gds`: "/data/cohort_variants.gds" (SeqArray GDS file containing genomic variants)

---

## [812] source=multitask_sft_big

**USER:** I have my raw UMI counts in a matrix variable called pbmcSmall. If I execute the Dino normalization workflow, what outputs will it produce?

**ASSISTANT:** The `dino_single_cell_experiment_normalization` workflow will consume your `pbmcSmall` raw UMI count matrix and generate three outputs:
1. `singlecellexperiment`
2. `counts_matrix`
3. `normalized_data`

---

## [813] source=multitask_sft_big

**USER:** What input parameters or data inputs are declared for the SNPediaR workflow?

**ASSISTANT:** The workflow declares a single required data input slot named `input_files` (of type `data`), which maps to `count_data` inputs read by the Nextflow workflow. It does not declare additional configurable parameters.

---

## [814] source=multitask_sft_big

**USER:** What data inputs are required by the muscat workflow according to its configuration?

**ASSISTANT:** The muscat workflow requires an input named `input_files` (declared .nf input slot) of type `data`, which is non-optional (`optional: false`) and read by the workflow, taking `count_data`.

---

## [815] source=multitask_sft_big

**USER:** I am preparing my BED file to run Average intervals on some ChIP-seq peak regions. Which column does the tool specifically inspect to find the anchor or alignment point?

**ASSISTANT:** The 'Average intervals' tool expects the alignment point to be specified in column 5 of the input BED file.

---

## [816] source=multitask_sft_big

**USER:** Please set up the ETE taxa DB generator to use my local archive located at /data/reference/taxonomy/taxdump.tar.gz.

**ASSISTANT:** Extracted parameter:
- NCBI taxdump: `/data/reference/taxonomy/taxdump.tar.gz`

---

## [817] source=multitask_sft_big

**USER:** Please search PubMed for articles discussing 'BRAF V600E melanoma resistance mechanisms'.

**ASSISTANT:** I will configure `Query Pubmed` with the search query: 'BRAF V600E melanoma resistance mechanisms'.

---

## [818] source=multitask_sft_big

**USER:** I need to set up the sseq workflow. I have my count matrix stored in 'raw_counts.tsv' and condition labels stored in 'treatment_group_vector'. Which inputs do these correspond to?

**ASSISTANT:** For the sseq workflow, map your data as follows:
- `countsTable`: 'raw_counts.tsv' (matrix or data frame of raw RNA-seq counts)
- `conds.Hammer`: 'treatment_group_vector' (character vector of conditions)

---

## [819] source=multitask_sft_big

**USER:** Please list all valid input parameters accepted by the Antibody Developability (pharmacology/antibody_developability) workflow.

**ASSISTANT:** The Antibody Developability workflow accepts the following inputs: `full_sequence`, `hcdr1`, `hcdr2`, `hcdr3`, `lcdr1`, `lcdr2`, `lcdr3`, `antibody_format`, `target_indication`, and `dose_mg_kg`.

---

## [820] source=multitask_sft_big

**USER:** What are the exact data input requirements for the `dada2` workflow?

**ASSISTANT:** The workflow expects paired-end raw reads:
- `sample_F.fastq.gz (Forward raw reads)` (data input parameter: `forward_reads.fastq.gz`)
- `sample_R.fastq.gz (Reverse raw reads)` (data input parameter: reverse reads)

---

## [821] source=multitask_sft_big

**USER:** I want to train a deep learning classifier based on architecture.json. Please set it up with the Adam optimizer, categorical cross-entropy loss, 100 training epochs, and a batch size of 64.

**ASSISTANT:** Extracted parameters for 'Create deep learning model':
- Estimator type: classifier
- Architecture: architecture.json (from 'Create architecture')
- Optimizer: Adam
- Loss function: categorical cross-entropy
- Number of training epochs: 100
- Batch size: 64

---

## [822] source=multitask_sft_big

**USER:** Configure the index size parameter for `raptor build` so that the resulting index file size is set to 8 gigabytes.

**ASSISTANT:** To set the index size to 8 gigabytes in `raptor build`, specify the size parameter as `8g` (or `8G`). The tool expects an integer followed by a case-insensitive unit suffix [k, m, g, t].

---

## [823] source=multitask_sft_big

**USER:** We want to execute the mitoclone2 cohort shared noise workflow. We have prepared our alignment data in the path '/data/cohort/sample_alignments.bam'. Please configure the input.

**ASSISTANT:** Here is the extracted input configuration for `mitoclone2_cohort_shared_noise_workflow`:
- `cohort_bams`: "/data/cohort/sample_alignments.bam"

---

## [824] source=multitask_sft_big

**USER:** Set up the CryoSPARC Filament Tracer job for intermediate filaments. The filament diameter is 100 Å, helical rise is 4.75 Å, overlap fraction is 0.6, minimum length is 400 Å, and CryoSPARC should be enabled.

**ASSISTANT:** Here are the extracted parameters for the Filament Tracer workflow:
- `filament_diameter_angstroms`: 100
- `helical_rise_angstroms`: 4.75
- `overlap_fraction`: 0.6
- `min_filament_length_angstroms`: 400
- `use_cryosparc`: true

---

## [825] source=multitask_sft_big

**USER:** Can you list the exact outputs produced by the mosdef_report_beautification workflow?

**ASSISTANT:** The mosdef_report_beautification workflow outputs 'de_table' (interactive differential expression tables with links and color coding) and 'visualizations'.

---

## [826] source=multitask_sft_big

**USER:** What are the required input data types and expected primary output files for nf-core/taxprofiler?

**ASSISTANT:** The required inputs are 'fastq' reads and a 'samplesheet'. The primary output files include 'taxonomy_profiles', 'kraken2_report', and 'metaphlan_report'.

---

## [827] source=multitask_sft_big

**USER:** For running the variantfiltering_inheritance_model_analysis pipeline, I have prepared my trio files: 'CEUtrio.vcf.bgz' containing the multisample variants and 'CEUtrio.ped' specifying the family structure. Please extract these data inputs.

**ASSISTANT:** Here are the extracted data input parameters for `variantfiltering_inheritance_model_analysis`:
- `CEUtrio.vcf.bgz`: "CEUtrio.vcf.bgz" (multisample VCF file)
- `CEUtrio.ped`: "CEUtrio.ped" (pedigree file)

---

## [828] source=multitask_sft_big

**USER:** How does hmmfetch expect the input profile names to be provided when querying an HMM database?

**ASSISTANT:** The profile names should be provided in a text file where each name is separated by newlines, alongside the target `<hmmfile>` (such as a large Pfam database).

---

## [829] source=multitask_sft_big

**USER:** What input table is required to run the Check SAM Compare Output tool?

**ASSISTANT:** The tool requires the ASE Totals tables containing read counts that were generated by the 'Compare SAM Files and Create ASE Counts Tables' tool.

---

## [830] source=multitask_sft_big

**USER:** I want to run rawdiag with two Orbitrap files: 'sample_rep1.raw' and 'sample_rep2.raw'. How should these be assigned to the workflow inputs?

**ASSISTANT:** In the rawdiag workflow, your files can be mapped to the data inputs as:
- `file1.raw`: sample_rep1.raw
- `file2.raw`: sample_rep2.raw

Both are Thermo Fisher Scientific raw mass spectrometry files used to generate diagnostic visualizations.

---

## [831] source=multitask_sft_big

**USER:** What specific fields or parameters are required when running VCFflatten on a VCF file?

**ASSISTANT:** VCFflatten requires an allele frequency specification ('AF') and the use of 'G' and 'A' to denote the fields that vary according to Genotype or Allele, respectively.

---

## [832] source=multitask_sft_big

**USER:** I need to upload our consensus genome to ENA via the Webin CLI tool. Center name is 'Sanger Institute', assembly file is 'consensus_seq.fa', gap threshold is 10, and describe it as 'WGS consensus for microbial isolate'.

**ASSISTANT:** Extracted parameters for 'Submit consensus sequence to ENA':
- Center name: Sanger Institute
- Select the consensus sequence assembly file: consensus_seq.fa
- Minimum gap length (optional): 10
- Free text description of the genome assembly (optional): WGS consensus for microbial isolate

---

## [833] source=multitask_sft_big

**USER:** In Column Join, what happens to the output header if the header line parameter is set to 0?

**ASSISTANT:** If this parameter is set to 0, a header line is added automatically where the identifier column is named `#KEY` and the remaining columns are named according to the input dataset names and columns.

---

## [834] source=multitask_sft_big

**USER:** I am configuring BLAT with tileSize 11, but I am halving the stepSize. What should repMatch be adjusted to?

**ASSISTANT:** For `tileSize` 11, the baseline `repMatch` is typically 1024. Because halving `stepSize` requires doubling `repMatch` to compensate, the adjusted `repMatch` is 2048.

---

## [835] source=multitask_sft_big

**USER:** What is the parameter name and type for sequence inputs in `rhinotyper_genotyping_with_in_r_alignment`?

**ASSISTANT:** The sequence input parameter is `user_sequences.fasta`, which is of type `data` (representing unaligned user sequences) and is marked as optional.

---

## [836] source=multitask_sft_big

**USER:** I am running `NSPDK_candidateClusters` on RNA neighborhood graph data. What operational constraints govern how neighborhoods are selected as candidate clusters?

**ASSISTANT:** Neighborhood selection in `NSPDK_candidateClusters` is governed by dense set ranking and an overlap threshold constraint, which filters out candidate clusters whose overlap exceeds the defined threshold.

---

## [837] source=multitask_sft_big

**USER:** I want to preserve INFO annotations when decomposing variants with VcfAllelicPrimitives. Which option controls this, and are there caveats?

**ASSISTANT:** You can use the `--keep-info` flag. However, note that in many cases, such as multisample VCFs, these INFO annotations will not be valid post-decomposition. For biallelic loci in single-sample VCFs, they should still be used with caution.

---

## [838] source=multitask_sft_big

**USER:** Here are my project files for methQTL discovery:
- Genotypes in `/data/cohort_plink/` (has chr1.bed, chr1.bim, chr1.fam)
- RnBeads output directory at `/data/rnbeads_methylation/`
- Metadata sheet `/data/cohort_samples_annot.csv`
How do these map to the `magar` workflow inputs?

**ASSISTANT:** The files map to the `magar` workflow inputs as follows:
- `plink_data`: `/data/cohort_plink/`
- `rnb_set_dir`: `/data/rnbeads_methylation/`
- `sample_annotation.csv`: `/data/cohort_samples_annot.csv`

---

## [839] source=multitask_sft_big

**USER:** Here is my configuration for tracktables: I have a FileSheet matrix mapped with columns SampleName, bigwig, interval, bam, and a SampleSheet data frame containing SampleName, Antibody, and Species metadata. Are all mandatory inputs covered?

**ASSISTANT:** Yes. The `tracktables` workflow requires two mandatory matrix/data-frame inputs: `FileSheet` (which contains "SampleName", "bigwig", "interval", and "bam") and `SampleSheet` (which contains "SampleName" along with metadata like "Antibody" and "Species"). Both required data inputs are fully satisfied.

---

## [840] source=multitask_sft_big

**USER:** What sampling rules does Downsample SAM/BAM follow regarding retention probability and alignment flags?

**ASSISTANT:** Downsample SAM/BAM follows these rules:
- Each read is given a retention probability P.
- Mate-pairs are treated jointly: both are either kept or discarded.
- Reads marked as not primary alignments are entirely discarded.

---

## [841] source=multitask_sft_big

**USER:** I checked the scale independence plot from 'WGCNA: construct network' and determined that my optimal soft threshold power is 9. Please run WGCNA: eigengene visualization with that power.

**ASSISTANT:** Extracted parameter:
- Soft threshold power: 9

I will configure 'WGCNA: eigengene visualization' using a soft threshold power of 9 as derived from your scale independence plot.

---

## [842] source=multitask_sft_big

**USER:** Please configure the Refine shape tool so that all edge lengths are limited to 2.5 mm.

**ASSISTANT:** Extracted parameter for Refine shape:
- Specified edge length: 2.5 mm

This will refine the shape by limiting all edges to this specified length, producing a more detailed geometric result.

---

## [843] source=multitask_sft_big

**USER:** What input format does Dshbio Splitgff3 require to process genomic features?

**ASSISTANT:** Dshbio Splitgff3 requires input in gzipped GFF3 format (`.gff3.gz`).

---

## [844] source=multitask_sft_big

**USER:** Set up epistack_promoter_epigenetics_expression using gene_models.rds for gene annotations, expression_rpkm.rds for expression, promoter_meth.rds for methylation scores, and histone_h3k4me3.rds for ChIP-seq.

**ASSISTANT:** Here are the extracted parameters for the workflow:
- `genes`: gene_models.rds
- `rpkm`: expression_rpkm.rds
- `meth`: promoter_meth.rds
- `H3K4me3`: histone_h3k4me3.rds

---

## [845] source=multitask_sft_big

**USER:** I am configuring `pcdl_get_anndata` for my spatial transcriptomics experiment. What values are accepted by the `scale` parameter?

**ASSISTANT:** The accepted values for the `scale` parameter in `pcdl_get_anndata` are `None`, `maxabs`, `minmax`, and `std`.

---

## [846] source=multitask_sft_big

**USER:** What input slots and software tools are defined in the SpatialExperiment workflow configuration?

**ASSISTANT:** The SpatialExperiment workflow defines one data input slot: 'count_data' (type: data, optional: true, read_by_workflow: false). The tools leveraged in this workflow are 'bioconductor/spatialexperiment' and 'bioconductor/bumpymatrix'.

---

## [847] source=multitask_sft_big

**USER:** If I configure Split Genome with a window size of N bp, how does it partition the genomic regions and what overlap does it apply?

**ASSISTANT:** Split Genome divides input genomic regions into segments of size N bp with an overlap of N/2 bp between consecutive regions.

---

## [848] source=multitask_sft_big

**USER:** I want to use hmmbuild with my alignment file 'input_alignments.aln' to create a profile HMM saved at 'output.hmm'. Which inputs map to which parameters?

**ASSISTANT:** The file 'input_alignments.aln' maps to the '<msafile>' parameter (the input multiple sequence alignment), and 'output.hmm' maps to the '<hmmfile out>' parameter (the output profile HMM destination).

---

## [849] source=multitask_sft_big

**USER:** I have an input file called `example.sff`. What is this file's specification in the `r453plus1toolbox_sff_manipulation` workflow?

**ASSISTANT:** In the `r453plus1toolbox_sff_manipulation` workflow, `example.sff` is the primary input specified as a binary Standard Flowgram Format (SFF) file.

---

## [850] source=multitask_sft_big

**USER:** Here are my run parameters: I have a master table called `tissue_index.csv` listing my tissue state identifiers and paths to their respective QTL summary sheets. Please set up the input mapping for `multistateqtl`.

**ASSISTANT:** I will map your configuration to the `multistateqtl` workflow inputs:
- `input_df`: Set to `tissue_index.csv` (contains state names and corresponding file paths to the summary statistics).
- Expected outputs from this execution will be `gwas_summary_statistics` and `visualizations`.

---

## [851] source=multitask_sft_big

**USER:** I am configuring nf-core/metaboigniter for my metabolomics run. Here are my settings: use raw mzML files from './data/mzml_samples', store the output in './analysis/metabo_out', skip alignment and adduct detection, set polarity to positive, and run MS2Query in offline mode pointing to '/models/ms2query_v1'. Extract the parameters.

**ASSISTANT:** Here are the extracted parameters for `nf-core/metaboigniter`:
- `input`: "./data/mzml_samples"
- `results_dir`: "./analysis/metabo_out"
- `skip_alignment`: true
- `skip_adduct_detection`: true
- `polarity`: "positive"
- `offline_model_ms2query`: true
- `models_dir_ms2query`: "/models/ms2query_v1"

---

## [852] source=multitask_sft_big

**USER:** We digested our proteomics sample using chymotrypsin. How should I set the enzyme parameter in TopPerc?

**ASSISTANT:** In TopPerc, set the enzyme parameter to 'chymotrypsin'.

---

## [853] source=multitask_sft_big

**USER:** What output files will be produced by the proteodisco_manual_transcripts_workflow?

**ASSISTANT:** The workflow produces three outputs: a table in CSV format (`table/csv`), a plot in PDF format (`plot/pdf`), and an R data object (`object/rds`).

---

## [854] source=multitask_sft_big

**USER:** In a pipeline requiring gene quantification from aligned reads and a GTF file, which tool handles feature counting?

**ASSISTANT:** The tool for this task is `Htseq Count`.

---

## [855] source=multitask_sft_big

**USER:** What input datasets are required to execute the `sparsenetgls_ggm_accuracy_assessment` workflow?

**ASSISTANT:** The workflow requires three mandatory matrix inputs:
1. `databand_Y`: matrix of multivariate response variables
2. `databand_X`: matrix of predictor variables
3. `prec`: known true precision matrix

---

## [856] source=multitask_sft_big

**USER:** I want to preserve annotations that appear after spaces in my FASTA headers using FASTA read name affixer. What parameter value should I provide?

**ASSISTANT:** To keep the information following the space(s) in the read name, you must enter a positive integer.

---

## [857] source=multitask_sft_big

**USER:** Please prepare the parameters for the Metabolights downloader to fetch public study MTBLS1234.

**ASSISTANT:** Based on your request, the parameter configuration is:
- Study name: `MTBLS1234`

---

## [858] source=multitask_sft_big

**USER:** I am configuring the Frequency tool for my GWAS/eQTL mapping study using 2cM bins. I want to use sliding intervals of 6-7.9 cM. What value should I select?

**ASSISTANT:** To work with sliding intervals of 6-7.9 cM (with 2cM bins) in the Frequency tool, set the selection parameter to 3.

---

## [859] source=multitask_sft_big

**USER:** I need to run the Validator tool on my QSAR model and I want to set the validation technique to cross-validation. Which flag should I use?

**ASSISTANT:** You should use the `-type` flag to select the validation technique.

---

## [860] source=multitask_sft_big

**USER:** Configure the aizynthfinder_retrosynthesis run with a maximum of 10 routes, search depth limited to 5, minimum passing score of 0.75, and run the real prediction rather than synthetic test data.

**ASSISTANT:** Here are the extracted parameters for `drug_discovery/aizynthfinder_retrosynthesis` based on your criteria:
- `max_routes`: 10
- `max_depth`: 5
- `pass_min_score`: 0.75
- `mock_mode`: false

---

## [861] source=multitask_sft_big

**USER:** What data inputs and Bioconductor tools are configured for the rcellminer workflow?

**ASSISTANT:** The `rcellminer` workflow accepts `count_data` (specified as `input_files`) as a mandatory data input, and utilizes the following tools: `bioconductor/rcellminer`, `bioconductor/knitr`, and `bioconductor/rcellminerdata`.

---

## [862] source=multitask_sft_big

**USER:** Please set up the Virtual Trial Gate3 workflow using spec_file 'trial_spec.json', with analysis 'interaction', running 500 simulations at alpha 0.025, target power 0.85, base seed 101, minimum interaction effect 0.4, outcome type 'continuous', and higher values being better.

**ASSISTANT:** Here are the extracted parameters for `Virtual Trial Gate3`:
- `spec_file`: 'trial_spec.json'
- `analysis`: 'interaction'
- `n_sim`: 500
- `alpha`: 0.025
- `target_power`: 0.85
- `seed_base`: 101
- `min_interaction`: 0.4
- `outcome_type`: 'continuous'
- `higher_is_better`: true

---

## [863] source=multitask_sft_big

**USER:** I want to run the metagene2_metagene_heatmap workflow. My pre-calculated metagene2 object is saved at `results/metagene_obj.rds`. How should this parameter be assigned?

**ASSISTANT:** Assign the dataset to the required input parameter `mg`:
- `mg`: `results/metagene_obj.rds` (type: rds, non-optional pre-calculated metagene2 object).

---

## [864] source=multitask_sft_big

**USER:** In the Chado load gff tool, what parameter helps accelerate the loading process, and what kind of value does it expect?

**ASSISTANT:** The tool accepts a landmark type parameter (e.g., specifying the type of the landmarks such as `contig`). It speeds up the loading process when provided and should be a valid term from the Sequence Ontology.

---

## [865] source=multitask_sft_big

**USER:** I need to run differential expression using the ctrap workflow for the cell line 'HEPG2' targeting the gene 'MYC'. Please configure the inputs.

**ASSISTANT:** Here are the extracted parameters for the `ctrap` workflow:
- `cellLine`: "HEPG2"
- `gene`: "MYC"

Both mandatory inputs are set and ready to download ENCODE RNA-seq data and perform differential expression analysis.

---

## [866] source=multitask_sft_big

**USER:** What input and optional parameters are available for configuring PDBRMSDCalculator?

**ASSISTANT:** PDBRMSDCalculator takes a second input query file (`i_query`) whose type must be specified via `i_type` (which can be a single pdb, a dcd, or a transformation file). It also accepts optional parameters: `-rmsd_type` (specifying the RMSD type) and `-scope` (defining the type of atoms used for scoring a pose).

---

## [867] source=multitask_sft_big

**USER:** In the 'Sink from SBML' tool, what is the default compartment setting for extracting sink molecules?

**ASSISTANT:** In the 'Sink from SBML' tool, the default compartment setting is configured for BiGG models, which is the cytosol.

---

## [868] source=multitask_sft_big

**USER:** I need to run the `haplotypecaller_simple` workflow for sample 'NA12878' using my mapped reads in 'sample.bam' (indexed as 'sample.bam.bai') and the hg38 reference genome 'hg38.fasta'. Please format the inputs required.

**ASSISTANT:** Here are the mapped inputs for `haplotypecaller_simple`:
- `bam`: sample.bam
- `bam_index`: sample.bam.bai
- `reference`: hg38.fasta
- `sample_id`: NA12878

---

## [869] source=multitask_sft_big

**USER:** What rule must be followed when specifying the `output_files` parameter in SpectraSTSearchAdapter?

**ASSISTANT:** When specifying `output_files` in SpectraSTSearchAdapter, you must ensure that exactly one output file is specified for each input file.

---

## [870] source=multitask_sft_big

**USER:** What msconvert command-line arguments are required to prepare RAW files for Walnut DIA mass spectrometry analysis?

**ASSISTANT:** To convert RAW files to mzML for Walnut, you must run:
`msconvert --zlib --64 --mzML --simAsSpectra --filter "peakPicking true 1-" --filter "demultiplex optimization=overlap_only" *.raw`

---

## [871] source=multitask_sft_big

**USER:** Please set up pathview_discrete_data_visualization using my gene hits file '/data/de_genes.txt' and compound hits file '/data/metabolites.tsv'.

**ASSISTANT:** Here is the parameter mapping for `pathview_discrete_data_visualization`:
- `significant_genes.txt`: `/data/de_genes.txt`
- `significant_compounds.txt`: `/data/metabolites.tsv`

Note that both files will be parsed as discrete ID lists for pathway visualization.

---

## [872] source=multitask_sft_big

**USER:** Set up a query in Beacon2 Analyses to locate variant analysis records generated with the BWA-MEM aligner on 2023-10-12 for biosample SAMN04829104.

**ASSISTANT:** Here are the extracted parameters for **Beacon2 Analyses**:
- **aligner**: BWA-MEM
- **analysis date**: 2023-10-12
- **biosample ID**: SAMN04829104

---

## [873] source=multitask_sft_big

**USER:** Here are the files I have for my association analysis: hierarchy_object.rds (our Sincell object with cell-state hierarchy) and c2_pathways.gmt (the pathway gene set list). Can you map these to the inputs for sincell_functional_association_testing?

**ASSISTANT:** Based on the sincell_functional_association_testing specifications, the files map as follows:
- `SO_t72`: hierarchy_object.rds (Sincell object containing a reconstructed hierarchy)
- `geneset.list`: c2_pathways.gmt (list of predefined gene sets)

---

## [874] source=multitask_sft_big

**USER:** I am configuring an automated sequence retrieval job with kfetchbatch. What values are allowed for the output data format?

**ASSISTANT:** For `kfetchbatch`, the supported output data format values are: 'default', 'annot', 'embl', 'emblxml-1.1', 'emblxml-1.2', 'fasta', 'insdxml', 'seqxml', and 'entrysize'.

---

## [875] source=multitask_sft_big

**USER:** I am configuring a phylogenetics run with ConcatPhyl. I need 20 alternative runs on distinct starting trees, bootstrap analysis enabled, and the autoMRE bootstopping criterion.

**ASSISTANT:** Here are the extracted parameters for ConcatPhyl:
- Alternative starting tree runs: `-N 20`
- Bootstrap mode: `-b`
- Bootstopping criterion: `autoMRE`

---

## [876] source=multitask_sft_big

**USER:** Please set up the Target Evidence Positioning workflow for target BRAF in melanoma (EFO:0000756), focusing on the MAPK signaling pathway with small molecule modality.

**ASSISTANT:** Here are the extracted parameters for the `Target Evidence Positioning` workflow:
- `target_name`: "BRAF"
- `disease_name`: "melanoma"
- `efo_id`: "EFO:0000756"
- `pathway`: "MAPK signaling pathway"
- `modality`: "small molecule"

---

## [877] source=multitask_sft_big

**USER:** I want to use UniProt Id Mapping through API. What parameters are required if my input file is a BLAST TSV result versus a protein FASTA file?

**ASSISTANT:** For `UniProt Id Mapping through API`:
- If you provide a BLAST TSV result file, you must specify the `--blast` parameter.
- If you provide a protein FASTA file to be annotated, you must specify the `-db` parameter.

---

## [878] source=multitask_sft_big

**USER:** I want to run hmmsearch with my kinase model file 'kinase.hmm' against the database 'swissprot.fasta'. How should the command arguments be specified?

**ASSISTANT:** Based on the tool's input structure, specify:
- `<hmmfile>`: kinase.hmm
- `<seqdb>`: swissprot.fasta

---

## [879] source=multitask_sft_big

**USER:** What parameter in qiime2 quality-control evaluate-taxonomy controls how deep the taxonomic evaluation goes, and how must taxonomic strings be formatted?

**ASSISTANT:** The taxonomic depth is controlled by the 'depth' parameter, which sets the maximum level evaluated. The tool calculates metrics across semicolon-delimited taxonomic levels.

---

## [880] source=multitask_sft_big

**USER:** In the ipaPy2 gibbs sampler additive tool, how is the number of ignored iterations handled if I leave it as None?

**ASSISTANT:** If the number of iterations to be ignored when computing posterior probabilities is set to None, it defaults to 10% of the total iterations.

---

## [881] source=multitask_sft_big

**USER:** Here is what I have for motif comparison: I have protein FASTA files `motifs_asn.fa` and alignment files in `motifs_dna.txt`, but I do not have a precomputed PWM file `motifs_dna.pwm`. Can I still run `difflogo_multiple_motif_comparison_table`?

**ASSISTANT:** Yes, you can. In the `difflogo_multiple_motif_comparison_table` specification, `motifs_dna.pwm` (a set of multiple PWM files) is marked as optional (`optional: true`), so you can proceed using your primary alignment and FASTA inputs (`motifs_dna.txt` and `motifs_asn.fa`).

---

## [882] source=multitask_sft_big

**USER:** What input datasets are defined for the systemPipeShiny workflow, and is count_data required?

**ASSISTANT:** The workflow defines an input slot named `count_data` (type: data). It is marked as optional (`optional: true`) and is not read by the workflow directly (`read_by_workflow: false`).

---

## [883] source=multitask_sft_big

**USER:** Can you check the parameter configuration for the OLINgui workflow? Are there any optional parameters or flags available?

**ASSISTANT:** According to the OLINgui workflow definition, there are no additional tunable parameters or flags listed; it only defines the mandatory data input 'input_files' (optional: false) read directly by the workflow.

---

## [884] source=multitask_sft_big

**USER:** What tool and outputs are configured for the dominoeffect workflow?

**ASSISTANT:** The dominoeffect workflow utilizes the tool 'bioconductor/dominoeffect' and generates the output dataset 'annotated_genes'.

---

## [885] source=multitask_sft_big

**USER:** What are the required data input parameters for the topconfects_edger_confects workflow?

**ASSISTANT:** The workflow requires two mandatory data inputs:
1. 'y': A list representing a DGEList with normalization factors ('optional: false', 'read_by_workflow: true').
2. 'design': A matrix representing the model matrix.

---

## [886] source=multitask_sft_big

**USER:** I am configuring the multibac workflow. What are the required input matrices and expected outputs?

**ASSISTANT:** The required input matrices are:
- `A.rna`: Matrix of gene expression for batch A
- `B.rna`: Matrix of gene expression for batch B
- `C.rna`: Matrix of gene expression for batch C

The workflow outputs:
- `normalized_data`
- `visualizations`

---

## [887] source=multitask_sft_big

**USER:** How does the 'Enrich dataset with WoRMS' tool know which data points to pull from WoRMS, and how does it query the database?

**ASSISTANT:** The tool uses the **scientific name** of each taxon to access the corresponding entry returned by WoRMS. It then filters by the specific **measurementType(s)** you request and extracts the associated measurement values to enrich your dataset.

---

## [888] source=multitask_sft_big

**USER:** When combining tables using `qiime2 feature-table merge`, what parameter dictates how features shared across tables are resolved?

**ASSISTANT:** The combination behavior for shared features is controlled by the `overlap_method` parameter.

---

## [889] source=multitask_sft_big

**USER:** I have a metabolomics abundance table where rows are samples and columns are metabolite IDs. Can I feed this directly into dimet differential multigroup analysis?

**ASSISTANT:** No. The tool requires the matrix to be organized such that rows correspond to metabolites and columns correspond to samples, with the first column strictly containing unique Metabolite IDs. You must transpose your table and ensure unique IDs in column 1 before running the analysis.

---

## [890] source=multitask_sft_big

**USER:** What are the required inputs and expected outputs for the densvis_density_preserving_umap workflow?

**ASSISTANT:** The required input parameter is 'data', which must be a numeric matrix or data frame of high-dimensional features (such as normalized gene expression values). The workflow outputs 'visualizations'.

---

## [891] source=multitask_sft_big

**USER:** I'm setting up a mirit run. My gene counts are stored in `gene_exp_matrix.tsv`, miRNA counts in `mirna_counts.tsv`, and the sample annotation table is `samples_metadata.csv` (which has primary, mirnaCol, geneCol, and condition columns). Please map these to the workflow inputs.

**ASSISTANT:** Here is the parameter and input mapping for the `mirit` workflow:
- `geneCounts`: `gene_exp_matrix.tsv` (matrix of gene expression counts)
- `mirnaCounts`: `mirna_counts.tsv` (matrix of miRNA expression counts)
- `meta`: `samples_metadata.csv` (data.frame containing sample metadata with `primary`, `mirnaCol`, `geneCol`, and `condition` columns)

---

## [892] source=multitask_sft_big

**USER:** I am configuring RNAinverse for synthetic RNA design. Please extract the search parameter: use -R set to search for exact solutions with value -2.

**ASSISTANT:** Extracted parameter:
- -R: -2

Note: Setting -R to a negative value searches for exact solutions but may cause RNAinverse to not terminate. Consider testing locally or consulting your administrator if runtime limits are exceeded.

---

## [893] source=multitask_sft_big

**USER:** I need to run hmmsearch with my profile file 'kinases.hmm' against 'uniprot_reference.fasta'. How are these positional arguments assigned?

**ASSISTANT:** In hmmsearch, 'kinases.hmm' corresponds to the query `<hmmfile>`, and 'uniprot_reference.fasta' corresponds to the target sequence database `<seqdb>`.

---

## [894] source=multitask_sft_big

**USER:** What input data parameters are declared for the sevenbridges workflow?

**ASSISTANT:** The sevenbridges workflow declares an optional data input named 'count_data' (type: data, optional: true, read_by_workflow: false).

---

## [895] source=multitask_sft_big

**USER:** I want to configure Metabolite - Gene Integration. I have an annotation file `metabolite_annotations.tsv` with metabolite IDs and standard chemical names ready for labeling the results. Please confirm how this input is used.

**ASSISTANT:** Your annotation file `metabolite_annotations.tsv` will be supplied as the metabolite annotation information input. The tool uses these metabolite names and identifiers to label the output files.

---

## [896] source=multitask_sft_big

**USER:** Can I execute the heatplus_legacy_heatmap workflow without providing `exprs_matrix.csv`?

**ASSISTANT:** No, `exprs_matrix.csv` has the property `optional: false`, meaning it is a mandatory input matrix representing features by samples.

---

## [897] source=multitask_sft_big

**USER:** Please set up the speckle workflow using my input file path '/data/sce_processed.rds', which contains the necessary cluster, sample, and group metadata.

**ASSISTANT:** Here is the extracted input mapping for the speckle workflow:

- `sce_all`: "/data/sce_processed.rds" (SingleCellExperiment or Seurat object containing 'cluster', 'sample', and 'group' metadata columns)

---

## [898] source=multitask_sft_big

**USER:** I need to run ProfRep Masker on my draft assembly using repeats.gff. Please preserve the sequence letters by using lowercase masking instead of hard-masking them.

**ASSISTANT:** Based on your request, here are the extracted settings for ProfRep Masker:
- Repeat annotation: repeats.gff
- Masking mode: lowercase (sequence preserved)

---

## [899] source=multitask_sft_big

**USER:** I have a tab-delimited file named 'diff_scores.tsv' where column 1 is 'chrom', column 2 is 'pos', and column 5 contains the population FST values. How should Remarkable Intervals be configured for this file?

**ASSISTANT:** Configure Remarkable Intervals by supplying 'diff_scores.tsv' as your tabular input and setting the column parameters as follows: specify column 1 for the chromosome, column 2 for the position, and column 5 for the score (FST value).

---

## [900] source=multitask_sft_big

**USER:** Please set up dmrcate_sequencing_dmr_analysis with my BSseq RDS file 'wgbs_bsseq_1072.rds', design matrix 'design_matrix.tsv', and comparison contrast matrix 'contrast_matrix.tsv'.

**ASSISTANT:** I have extracted the following inputs for `dmrcate_sequencing_dmr_analysis`:
- `bis_1072`: 'wgbs_bsseq_1072.rds'
- `methdesign`: 'design_matrix.tsv'
- `cont.mat`: 'contrast_matrix.tsv'

---

## [901] source=multitask_sft_big

**USER:** What formats of output files should I expect from the deconvr_atlas_extension_and_signature_generation workflow?

**ASSISTANT:** The workflow generates outputs in three formats: `table/csv`, `plot/pdf`, and `object/rds`.

---

## [902] source=multitask_sft_big

**USER:** What parameters and input data files are used by the r453plus1toolbox_gs_mapper_analysis workflow?

**ASSISTANT:** The workflow uses input files 'mapping/454HCDiffs.txt' (high-confidence differences) and 'mapping/454NewblerMetrics.txt' (mapping metrics). It also accepts an optional data parameter 'dirs', which is a character vector of GS Mapper sample directories containing these files.

---

## [903] source=multitask_sft_big

**USER:** I want to design pegRNAs using crisprseek_prime_editing_pegrna_design. My target sequences are saved in an RDS file located at 'experiment/targets.rds' as a DNAStringSet object. How should I pass this file to the workflow?

**ASSISTANT:** You should supply the file to the `inputFilePath` parameter:
- `inputFilePath`: "experiment/targets.rds"

This parameter is mandatory (`optional: false`) and expects an RDS file containing a DNAStringSet object.

---

## [904] source=multitask_sft_big

**USER:** I am plotting data with csvtk-plot, but my input TSV file contains some illegal rows that cause errors. Which parameter should I adjust?

**ASSISTANT:** You should set the "Illegal Rows" parameter to "Yes" to allow your file to pass through despite the invalid rows.

---

## [905] source=multitask_sft_big

**USER:** I need to run the DistanceMatrix tool in my systems biology analysis, and I have a custom text file 'target_compounds.txt' defining the subset of metabolites to analyze. How is this file handled?

**ASSISTANT:** The file 'target_compounds.txt' will be passed as the optional compound list input to `DistanceMatrix`. The tool will restrict the computation so that only the rows and columns corresponding to the compounds listed in that file appear in the output distance matrix.

---

## [906] source=multitask_sft_big

**USER:** What data inputs are required by the msqrob2 workflow, and what formats do they need to be in?

**ASSISTANT:** The msqrob2 workflow requires two data inputs:
1. `peptides.txt`: A MaxQuant peptide-level intensity table provided in wide format.
2. `experimental_design.csv`: A sample annotation table mapping the quantification columns to their corresponding experimental conditions.

---

## [907] source=multitask_sft_big

**USER:** I am configuring 'DESeq2: Results' and need to evaluate multiple factors from my design formula: 'genotype' and 'treatment'. How should I enter them?

**ASSISTANT:** When specifying multiple factors from the design formula in 'DESeq2: Results', separate them with a comma (,). For example: 'genotype,treatment'.

---

## [908] source=multitask_sft_big

**USER:** Here are the parameters for my target prioritization analysis: I want to test target gene 'BRCA1' across 'breast_cancer' using GWAS terms 'triple-negative breast cancer' and cell types 'luminal_epithelial'. Let's set the minimum GWAS p-value to 5e-8, eQTL tissue to 'Breast_Mammary_Tissue', and pathway to 'DNA_Repair'. Please set up the inputs for Gwas Scrna Eqtl Target Chain.

**ASSISTANT:** Here are the extracted parameters mapped to the `Gwas Scrna Eqtl Target Chain` workflow inputs:
- `target_gene`: "BRCA1"
- `diseases`: "breast_cancer"
- `gwas_trait_terms`: "triple-negative breast cancer"
- `cell_types`: "luminal_epithelial"
- `min_gwas_pvalue`: 5e-8
- `eqtl_tissue`: "Breast_Mammary_Tissue"
- `pathway`: "DNA_Repair"

---

## [909] source=multitask_sft_big

**USER:** What are the mandatory data inputs and outputs for running the complexheatmap_annotations_only workflow?

**ASSISTANT:** The workflow requires one mandatory data input:
- `matrix`: A non-optional numeric matrix used to compute the dendrogram.

It generates two outputs:
- `cluster_assignments`
- `visualizations`

---

## [910] source=multitask_sft_big

**USER:** What outputs does the proteomm workflow produce upon completion?

**ASSISTANT:** The workflow produces two outputs: `de_table` (containing the differential expression analysis results) and `normalized_data` (containing the normalized and imputed peptide data).

---

## [911] source=multitask_sft_big

**USER:** I want to run Image Embedding Extraction on 'archive_cells.zip' using a ViT architecture. Please normalize the final feature vectors, and apply standard resizing transformations beforehand.

**ASSISTANT:** Here are the extracted parameters for Image Embedding Extraction:
- Input images: `archive_cells.zip` (zip file containing images)
- Model selection: ViT architecture
- Normalization option: True / Enabled
- Image transformation type: Standard resizing

---

## [912] source=multitask_sft_big

**USER:** I want to run nf-core/fetchngs to retrieve metadata for GEO samples listed in 'samples.csv' and store the results in './results_fetch', but I only need the run metadata and want to skip downloading the heavy FastQ files. Can you map this to the pipeline parameters?

**ASSISTANT:** Here are the extracted parameters for `nf-core/fetchngs`:
- `input`: 'samples.csv'
- `outdir`: './results_fetch'
- `skip_fastq_download`: true

---

## [913] source=multitask_sft_big

**USER:** In Samtools view (SAM), how can I keep the original read order when converting BAM input to BAM output?

**ASSISTANT:** For BAM input, select 'Same as input' to generate BAM output with the original read order retained.

---

## [914] source=multitask_sft_big

**USER:** Here is what I want to do: stratify my transcriptomics cohort using a 50% median quantile threshold on survival data. How will the kmcut_fixed_or_quantile_cutoff workflow interpret this setup?

**ASSISTANT:** The `kmcut_fixed_or_quantile_cutoff` workflow will use your specified quantile cutoff (e.g., median) to stratify the samples into groups using the survival metrics (`stime`, `scens`) mapped to `sample_id`, calculate the log-rank test p-values, and output the `enrichment_results`.

---

## [915] source=multitask_sft_big

**USER:** In the eximir_limma_integration_normalization workflow, what is the description and requirement for the 'Exiqon' input parameter?

**ASSISTANT:** The 'Exiqon' parameter is a non-optional data input (optional: false) that expects 'Exiqon/Targets.txt (limma targets file)'.

---

## [916] source=multitask_sft_big

**USER:** I'm setting up TransformationEvaluation. If my specified maximum value to transform ends up being equal to or lower than the minimum, what should be done?

**ASSISTANT:** In TransformationEvaluation, if the maximum value to transform is at or below 'min', you must select a suitable maximum value based on the transformation description.

---

## [917] source=multitask_sft_big

**USER:** Does bsgenome_masked_sequence_analysis require a mandatory input for BSgenome.Hsapiens.UCSC.hg38.masked?

**ASSISTANT:** No, the `BSgenome.Hsapiens.UCSC.hg38.masked` parameter is marked as optional (`"optional": true`) and is not read by the workflow (`"read_by_workflow": false`).

---

## [918] source=multitask_sft_big

**USER:** Set up the execution inputs for the matter workflow using my imaging array located at `/data/imaging/raw_data.bin`.

**ASSISTANT:** Here is the parameter and input specification for running the `matter` workflow:

```json
{
  "workflow": "matter",
  "data_inputs": [
    {
      "name": "raw_data.bin",
      "type": "matrix",
      "path": "/data/imaging/raw_data.bin",
      "optional": false,
      "read_by_workflow": true,
      "description": "binary file containing large matrix or array data"
    }
  ]
}
```

---

## [919] source=multitask_sft_big

**USER:** I am preparing to run parglms with my matrix file located at `/workspace/dispersed_counts.matrix`. Please extract the required input configuration.

**ASSISTANT:** The input configuration for `parglms` is:
- `input_files`: `/workspace/dispersed_counts.matrix` (type: `data`, corresponding to the declared Nextflow input slot for count data).

---

## [920] source=multitask_sft_big

**USER:** I am running `sylph profile` on short contigs around 1000 bp. How does `--min-number-kmers` relate to contig length, and what flag should I adjust?

**ASSISTANT:** In `sylph profile`, the minimum number of k-mers required to output a result is approximately the contig length divided by `-c`. While default settings with `--min-number-kmers 10` work for contigs around ~2500 bp, for smaller contigs you should consider adjusting `-c` to 100.

---

## [921] source=multitask_sft_big

**USER:** Here are my files for clustering: the processed object is located at '/data/sample_colorectal.rds' and the raw array data is at '/data/clones.dat'. Map them to the acgh_clustering workflow inputs.

**ASSISTANT:** The files map to the workflow inputs as follows:
- `colorectal.na`: `/data/sample_colorectal.rds` (type: rds)
- `input_files`: `/data/clones.dat` (type: dat)

---

## [922] source=multitask_sft_big

**USER:** What tool and input data does the Path2PPI workflow require?

**ASSISTANT:** The workflow is powered by `bioconductor/path2ppi`. It requires the non-optional data input `input_files` (associated with the `count_data` input type declared in its workflow configuration).

---

## [923] source=multitask_sft_big

**USER:** Please run the nipalsmcia_multi_block_decomposition workflow. My CITE-seq data is in 'pbmc_multimodal.rds' and the cell type annotations are stored in 'cell_metadata.tsv'.

**ASSISTANT:** I have extracted the following parameters for `nipalsmcia_multi_block_decomposition`:
- `obj`: "pbmc_multimodal.rds" (processed Seurat object with RNA and ADT assays)
- `metadata_sc`: "cell_metadata.tsv" (data frame with cell-type annotations and metadata)

All required inputs are identified and ready for execution.

---

## [924] source=multitask_sft_big

**USER:** I am looking at the rblast_create_and_query_custom_db workflow parameters. What is 'RNA_example.fasta' designated for, and is it mandatory?

**ASSISTANT:** In `rblast_create_and_query_custom_db`, 'RNA_example.fasta' serves as reference sequences in FASTA format. It is marked with `"optional": true` and `"read_by_workflow": false`, meaning it is not a mandatory input.

---

## [925] source=multitask_sft_big

**USER:** Configure Seqkit Grep to filter target sequences matching IDs from 'target_ids.txt' out of 'all_reads.fasta'.

**ASSISTANT:** For `Seqkit Grep`, the extracted configuration is:
- **Tool**: Seqkit Grep
- **Pattern/List Source**: `target_ids.txt` (ID/name list)
- **Input Sequence File**: `all_reads.fasta`
- **Operation**: Match/select sequences by name/ID

---

## [926] source=multitask_sft_big

**USER:** Can I supply individual files to make_rarefaction_plots, or must it always be a folder?

**ASSISTANT:** You can do either. `make_rarefaction_plots` accepts the name of the folder containing the rarefaction files, or the user can supply a comma-separated list of individual rarefaction files.

---

## [927] source=multitask_sft_big

**USER:** I want to run rvs_gene_based_partial_sharing. My VCF file is located at `cohort_rare_vars.vcf` and my pedigree R list is saved at `ped_list.rds`. Can you map these to the workflow inputs?

**ASSISTANT:** Here is the parameter mapping for `rvs_gene_based_partial_sharing`:
- `family_variants.vcf`: `cohort_rare_vars.vcf`
- `pedigree_structures.rds`: `ped_list.rds`

The workflow will process these files to generate `burden_test_results`.

---

## [928] source=multitask_sft_big

**USER:** What tool and output formats are produced by the precisetad workflow?

**ASSISTANT:** The workflow wraps 'bioconductor/precisetad' and produces outputs in 'table/csv', 'plot/pdf', and 'object/rds' formats.

---

## [929] source=multitask_sft_big

**USER:** For the `graphalignment` workflow, what represents the node similarity matrix between network A and network B?

**ASSISTANT:** In the `graphalignment` workflow, the node similarity matrix between network A and network B is represented by `ex$r`.

---

## [930] source=multitask_sft_big

**USER:** What input format does make_2d_plots accept for its primary required argument?

**ASSISTANT:** For `make_2d_plots`, the required argument accepts either the direct path to a principal coordinates file (the output from `principal_coordinates.py`) or a path to a directory containing multiple principal coordinates files.

---

## [931] source=multitask_sft_big

**USER:** I want to run StrainDesign analyzing-model to evaluate target production. Here is my setup: model = iML1515, target reaction = EX_succ_e, biomass reaction = BIOMASS_Ec_iML1515_core_75p37M, carbon substrate = EX_glc__D_e, and media = M9 minimal. Please extract the mandatory vs optional parameters.

**ASSISTANT:** Based on StrainDesign analyzing-model specifications:

**Required parameters:**
- `model`: iML1515
- `reaction producing a target`: EX_succ_e
- `biomass reaction`: BIOMASS_Ec_iML1515_core_75p37M

**Optional parameters:**
- `carbon substrate`: EX_glc__D_e
- `media composition`: M9 minimal
*(Note: `an heterologous pathway` was not specified and remains unset)*

---

## [932] source=multitask_sft_big

**USER:** How should the `gene_sets` parameter be structured when using the `intact_gse` workflow?

**ASSISTANT:** The `gene_sets` input for `intact_gse` must be formatted as a named list where each list item is a character vector containing gene IDs corresponding to those in `gene_data`.

---

## [933] source=multitask_sft_big

**USER:** Please set up `mnem_discrete_data_pipeline` using the file `datadisc.csv` from our perturbation screen.

**ASSISTANT:** Extracted parameter configuration:
- `datadisc.csv`: "datadisc.csv" (m x n matrix of binary values 0 and 1)

Please also specify the false positive and false negative error rates required for causal network and subpopulation inference to proceed.

---

## [934] source=multitask_sft_big

**USER:** I want to execute cmscan. I have my query file stored at /data/transcripts.fasta and my covariance model database at /db/Rfam.cm. What are the input parameters?

**ASSISTANT:** Based on the cmscan specification, the parameters are:
- `<seqfile>`: `/data/transcripts.fasta`
- `<cmdb>`: `/db/Rfam.cm`

---

## [935] source=multitask_sft_big

**USER:** Which fixmate option must be used so that Samtools markdup can identify duplicates?

**ASSISTANT:** You must run fixmate with the `-m` option. This option ensures the necessary `MC` and `ms` tags are generated, which Samtools markdup requires to mark duplicates.

---

## [936] source=multitask_sft_big

**USER:** I have my dataset ready: 'pvals_named.rds' contains my named numeric vector of CpG p-values, 'cpg_map.tsv' contains the matrix mapping CpG IDs to gene symbols, and 'pathways.RData' contains the list of custom gene sets. How should these map to methylgsa_custom_annotation_analysis?

**ASSISTANT:** The parameters should be mapped as follows:
- `cpg.pval`: 'pvals_named.rds' (named numeric vector of CpG p-values)
- `CpG2Gene`: 'cpg_map.tsv' (data frame or matrix mapping CpG IDs to gene names)
- `GS.list`: 'pathways.RData' (list of custom gene sets containing gene symbols)

Running this will yield the `enrichment_results` output.

---

## [937] source=multitask_sft_big

**USER:** I want to run `precisetad_cross_cell_type_prediction`. Here are my inputs: I have a trained model named 'CHR22_GM12878_5kb_Peakachu.rds' and BED files 'ctcf.bed', 'rad21.bed', 'smc3.bed', and 'znf143.bed'. Can you map these into the workflow inputs?

**ASSISTANT:** The workflow inputs are mapped as follows:
- Model input: `CHR22_GM12878_5kb_Peakachu.rds` (Pre-trained Random Forest model)
- Transcription factor binding sites: `ctcf.bed`, `rad21.bed`, `smc3.bed`, `znf143.bed` (BED files for the target cell type)

---

## [938] source=multitask_sft_big

**USER:** Here is my setup: I want to test Entrez gene ID 5728 against phenotypes 'HP:0001250' and 'HP:0002808'. I also loaded my mapping tables `g_trait_tbl` and `trait_hpo_tbl`. How should these be passed to the pcan workflow?

**ASSISTANT:** The parameters map to the `pcan` workflow as follows:
- `genId`: 5728
- `hpOfInterest`: ["HP:0001250", "HP:0002808"]
- `geneByTrait`: g_trait_tbl
- `hpByTrait`: trait_hpo_tbl

---

## [939] source=multitask_sft_big

**USER:** I want to run the Exiqon miRNA normalization workflow on my ImaGene raw text files using quantile normalization, my array GAL annotation, and samplesinfo.txt for the Hy3/Hy5 channels. What parameters and inputs are identified?

**ASSISTANT:** Based on your request, the extracted inputs and configuration are:
- **Workflow**: `eximir_exiqon_mirna_normalization`
- **Input Files**:
  - Raw data: ImaGene raw TXT files
  - Array annotation: GAL file
  - Channel mapping: `samplesinfo.txt` (TAB-separated Hy3 and Hy5 designations)
- **Normalization Method**: Quantile normalization (alternative available: spike-in normalization)
- **Expected Output**: `normalized_data`

---

## [940] source=multitask_sft_big

**USER:** I'm setting up a Golden Gate assembly run with 5 inserts into my target backbone vector. What input parameter needs to be passed to Biomni's Get Golden Gate Assembly Protocol?

**ASSISTANT:** From your request, the extracted parameter is the number of inserts: 5. The 'Get Golden Gate Assembly Protocol' tool uses this value to generate the appropriate customized assembly protocol.

---

## [941] source=multitask_sft_big

**USER:** I am configuring EstimateLibraryComplexity. What is the default length of the initial prefix used when sorting and comparing reads?

**ASSISTANT:** The default prefix length is 5 bases (N = 5).

---

## [942] source=multitask_sft_big

**USER:** What is the default value for the SORT_ORDER parameter in SortSam, and what happens if I change it to Queryname in Galaxy?

**ASSISTANT:** The default value for `SORT_ORDER` is `coordinate`. If you select `Queryname`, SortSam will output a SAM file instead of a BAM file, because Galaxy does not support BAM files that are not coordinate sorted.

---

## [943] source=multitask_sft_big

**USER:** Here is my command-line specification request: 'Run bedtools shuffle on my ChIP peaks file peaks.bed using the human chromosome sizes reference hg38.sizes'. Can you identify the input feature file and genome definition file?

**ASSISTANT:** From your request:
- Feature file: `peaks.bed`
- Genome definition file: `hg38.sizes`

---

## [944] source=multitask_sft_big

**USER:** Which QIIME parallel script does poller_example reference?

**ASSISTANT:** It references the full path to `qiime/parallel/poller.py`.

---

## [945] source=multitask_sft_big

**USER:** I want to run reference-free deconvolution using TOAST on my bulk expression matrix stored in 'bulk_expression_matrix.csv', assuming there are 5 distinct cell populations in the mixture.

**ASSISTANT:** Here are the extracted parameters for `toast_reference_free_deconvolution`:
- `Y_raw`: 'bulk_expression_matrix.csv' (matrix of bulk high-throughput data)
- `K`: 5 (integer, number of cell types)

---

## [946] source=multitask_sft_big

**USER:** Please set up linnorm using my raw expression dataset saved in the matrix variable Islam2011.

**ASSISTANT:** The input parameter has been extracted for the `linnorm` workflow:

- `Islam2011`: `Islam2011` (matrix of raw count/expression values with samples in columns and genes in rows).

---

## [947] source=multitask_sft_big

**USER:** In PAPAA: PanCancer within disease analysis, how should I specify the cancer types, and what happens if I omit that parameter?

**ASSISTANT:** Disease types should be provided as a comma-separated string of TCGA disease acronyms. If no arguments are passed, the tool defaults to the filtering options specified in --filter_count and --filter_prop.

---

## [948] source=multitask_sft_big

**USER:** In the Hierarchical clustering tool, I want to use only the top 250 elements based on variance instead of running all features. How should this parameter be configured?

**ASSISTANT:** Set the parameter for the number of top elements to use for clustering to '250'. The tool will select these top 250 elements by highest row variance. (If left as NULL, all elements would be used).

---

## [949] source=multitask_sft_big

**USER:** I want to run a protein search using phmmer with my query fasta file `query_proteins.faa` against the database `uniprot_ref.faa`. How are these positional arguments structured?

**ASSISTANT:** The core positional syntax for phmmer requires the query sequence file followed by the target sequence database:

```bash
phmmer query_proteins.faa uniprot_ref.faa
```

Here, `<seqfile>` is `query_proteins.faa` and `<seqdb>` is `uniprot_ref.faa`.

---

## [950] source=multitask_sft_big

**USER:** Here is my target requirement: 'Design a CAR against CLDN18.2 using CD28 hinge/TM and CD28 costimulatory domain.' Which parameters and components are identified for the cart_construct_design workflow?

**ASSISTANT:** The extracted parameters and structural components are:
- **Antigen target:** CLDN18.2 (selected from the 20-target library)
- **scFv architecture:** VH-(G4S)3-VL orientation targeting CLDN18.2
- **Hinge & Transmembrane domain:** CD28
- **Costimulatory domain:** CD28
- **Signaling domain:** CD3zeta
- **Overall construct architecture:** Signal peptide -> scFv -> CD28 hinge/TM -> CD28 costimulatory -> CD3zeta.

---

## [951] source=multitask_sft_big

**USER:** I want to calculate both gene length and GC content using 'Gene length and GC content'. What files do I need to supply?

**ASSISTANT:** You must provide a GTF file containing the gene annotations. Because you are calculating GC content, you also need to provide a genome FASTA file matching the exact genome version of the GTF file.

---

## [952] source=multitask_sft_big

**USER:** I want to run the flowchic workflow. What inputs are accepted, and which ones are mandatory?

**ASSISTANT:** The flowchic workflow accepts the following inputs:
- `files` (mandatory): a list of FCS files.
- `abiotic_incol` (optional): a data frame of abiotic parameters.

---

## [953] source=multitask_sft_big

**USER:** How does Samtools flag_filter filter SAM alignment records, and what parameters does it expose for this?

**ASSISTANT:** Samtools flag_filter uses the samtools view method and filters alignments using the `-f` parameter (to retain alignments matching specific flag bits) and the `-F` parameter (to exclude alignments matching specific flag bits).

---

## [954] source=multitask_sft_big

**USER:** Run SeqKit locate to find plain motif sequence ACTGN in my genome file.

**ASSISTANT:** Extracted parameter for SeqKit locate:
- Pattern type: Plain sequence
- Motif sequence: 'ACTGN'

---

## [955] source=multitask_sft_big

**USER:** What are the configuration properties of the input HEK293_ingolia.ribo in the ribor_translational_efficiency workflow?

**ASSISTANT:** In the ribor_translational_efficiency workflow, HEK293_ingolia.ribo has the following properties: type is 'data', optional is true, read_by_workflow is false, and it is described as a .ribo file containing ribosome profiling data.

---

## [956] source=multitask_sft_big

**USER:** In Scanpy Inspect and manipulate, I want to calculate cumulative proportions for the top 20, 50, and 100 most expressed genes. How should I format this value?

**ASSISTANT:** You should format the parameter as a comma-separated string of 1-indexed integers: '20,50,100'. This will compute the cumulative proportion of counts up to the 20th, 50th, and 100th most expressed genes.

---

## [957] source=multitask_sft_big

**USER:** Please run the ClinVar benchmarking workflow for AlphaMissense on human p53 with UniProt ID P04637.

**ASSISTANT:** I have extracted the required input parameter for the `alphamissenser_clinvar_benchmarking` workflow:
- `uniprotId`: "P04637"

---

## [958] source=multitask_sft_big

**USER:** What msconvert command and parameter options are required to convert RAW files to mzML for EncyclopeDIA?

**ASSISTANT:** EncyclopeDIA requires the following msconvert command line:
`msconvert --zlib --64 --mzML --simAsSpectra --filter "peakPicking true 1-" --filter "demultiplex optimization=overlap_only" *.raw`

---

## [959] source=multitask_sft_big

**USER:** In rcx-tk, what primary option must I select, and how does it impact the analysis configuration?

**ASSISTANT:** In rcx-tk, you must select whether to process a 'metadata file' or an 'alkane file'. This primary choice determines the required column arrangement and validation steps applied to the file.

---

## [960] source=multitask_sft_big

**USER:** I am configuring the input slot for spatialdecon. What parameter name, file type, and expected contents should be defined?

**ASSISTANT:** The input parameter name is `nsclc`, the required file type is `rds`, and it must contain a `NanoStringGeoMxSet` object with normalized and raw expression data, feature data, and phenotypic data.

---

## [961] source=multitask_sft_big

**USER:** I want to run GAMMA with a 95% nucleotide identity threshold for the Blat search. How should I provide this parameter?

**ASSISTANT:** In GAMMA, you specify the minimum nucleotide sequence identity percentage for the Blat search as an integer using the `-i` parameter, so you should pass `-i 95`.

---

## [962] source=multitask_sft_big

**USER:** I am configuring 'Chado load GO annotation' to import functional annotations. I have query entities specified as 'protein_coding_gene' and 'custom_locus'. Will these work for the feature type parameter?

**ASSISTANT:** The feature type parameter for 'Chado load GO annotation' must be a valid Sequence Ontology (SO) term (such as 'gene', 'mRNA', 'polypeptide', or 'contig'). While 'gene' is a standard Sequence Ontology term, non-standard terms like 'custom_locus' or informal labels will fail validation if they are not recognised SO terms.

---

## [963] source=multitask_sft_big

**USER:** Please set up our Phase II to III enrichment analysis with Phase II records in clinical_cohort.json, tracking an overall survival response_type, an alpha threshold of 0.05, target Phase III power of 0.90, and Phase III alpha of 0.025.

**ASSISTANT:** Here are the extracted parameters for the workflow:
- `patient_data_json`: "clinical_cohort.json"
- `response_type`: "overall survival"
- `alpha`: 0.05
- `phase3_power`: 0.90
- `phase3_alpha`: 0.025

---

## [964] source=multitask_sft_big

**USER:** Extract the input parameters for the P0 Mrna Validation workflow based on the following request: 'Validate mRNA design using GenBank accession MN908947.3 spanning coordinates 21563 to 25384, setting CAI cutoff to 0.8 and minimum free energy threshold to -250 kcal/mol.'

**ASSISTANT:** Extracted parameters for the P0 Mrna Validation workflow:
- genbank_id: "MN908947.3"
- orf_start: 21563
- orf_end: 25384
- cai_threshold: 0.8
- mfe_threshold: -250

---

## [965] source=multitask_sft_big

**USER:** Set up WGSCoveragePlotter for chr19 using aligned reads `/data/sample1.bam`, reference contig file `/data/chr19.fa`, and make sure it outputs a vector graphic.

**ASSISTANT:** Here are the extracted parameters for BAM Coverage Plotter (WGSCoveragePlotter):
- BAM file: `/data/sample1.bam`
- Genomic contig FASTA: `/data/chr19.fa`
- Output format: SVG (vector graphic)

---

## [966] source=multitask_sft_big

**USER:** Please set up the scrapper_batch_blocked_analysis workflow. I have my batch 1 object in 'batch1_cells.rds' and batch 2 in 'batch2_cells.rds'.

**ASSISTANT:** Here are the extracted input parameters for `scrapper_batch_blocked_analysis`:
- `sce.t`: "batch1_cells.rds"
- `sce.z`: "batch2_cells.rds"

---

## [967] source=multitask_sft_big

**USER:** What are the declared input data slots and parameters for the ReportingTools workflow?

**ASSISTANT:** The workflow declares one optional data input: `count_data` (type: `data`, optional: `true`, `read_by_workflow`: `false`). It has no configurable workflow parameters (`parameters: []`) and produces no declared workflow outputs (`out: []`).

---

## [968] source=multitask_sft_big

**USER:** What input data is required to run rjmcmcnucleosomes_chromosomal_nucleosome_positioning, and is it optional?

**ASSISTANT:** The workflow requires the non-optional data input `syntheticNucleosomeReads` (specifically `syntheticNucleosomeReads$dataIP`), which is a data frame containing chromosome, start, end, and strand information of aligned short reads.

---

## [969] source=multitask_sft_big

**USER:** I am replotting my ChIP-seq ngsplot profile curves and want to add semi-transparent shading underneath each curve. What value should I provide?

**ASSISTANT:** For semi-transparent shading under each curve in `replot`, provide a value between 0 and 0.5. A value of 0 applies no shading.

---

## [970] source=multitask_sft_big

**USER:** I need to feed my file 'sample_bands.bed' into chromdraw_bed_file_karyotype. What is the expected input parameter definition?

**ASSISTANT:** The workflow accepts the primary input under the data parameter `bed.bed` (or `bed_file.bed`), which expects a BED file containing at least the first nine fields per record.

---

## [971] source=multitask_sft_big

**USER:** Set up consensusSeekeR to identify consensus regions with an analyzed region size of 300 bp, requiring a feature to be present in at least 4 experiments.

**ASSISTANT:** Extracted parameters for consensusSeekeR:
- Analyzed region size: 300 bp
- Minimum number of experiments/experiences with feature present: 4

---

## [972] source=multitask_sft_big

**USER:** Please set up the GRB detection tool for the interval from T1=120.5 to T2=450.0. I want the background calculated using a background_age of 60 seconds and a minimal S/N ratio threshold of 4.5.

**ASSISTANT:** I have extracted the following parameters for the GRB detection tool:
- T1: 120.5
- T2: 450.0
- background_age: 60
- minimal S/N ratio: 4.5

---

## [973] source=multitask_sft_big

**USER:** Which parameters control the gene filtering step in `sc3_prepare` that caused all genes to be dropped in `sc3_hybrid_svm_clustering`?

**ASSISTANT:** The relevant parameters mentioned in the call are `gene_filter` (which can be set to `FALSE` to disable filtering), `pct_dropout_min`, and `pct_dropout_max`.

---

## [974] source=multitask_sft_big

**USER:** I have prepared my reference genome as a Seqinfo object (`hg38_seqinfo.rds`), a focal peak set as a GRanges object (`h3k27ac_peaks.rds`), and a list of target transcription factor binding sites (`tf_list_granges.rds`). How do these map to `regionereloaded_multi_local_zscore`?

**ASSISTANT:** Here is the parameter mapping for `regionereloaded_multi_local_zscore`:
- `A`: `h3k27ac_peaks.rds` (single genomic region set as a GRanges object)
- `Blist`: `tf_list_granges.rds` (list of genomic region sets as GRanges objects)
- `genome`: `hg38_seqinfo.rds` (reference genome Seqinfo object)

The workflow will process these inputs and generate output `visualizations`.

---

## [975] source=multitask_sft_big

**USER:** What are the declared input data parameters for the GeDi Nextflow pipeline?

**ASSISTANT:** The GeDi pipeline requires a single non-optional data input parameter named 'input_files' (read by the workflow as count_data). It does not declare any additional workflow parameters.

---

## [976] source=multitask_sft_big

**USER:** Which option should I provide to 'Interproscan functional predictions of ORFs' if I want to include pathway information mapped from curated InterPro entries?

**ASSISTANT:** You should use the `--pathways` option.

---

## [977] source=multitask_sft_big

**USER:** I want to run treekor. Here is my setup: I have an expression matrix with cells in rows and markers in columns, cell cluster labels, sample IDs for each cell, and patient clinical response classes. Which workflow parameters do these correspond to?

**ASSISTANT:** These map directly to the required `treekor` inputs:
- `exprs`: Matrix of single-cell marker expressions (cells as rows, markers as columns)
- `clusters`: Vector of cell cluster/type assignments
- `classes`: Vector of patient clinical outcomes/classes per cell
- `samples`: Vector of patient/sample IDs per cell

---

## [978] source=multitask_sft_big

**USER:** How does the 'Number of classes' parameter work in the 'Run IDW interpolation' tool?

**ASSISTANT:** In 'Run IDW interpolation', not all values for 'Number of classes' are strictly possible. The underlying library (tmap) attempts to generate a number of classes that is as close to your specified value as possible.

---

## [979] source=multitask_sft_big

**USER:** What specific column fields must be present in the OpenLabCDS Internal Standard Report rows for the OpenLabCDS to CSV converter?

**ASSISTANT:** The expected columns in the OpenLabCDS Internal Standard Report row format are: RetTime, Type, ISTD, Area, Amt/Area, Amount, Grp, and Name.

---

## [980] source=multitask_sft_big

**USER:** In the virtual_patient_cohort workflow, how is body weight integrated into the pharmacokinetic clearance and volume parameters?

**ASSISTANT:** In the `virtual_patient_cohort` workflow, allometric body weight scaling is implemented using a 70 kg reference: clearance (CL) scales as `(BWt/70)^0.75` and volume of distribution (Vd) scales as `(BWt/70)^1.0`.

---

## [981] source=multitask_sft_big

**USER:** I have the following files prepared for deeptarget: 'secondary_prism.csv', 'avana_CRISPR.csv', 'mutations_mat.csv', 'expression_20Q4.csv', and 'DrugMetadata.csv'. Can you extract the data input mapping for this workflow?

**ASSISTANT:** Here is the extracted data input configuration for deeptarget:
- secondary_prism.csv: matrix of drug response scores (drug IDs as rows, cell lines as columns; required)
- avana_CRISPR.csv: matrix of CRISPR gene effect scores (gene names as rows, cell lines as columns; required)
- mutations_mat.csv: binary matrix of mutation status (gene names as rows, cell lines as columns; required)
- expression_20Q4.csv: matrix of gene expression values (gene names as rows, cell lines as columns; required)
- DrugMetadata.csv: table of drug names and Broad IDs (required)
All five files are mandatory inputs read by the workflow to generate target visualizations.

---

## [982] source=multitask_sft_big

**USER:** Please set up the Transcriptformer Cell State pipeline for human cells using expression matrix 'expr_matrix.h5ad'. Provide a cell type hint of 'CD8 T cell', request the top 5 types, and test against drug 'imatinib' under condition 'treated'.

**ASSISTANT:** Here are the extracted parameters for the transcriptformer_cell_state workflow:
- gene_expression: expr_matrix.h5ad
- species: human
- cell_type_hint: CD8 T cell
- top_k_types: 5
- drug_name: imatinib
- condition: treated

---

## [983] source=multitask_sft_big

**USER:** Here are my files: annotations in 'gencode_v38.sqlite' and genomic features in a list containing 'm6A_peaks.bed'. How should these be assigned to the guitar_custom_guitar_coordinates_and_sampling workflow parameters?

**ASSISTANT:** The parameters should be assigned as follows:
- `txdb_file`: "gencode_v38.sqlite" (SQLite file containing TxDb transcript annotations)
- `stBedFiles`: ["m6A_peaks.bed"] (list of BED files containing genomic features)

---

## [984] source=multitask_sft_big

**USER:** I am setting up knowyourcg_feature_aggregation_and_annotation. I have my beta values in 'sample_betas.tsv' (probes as rows, samples as columns) and my probe ID list in 'probes_query.txt'. How should these be passed?

**ASSISTANT:** Your inputs map to the workflow's data inputs as follows:
- `betas`: 'sample_betas.tsv' (numeric matrix of beta values with probes as rows and samples as columns)
- `query`: 'probes_query.txt' (character vector of probe IDs to annotate)

---

## [985] source=multitask_sft_big

**USER:** Here are the files I have prepared for my gsreg analysis: an expression matrix with gene names and no NAs (`exprsdata.csv`), a pathway list object (`diracpathways.rds`), and sample phenotype labels (`phenotypes.csv`). What outputs will this generate?

**ASSISTANT:** The `gsreg` workflow will process your inputs (`exprsdata.csv`, `diracpathways.rds`, and `phenotypes.csv`) and generate three types of output files:
- Tabular results (`table/csv`)
- Visual plots (`plot/pdf`)
- Saved R data objects (`object/rds`)

---

## [986] source=multitask_sft_big

**USER:** What input data objects and files are required to run the gmapr workflow?

**ASSISTANT:** The required data inputs for `gmapr` are:
1. `p53Seq`: a DNAStringSet of the genome sequence.
2. `fastqs["H1993.first"]`: a FASTQ file containing the forward reads.
3. `fastqs["H1993.last"]`: a FASTQ file containing the reverse reads.

---

## [987] source=multitask_sft_big

**USER:** I need to configure `Make taxonomic coverage template` with multiple taxonomic authorities. How should I specify them?

**ASSISTANT:** When selecting multiple taxonomic authorities in `Make taxonomic coverage template`, you should select them in order of decreasing preference.

---

## [988] source=multitask_sft_big

**USER:** What required input file must I provide to run the `brain_heuristic_isotopic_distribution` workflow, and what output formats will it return?

**ASSISTANT:** The workflow requires `large_molecule_composition.txt` (a non-optional list of the biomolecule's atomic composition). It outputs results in three formats: `table/csv`, `plot/pdf`, and `object/rds`.

---

## [989] source=multitask_sft_big

**USER:** Please analyze my dataset using cellid_functional_annotation. My counts are stored in 'raw_counts.rds', cell annotations are in 'cell_meta.rds', and MSigDB gene sets are in 'h_hallmarks.rds'.

**ASSISTANT:** The input parameters for the `cellid_functional_annotation` workflow have been extracted:
- `expression_matrix.rds`: "raw_counts.rds"
- `metadata.rds`: "cell_meta.rds"
- `pathway_genesets.rds`: "h_hallmarks.rds"

---

## [990] source=multitask_sft_big

**USER:** Configure nanostringnctools with raw counts at '/data/sample1.rcc', probe definition at '/data/panel.rlf', and phenotypic metadata at '/data/meta.csv'.

**ASSISTANT:** Extracted workflow parameters:
- `rcc_files`: '/data/sample1.rcc'
- `rlf_file`: '/data/panel.rlf'
- `sample_annotation`: '/data/meta.csv'

---

## [991] source=multitask_sft_big

**USER:** I want to estimate power using TCGA RNA-seq reference data. What is the mandatory data input required by the rnaseqsamplesize_reference_distribution_estimation workflow?

**ASSISTANT:** The workflow requires the `TCGA` parameter (non-optional data input), which is a string specifying the TCGA dataset name along with the associated user parameters.

---

## [992] source=multitask_sft_big

**USER:** What are the primary input parameters and expected output files for the peca workflow?

**ASSISTANT:** The primary input parameter is 'peptides.tsv' (a non-optional tab-separated text file of peptide-level intensities with protein IDs in column 1). The expected output from the workflow is 'de_table', which contains the differential expression results.

---

## [993] source=multitask_sft_big

**USER:** I provided 'SwissProt.fasta' as the database file name in OMSSAAdapter. Will OMSSAAdapter fail because it lacks the '.psq' extension?

**ASSISTANT:** No, it will not fail. In OMSSAAdapter, if the database filename does not end in '.psq' (such as 'SwissProt.fasta'), the '.psq' suffix will be appended automatically.

---

## [994] source=multitask_sft_big

**USER:** I need to calculate the correlation between Length and GC Content in my tabular genomics data using csvtk-correlation. How should I specify the column parameter?

**ASSISTANT:** Specify the columns as the exact spelling of the two column names separated by a comma: 'Length,GC Content'.

---

## [995] source=multitask_sft_big

**USER:** What is the mandatory count input for the dropletutils_detect_empty_droplets workflow?

**ASSISTANT:** The mandatory input is 'my.counts', which must be provided as a matrix containing the raw UMI counts across all barcodes.

---

## [996] source=multitask_sft_big

**USER:** I am configuring the `awfisher_biomarker_categorization_and_pattern_detection` workflow. What structure should I pass for the `studies` input?

**ASSISTANT:** The `studies` parameter must be provided as a list of lists. Each sublist corresponds to an individual study and must contain two keys:
- `'data'`: the expression matrix for that study.
- `'label'`: a binary group indicator vector corresponding to the samples in that matrix.

---

## [997] source=multitask_sft_big

**USER:** Which input files are listed as mandatory data inputs for the ballgown_transcript_clustering_and_analysis workflow?

**ASSISTANT:** The workflow specifies `e_data.ctab` (exon expression) and `i_data.ctab` as required (non-optional) data inputs read by the workflow.

---

## [998] source=multitask_sft_big

**USER:** Here are my study requirements for HPA histology analysis: genes are TP53, BRCA1; tissues are breast, ovary; cancers are breast cancer, ovarian cancer. Please map these to the hpaanalyze workflow inputs.

**ASSISTANT:** Here is the parameter mapping for the `hpaanalyze` workflow:
- `geneList`: ["TP53", "BRCA1"]
- `tissueList`: ["breast", "ovary"]
- `cancerList`: ["breast cancer", "ovarian cancer"]

---

## [999] source=multitask_sft_big

**USER:** Please set up the pharmacophore filtering run using reference actives in 'actives.smi' and screening library 'zinc_subset.smi'. Ensure 3D generation is enabled and set the minimum features to 4.

**ASSISTANT:** I have extracted the following parameters for the Pharmacophore Filtering workflow:
- `reference_actives`: "actives.smi"
- `compound_library`: "zinc_subset.smi"
- `generate_3d`: true
- `min_features`: 4

---

## [1000] source=multitask_sft_big

**USER:** Run the AlphaFold DB Search workflow for my structure 'query_sample.pdb' with sequence 'query_sample.fasta'. Please limit the output to the top 25 hits with an e-value threshold of 0.001.

**ASSISTANT:** Here are the extracted parameters for the AlphaFold DB Search workflow:
- `query_pdb`: query_sample.pdb
- `query_fasta`: query_sample.fasta
- `max_hits`: 25
- `evalue`: 0.001

---

## [1001] source=multitask_sft_big

**USER:** I am preparing inputs for `gsar_rnaseq_gsa`. Here are my variables: a count table `raw_counts` (genes x samples), gene lengths `len_vec`, sample conditions `conditions`, and target pathway genes `target_genes`. What workflow outputs can I expect once these are provided?

**ASSISTANT:** Once configured with your count matrix, gene lengths, group labels, and target gene set, the `gsar_rnaseq_gsa` workflow produces two main outputs: `expression_matrix` and `normalized_data`.

---

## [1002] source=multitask_sft_big

**USER:** What is the purpose of the 'input edge weight file' in the MetaboRank tool?

**ASSISTANT:** In MetaboRank, the 'input edge weight file' is a recommended input specifying the path to a file containing edge weights, which are normalized by the tool to serve as transition probabilities.

---

## [1003] source=multitask_sft_big

**USER:** What data inputs are defined for the rmassbank_combining_multiplicities workflow?

**ASSISTANT:** The workflow defines two inputs: an optional list named `NarcoticsDataset.csv` (described as 'Compound list') and raw LC-MS/MS files matching the pattern `*.mzML`.

---

## [1004] source=multitask_sft_big

**USER:** What variables can I include in the mathematical expression for the 'Add surface field' tool, and what output format does it produce?

**ASSISTANT:** You can use the spatial coordinates x, y, z (shape point coordinates) and t (representing time) in the mathematical expression. The tool generates output files in VTK POLYDATA format.

---

## [1005] source=multitask_sft_big

**USER:** Please set up kpsort sequence analysis for my samples. They are derived from an animal tissue proteome.

**ASSISTANT:** Extracted parameter for kpsort:
- Source organism: 'animal'

---

## [1006] source=multitask_sft_big

**USER:** From this user config description, extract the input data slots for rtca_data_transformation:
'We have exported raw RTCA cell index data saved as raw_run1.tsv and our sample well plate metadata as plate1_meta.csv.'

**ASSISTANT:** Based on the specification for `rtca_data_transformation`, the parameters map as follows:
- `testOutput.csv`: raw_run1.tsv (raw RTCA exported tab-delimited file)
- `testOutputPhenoData.csv`: plate1_meta.csv (well annotation metadata file)

---

## [1007] source=multitask_sft_big

**USER:** I need to horizontally concatenate two 2-D microscopy images using the 'Concatenate images or channels' tool. Which axis value should I supply?

**ASSISTANT:** For a 2-D image, set the axis parameter to `0` for horizontal concatenation. (A value of `1` is used for vertical concatenation).

---

## [1008] source=multitask_sft_big

**USER:** I have an RDS file from DESeq2 named 'deseq_res.rds' containing normalized counts and differential expression statistics. How does this map into the vidger_deseq2_dge_visualization workflow?

**ASSISTANT:** The file 'deseq_res.rds' maps directly to the required input parameter `df.deseq` (type: rds), which accepts a DESeq2 results object or data frame containing normalized counts and DGE statistics.

---

## [1009] source=multitask_sft_big

**USER:** What input file and format are required to run the `spktools` workflow?

**ASSISTANT:** The workflow requires `SpikeInExpressionSet.RData`, which must be an R object of class `SpikeInExpressionSet` containing the expression matrix and nominal concentrations.

---

## [1010] source=multitask_sft_big

**USER:** I want to supply my motif files to the motifstack_multiple_motif_stack_and_tree workflow from a folder called '/data/motifs/'. What parameter should I set?

**ASSISTANT:** You should set the parameter `motifs_folder` to `"/data/motifs/"`. Note that this parameter expects a directory containing multiple `.pcm` files.

---

## [1011] source=multitask_sft_big

**USER:** What input parameters or data slots are defined for the GenomicPlot workflow?

**ASSISTANT:** The GenomicPlot workflow defines one mandatory data input slot named 'input_files' (type: data, accepting count_data). It does not declare additional workflow parameters.

---

## [1012] source=multitask_sft_big

**USER:** I am running `scHicMergeMatrixBins` on a 10kb single-cell Hi-C matrix and want to downsample it to a 1MB resolution matrix. How should I set the number of bins to merge?

**ASSISTANT:** To merge from 10kb to 1MB, calculate the ratio: 1MB / 10kb = 100. Therefore, you should set the number of bins to merge to 100.

---

## [1013] source=multitask_sft_big

**USER:** In obistat, which option allows me to categorize sequence records to compute statistics?

**ASSISTANT:** You can categorize sequence records in `obistat` using one or several `-c` options.

---

## [1014] source=multitask_sft_big

**USER:** I have completed a de novo transcriptome assembly using Trinity and obtained `trinity_out_dir/Trinity.fasta`. I want to configure `ctat_rsem_align_and_estimate_abundance` to quantify expression against these transcripts using paired RNA-seq reads `reads_1.fq.gz` and `reads_2.fq.gz`. What is the reference FASTA input?

**ASSISTANT:** For `ctat_rsem_align_and_estimate_abundance`, the required FASTA input against which reads are aligned is your assembled transcripts file, which in this case is `trinity_out_dir/Trinity.fasta`.

---

## [1015] source=multitask_sft_big

**USER:** I want to run Neptune: Signature Discovery to compare our target inclusion strains against our background exclusion strains. Please configure the target categories.

**ASSISTANT:** Parameters extracted for Neptune: Signature Discovery:
- Inclusion targets: Specified target group genomes (signatures must be sufficiently represented)
- Exclusion targets: Specified background control genomes (signatures must be sufficiently absent)

---

## [1016] source=multitask_sft_big

**USER:** What inputs and outputs are defined for the 'Fasta Build Add Kraken2 Bracken' subworkflow?

**ASSISTANT:** The workflow inputs are: 'fasta1', 'fasta2', 'fasta3', 'names', 'dmp', 'nodes', 'acc2taxidfile', 'seqid2taxidfile', and boolean values 'true' and 'false'. The outputs generated are 'db', 'versions', and 'yml'.

---

## [1017] source=multitask_sft_big

**USER:** What is the expected sequence input parameter for the crisprseek_offtarget_search_with_bulges workflow?

**ASSISTANT:** The sequence input is 'inputseq.fa', which expects a FASTA file containing the target sequences. It is listed as an optional input file for the workflow.

---

## [1018] source=multitask_sft_big

**USER:** What mandatory input matrices are expected by the snpstats_snp_imputation_and_association workflow?

**ASSISTANT:** According to the workflow specification, the required genotype input is `snps.10`, which must be provided as a matrix (specifically a `SnpMatrix` object of genotypes) with `optional: false`.

---

## [1019] source=multitask_sft_big

**USER:** What are the required input formats for the read data and starter sequences when using Mapsembler2?

**ASSISTANT:** Mapsembler2 accepts raw NGS reads in either FASTA or FASTQ format (which can be either uncompressed or gzipped) along with a set of input starter sequences.

---

## [1020] source=multitask_sft_big

**USER:** Please configure EDIRquery with the following criteria: Target gene: BRCA1, repeat length of 12 bp, minimum distance of 50 bp, and maximum distance between sequences of 1000 bp.

**ASSISTANT:** Here are the extracted parameters for `EDIRquery`:
- Gene Name: `BRCA1` (required)
- Repeat Sequence Length: `12`
- Minimum Distance Between Sequences: `50`
- Maximum Distance Between Sequences: `1000`

---

## [1021] source=multitask_sft_big

**USER:** What parameters do I use in ModelCreator to configure the QSAR model type and the kernel function?

**ASSISTANT:** In ModelCreator, specify the QSAR model type using the `-type` flag and the kernel function using the `-kernel` flag.

---

## [1022] source=multitask_sft_big

**USER:** What input data does `cgen_snp_logistic_interaction` expect, and what variables must it contain?

**ASSISTANT:** The workflow requires a single mandatory input called `Xdata`, which is a data frame containing case-control status, SNP genotypes, stratification variables, and relevant covariates.

---

## [1023] source=multitask_sft_big

**USER:** What exact input file does the 'Convert RepeatExplorer2 CLUSTER_table.csv to Krona formatted input' tool accept?

**ASSISTANT:** The tool accepts a `CLUSTER_table.csv` file obtained directly from a RepeatExplorer2 analysis.

---

## [1024] source=multitask_sft_big

**USER:** Set up the AlphaGenome track prediction workflow for region chr1:1000000-2000000 on hg38 using API key 'AG-KEY-987' across HepG2 cells, predicting chromatin tracks, and format the output as json.

**ASSISTANT:** Here are the extracted parameters for the `alphagenome_track_prediction` workflow:
- `genomic_region`: "chr1:1000000-2000000"
- `reference_genome`: "hg38"
- `cell_types`: ["HepG2"]
- `tracks_to_predict`: "chromatin"
- `alphagenome_api_key`: "AG-KEY-987"
- `output_format`: "json"

---

## [1025] source=multitask_sft_big

**USER:** I have compiled my position frequency matrices into an R list called `pfm_list`, my target sequences as a DNAStringSet named `peaks_seq`, and matched genomic background sequences in `control_seq`. How should these be mapped to the `motiftestr_clustered_motif_analysis` input parameters?

**ASSISTANT:** Map your datasets to the workflow parameters as follows:
- `ex_pfm`: `pfm_list` (List of position frequency matrices)
- `test_seq`: `peaks_seq` (DNAStringSet of test sequences)
- `rm_seq`: `control_seq` (DNAStringSet of background sequences)

---

## [1026] source=multitask_sft_big

**USER:** Looking at the enrichViewNet workflow definition, what is the declared mandatory input parameter?

**ASSISTANT:** The workflow expects a single mandatory input slot named `input_files` of type `data` (which takes `count_data`). It has `optional: false` and `read_by_workflow: true`.

---

## [1027] source=multitask_sft_big

**USER:** Here is my input configuration for the cfDNA analysis: I have a BAM cohort directory stored at '/data/cfdna/cohorts_bam'. Please extract the necessary parameter for cfdnapro_inter_peak_valley_distance.

**ASSISTANT:** Extracted parameter:
- groups_picard: "/data/cfdna/cohorts_bam" (type: bam directory)

---

## [1028] source=multitask_sft_big

**USER:** Run miaviz on my count experiment file saved at /data/metagenomics/sample_GlobalPatterns.rds.

**ASSISTANT:** Extracted parameter for the miaviz workflow:
- `GlobalPatterns`: "/data/metagenomics/sample_GlobalPatterns.rds" (type: `rds_se`, non-optional TreeSummarizedExperiment object).

---

## [1029] source=multitask_sft_big

**USER:** I have an interval file `targets.interval.txt`, somatic variants `sample_mutect.vcf`, pre-computed segmentations `sample.seg`, and optionally CNVkit log2-ratios `sample.cnr`. How should these be mapped to the `purecn_third_party_segmentation` workflow?

**ASSISTANT:** The input mapping for `purecn_third_party_segmentation` is:
- `tumor.seg`: `sample.seg` (required segmented copy number file from your third-party tool)
- `tumor_mutect.vcf`: `sample_mutect.vcf` (required VCF with germline and somatic variants)
- `interval.txt`: `targets.interval.txt` (required interval file)
- `tumor.cnr`: `sample.cnr` (optional CNVkit copy number log2-ratio file)

---

## [1030] source=multitask_sft_big

**USER:** I want to build a phylogenetic tree using RAxML for my 16S rRNA gene analysis using the make_phylogeny tool. How should I specify the method parameter?

**ASSISTANT:** In the `make_phylogeny` tool, specify the method parameter as `raxml`. The valid options for tree building are `clearcut`, `clustalw`, `raxml`, `fasttree_v1`, `fasttree`, and `muscle` (default is `fasttree`).

---

## [1031] source=multitask_sft_big

**USER:** Configure SnapATAC2 peaks and motif so that peak summits are expanded by 250 base pairs on each side.

**ASSISTANT:** The extracted parameter for the summit expansion is:
- half_width: 250

---

## [1032] source=multitask_sft_big

**USER:** What are the mandatory input files and output files for the `sigfeature` transcriptomics workflow?

**ASSISTANT:** The required input files for `sigfeature` are:
- `expression_matrix.csv`: A microarray or RNA-seq expression matrix with features as rows and samples as columns.
- `sample_metadata.csv`: Metadata containing binary class labels.

The outputs produced are:
- `de_table`
- `expression_matrix`
- `feature_selection`

---

## [1033] source=multitask_sft_big

**USER:** I want to plot my ChIP-seq signals as log2 fold enrichment over my input control using ngs.plot. What specific input is required to enable fold change calculation instead of intensity plotting?

**ASSISTANT:** You must supply the control dataset as a reference BAM file to ngs.plot. Providing a reference BAM file prompts the tool to calculate and display log2 fold changes instead of absolute read count intensities.

---

## [1034] source=multitask_sft_big

**USER:** I want to apply GC content constraints to Sculpt Sequences with a minimum of 30%, a maximum of 70%, and a window of 100. How should these parameters be formatted?

**ASSISTANT:** Under the GC content constraints configuration for Sculpt Sequences, specify the parameters as: `mini=0.3, maxi=0.7, window=100`.

---

## [1035] source=multitask_sft_big

**USER:** I want to export my cg/wgMLST database results, but I only want to retain genes present in at least 15 strains and keep only polymorphic genes with varying alleles while omitting missing ones. Which CLI flags should I use?

**ASSISTANT:** You should set the following parameters:
- `-m 15` (or `--mincover 15`) to specify the minimum number of strains required to retain a gene.
- `-k` (or `--keep`) to keep only genes with different alleles and omit missing data.

---

## [1036] source=multitask_sft_big

**USER:** Convert my multi-extension file 'galaxy_survey.fits' to TIFF format using HDU index 3 with fits2tiff.

**ASSISTANT:** The parameters extracted for 'fits2tiff' are:
- Input file: "galaxy_survey.fits"
- HDU index: 3

---

## [1037] source=multitask_sft_big

**USER:** What data inputs are defined for the iSEEhex workflow in its configuration?

**ASSISTANT:** The declared data input for the `iSEEhex` workflow is `seurat_object` (type: data, optional: true, read_by_workflow: false).

---

## [1038] source=multitask_sft_big

**USER:** I want to launch the gsva workflow using 'normalized_counts.csv' as my expression matrix and 'c2_curated.gmt' for the pathways. Please configure the inputs.

**ASSISTANT:** Here are the extracted parameters for the **gsva** workflow:

- **expression_matrix.csv**: `normalized_counts.csv` (normalized gene expression matrix or SummarizedExperiment)
- **pathways.gmt**: `c2_curated.gmt` (gene sets in GMT format)

This will generate the output targets: `de_table`, `pathway_results`, and `cluster_assignments`.

---

## [1039] source=multitask_sft_big

**USER:** For what study designs and omics types is the 'Generate gene to transcript map' tool suitable?

**ASSISTANT:** Based on its metadata, the tool is categorized under primary omics 'transcriptomics' and is suitable for:
- RNA-Seq studies using Trinity de novo assembly
- Transcript quantification workflows
- Studies requiring gene-to-transcript mapping based on Trinity-assembled transcripts

---

## [1040] source=multitask_sft_big

**USER:** I need to configure FASTA-to-FASTQ for standard runs where I don't want to customize base quality. What is the default base quality parameter value?

**ASSISTANT:** The default quality score parameter for each base in FASTA-to-FASTQ is 40.

---

## [1041] source=multitask_sft_big

**USER:** Please set up gene_set_enrichment_analysis using my target file target_genes.txt, reference background file background_universe.txt, and make sure visualization plots are generated.

**ASSISTANT:** Here are the extracted parameters for `gene_set_enrichment_analysis`:
- Gene list: target_genes.txt
- Background gene set: background_universe.txt
- Plotting: true

---

## [1042] source=multitask_sft_big

**USER:** For my CryoSPARC Global CTF Refinement run, I want to refine beam tilt, trefoil, and spherical aberration, but skip anisotropic magnification, and enable CryoSPARC integration. Which parameters should I set?

**ASSISTANT:** You should set the following parameters:
- `fit_tilt`: true
- `fit_trefoil`: true
- `fit_spherical`: true
- `fit_anisomag`: false
- `use_cryosparc`: true

---

## [1043] source=multitask_sft_big

**USER:** I am setting up a run for the cnorfeeder workflow. Here is my setup: I have perturbation data in `perturbation_cno.RData`, a prior knowledge network in `pk_network.model`, and an optional protein-protein interaction network in `string_ppi.igraph`. I do not have a Uniprot ID mapping list. Can you map these to the workflow inputs?

**ASSISTANT:** Here is the parameter mapping for the `cnorfeeder` workflow:
- `CNOlistDREAM`: `perturbation_cno.RData` (mandatory CNOlist containing perturbation data)
- `DreamModel`: `pk_network.model` (mandatory Prior knowledge network model in CNO format)
- `PPINigraph`: `string_ppi.igraph` (optional igraph object representing protein-protein interactions)
- `UniprotIDdream`: None (optional mapping list omitted)

---

## [1044] source=multitask_sft_big

**USER:** Here are our input files for the chromosome 21 run: ChIP signal file `chip_chr21.txt` and background file `input_chr21.txt`. Can you configure the data inputs for `mosaics_two_sample_with_genomic_features`?

**ASSISTANT:** The data inputs for `mosaics_two_sample_with_genomic_features` are mapped as follows:
- `chip_chr21.txt`: ChIP bin-level data
- `input_chr21.txt`: Control/input data

---

## [1045] source=multitask_sft_big

**USER:** What options are available for the percentile calculation flag in metagenomeSeq Normalization?

**ASSISTANT:** The flag allows choosing between calculating the proper percentile using R's step-wise quantile function or using an approximate function.

---

## [1046] source=multitask_sft_big

**USER:** Set up 3D Variability Analysis with 3 components, resolution filtered to 4.0 Angstroms, 20 iterations, using CryoSPARC, and run clustering with 5 clusters in cluster mode.

**ASSISTANT:** Extracted parameters for 3D Variability Analysis:
- num_components: 3
- filter_res_angstroms: 4.0
- num_iterations: 20
- use_cryosparc: true
- cluster_mode: true
- num_clusters: 5

---

## [1047] source=multitask_sft_big

**USER:** I need to run 'change tag name' on my GFF3 annotation file because downstream tools expect 'gene_id' instead of the tag currently named 'locus_tag' in field 9. What tag rename mapping is being requested?

**ASSISTANT:** The operation requires targeting the 9th field of the GFF3 file to change the existing tag name 'locus_tag' to the new tag name 'gene_id'.

---

## [1048] source=multitask_sft_big

**USER:** What are the required input datasets and expected outputs of the zenith workflow?

**ASSISTANT:** The `zenith` workflow requires:
- Inputs:
  1. `geneCounts`: A matrix of raw gene expression counts.
  2. `df_metadata`: A data frame containing sample metadata and covariates.
- Outputs:
  1. `de_table`: The differential expression table.
  2. `enrichment_results`: The gene set enrichment analysis results.
  3. `normalized_data`: The normalized expression data.

---

## [1049] source=multitask_sft_big

**USER:** Which underlying Bioconductor software packages are bundled and executed by the 'specl' workflow?

**ASSISTANT:** The 'specl' workflow executes the following tools:
- `bioconductor/specl`
- `bioconductor/biocstyle`
- `bioconductor/knitr`
- `bioconductor/rmarkdown`

---

## [1050] source=multitask_sft_big

**USER:** I am configuring filter_alignment for my metagenomics pipeline. My qiime_config has a default set for --lane_mask_fp, but I want to turn off lane-mask-based filtering completely. Which parameter should I toggle?

**ASSISTANT:** You should set `suppress lane mask filtering` to True. This flag explicitly turns off lane-mask-based filtering when a default `--lane_mask_fp` is provided.

---

## [1051] source=multitask_sft_big

**USER:** Here are the transformed RDS files for my samples that I want to process: c('/data/cohort/sample1_transformed.rds', '/data/cohort/sample2_transformed.rds', '/data/cohort/sample3_transformed.rds'). Can you prepare the parameter mapping for the cytomds_large_dataset_parallel workflow?

**ASSISTANT:** Based on your inputs, the extracted parameter for `cytomds_large_dataset_parallel` is:

```json
{
  "fileNames": [
    "/data/cohort/sample1_transformed.rds",
    "/data/cohort/sample2_transformed.rds",
    "/data/cohort/sample3_transformed.rds"
  ]
}
```

This provides the required character vector of file paths to transformed sample RDS files on disk.

---

## [1052] source=multitask_sft_big

**USER:** I have an ExpressionSet RDS file called 'sample.ExpressionSet' and a genomic coordinate object 'chrObj'. Which inputs do these correspond to in geneplotter_single_chromosome_expression_plotting?

**ASSISTANT:** These correspond directly to the workflow's data inputs:
- `sample.ExpressionSet`: `sample.ExpressionSet` (ExpressionSet object containing expression data in RDS format)
- `chrObj`: `chrObj` (chromLocation object containing genomic coordinates)

---

## [1053] source=multitask_sft_big

**USER:** I need to shuffle genomic coordinates across my genome file but must ensure they do not fall into blacklisted regions provided in a BED or VCF file. Does bedtools ShuffleBed support these input formats for exclusions?

**ASSISTANT:** Yes. bedtools ShuffleBed accepts exclusion regions provided as BED, bedGraph, GFF, VCF, or EncodePeak files to ensure permuted features are not placed within those specified intervals.

---

## [1054] source=multitask_sft_big

**USER:** Which mandatory data inputs must be supplied to `ramwas_custom_cpg_set_and_qc`?

**ASSISTANT:** Based on the workflow specification, the required non-optional data inputs are:
- `BSgenome`: reference genome package
- `count_ALL_chr22.txt`: count data file

---

## [1055] source=multitask_sft_big

**USER:** I am preparing a VADR 1.6.4 execution for my sequence file `isolate_contigs.fasta`. How should the basic invocation be structured?

**ASSISTANT:** The basic usage syntax for VADR 1.6.4 is `v-annotate.pl [-options] <fasta file to annotate>`. For your file, the invocation starts with: `v-annotate.pl [options] isolate_contigs.fasta`.

---

## [1056] source=multitask_sft_big

**USER:** What input parameters or data slots are defined for the biomaRt workflow?

**ASSISTANT:** The biomaRt workflow defines a single non-optional input data slot named `input_files` (type: data), which accepts `count_data`.

---

## [1057] source=multitask_sft_big

**USER:** Which underlying Bioconductor packages power the sparsenetgls workflow, and what output does it produce?

**ASSISTANT:** The `sparsenetgls` workflow uses `bioconductor/sparsenetgls`, `bioconductor/mass`, and `bioconductor/matrix`. Its primary output is `visualizations` illustrating the model fit and results.

---

## [1058] source=multitask_sft_big

**USER:** I am configuring a run for `sva_combat_seq_rna_seq`. Here are my files: 'raw_counts.csv' which has raw integer RNA-Seq read counts per gene, and 'sample_metadata.csv' documenting the sequencing batch and treatment conditions. What are the expected inputs and outputs?

**ASSISTANT:** For `sva_combat_seq_rna_seq`:
- Required Data Inputs:
  1. `raw_counts.csv`: Matrix of raw integer RNA-Seq counts (genes in rows, samples in columns).
  2. `sample_metadata.csv`: Metadata containing batch designations and biological group/covariate variables.
- Outputs:
  1. `counts_matrix`: Batch-adjusted RNA-Seq integer count matrix.
  2. `de_table`: Differential expression results table.

---

## [1059] source=multitask_sft_big

**USER:** Configure the inputs for safe_custom_cmatrix_safe_analysis with my data: gene expression matrix 'e3.upp', phenotype vector 'p3.upp$p53', and gene symbol vector 'genes'.

**ASSISTANT:** The extracted inputs for `safe_custom_cmatrix_safe_analysis` are:
- `e3.upp`: gene expression matrix
- `p3.upp$p53`: phenotype vector
- `genes`: named character vector of gene symbols

---

## [1060] source=multitask_sft_big

**USER:** I am configuring filter_alignment for my metagenomics pipeline. What is the default behavior regarding lane mask filtering, and why would someone need to suppress it?

**ASSISTANT:** By default, suppressing lane mask filtering is set to False. Suppressing lane mask filtering is necessary when a default lane mask filepath (`--lane_mask_fp`) has been configured in `qiime_config` and you want to explicitly turn off lane-mask-based filtering for your run.

---

## [1061] source=multitask_sft_big

**USER:** I am preparing RNA STAR mapping and want to utilize annotated splice junction information from the reference index. Which index option should I select?

**ASSISTANT:** You should select the '... with builtin gene-model' option to choose an index built with splice junction information.

---

## [1062] source=multitask_sft_big

**USER:** What input does the atlas_expression_query workflow take, and what output formats does it return?

**ASSISTANT:** The `atlas_expression_query` workflow takes a single string input (the gene identifier) and returns outputs in json, csv, and txt formats.

---

## [1063] source=multitask_sft_big

**USER:** Configure the spiky_cfmedip_analysis_bedpe workflow to use my aligned read archive located at '/data/cfmedip/sample_genomic.bedpe.gz'.

**ASSISTANT:** The parameter configuration for `spiky_cfmedip_analysis_bedpe` is:
- `genomic_bedpe_path`: "/data/cfmedip/sample_genomic.bedpe.gz"

---

## [1064] source=multitask_sft_big

**USER:** Please check the required inputs and expected outputs for running the `multiscan` workflow.

**ASSISTANT:** The parameters and artifacts for the `multiscan` workflow are:

- **Required Data Input**: `intensity_data.csv` (CSV file with raw, untransformed intensity measurements; rows as probes, columns as scans at different sensitivity settings)
- **Output**: `visualizations` (model diagnostics)
- **Underlying Tool**: `bioconductor/multiscan`

---

## [1065] source=multitask_sft_big

**USER:** I want to subset my table using csvtk-sample and make sure the sampling is reproducible using seed 12345.

**ASSISTANT:** Here is the extracted parameter for `csvtk-sample`:
- `seed`: 12345

This ensures a deterministic, reproducible random proportion of your dataset is sampled.

---

## [1066] source=multitask_sft_big

**USER:** Set up a run for the Fcrn Antibody PK workflow with a human IgG1 antibody (150 kDa), standard YTE mutation, dosed intravenously at 10 mg/kg across 3 doses for oncology, with an FcRn affinity at pH 6.0 of 120 nM.

**ASSISTANT:** Here are the extracted parameters for the Fcrn Antibody Pk workflow:
- antibody_format: "IgG1"
- fc_mutation: "YTE"
- mw_kda: 150
- dose_mg_kg: 10
- route: "intravenous"
- species: "human"
- indication: "oncology"
- n_doses: 3
- fcrn_affinity_ph6: 120
(Note: sc_volume_mL remains unspecified as the route is intravenous).

---

## [1067] source=multitask_sft_big

**USER:** What are the designated output targets generated by `epigenomix_rnaseq_chipseq_integration`?

**ASSISTANT:** The workflow generates two outputs: `normalized_data` and `visualizations`.

---

## [1068] source=multitask_sft_big

**USER:** In the 'ihw_incomplete_pvalues_ihw' workflow configuration, is the 'sim.csv' input file optional?

**ASSISTANT:** No, according to the workflow parameters, 'sim.csv' is not optional ('optional': false) and is required to calculate group sizes from the covariate.

---

## [1069] source=multitask_sft_big

**USER:** I need to run VCFgenotype-to-haplotype to construct haplotypes from phased alleles within a 200 base-pair window. Which parameter defines this window?

**ASSISTANT:** The parameter is `-w`. For your 200 base-pair window, you should specify `-w 200`.

---

## [1070] source=multitask_sft_big

**USER:** I have sparse interaction tables for two conditions named `dat1.1000000.pixels.tsv` and `dat2.1000000.pixels.tsv`. How are these mapped into `hiccompare_genome_wide_parallel_comparison`?

**ASSISTANT:** These correspond directly to the required data inputs: `dat1.1000000.pixels.tsv` is mapped as the genome-wide sparse interaction table for condition 1, and `dat2.1000000.pixels.tsv` is mapped as the genome-wide sparse interaction table for condition 2. Both are required table inputs read by the workflow.

---

## [1071] source=multitask_sft_big

**USER:** Which Bioconductor packages are integrated into the oncoscanr workflow pipeline?

**ASSISTANT:** The `oncoscanr` workflow uses the following tools: `bioconductor/oncoscanr`, `bioconductor/jsonlite`, and `bioconductor/magrittr`.

---

## [1072] source=multitask_sft_big

**USER:** How does lifelineskmcph identify columns in an input file if the header is missing versus present?

**ASSISTANT:** If the file has a header, lifelineskmcph can use the column name directly from the header or select one from the supplied parameter list. If the data lacks header names, it falls back to column position identifiers in the format `col1....colN`.

---

## [1073] source=multitask_sft_big

**USER:** Here is my workflow configuration draft for pharmacogx_gene_drug_association:
- target: drug-gene modeling
- pset_file: CCLEsmall.rds (PharmacoSet object)
- extra_inputs: null

Can you extract and format the required inputs based on the workflow specifications?

**ASSISTANT:** Based on the workflow specifications for `pharmacogx_gene_drug_association`, the extracted input parameter is:

- `CCLEsmall`: `CCLEsmall.rds` (type: `rds`, description: `PharmacoSet object`, optional: `false`, read_by_workflow: `true`)

This PharmacoSet object satisfies the mandatory input required to model molecular feature associations with drug sensitivity.

---

## [1074] source=multitask_sft_big

**USER:** I am configuring the Metagenome Contributions tool and want to restrict the analysis to functions K00500 and K00501. How should I enter them?

**ASSISTANT:** You should format the specified function IDs as comma-separated values without any spaces: `K00500,K00501`.

---

## [1075] source=multitask_sft_big

**USER:** I want to set up pcan_pathway_consensus with the following: Candidate gene Entrez is 7157, my Reactome gene lists are in 'reactome_genes.rds', pathway definitions are in 'reactome_paths.rds', semantic matrices are 'gene_hpo_mats.rds', and the Resnik score vector is 'similarity_scores.rds'. Please map these.

**ASSISTANT:** Here is the parameter mapping for `pcan_pathway_consensus`:
- `genId`: 7157
- `hsEntrezByRPath`: 'reactome_genes.rds'
- `rPath`: 'reactome_paths.rds'
- `hpMatByGene`: 'gene_hpo_mats.rds'
- `resnSss`: 'similarity_scores.rds'

This configuration will generate the workflow's outputs: `consensus_score` and `visualizations`.

---

## [1076] source=multitask_sft_big

**USER:** What happens if I don't enter an assay file name when running the ISA to W4M tool?

**ASSISTANT:** If the assay file name is left unset, the tool will automatically use the first listed study in the ISA archive.

---

## [1077] source=multitask_sft_big

**USER:** What types of input array files are accepted by the rcgh workflow?

**ASSISTANT:** The rcgh workflow accepts Affymetrix CytoScan HD exported text files (Affy_cytoScan.cyhd.CN5.CNCHP.txt.bz2), Affymetrix SNP6.0 exported text files (Affy_snp6_cnchp.txt.bz2), Agilent Feature Extraction text files (Agilent4x180K.txt.bz2), and custom array text files (generic.txt.bz2).

---

## [1078] source=multitask_sft_big

**USER:** Configure Consolidate VCFs for high-density SNV detection with density filtering enabled and a search window of 500 base pairs.

**ASSISTANT:** The extracted parameter configuration is:
- `--window-size`: 500
- Density filtering: enabled (required for `--window-size` to take effect).

---

## [1079] source=multitask_sft_big

**USER:** Extract the command-line options and their argument values from this command: `beta_diversity_through_3d_plots.py -i wf_da/uclust_picked_otus/rep_set/rdp_assigned_taxonomy/otu_table/seqs_otu_table.txt -m Fasting_Map.txt -o wf_bdiv_even146_test/ -p custom_parameters.tt -t wf_da/uclust_picked_otus/rep_set/pynast_aligned_seqs/fasttree_phy`

**ASSISTANT:** Here are the extracted parameters from the command:
- `-i`: `wf_da/uclust_picked_otus/rep_set/rdp_assigned_taxonomy/otu_table/seqs_otu_table.txt` (Input OTU table)
- `-m`: `Fasting_Map.txt` (Sample metadata/mapping file)
- `-o`: `wf_bdiv_even146_test/` (Output directory)
- `-p`: `custom_parameters.tt` (Parameters file)
- `-t`: `wf_da/uclust_picked_otus/rep_set/pynast_aligned_seqs/fasttree_phy` (Phylogenetic tree file)

---

## [1080] source=multitask_sft_big

**USER:** What are the declared input slots and underlying tool components for the scPipe workflow?

**ASSISTANT:** The `scPipe` workflow expects data under the input slot `input_files` (non-optional data input read by the workflow). Its underlying tools are `bioconductor/scpipe` and `bioconductor/singlecellexperiment`.

---

## [1081] source=multitask_sft_big

**USER:** When should I select the 'No packaged matrix output' option in Scanpy FindMarkers?

**ASSISTANT:** You should choose 'No packaged matrix output' when auxiliary files are generated (such as marker gene tables). However, do not select this option if there are no other output files being produced.

---

## [1082] source=multitask_sft_big

**USER:** What input and parameters do I need to specify when running the Rooting tool?

**ASSISTANT:** For the Rooting tool, you must provide:
- Input file: A Newick format tree file (`Input tree file`)
- Parameter: `Output name` (the output base name used for generating the output files).

---

## [1083] source=multitask_sft_big

**USER:** In Hammock - cluster peptides, how can I configure the tool to use all labels in my dataset, and which flag controls this in the manual?

**ASSISTANT:** You can set the labels option to "Automatic" to use all labels present in your data. In the manual, this configuration is controlled by the `-l` or `--labels` parameter.

---

## [1084] source=multitask_sft_big

**USER:** I want to run targetscore_target_score_via_targetscoredata for microRNA hsa-miR-1 without supplying an external fold-change matrix.

**ASSISTANT:** The extracted parameters for the workflow are:
- `miRNA`: "hsa-miR-1" (required)
- `logFC.imputed`: omitted (optional precomputed or user-supplied matrix)

---

## [1085] source=multitask_sft_big

**USER:** I need to join file_1.txt and file_2.txt based on column 3. Since they are numerical approximations, allow a maximum absolute difference of 0.02 between matching values.

**ASSISTANT:** Extracted parameters for 'Join two files':
- Common column: 3
- Matching tolerance type: Maximum absolute difference
- Allowed difference value: 0.02

---

## [1086] source=multitask_sft_big

**USER:** What functionalities does the Compound conversion tool provide for chemistry data pipelines?

**ASSISTANT:** The Compound conversion tool provides an interface wrapping Open Babel command prompt utilities to convert between diverse chemical and molecular modeling file formats. It allows you to configure target output formats and set format-specific conversion parameters.

---

## [1087] source=multitask_sft_big

**USER:** I want to run seqgate. I have raw_counts.csv containing my raw transcriptomic counts and conditions.csv describing the biological conditions across samples.

**ASSISTANT:** I have extracted the following inputs for `seqgate`:
- `counts_matrix.csv`: `raw_counts.csv` (matrix of raw transcriptomic counts)
- `sample_metadata.csv`: `conditions.csv` (sample annotations containing biological conditions)

---

## [1088] source=multitask_sft_big

**USER:** Please set up the State Perturbation Prediction workflow using 'pbmc_treated.h5ad', testing the perturbation 'IFN-gamma' of type 'cytokine' specifically in 'CD4_T_cells'. Set it to output 50 predictions using mode 'stochastic'.

**ASSISTANT:** Extracted parameters for the `state_perturbation_prediction` workflow:
- `input_h5ad`: 'pbmc_treated.h5ad'
- `perturbation`: 'IFN-gamma'
- `perturbation_type`: 'cytokine'
- `cell_type`: 'CD4_T_cells'
- `n_predictions`: 50
- `mode`: 'stochastic'

---

## [1089] source=multitask_sft_big

**USER:** What data inputs are required by the `canceR` workflow, and what input slot must be populated?

**ASSISTANT:** The `canceR` workflow requires an input of type `count_data` assigned to the mandatory parameter `input_files` (which is read by the workflow).

---

## [1090] source=multitask_sft_big

**USER:** What are the required input files and parameters for running the dir_expiry workflow?

**ASSISTANT:** The `dir_expiry` workflow requires one mandatory data input slot named `count_data` (`optional: false`). It does not declare any additional pipeline parameters.

---

## [1091] source=multitask_sft_big

**USER:** I want to update the column headers in my metabolomics abundance table at /data/abundance.tsv using annotations from /data/annot.tsv. Please save the output to /results/renamed.csv using the single best match.

**ASSISTANT:** I have extracted the following parameters for Rename Annotated Feature:
- Abundance table path: `/data/abundance.tsv`
- Annotations table path: `/data/annot.tsv`
- Renaming mode: `single` (renames based on the highest match)
- Output path: `/results/renamed.csv`

---

## [1092] source=multitask_sft_big

**USER:** Please set up deepsnv using 'patient01_tumor.bam' for my test alignment and 'patient01_germline.bam' for my matched control.

**ASSISTANT:** The input parameters for the `deepsnv` workflow have been mapped as follows:
- `test.bam`: 'patient01_tumor.bam'
- `control.bam`: 'patient01_germline.bam'

---

## [1093] source=multitask_sft_big

**USER:** Please set up the inputs for switchbox_legacy_ktsp_workflow using my variables: `train_matrix` (training feature expression), `labels_factor` (class factor for training), and `test_matrix` (testing feature expression).

**ASSISTANT:** The parameters extracted for `switchbox_legacy_ktsp_workflow` are:
- `matTraining`: `train_matrix`
- `trainingGroup`: `labels_factor`
- `matTesting`: `test_matrix`

---

## [1094] source=multitask_sft_big

**USER:** Please set up scbfa_binary_pca for my project using my gene counts matrix file 'raw_counts_cell_matrix.tsv'.

**ASSISTANT:** I will configure `scbfa_binary_pca` with the following input parameter:
- `exprdata`: 'raw_counts_cell_matrix.tsv' (raw counts matrix with genes as rows and cells as columns)

---

## [1095] source=multitask_sft_big

**USER:** I am configuring Sbml2CarbonSkeletonNet. Aside from the default edge list, what other graph export formats can I select?

**ASSISTANT:** In addition to the default tabulated edge list, Sbml2CarbonSkeletonNet supports the following export formats:
- GML
- JsonGraph
- Tabulated node list (formatted as: label node id node type)

---

## [1096] source=multitask_sft_big

**USER:** What format and identifier requirements exist for the input gene list in the norce workflow?

**ASSISTANT:** In the 'norce' workflow, the mandatory input 'gene_list.txt' must be provided as a list of ncRNA genes formatted with HUGO, ENSEMBL, or ENTREZ identifiers.

---

## [1097] source=multitask_sft_big

**USER:** I am configuring FastUniq (Remove DNA duplicates). I want the output read pairs written in FASTQ format into two files. How do I specify the format?

**ASSISTANT:** Set the sequence format parameter to 'q' for FASTQ format (or 'f' if you need FASTA). FastUniq will output read pairs into two files in that format, keeping paired reads in the same order.

---

## [1098] source=multitask_sft_big

**USER:** What input slots are configured for the VariantExperiment workflow, and is count data required?

**ASSISTANT:** The VariantExperiment workflow declares a data input slot named 'count_data'. It is marked with optional: true and read_by_workflow: false, meaning count data is not strictly required to execute the workflow.

---

## [1099] source=multitask_sft_big

**USER:** Is the multi_sample_gene_expression.tsv input optional in the pathview_multi_sample_comparison workflow?

**ASSISTANT:** No, `multi_sample_gene_expression.tsv` is a required input matrix (`optional: false`) that is directly read by the workflow to compare gene expression across multiple samples.

---

## [1100] source=multitask_sft_big

**USER:** I want to run hicCorrelate on my contact matrices. Please make sure log1p is applied to the matrix values so the scatter plot is easier to inspect.

**ASSISTANT:** I have extracted the parameter requirement: enable the log1p transformation setting for the matrix values. This will adjust the Pearson correlation computation and facilitate clearer scatter plot visualization without altering Spearman correlation results.

---

## [1101] source=multitask_sft_big

**USER:** For `glmsparsenet_binary_classification_binomial`, can I pass an optional continuous response vector for `ydata`?

**ASSISTANT:** No. `ydata` is strictly required (`optional: false`) and must be a factor vector of binary class labels for each sample, as the workflow fits a binomial logistic regression model.

---

## [1102] source=multitask_sft_big

**USER:** Can you list the tools employed by the rsweep workflow and its generated output?

**ASSISTANT:** The `rsweep` workflow utilizes the tools `bioconductor/rsweep` and `bioconductor/ape`, and its primary output is `phylogenetic_tree`.

---

## [1103] source=multitask_sft_big

**USER:** I have an RDS file named 'experimental_msi.rds' containing a processed MSImagingExperiment object. Does it fulfill the input requirements of `cardinal_class_comparison`?

**ASSISTANT:** Yes. The `cardinal_class_comparison` workflow specifically requires `experimental_msi.rds` of type RDS, which must be a processed `MSImagingExperiment` object containing condition information.

---

## [1104] source=multitask_sft_big

**USER:** Run pocket detection on 'target_protein.pdb'. I only want pockets with a druggability score of at least 0.6, issue a warning if below 0.7, and disregard any pocket with volume under 300 Å³.

**ASSISTANT:** I have extracted the following parameters for the `Pocket Detection Druggability` workflow:
- `pdb_input`: "target_protein.pdb"
- `min_druggability`: 0.6
- `warn_druggability`: 0.7
- `min_volume`: 300

---

## [1105] source=multitask_sft_big

**USER:** Please set up edger_glm_lrt_pipeline using my DGEList object stored at 'experiment_dgelist.rds' along with the required input files.

**ASSISTANT:** I have configured the inputs for `edger_glm_lrt_pipeline`:
- `y`: `experiment_dgelist.rds` (DGEList object in RDS format)
- `input_files`: provided data files

Upon execution, the workflow will generate the differential expression results table (`de_table`).

---

## [1106] source=multitask_sft_big

**USER:** I am configuring a run for nf-core/marsseq with the human genome reference GRCh38, custom fasta/gtf files, and want to bypass the QC steps. Can you identify the relevant parameters from the workflow specification to achieve this?

**ASSISTANT:** Based on the `nf-core/marsseq` workflow parameters, you should set:
- `genome`: Specify your reference genome identifier (e.g., `GRCh38`)
- `fasta`: Path to your genomic FASTA file
- `gtf`: Path to your transcript annotation GTF file
- `skip_qc`: Set to `true` to skip quality control steps
- `input`: Path to your input samplesheet/reads
- `outdir`: Directory to save the final outputs

---

## [1107] source=multitask_sft_big

**USER:** What data inputs does the splicewiz_novel_splicing_analysis workflow accept, and is the genome sequence required?

**ASSISTANT:** The workflow accepts 'genome.fa' (genome sequence) and 'transcripts.gtf'. 'genome.fa' is marked as optional (optional: true).

---

## [1108] source=multitask_sft_big

**USER:** Can I run the isoformswitchanalyzer_detailed_isoform_switch_workflow without passing a switchAnalyzeRlist object?

**ASSISTANT:** No. The `switchAnalyzeRlist` parameter is mandatory (`optional: false`) and must be an RDS data input representing a pre-existing or imported switch list object.

---

## [1109] source=multitask_sft_big

**USER:** I am configuring PhaBOX phatyp for my contigs. Here are my inputs: I already have my own predicted protein sequences ready, so I don't want the default Prodigal and DIAMOND blastp steps to run.

**ASSISTANT:** Based on your inputs, PhaBOX phatyp can accept your own predicted protein sequences directly as an optional parameter. When this option is provided, the tool bypasses its default gene prediction workflow (Prodigal and DIAMOND blastp).

---

## [1110] source=multitask_sft_big

**USER:** Here is my setup: I put my paired fastq.gz files in `./raw_reads/` and my guide/primer layout in `./experiment_design.csv`. How do these map to the inputs of the amplican workflow?

**ASSISTANT:** Based on the amplican workflow parameters, the mapping is:
- `config.csv`: `./experiment_design.csv` (contains metadata, primers, guides, and amplicon sequences)
- `fastq_folder`: `./raw_reads/` (directory containing the raw forward and reverse fastq/fastq.gz files)

---

## [1111] source=multitask_sft_big

**USER:** I need to search our Beacon instance for individual biosamples collected on '2023-05-12' that have positive 'HER2' diagnostic markers and are marked as 'active'. What parameters does Beacon2 Biosamples accept for this?

**ASSISTANT:** Based on Beacon2 Biosamples capabilities, the relevant query filters to specify are: collection date ('2023-05-12'), diagnostic markers ('HER2'), and biosample status ('active').

---

## [1112] source=multitask_sft_big

**USER:** What are the input and output data specifications for running bispecific_format_triage?

**ASSISTANT:** The workflow accepts input of type 'string' (specifying the target proteins) and yields results in 'json', 'csv', and 'txt' formats.

---

## [1113] source=multitask_sft_big

**USER:** I want to supply DNA sequences to the tfbstools_de_novo_motif_discovery workflow. What specific input parameter handles FASTA DNA sequence files?

**ASSISTANT:** The workflow provides the 'crp0.s' data input parameter, which is a FASTA file containing DNA sequences (marked optional: true, read_by_workflow: false).

---

## [1114] source=multitask_sft_big

**USER:** What data inputs and parameters are required to run the `igvR` workflow?

**ASSISTANT:** The `igvR` workflow requires one mandatory data input slot named `input_files` (which accepts `count_data`). It does not require any additional configuration parameters.

---

## [1115] source=multitask_sft_big

**USER:** I am setting up a query using 'Chado expression add'. What constraint must the feature type adhere to?

**ASSISTANT:** The feature type parameter (e.g., 'gene', 'mRNA', 'polypeptide', 'contig') must be a valid Sequence Ontology term.

---

## [1116] source=multitask_sft_big

**USER:** What format does gffread expect for the `chr_replace` file?

**ASSISTANT:** The `chr_replace` parameter expects a reference sequence replacement table consisting of 2 columns: "original_ref_ID" and "new_ref_ID".

---

## [1117] source=multitask_sft_big

**USER:** I want to run the `process_mean_spectrum_peaks` workflow on my mass spectrometry data. Here are my raw files: '/data/ms/sample1.csv' and '/data/ms/sample2.csv'. Can you extract the necessary input parameter?

**ASSISTANT:** The extracted parameter for `process_mean_spectrum_peaks` is:
- `fs`: `["/data/ms/sample1.csv", "/data/ms/sample2.csv"]` (vector of file paths to raw mass spectrometry CSV files).

---

## [1118] source=multitask_sft_big

**USER:** Run the nf-core/hicar pipeline using input samplesheet 'samples.csv', anchor peaks from 'anchors.bed', genome 'GRCh38' with fasta 'genome.fa', and output everything to 'results/hicar_run'.

**ASSISTANT:** Here are the extracted parameters for running nf-core/hicar:
- input: 'samples.csv'
- anchor_peaks: 'anchors.bed'
- genome: 'GRCh38'
- fasta: 'genome.fa'
- outdir: 'results/hicar_run'

---

## [1119] source=multitask_sft_big

**USER:** What input data does the `goprofiles_equivalence_testing` workflow require to run?

**ASSISTANT:** The `goprofiles_equivalence_testing` workflow requires two mandatory data inputs:
- `list1`: a vector of Entrez gene IDs
- `list2`: a vector of Entrez gene IDs

---

## [1120] source=multitask_sft_big

**USER:** I have a collection of flowtext files from my flow cytometry run. Please use 'Add sample information and merge' with the sample names: WT_rep1, WT_rep2, KO_rep1, KO_rep2.

**ASSISTANT:** The extracted parameter for sample names is: 'WT_rep1, WT_rep2, KO_rep1, KO_rep2', provided as a comma-separated list corresponding to the order of the flowtext files in your collection to override the collection identifier.

---

## [1121] source=multitask_sft_big

**USER:** What input parameters and data files are required by the GDSArray workflow?

**ASSISTANT:** The `GDSArray` workflow requires one non-optional data input:
- `input_files`: Input data slot representing count data (GDS files). It has no other workflow parameters declared.

---

## [1122] source=multitask_sft_big

**USER:** In the Emm-typing tool for Streptococcus pyogenes, what argument defines the threshold difference between the alignment length and the subject length in BLAST hits, and what is its default value?

**ASSISTANT:** The argument is `--align-diff` (an integer), and its default value is 5.

---

## [1123] source=multitask_sft_big

**USER:** Here is my genomic query file: `chr1_promoters.fa`. Please prepare the input parameter for running G-quadruplex detection with pqsfinder.

**ASSISTANT:** For the `pqsfinder` workflow, your file maps to the primary sequence input parameter:
- `sequence.fa`: `chr1_promoters.fa` (FASTA file containing the DNA sequence of interest).

---

## [1124] source=multitask_sft_big

**USER:** I am configuring CD-HIT PROTEIN for sequence clustering at a sequence identity threshold of 0.55. What word size should I set?

**ASSISTANT:** For a sequence identity threshold between 0.5 and 0.6 (such as 0.55), the suggested word size for CD-HIT PROTEIN is 3.

---

## [1125] source=multitask_sft_big

**USER:** Please set up epigrahmm_differential_peak_calling for my files: I have BAM files at c('/data/condA_r1.bam', '/data/condA_r2.bam', '/data/condB_r1.bam', '/data/condB_r2.bam') and my sample sheet is in meta_df (which contains the condition and replicate columns).

**ASSISTANT:** Extracted workflow parameters:
- bamFiles: c('/data/condA_r1.bam', '/data/condA_r2.bam', '/data/condB_r1.bam', '/data/condB_r2.bam')
- colData: meta_df

---

## [1126] source=multitask_sft_big

**USER:** What inputs and outputs are defined for the Fasta Index Bismark Bwameth workflow?

**ASSISTANT:** The workflow takes inputs categorized as `fasta`, `index`, `bismark`, and `bwameth`. Its produced outputs are `fasta`, `index`, `bismark`, `bwameth`, `versions`, and `yml`.

---

## [1127] source=multitask_sft_big

**USER:** I have multiallelic records in my genomics dataset that I need to decompose into distinct lines. What user selection in `VCFbreakCreateMulti` should I configure?

**ASSISTANT:** You should configure the user selection to 'Break' in `VCFbreakCreateMulti`. This setting will break multiallelic VCF records into individual entries.

---

## [1128] source=multitask_sft_big

**USER:** In Scanpy cluster, embed, what does the resolution parameter do, and what is its default setting?

**ASSISTANT:** In `Scanpy cluster, embed`, the resolution parameter controls cluster granularity: higher resolution leads to finding more and smaller clusters. It defaults to a value of 1.0.

---

## [1129] source=multitask_sft_big

**USER:** I am preparing a run for Model-based Analysis of Genome-wide CRISPR-Cas9 Knockout (MAGeCK) count on my GeCKO screen fastq files. Can this tool be used to prioritize genes as well as sgRNAs?

**ASSISTANT:** Yes. MAGeCK is designed for prioritizing both single-guide RNAs (sgRNAs) and genes from genome-scale CRISPR-Cas9 knockout screen datasets.

---

## [1130] source=multitask_sft_big

**USER:** Here is my configuration request: I want to execute flowplots_ternary_plot_pfd using my summarized dataset stored at '/data/study_cohorts/pfd_summary_final.csv'. Can you extract the workflow parameters?

**ASSISTANT:** Extracted parameter configuration for `flowplots_ternary_plot_pfd`:
- `pfd_data.csv`: "/data/study_cohorts/pfd_summary_final.csv"

---

## [1131] source=multitask_sft_big

**USER:** I want to run foldseek_structure_search with query files queryA.pdb and queryB.cif against the AlphaFold DB target database staged on S3. How should the parameters be formatted?

**ASSISTANT:** You should set the parameters as follows:
- `query_structures`: "queryA.pdb,queryB.cif"
- `foldseek_db`: "AlphaFold DB"

---

## [1132] source=multitask_sft_big

**USER:** What outputs are generated when derfinder_feature_level_analysis is run with fullCov and genomicState?

**ASSISTANT:** The workflow generates three outputs: 'counts_matrix', 'de_table', and 'visualizations'.

---

## [1133] source=multitask_sft_big

**USER:** I am setting up nf-core/isoseq. I have subreads in 'samplesheet.csv', output to './results', primers in 'primers.fasta', annotation in 'genes.gtf', and I want to filter reads with min_passes 3 and rq 0.99. Extract the pipeline parameters.

**ASSISTANT:** Here are the extracted parameters for nf-core/isoseq:
- `input`: 'samplesheet.csv'
- `outdir`: './results'
- `primers`: 'primers.fasta'
- `gtf`: 'genes.gtf'
- `min_passes`: 3
- `rq`: 0.99

---

## [1134] source=multitask_sft_big

**USER:** What data inputs are defined for the deepsnv_shearwater_bayes_variant_calling workflow?

**ASSISTANT:** The workflow defines `test.bam` (alignment file for test sample) and `control.bam` (alignment file for control sample) as data inputs.

---

## [1135] source=multitask_sft_big

**USER:** What input data does the knowyourcg_continuous_data_sea workflow require, and is it optional?

**ASSISTANT:** The `knowyourcg_continuous_data_sea` workflow requires a non-optional input parameter named `named`, which must be a named numeric vector representing CpG probes with continuous values (e.g., beta values).

---

## [1136] source=multitask_sft_big

**USER:** Are there any adjustable parameters defined for the `uniprot_ws` workflow besides data inputs?

**ASSISTANT:** No, the `uniprot_ws` workflow defines no additional adjustable parameters (`parameters: []`), only requiring the `input_files` data input.

---

## [1137] source=multitask_sft_big

**USER:** I want to preprocess my raw Illumina array files located at '/data/methylation/idat_files/' using enmix_customized_preprocessing. Please configure the required input.

**ASSISTANT:** The parameter has been extracted for enmix_customized_preprocessing:
- directory: '/data/methylation/idat_files/' (directory path for raw IDAT files)

---

## [1138] source=multitask_sft_big

**USER:** Can you check the parameter specifications for the MSstatsPTM workflow and tell me if any optional runtime parameters need to be configured?

**ASSISTANT:** The MSstatsPTM workflow does not specify any configurable runtime parameters (`parameters: []`). It only requires the non-optional data input `input_files` of type `data`.

---

## [1139] source=multitask_sft_big

**USER:** What output formats does compepitools_genomic_region_annotation generate?

**ASSISTANT:** The compepitools_genomic_region_annotation workflow outputs results in three formats: table/csv, plot/pdf, and object/rds.

---

## [1140] source=multitask_sft_big

**USER:** What input data parameters does the `parody` workflow require?

**ASSISTANT:** The workflow requires one non-optional input parameter named `lead`. It is a data input described as a numeric vector of univariate measurements, such as tapping frequencies.

---

## [1141] source=multitask_sft_big

**USER:** Which Bioconductor packages and tools are utilized within the messina workflow?

**ASSISTANT:** The messina workflow utilizes the following tools: `bioconductor/messina`, `bioconductor/antiprofilesdata`, `bioconductor/ggplot2`, and `bioconductor/survival`.

---

## [1142] source=multitask_sft_big

**USER:** What threshold does `mad-max` control when running `cooler_balance`?

**ASSISTANT:** The `mad-max` parameter defines the cutoff for filtering out low-coverage bins, setting how many median absolute deviations (MAD) below the intra-chromosomal median log marginal sum a bin can fall before it is ignored during matrix balancing.

---

## [1143] source=multitask_sft_big

**USER:** I am configuring plot_taxa_summary for my 16S taxonomic profiling charts. How many categories are displayed on pie charts by default, and what happens to the remaining categories?

**ASSISTANT:** By default, `plot_taxa_summary` displays a maximum of 20 individual categories in each pie chart. All additional categories beyond this threshold are grouped into an 'other' category. Note that this threshold applies only to the pie charts.

---

## [1144] source=multitask_sft_big

**USER:** Where should the input amplitude files be provided for the `twoddpcr_custom_classification_integration` workflow?

**ASSISTANT:** The workflow accepts an input parameter named `data`, which is designated for a directory (such as `data/amplitudes`) containing raw amplitude CSV files exported from QuantaSoft.

---

## [1145] source=multitask_sft_big

**USER:** What are the expected data inputs and output formats for the edaseq transcriptomics workflow?

**ASSISTANT:** The 'edaseq' workflow accepts the following data inputs:
- `fastq`: directory or files of raw unaligned reads (FASTQ, optional)
- `bam`: aligned reads (BAM, optional)

It produces outputs in the following formats:
- `table/csv`
- `plot/pdf`
- `object/rds`

---

## [1146] source=multitask_sft_big

**USER:** In the plotlyblast tool, what parameter setting controls custom column header names for the tabular file, and what is its default behavior?

**ASSISTANT:** In plotlyblast, you can provide a comma-delimited list of column header names for the tabular file. The default setting is None, in which case default names (col1...coln) will be used.

---

## [1147] source=multitask_sft_big

**USER:** Given the following workflow config for tximport_gene_level_import_and_edger_limma:
Inputs:
- Transcript quant: raw_data/sample1/quant.sf.gz
- Annotation: annotations/tx2gene.gencode.v27.csv

Please extract and map these to the workflow's formal input parameters and indicate the expected outputs.

**ASSISTANT:** The extracted parameters mapped to the workflow requirements are:
- `quant.sf.gz`: `raw_data/sample1/quant.sf.gz` (Salmon quantification files)
- `tx2gene.gencode.v27.csv`: `annotations/tx2gene.gencode.v27.csv` (Transcript-to-gene mapping file)

Expected outputs upon workflow completion:
- `de_table`
- `visualizations`

---

## [1148] source=multitask_sft_big

**USER:** Here are my input datasets for the CiteFuse sample comparison analysis: control is located at `/data/cohortA_control_sce.rds` and disease sample is at `/data/cohortA_treated_sce.rds`. Please set up the workflow inputs.

**ASSISTANT:** The inputs for `citefuse_between_sample_analysis` have been extracted as follows:
- `sce_control.rds`: `/data/cohortA_control_sce.rds`
- `sce_disease.rds`: `/data/cohortA_treated_sce.rds`

---

## [1149] source=multitask_sft_big

**USER:** What are the required input data fields for the EnrichedHeatmap workflow?

**ASSISTANT:** The workflow requires `count_data`, which is passed to the declared input slot `input_files`.

---

## [1150] source=multitask_sft_big

**USER:** I am configuring metaseqr2_combine_p_values. I have a data frame called 'hg19pvalues' containing p-values from multiple algorithms. How should this be supplied?

**ASSISTANT:** You should map your data frame to the `hg19pvalues` parameter. It is a non-optional data input defined as a data frame containing p-values from different statistical algorithms.

---

## [1151] source=multitask_sft_big

**USER:** I need to sort the columns of my tabular file by header name, but my first column is 'Sample_ID' and it must stay on the far left. Which parameter handles this in 'Sort Column Order'?

**ASSISTANT:** You should use the optional 'Identifier column' parameter. Setting your key column (e.g., 'Sample_ID') as the Identifier column keeps it left-most rather than sorting it alphabetically among the other headers.

---

## [1152] source=multitask_sft_big

**USER:** Are there specific assumptions about the taxonomic hierarchy format when using qiime2 feature-classifier find-consensus-annotation?

**ASSISTANT:** Yes. The tool assumes that the semicolon-delimited hierarchical annotations have an even number of ranks.

---

## [1153] source=multitask_sft_big

**USER:** How do I configure the output format parameter for the Hmmer Eslreformat module in my configuration file?

**ASSISTANT:** For `Hmmer Eslreformat`, specify the desired output format within `ext.args` in your configuration file, ensuring that the format parameter is positioned as the final argument (it must come last). Refer to the tool's help documentation for the list of supported format values.

---

## [1154] source=multitask_sft_big

**USER:** Set up the IVIVE hepatic clearance analysis for human microsomal assay with an in vitro CLint of 18.5, plasma unbound fraction of 0.08, incubation unbound fraction of 0.75, using the well-stirred scaling model for compound 'CC(=O)Nc1ccc(O)cc1'.

**ASSISTANT:** Extracted parameters for the Ivive Hepatic Clearance workflow:
- clint_in_vitro: 18.5
- assay_type: "microsomal"
- species: "human"
- fu_plasma: 0.08
- fu_inc: 0.75
- scaling_model: "well-stirred"
- smiles: "CC(=O)Nc1ccc(O)cc1"

---

## [1155] source=multitask_sft_big

**USER:** What is the expected input format and parameter name for the microarray data in the peca_microarray_affy workflow?

**ASSISTANT:** The workflow expects an input named 'SpikeIn133', which must be provided as an RDS file containing an AffyBatch object with probe-level microarray data. It is a mandatory (non-optional) input.

---

## [1156] source=multitask_sft_big

**USER:** I have set up my analysis files: phenotypes in `case_control_vec.rds` (binary numeric vector), genotype matrix in `genotypes_num.mat`, and kinship in `kinship_mat.rds`. Map these to the inputs for the `bg2_binary_gwas` workflow.

**ASSISTANT:** Here is the parameter mapping for `bg2_binary_gwas`:
- `Y_binary`: `case_control_vec.rds`
- `SNPs`: `genotypes_num.mat`
- `kinship`: `kinship_mat.rds`

These satisfy the required inputs to generate `gwas_summary_statistics`.

---

## [1157] source=multitask_sft_big

**USER:** My proteomics run files contain the sample tags '_rep1', '_rep2', and '_rep3'. Please format this code list for NapQ.

**ASSISTANT:** For NapQ, the sample code list formatted as required is:
`_rep1,_rep2,_rep3`

---

## [1158] source=multitask_sft_big

**USER:** I want to map multiple annotation columns ('KEGG_ID' and 'Pathway_Name') from my lookup table to my target file in TermMapperTool. How should I enter this parameter?

**ASSISTANT:** In TermMapperTool, enter multiple term column names separated by a comma: `KEGG_ID,Pathway_Name` (or provide their corresponding column numbers).

---

## [1159] source=multitask_sft_big

**USER:** I am preparing the inputs for rsubread_bulk_rnaseq_junction_detection. The reference genome is located at '/references/GRCh38.fa' and my sequencing data is at '/data/sample_reads.bam'. Please extract these inputs.

**ASSISTANT:** Here are the extracted input parameters for `rsubread_bulk_rnaseq_junction_detection`:
- `genome.fa`: `/references/GRCh38.fa` (FASTA reference genome)
- `rnaseq`: `/data/sample_reads.bam` (RNA-seq data input)

---

## [1160] source=multitask_sft_big

**USER:** I ran `assign_taxonomy.py` and received a resulting text file with taxon-to-sequence mappings. Which parameter in `make_otu_table` receives this file?

**ASSISTANT:** You pass this file to the parameter specifying the path to taxonomy assignment in `make_otu_table`, which expects the text file containing the assignments of taxons to sequences resulting from `assign_taxonomy.py`.

---

## [1161] source=multitask_sft_big

**USER:** I need to run DockResultMerger on my docking output. I want to sort molecules by 'Chemgauss4' score and discard any results with scores above -6.5.

**ASSISTANT:** Extracted parameters for DockResultMerger:
- Property-tag name: `Chemgauss4` (used for sorting molecules)
- Upper score threshold filter: `-6.5` (molecules with scores above this value will be filtered out)

---

## [1162] source=multitask_sft_big

**USER:** Which input parameter holds the paths to the Affymetrix CEL files in the crlmm workflow?

**ASSISTANT:** The input parameter is `celFiles`, which accepts a vector of file paths pointing to raw Affymetrix .CEL files.

---

## [1163] source=multitask_sft_big

**USER:** I want to set custom transition and seed parameters for the ASAP Galaxy tool. Are these options available?

**ASSISTANT:** No. In the current Galaxy wrapper for ASAP (developed by F. Fischell in the iTaxoTools project), transition and seed parameters are not supported.

---

## [1164] source=multitask_sft_big

**USER:** What is the default threshold value for the minimum percent of cells in a cluster expressing above or below a marker's cutoff in Autoclustering analysis?

**ASSISTANT:** The default value is 0.95 (representing 95% of cells in a cluster expressing more or less than the cutoff value of the marker).

---

## [1165] source=multitask_sft_big

**USER:** Extract the inputs for Pbpk Disease State from our compound summary: Drug name is 'ATX-204', indication 'Type 2 Diabetes', logP of 2.8, unbound plasma fraction 0.08, volume of distribution 1.4 L/kg, renal clearance fraction 0.35, hepatic clearance fraction 0.65, not a high extraction ratio drug (false), and ADMET profile is in 'atx204_admet.json'.

**ASSISTANT:** Here are the extracted parameters for the Pbpk Disease State workflow:
- drug_name: "ATX-204"
- primary_indication: "Type 2 Diabetes"
- logP: 2.8
- fu_plasma: 0.08
- vd_lkg: 1.4
- cl_renal_fraction: 0.35
- cl_hepatic_fraction: 0.65
- high_extraction_ratio: false
- admet_json: "atx204_admet.json"

---

## [1166] source=multitask_sft_big

**USER:** I need to run idconvert on a list of files specified in 'id_files.txt'. I want the converted files written as pepXML into the directory './converted_ids/'. How should I set the command-line arguments?

**ASSISTANT:** You can map your requirements to `idconvert` using the following parameters:
- `-f` / `--filelist`: `id_files.txt`
- `-o` / `--outdir`: `./converted_ids/`
- `-e` / `--ext`: `pepXML`

Command example:
```bash
idconvert -f id_files.txt -o ./converted_ids/ -e pepXML
```

---

## [1167] source=multitask_sft_big

**USER:** Which option or flag sets the feature selection strategy when executing the FeatureSelector tool?

**ASSISTANT:** The type of feature selection to be performed is specified using the '-type' parameter.

---

## [1168] source=multitask_sft_big

**USER:** Here are my test parameters for the qiime2 stats wilcoxon-srt command: run against timedist.qza, compare to the baseline, set baseline group to 0, and use an asymptotic p-value approximation. How should the tool parameters be formatted?

**ASSISTANT:** Configure the parameters for `qiime2 stats wilcoxon-srt` as follows:
- `distribution`: `timedist.qza`
- `compare`: `baseline`
- `baseline_group`: `0`
- `p_val_approx`: `asymptotic`

---

## [1169] source=multitask_sft_big

**USER:** In the hmmcopy_matched_tumor_normal_correction workflow, what is the 'tumour.wig' input?

**ASSISTANT:** The 'tumour.wig' parameter is an input of type 'data' (described as a WIG file) containing tumor read counts per bin. It is marked as optional in the workflow parameters.

---

## [1170] source=multitask_sft_big

**USER:** Please pull dataset GSE227835 from GEO and prepare the pseudobulk aggregation outputs.

**ASSISTANT:** Extracted parameter for 'geo_scrna_pseudobulk':
- geo_accession: 'GSE227835'

---

## [1171] source=multitask_sft_big

**USER:** Configure the inputs for running `cftools_tissue_deconvolution_cfsort` using my sample file located at `/data/sample_cfsort_reads.txt.gz`.

**ASSISTANT:** Here is the configured input parameter for `cftools_tissue_deconvolution_cfsort`:

```json
{
  "cfsort_reads.txt.gz": "/data/sample_cfsort_reads.txt.gz"
}
```

---

## [1172] source=multitask_sft_big

**USER:** From this instruction, extract the transcript parameter value for 'Prepare riboSeqR input': 'Please restrict the downstream analysis only to transcripts NM_001001, NM_001002, and NM_001003.'

**ASSISTANT:** Following the formatting rules for 'Prepare riboSeqR input' (comma-separated with no quotes), the extracted value is:
`NM_001001,NM_001002,NM_001003`

---

## [1173] source=multitask_sft_big

**USER:** What parameter is required to configure the `Select last` tool?

**ASSISTANT:** You need to specify the number of lines to extract from the end of the dataset.

---

## [1174] source=multitask_sft_big

**USER:** What is the mandatory input parameter for `ontoproc_import_and_visualize_owl_ontology`?

**ASSISTANT:** The mandatory parameter is `url`, which requires a URL string pointing to an OWL ontology file (`optional: false`, `read_by_workflow: true`).

---

## [1175] source=multitask_sft_big

**USER:** Here are our project files for mitochondrial mutation lineage tracing: `mini_dataset.tsv.gz` and metadata `mini_dataset_cell_ann.csv`. Can you map these into the expected data inputs for scmitomut?

**ASSISTANT:** The parameters and input mappings for the `scmitomut` workflow are:
- `mini_dataset.tsv.gz`: Allele count table (containing columns `loc`, `cell_barcode`, `fwd_depth`, `rev_depth`, `alt`, `coverage`, `ref`)
- `mini_dataset_cell_ann.csv`: Cell annotation CSV file (containing cell barcodes and cell type metadata)

---

## [1176] source=multitask_sft_big

**USER:** I am using Mothur's Rarefaction.shared tool. Instead of standard sample randomization, I want to produce a collector's curve across samples. Which option should I set?

**ASSISTANT:** You should use the `jumble` option. While the default goal of rarefaction is to randomize across samples, setting the `jumble` option allows you to generate a collector's curve across samples.

---

## [1177] source=multitask_sft_big

**USER:** How does PPanGGOLiN projection handle spaces and special characters in genome file inputs?

**ASSISTANT:** PPanGGOLiN projection automatically replaces all special characters and spaces in genome files with underscores (`_`).

---

## [1178] source=multitask_sft_big

**USER:** Configure DiffDock for molecular docking with 40 inference steps and set the denoising steps to 30.

**ASSISTANT:** The extracted parameters for DiffDock are:
- Inference steps: 40
- Denoising steps: 30 (valid, as denoising steps must be less than or equal to inference steps).

---

## [1179] source=multitask_sft_big

**USER:** I am preparing my input matrix for `frenchfish_correct_manual_counts`. What formatting is required for `manual_counts`?

**ASSISTANT:** The required input `manual_counts` must be a matrix where columns represent distinct probes and rows represent individual nuclei. It must not contain an area column.

---

## [1180] source=multitask_sft_big

**USER:** Set up the deseq2_transformation_and_qc workflow using my dataset file located at 'experiments/deseq_dataset.rds'.

**ASSISTANT:** Extracted parameter configuration for `deseq2_transformation_and_qc`:
- `dds`: "experiments/deseq_dataset.rds" (DESeqDataSet object, type: rds, non-optional)

---

## [1181] source=multitask_sft_big

**USER:** What input data formats are accepted for user_methylation_data.RData in the remp workflow?

**ASSISTANT:** user_methylation_data.RData accepts a RatioSet, GenomicRatioSet, data.table, data.frame, DataFrame, or a matrix containing beta or M-values.

---

## [1182] source=multitask_sft_big

**USER:** In the 'Translate BED Sequences' tool, how does the tool handle early stop codons on the positive strand near the start coordinates?

**ASSISTANT:** The tool provides an option where it will not reject the translation if stop codons occur within a specified number of base pairs of the BED start position on the positive strand.

---

## [1183] source=multitask_sft_big

**USER:** What are the required input data and the resulting outputs for the `screencounter_dual_barcodes_single_end` workflow?

**ASSISTANT:** For `screencounter_dual_barcodes_single_end`:
- **Input**: A single-end FASTQ file containing dual barcodes (`dual_single.fastq` via the non-optional data parameter `tmp`).
- **Outputs**: Table/CSV (`table/csv`), PDF plot (`plot/pdf`), and an RDS object (`object/rds`).

---

## [1184] source=multitask_sft_big

**USER:** I want to extract specific profile HMMs using hmmfetch. How should I provide the target profile names to the tool?

**ASSISTANT:** The target profile names should be provided in a plain text file where the profile names are listed and separated by newlines, alongside specifying your target `<hmmfile>`.

---

## [1185] source=multitask_sft_big

**USER:** I have prepared my experimental files: 'col_annotations.tsv', 'dna_counts.tsv', and 'rna_counts.tsv'. Can you map them to the input parameters of `mpranalyze_scalable_comparative_analysis` and tell me what output to expect?

**ASSISTANT:** The inputs map directly as follows:
- `dna_counts.tsv` -> `dna_counts.tsv` (matrix of DNA counts)
- `rna_counts.tsv` -> `rna_counts.tsv` (matrix of RNA counts)
- `col_annotations.tsv` -> `col_annotations.tsv` (sample/column annotations)

The workflow produces `normalized_data` as its output.

---

## [1186] source=multitask_sft_big

**USER:** What data inputs are defined for the `bambu_custom_model_training_and_application` workflow?

**ASSISTANT:** The workflow defines two primary data inputs: `sample1.bam` (a required, well-annotated sample BAM file) and `annotations` (reference annotations).

---

## [1187] source=multitask_sft_big

**USER:** Run sitepath with my files: alignment is at /data/msa_proteins.fasta and tree is at /data/tree_rooted.newick.

**ASSISTANT:** Extracted inputs for the `sitepath` workflow:
- `alignment_file.fasta`: `/data/msa_proteins.fasta`
- `tree_file.newick`: `/data/tree_rooted.newick`

These will be passed to `bioconductor/sitepath` to generate the analyzed phylogenetic tree output.

---

## [1188] source=multitask_sft_big

**USER:** I am configuring DRAM: Download databases and already have the CAZy family activities file locally. What is the expected file name/parameter for it?

**ASSISTANT:** The expected input parameter is the absolute path to the CAZy family activities file, specifically named 'CAZyDB.07302020.fam-activities.txt' if already installed.

---

## [1189] source=multitask_sft_big

**USER:** Please set up profam_fitness_prediction using variants_input.csv as the input table and output the fitness scores in both csv and json formats.

**ASSISTANT:** Extracted configuration for `profam_fitness_prediction`:
- Input: `variants_input.csv` (format: CSV variant table)
- Output formats requested: `csv`, `json`
- Inference engine: ProFAM-1

---

## [1190] source=multitask_sft_big

**USER:** We want to run Admixture on our variant dataset. We have defined two source populations and our target set of admixed individuals, and we want to evaluate similarity using estimated genotypes.

**ASSISTANT:** I have extracted the following parameters for the Admixture tool:
- Number of source populations: 2
- Target individuals: Admixed individuals
- Similarity metric: Estimated genotypes

---

## [1191] source=multitask_sft_big

**USER:** I am configuring the HuBMAPR workflow. What data inputs does it accept, and is the count data mandatory?

**ASSISTANT:** The HuBMAPR workflow specifies one data input slot: `count_data`. According to the workflow parameters, `count_data` is marked as optional (`optional: true`) and is not read directly by the workflow.

---

## [1192] source=multitask_sft_big

**USER:** Please parse this compound info for the ICH S5 tox workflow: Candidate lead CP-409, SMILES 'CC(=O)NC1=CC=C(O)C=C1', MW 151.16 g/mol, LogP 0.46, human Cmax 1250 ng/mL, dose 10 mg/kg oral for rheumatoid arthritis in WOCBP population. Evaluating EFD in rat species.

**ASSISTANT:** Here are the extracted parameters for `ich_s5_reproductive_tox`:
- `compound_name`: CP-409
- `smiles`: CC(=O)NC1=CC=C(O)C=C1
- `molecular_weight`: 151.16
- `logP`: 0.46
- `human_cmax_ng_ml`: 1250
- `dose_mg_kg`: 10
- `route`: oral
- `indication`: rheumatoid arthritis
- `wocbp_population`: true (or applicable population flag)
- `species_efd`: rat
- `efd_segment`: true

---

## [1193] source=multitask_sft_big

**USER:** I want to design a combinatorial genetic library of size 500 using OptSynBioDes. Here are my files: parts.csv for the parts, genes.csv for the gene list. Save the output design to design.csv, the diagnostics to diag.csv, and the SBOL library to library.sbol.

**ASSISTANT:** I have extracted the following parameters for OptSynBioDes:
- `size`: 500
- `partsfile`: parts.csv
- `genesfile`: genes.csv
- `outfile`: design.csv
- `diagfile`: diag.csv
- `sbolfile`: library.sbol

---

## [1194] source=multitask_sft_big

**USER:** What input slots are required to run the `scp` workflow?

**ASSISTANT:** The `scp` workflow requires the following input:
- `input_files`: quantitative count data (declared Nextflow input slot, required, `optional: false`).

---

## [1195] source=multitask_sft_big

**USER:** What URL parameter is needed for the RGI Database Builder tool, and where can I find older releases?

**ASSISTANT:** The tool requires the URL for the CARD data (e.g., `https://card.mcmaster.ca/lastest/data`). Previous releases can be found at `https://card.mcmaster.ca/download`.

---

## [1196] source=multitask_sft_big

**USER:** I want to map genomic features from my regions file /data/exons.bed onto my variants file /data/sample_vars.vcf using VCFannotate. Which files correspond to the inputs?

**ASSISTANT:** The input mapping for VCFannotate is:
- VCF file: `/data/sample_vars.vcf` (provides the reference sequence records)
- BED file: `/data/exons.bed` (provides intervals/features for the intersection)

---

## [1197] source=multitask_sft_big

**USER:** Set up the inputs for the `mirtarrnaseq` pipeline using our dataset files `cohort_mrna.txt.gz` and `cohort_mirna.txt.gz`.

**ASSISTANT:** Here is the mapped parameter configuration for `mirtarrnaseq`:

```json
{
  "data_inputs": [
    {
      "name": "EBV_mRNA.txt.gz",
      "file": "cohort_mrna.txt.gz",
      "type": "matrix",
      "optional": false
    },
    {
      "name": "EBV_miRNA.txt.gz",
      "file": "cohort_mirna.txt.gz",
      "type": "matrix",
      "optional": false
    }
  ]
}
```

---

## [1198] source=multitask_sft_big

**USER:** Configure a PBPK run for compound 'Caffeine' (SMILES: Cn1cnc2c1c(=O)n(c(=O)n2C)C, MW 194.19 Da, logP -0.07, fu 0.65). Simulate an oral dose of 5 mg/kg in a healthy human population aged 30 years across 50 individuals.

**ASSISTANT:** Extracted parameters for `drug_discovery/pk_sim_pbpk`:

```json
{
  "compound_name": "Caffeine",
  "smiles": "Cn1cnc2c1c(=O)n(c(=O)n2C)C",
  "mw_da": 194.19,
  "logP": -0.07,
  "fu_plasma": 0.65,
  "dose_mg_kg": 5.0,
  "route": "oral",
  "population": "human",
  "age_years": 30,
  "n_individuals": 50
}
```

*Note: Remaining parameters (such as `pKa_acid`, `pKa_base`, `blood_plasma_ratio`, `lipophilicity_method`, `dissolution_model`, `bcs_class`, `indication`, and `organ_impairment`) can be supplied prior to executing Phase A.*

---

## [1199] source=multitask_sft_big

**USER:** What are the required input data parameters for the drawProteins workflow?

**ASSISTANT:** The `drawProteins` workflow declares an input slot named `input_files` (type: data), which is non-optional (`optional: false`) and read directly by the workflow.

---

## [1200] source=multitask_sft_big

**USER:** I need to run phmmer with my query file `targets.faa` against the reference database `swissprot.fasta`. Which parameters map to these files?

**ASSISTANT:** Parameters extracted for `phmmer`:
- `<seqfile>`: `targets.faa` (file containing query protein sequence(s))
- `<seqdb>`: `swissprot.fasta` (target protein sequence database)

---

## [1201] source=multitask_sft_big

**USER:** I want to set up decipher_fish_probe_design using my GenBank sequence file 'target_sequences.gb' and my reference SQLite database 'decipher_taxa.sqlite'. Please map these to the workflow inputs.

**ASSISTANT:** The workflow inputs map as follows:
- `gb`: `target_sequences.gb` (GenBank file of sequences)
- `dbConn`: `decipher_taxa.sqlite` (SQLite database connection path)

---

## [1202] source=multitask_sft_big

**USER:** I am preparing my data for amountain two-layer module detection. I have two adjacency matrices for the two networks (`layer1_weights.mat`, `layer2_weights.mat`), two differential score arrays (`pvals_l1.vec`, `pvals_l2.vec`), and an inter-network mapping matrix (`cross_links.mat`). How do these map to the workflow's input parameters?

**ASSISTANT:** Based on the required inputs for `amountain_two_layer_module_detection`, map your data as follows:
- `W1`: `layer1_weights.mat` (edge weight matrix for layer 1)
- `z1`: `pvals_l1.vec` (node score vector for layer 1)
- `W2`: `layer2_weights.mat` (edge weight matrix for layer 2)
- `z2`: `pvals_l2.vec` (node score vector for layer 2)
- `A`: `cross_links.mat` (inter-layer weight matrix connecting the two layers)

---

## [1203] source=multitask_sft_big

**USER:** Convert my Illumina SRF file to FASTQ format, and make sure you filter out any bad reads that failed QC.

**ASSISTANT:** Extracted parameter:
- Filter out bad reads (QC fail): True (QC failing reads marked in the SRF file will be excluded from FASTQ generation).

---

## [1204] source=multitask_sft_big

**USER:** What output file types and Bioconductor/R packages are utilized by the seahtrue workflow?

**ASSISTANT:** The `seahtrue` workflow outputs `table/csv`, `plot/pdf`, and `object/rds` files. It utilizes the packages `bioconductor/seahtrue`, `bioconductor/dplyr`, `bioconductor/ggplot2`, and `bioconductor/tidyverse`.

---

## [1205] source=multitask_sft_big

**USER:** Does the 'qcmetrics' workflow require raw mass spectrometer instrument files as its primary input?

**ASSISTANT:** No. According to the workflow definition, the required input is 'user_data.csv', which can be any tabular or numeric data to be evaluated for quality metrics.

---

## [1206] source=multitask_sft_big

**USER:** What are the required data input parameters and the tools invoked by the sevenc workflow?

**ASSISTANT:** The sevenc workflow requires the following data inputs:
- `motifs.hg19.CTCF.chr22`: A GRanges object (type `rds_granges`) containing CTCF motif locations with -log10 transformed p-values in the 'score' column.
- `GM12878_Stat1.chr22_1-30000000.bigWig`: A ChIP-seq signal bigWig file.

The workflow relies on two tools:
- `bioconductor/sevenc`
- `bioconductor/genomicinteractions`

---

## [1207] source=multitask_sft_big

**USER:** What inputs must I provide to run the funOmics workflow?

**ASSISTANT:** The `funOmics` workflow requires count data mapped to the non-optional input parameter `input_files` (type: data).

---

## [1208] source=multitask_sft_big

**USER:** I want to run `sixgill build` with an output named 'db_out', minimum ORF length set to 60, minimum tryptic peptide length of 7, and max reads capped at 500000. Which flags should I specify?

**ASSISTANT:** Based on your requirements, the extracted parameters for `sixgill build` are:
- `--out db_out`
- `--minorflength 60`
- `--minlongesttryppeplen 7`
- `--maxreads 500000`

---

## [1209] source=multitask_sft_big

**USER:** Please configure 'Get ontology by id' so that I can manually enter BioPAX ID 1522.

**ASSISTANT:** For the 'Get ontology by id' tool:
- Tick the manual entry checkbox: True
- Ontology ID: 1522 (BioPAX)

---

## [1210] source=multitask_sft_big

**USER:** I want to visualize my fusion events. I have filtered results from deFuse stored at 'defuse_833ke_results.filtered.tsv'. How should this be specified in chimeraviz_fusion_reads_alignment_and_plotting?

**ASSISTANT:** You can provide the file directly under the data input `defuse_833ke_results.filtered.tsv`, which represents the filtered output file from the deFuse fusion finder.

---

## [1211] source=multitask_sft_big

**USER:** What input parameters are defined for raw data files in crlmm_affy_simple_genotyping_gwas?

**ASSISTANT:** The workflow defines `celFiles` as a data input parameter, described as a vector of paths to raw Affymetrix .CEL files (marked as optional: true, read_by_workflow: false).

---

## [1212] source=multitask_sft_big

**USER:** I want to supply my count dataset file `h3k4me3_counts.tsv` to EpiCompare. Which input slot should I assign it to?

**ASSISTANT:** You should assign `h3k4me3_counts.tsv` to the `input_files` parameter under `data_inputs`, which is the declared non-optional input slot for `EpiCompare`.

---

## [1213] source=multitask_sft_big

**USER:** What are the exact inputs, tools, and outputs defined for the Fastq Align Bwaaln workflow?

**ASSISTANT:** The defined components for `Fastq Align Bwaaln` are:
- **Inputs**: `reads`, `index`
- **Tools**: `bwa/aln`, `bwa/sampe`, `bwa/samse`, `samtools/index`
- **Outputs**: `fastq`, `multiqc_report`

---

## [1214] source=multitask_sft_big

**USER:** I want to visualize my omics expression table using the seaborn tool with a box plot. Can you confirm if box plots are natively supported by this tool?

**ASSISTANT:** Yes, `seaborn` explicitly supports multiple plot types including box plots, bar plots, and scatter plots for tabular omics datasets.

---

## [1215] source=multitask_sft_big

**USER:** Can you check the parameter specifications for data inputs in the mixomics workflow?

**ASSISTANT:** The workflow defines one data input: 'expression_matrix.csv', which is of type 'matrix', is not optional ('optional': false), is read by the workflow ('read_by_workflow': true), and must be a numeric matrix containing samples in rows and variables in columns.

---

## [1216] source=multitask_sft_big

**USER:** I want to run `goexpress_custom_annotation_generation`. What exact input information do I need to supply?

**ASSISTANT:** You need to provide `ensembl_host_metadata`, which contains the Ensembl archive host URL and the dataset name corresponding to your target species.

---

## [1217] source=multitask_sft_big

**USER:** I need to run schex using my preprocessed Seurat object `pbmc_small` (containing PCA and TSNE reductions) and SingleCellExperiment `tenx_pbmc3k` (containing PCA and UMAP reductions) to generate single-cell visualization outputs.

**ASSISTANT:** I have extracted the following inputs for the schex workflow:
- `pbmc_small`: Seurat object with PCA and TSNE reductions (type: rds)
- `tenx_pbmc3k`: SingleCellExperiment object with PCA and UMAP reductions

The workflow will generate `singlecellexperiment`, `seurat_object`, and `visualizations` as outputs.

---

## [1218] source=multitask_sft_big

**USER:** Set up a comparison on single-cell log2(CPM+1) data evaluating 'treated' versus 'untreated' conditions across cells using the differential analysis tool.

**ASSISTANT:** Here is the extracted configuration for the **Perform a differential analysis** tool:

- **Input Expression Data**: Table of log2(CPM+1) single-cell gene expression values (cells as columns)
- **Omics Type**: Single-cell transcriptomics (scRNA-seq)
- **Comparison Design**: Two-group comparison (`treated` vs. `untreated`)

---

## [1219] source=multitask_sft_big

**USER:** I am configuring Expression2RAS for a transcriptomics assay and need to target the cleavage sites for BamHI, EcoRI, and TaqI.

**ASSISTANT:** Extracted restriction enzyme parameters:
- Enzymes: BamHI, EcoRI, TaqI

---

## [1220] source=multitask_sft_big

**USER:** I have mapped and filtered reads from HiCUP located at /data/sample_hicup.bam. Which input parameter in gothic_hicup_pipeline accepts this file?

**ASSISTANT:** You should supply the file to the `fileName` parameter, which is designated for mapped and filtered reads from HiCUP (marked as an optional data input in the pipeline specification).

---

## [1221] source=multitask_sft_big

**USER:** Please set up the chicago_genomic_interactions_downstream run using my files: my_chicago_results.rds for the processed interaction data and enhancer_elements.rds as the GRanges feature track from AnnotationHub.

**ASSISTANT:** Here are the extracted parameters and inputs for `chicago_genomic_interactions_downstream`:
- `cd`: `my_chicago_results.rds` (processed chicagoData object, RDS format)
- `enhancerTrack`: `enhancer_elements.rds` (GRanges object with genomic features)

---

## [1222] source=multitask_sft_big

**USER:** In the Column Join tool, what does the 'hinge' parameter define?

**ASSISTANT:** In Column Join, the 'hinge' specifies the number of left-most columns to match on across the files being joined.

---

## [1223] source=multitask_sft_big

**USER:** I want to run splatter. Here is my configuration: use my file 'pbmc_real_sce.rds' as the SingleCellExperiment container and 'matrix_counts.tsv' as the raw count matrix.

**ASSISTANT:** Extracted workflow parameters:
- `sce`: "pbmc_real_sce.rds" (SingleCellExperiment containing real scRNA-seq counts)
- `counts`: "matrix_counts.tsv" (integer matrix of real scRNA-seq counts)

---

## [1224] source=multitask_sft_big

**USER:** What is the mandatory input required by generegionscan_gene_region_analysis_and_visualization?

**ASSISTANT:** The workflow requires a single mandatory input: `exampleProbeLevelSet`, which must be provided as an RDS file (`type: rds`) containing a `ProbeLevelSet` object with probe intensities.

---

## [1225] source=multitask_sft_big

**USER:** What are the required input datasets and their formats for the heron_smoothed_probe_level_analysis workflow?

**ASSISTANT:** The workflow requires two mandatory data inputs:
1. `seq_ds_qn`: an RDS file containing a Quantile normalized HERONSequenceDataSet object (`optional: false`).
2. `probe_meta`: a data.frame mapping `PROBE_SEQUENCE` to `PROBE_ID`.

---

## [1226] source=multitask_sft_big

**USER:** Please map my files to the geneplast_network_rooting_mapping input specification: rooting results are in 'rooting_ogr.rds', gene-to-orthology mappings are in 'orthology_cogdata.txt', and the network is in 'interactome_ppi.rds'.

**ASSISTANT:** Here is the parameter mapping for `geneplast_network_rooting_mapping`:
- `ogr`: `rooting_ogr.rds` (processed OGR object containing rooting results, RDS format)
- `cogdata`: `orthology_cogdata.txt` (data frame mapping genes to orthologous groups and species)
- `ppi.gs`: `interactome_ppi.rds` (igraph network object)

---

## [1227] source=multitask_sft_big

**USER:** Please configure tpsvg_covariate_adjusted_model using my preprocessed dataset stored at '/data/experiments/visium_annotated_spe.rds'.

**ASSISTANT:** Extracted parameter configuration:

```json
{
  "spe": "/data/experiments/visium_annotated_spe.rds"
}
```

The input satisfies the required `rds` SpatialExperiment format containing raw counts, coordinates, and colData covariates.

---

## [1228] source=multitask_sft_big

**USER:** In Alleyoop, how do I generate separate BAM files for T>C reads versus non-T>C reads, and what is the default behavior?

**ASSISTANT:** To output BAM files separating T>C reads from non-T>C reads, set the read-separator option to `Yes`. By default, this option is set to `No`.

---

## [1229] source=multitask_sft_big

**USER:** What are the required input data slots and tool dependencies for the GEOfastq workflow?

**ASSISTANT:** The GEOfastq workflow uses the tool 'bioconductor/geofastq'. It defines a mandatory input slot named 'input_files' (type: data, optional: false, read_by_workflow: true) with declared workflow input type 'count_data'.

---

## [1230] source=multitask_sft_big

**USER:** What does the mapper radius of the large sphere parameter do in the rDock cavity definition tool?

**ASSISTANT:** In 'rDock cavity definition', the mapper radius of the large sphere (measured in angstroms) defines an outer boundary: rDock searches for cavities up to the small sphere but excludes the region extending to the large sphere.

---

## [1231] source=multitask_sft_big

**USER:** I want to run repviz. My experiment has sequencing alignments listed in 'samples_replicates.csv' and my annotation peaks in 'features_legend.csv'. How do these map to the workflow's input parameters?

**ASSISTANT:** Based on the specification for `repviz`, your files map to the following inputs:
- `BAM_input.csv`: 'samples_replicates.csv' (serves as the CSV containing BAM file paths and group names)
- `BED_input.csv`: 'features_legend.csv' (serves as the CSV containing BED file paths and legend names)

Ensure you also have the associated BAM/BAI and BED files available as required by the workflow.

---

## [1232] source=multitask_sft_big

**USER:** I have prepared the following files for batch correction: 'train_expression.csv' (normalized counts for the training cohort), 'test_expression.csv' (validation counts), and 'train_phenotype.csv' (phenotype labels). Map these to the `sva_frozen_sva_prediction` inputs.

**ASSISTANT:** The files map directly to the inputs for `sva_frozen_sva_prediction`:
- `train_expression.csv`: 'train_expression.csv' (matrix, training expression matrix)
- `test_expression.csv`: 'test_expression.csv' (matrix, test expression matrix)
- `train_phenotype.csv`: 'train_phenotype.csv' (training phenotype data containing class labels)

The workflow will output `de_table`.

---

## [1233] source=multitask_sft_big

**USER:** What optional log input files does the ngsreports_ngs_log_import_and_plotting workflow take for trimming and alignment summaries?

**ASSISTANT:** Based on the workflow parameters, it accepts optional data inputs including `Sample1.trimmomaticPE.txt` (a Trimmomatic log file) and `bowtiePE.txt` (a Bowtie log file).

---

## [1234] source=multitask_sft_big

**USER:** What are the required input datasets for the radiogx workflow and are any of them optional?

**ASSISTANT:** The radiogx workflow requires two mandatory data inputs: 'radiation_doses.csv' (radiation dose values in Gy; optional: false) and 'survival_fractions.csv' (corresponding cell viability/survival fraction measurements; optional: false). Neither is optional.

---

## [1235] source=multitask_sft_big

**USER:** What are the designated inputs and outputs for saser_aberrant_splicing_analysis?

**ASSISTANT:** The workflow takes data inputs such as genome annotation (`genes.mini.gtf`) and alignments (`A_C_0.bam`), and produces a differential expression table (`de_table`) as output.

---

## [1236] source=multitask_sft_big

**USER:** Please set up the exposure-response modeling workflow for my preclinical dataset 'pkpd_data.json'. I want to fit an Emax sigmoid Hill model evaluating exposure via AUC against the efficacy endpoint 'tumor_inhibition'. Target effect is set to 80% and the safety threshold exposure is 25.5 uM.

**ASSISTANT:** I have extracted the following parameters for the Exposure Response Modelling workflow:
- `er_data_json`: "pkpd_data.json"
- `er_model`: "Emax (sigmoid Hill)"
- `exposure_metric`: "AUC"
- `efficacy_endpoint`: "tumor_inhibition"
- `target_effect_pct`: 80
- `safety_exposure_uM`: 25.5

---

## [1237] source=multitask_sft_big

**USER:** I am configuring the pvca analysis. Please confirm what primary input parameter is needed and whether it is mandatory.

**ASSISTANT:** The required parameter for the `pvca` workflow is `ExpressionSet`. It represents the R object containing the gene expression matrix and sample metadata. Its `optional` flag is set to `false`, meaning it is mandatory for executing the workflow.

---

## [1238] source=multitask_sft_big

**USER:** Configure the inputs for the `selex` pipeline using metadata file `/data/exp1/sample_info.xml`, baseline pool `/data/exp1/R0_pool.fastq.gz`, and selection pool `/data/exp1/R2_pool.fastq.gz`.

**ASSISTANT:** Here is the extracted input configuration for the `selex` workflow:

```json
{
  "sample_annotation.xml": "/data/exp1/sample_info.xml",
  "R0.fastq.gz": "/data/exp1/R0_pool.fastq.gz",
  "R2.fastq.gz": "/data/exp1/R2_pool.fastq.gz"
}
```

---

## [1239] source=multitask_sft_big

**USER:** What are the required input files and configuration parameters for running the iCheck workflow?

**ASSISTANT:** The iCheck workflow requires an input data file provided to the slot 'input_files' (containing count data). It does not take any additional workflow parameters.

---

## [1240] source=multitask_sft_big

**USER:** Here are my input datasets for chromplot_histogram_density_profiling: UCSC gap table is at 'data/ucsc_hg19_gap.df', transcript annotations in 'data/transcripts.rds', upregulated list in 'de_pos.tsv', and downregulated list in 'de_neg.tsv'. Please set up the inputs.

**ASSISTANT:** I have extracted the parameters for `chromplot_histogram_density_profiling`:
- `hg_gap`: 'data/ucsc_hg19_gap.df'
- `txgr`: 'data/transcripts.rds'
- `DEpos`: 'de_pos.tsv'
- `DEneg`: 'de_neg.tsv'

---

## [1241] source=multitask_sft_big

**USER:** Set up cbaf_multiple_studies_analysis to examine TP53 and BRCA1 across 'tcga_brca' and 'tcga_ov'.

**ASSISTANT:** The workflow parameters extracted from your request are:
- `genes`: `{"genes": ["TP53", "BRCA1"]}` (named list of gene symbol vectors)
- `studies`: `["tcga_brca", "tcga_ov"]` (character vector of standard cBioPortal study names)
- Output: `visualizations`

---

## [1242] source=multitask_sft_big

**USER:** I want to run Filter cells data on my scRNA-seq count matrix. Please extract the filtering thresholds from my requirement: 'Discard any cell barcodes that show fewer than 250 detected genes or have fewer than 1,000 aligned reads.'

**ASSISTANT:** The extracted filtering parameters for 'Filter cells data' are:
- Minimum detected genes per cell: 250
- Minimum aligned reads per cell: 1,000

---

## [1243] source=multitask_sft_big

**USER:** Can I run the eximir workflow if I do not provide the Affymetrix CEL files?

**ASSISTANT:** No, the raw Affymetrix intensity data (`Affymetrix/*.CEL`) is designated with `optional: false`, meaning it is a mandatory input for the workflow.

---

## [1244] source=multitask_sft_big

**USER:** I want to run `chipseeker_peak_annotation_and_feature_distribution` with my peak file located at 'data/H3K27ac_peaks.bed'.

**ASSISTANT:** Extracted parameter for `chipseeker_peak_annotation_and_feature_distribution`:
- `files`: 'data/H3K27ac_peaks.bed' (BED file containing ChIP-seq peak coordinates)

---

## [1245] source=multitask_sft_big

**USER:** In Larch LCF, where does the label for the main data (target of the fit) come from if I leave it unset in the configuration?

**ASSISTANT:** If the label for the main data (target of the fit) is unset, it will automatically be taken from the Athena project metadata.

---

## [1246] source=multitask_sft_big

**USER:** I need to run cellmixs_comprehensive_metric_evaluation on my dataset saved at '/data/pbmc_integrated.rds'. Please prepare the workflow parameters.

**ASSISTANT:** Here are the extracted parameters for `cellmixs_comprehensive_metric_evaluation`:

```json
{
  "sce50": "/data/pbmc_integrated.rds"
}
```
`sce50` is provided as the required SingleCellExperiment RDS object containing single-cell RNA-seq data.

---

## [1247] source=multitask_sft_big

**USER:** Please set up meskit_metastatic_routes_and_neutrality with my dataset stored at cohort_maf.rds and driver genes listed in drivers.da.

**ASSISTANT:** I have extracted the following parameters for the 'meskit_metastatic_routes_and_neutrality' workflow:
- maf: cohort_maf.rds
- driverGene: drivers.da

---

## [1248] source=multitask_sft_big

**USER:** In the 'Link Name to KEGGID' metabolomics tool, what information do I need to specify for mapping gene symbols to KEGG IDs?

**ASSISTANT:** You need to specify the column name in your Gene Expression Annotation dataset that contains the Gene Symbols, which the tool will use to link to KEGGIDs.

---

## [1249] source=multitask_sft_big

**USER:** Please set up the marr workflow to run on my replicate feature matrix stored at 'counts_replicates.csv'.

**ASSISTANT:** Here is the parameter configuration for the marr workflow based on your input:

```json
{
  "abundance_matrix.csv": "counts_replicates.csv"
}
```

---

## [1250] source=multitask_sft_big

**USER:** I want to run the transcriptomics workflow `hyper`. What are the mandatory input files I need to configure?

**ASSISTANT:** The `hyper` workflow requires two mandatory data inputs:
1. `signature.txt`: A list of genes (optionally ranked or weighted) of type `list`.
2. `genesets.gmt`: A GMT file containing gene sets (such as custom sets or downloaded MSigDB gene sets).

---

## [1251] source=multitask_sft_big

**USER:** Please prepare the parameters for kebabs_grid_search_and_model_selection with sequences at 'data/transcripts.fasta' and target classifications at 'data/classes.txt'.

**ASSISTANT:** Here are the extracted input parameters for `kebabs_grid_search_and_model_selection`:
- `sequences.fasta`: "data/transcripts.fasta"
- `labels.txt`: "data/classes.txt"

---

## [1252] source=multitask_sft_big

**USER:** Which parameter setting controls the Harmony iteration limit in Scpred predict?

**ASSISTANT:** The setting is the maximum number of rounds to run Harmony, where each round consists of one clustering step and one correction step.

---

## [1253] source=multitask_sft_big

**USER:** What input and output data types are defined for the modality_triage workflow?

**ASSISTANT:** According to the workflow specification for 'modality_triage', the expected input type is ['string'] and the supported output formats are ['json', 'csv', 'txt'].

---

## [1254] source=multitask_sft_big

**USER:** What format is required for the `mirna_list.txt` parameter in the norce_mirna_enrichment_with_targets_and_coexpression workflow?

**ASSISTANT:** The `mirna_list.txt` parameter requires a plain text list containing miRNA names strictly in miRBase format.

---

## [1255] source=multitask_sft_big

**USER:** Configure planttfhunter_multi_species_tf_counting for my data directory located at /scratch/users/genomes/plant_fastas/.

**ASSISTANT:** Here is the parameter setting for `planttfhunter_multi_species_tf_counting`:
- `proteomes_directory`: "/scratch/users/genomes/plant_fastas/"

---

## [1256] source=multitask_sft_big

**USER:** I am configuring Seurat NormaliseData for my single-cell RNA-seq experiment. Please set the normalization method to CLR.

**ASSISTANT:** Parameter extracted:
- Method for normalization: 'CLR'

---

## [1257] source=multitask_sft_big

**USER:** I am configuring GAMMA-S for a metagenomic search and want to require a minimum nucleotide sequence identity of 95% in Blat. What flag should I use?

**ASSISTANT:** You should use the `-i` parameter set to an integer value of 95 (i.e., `-i 95`).

---

## [1258] source=multitask_sft_big

**USER:** I want to run `bnbc_hic_normalization_from_cooler`. What exact inputs must I supply to execute the workflow?

**ASSISTANT:** You must provide the following inputs:
- `cools`: A list of `.mcool` files containing the Hi-C data.
- `hg19`: BSgenome or genome seqlengths data.
- `colData(cgEx)`: A DataFrame containing sample covariates used for batch correction.

---

## [1259] source=multitask_sft_big

**USER:** Please review my run request: 'Extract all gene-level coordinates and attributes from Homo_sapiens.GRCh38.106.gtf, making sure mitochondrial features are flagged.' What parameters are configured?

**ASSISTANT:** From your request, the following parameters are extracted:
- Input file: Homo_sapiens.GRCh38.106.gtf (Ensembl GTF format)
- Feature level: gene
- Flag mitochondrial features: true

---

## [1260] source=multitask_sft_big

**USER:** I have a table of taxonomic counts from 16S rRNA gene sequencing across cohorts formatted as a TSV with samples as columns and taxa as rows. Can mmuphin process this directly?

**ASSISTANT:** Yes. `mmuphin` is designed specifically for this input structure: a TSV file where columns represent samples and rows represent abundance values of features (such as taxa). It natively supports 16S rRNA gene sequencing and microbial community profiling datasets.

---

## [1261] source=multitask_sft_big

**USER:** How does 'PACU - mapping' determine the sample name that gets propagated downstream, and what tag does it modify in the resulting alignment file?

**ASSISTANT:** 'PACU - mapping' derives the sample name directly from the input FASTQ filenames and writes it as a custom tag in the generated BAM file to propagate the sample identity to PACU within Galaxy.

---

## [1262] source=multitask_sft_big

**USER:** Please set up the CytoMDS generic workflow with my cell matrix list saved at `norm_expr_matrices` and my metadata data frame `sample_annotations`.

**ASSISTANT:** I have extracted the parameters for `cytomds_generic_expression_matrices`:
- `exprMatrixList`: norm_expr_matrices
- `phenoDataExpr`: sample_annotations

---

## [1263] source=multitask_sft_big

**USER:** Set up FROGSSTAT Phyloseq Import Data using /data/otu_table.biom, /metadata/samples.tsv, and /trees/phylogeny.nwk.

**ASSISTANT:** Here are the extracted parameters for FROGSSTAT Phyloseq Import Data:
- `biomfile`: `/data/otu_table.biom`
- `samplefile`: `/metadata/samples.tsv`
- `treefile`: `/trees/phylogeny.nwk`

---

## [1264] source=multitask_sft_big

**USER:** I am configuring BAM filter for my SAM file. I want to check uniqueness across the entire read. What value should I provide for the nucleotide cutoff parameter?

**ASSISTANT:** You should set the parameter to 0. In BAM filter, 0 indicates that uniqueness is checked along the entire read, whereas -1 disables filtering and a positive number like 10 filters reads based on uniqueness up to that Nth nucleotide from the 5' end.

---

## [1265] source=multitask_sft_big

**USER:** Looking at the `rbwa` workflow specifications, what are the names and types of the declared data inputs?

**ASSISTANT:** Based on the `rbwa` workflow definition, the declared data inputs are:
1. `reference.fa` (type: `fasta`, optional: true, read_by_workflow: false) – Reference genome FASTA file
2. `reads.fastq` (type: `fastq`) – Short-read sequencing FASTQ file

---

## [1266] source=multitask_sft_big

**USER:** I am configuring Chimera.uchime for my metagenomics dataset. I want chimeric calls to be shared such that if one group flags a sequence as chimeric, all groups treat it as chimeric. How should I set this parameter?

**ASSISTANT:** To ensure that a sequence flagged as chimeric by any single group is treated as chimeric across all groups, set the parameter to `false`.

---

## [1267] source=multitask_sft_big

**USER:** I am configuring covariates for CCQTL: Run genome scan. Can I specify 'Sex,Batch,Diet,Age'?

**ASSISTANT:** No. CCQTL: Run genome scan accepts at most three covariates (continuous or categorical). Specifying four covariates ('Sex,Batch,Diet,Age') exceeds this limit. Additionally, make sure that the names of the covariates you choose match the exact labels in your input covar file.

---

## [1268] source=multitask_sft_big

**USER:** Set up the inputs for the snprelate_fst_estimation workflow using the open GDS file object `gds_stream` and limit the analysis to sample IDs listed in `selected_cohort_samples`.

**ASSISTANT:** Here are the extracted parameters for `snprelate_fst_estimation`:
- `genofile`: `gds_stream`
- `samp.sel`: `selected_cohort_samples`

---

## [1269] source=multitask_sft_big

**USER:** Can you list the declared input slots and parameters for the rebook workflow?

**ASSISTANT:** The rebook workflow defines an optional data input slot named 'count_data' (which is not read by the workflow itself). It does not require or declare any additional parameters.

---

## [1270] source=multitask_sft_big

**USER:** Please extract the text from this article: https://example.org/papers/study_2023.pdf using extract_pdf_content.

**ASSISTANT:** Extracted parameter for `extract_pdf_content`:
- URL: `https://example.org/papers/study_2023.pdf`

The tool will fetch the PDF from this link and extract its text content.

---

## [1271] source=multitask_sft_big

**USER:** What output files and formats does the globaltest_goodness_of_fit_testing pipeline generate?

**ASSISTANT:** The workflow generates three output formats: a table ('table/csv'), a plot ('plot/pdf'), and an R data object ('object/rds').

---

## [1272] source=multitask_sft_big

**USER:** What is the default method used by heatmap2 to calculate distance or dissimilarity across rows and columns?

**ASSISTANT:** The default distance method used by `heatmap2` to compute dissimilarity between both rows and columns is `Euclidean`.

---

## [1273] source=multitask_sft_big

**USER:** What input slots and underlying tools are configured for the GA4GHshiny workflow?

**ASSISTANT:** The workflow uses 'bioconductor/ga4ghshiny'. Its declared input is 'count_data' (which is optional and not read by the workflow), with no additional parameters defined.

---

## [1274] source=multitask_sft_big

**USER:** What output files does the motifbreakr workflow produce once it finishes running?

**ASSISTANT:** The workflow produces three outputs: a CSV summary table (`table/csv`), a visualization plot in PDF format (`plot/pdf`), and an R data object (`object/rds`).

---

## [1275] source=multitask_sft_big

**USER:** Where do I obtain the submission template for Funannotate functional if I intend to submit my results to GenBank?

**ASSISTANT:** You can generate the submission template at https://submit.ncbi.nlm.nih.gov/genbank/template/submission/. If left empty, Funannotate functional uses a default template, but that default is not suitable for official submission to NCBI.

---

## [1276] source=multitask_sft_big

**USER:** Here are my run configurations for nf-core/variantcatalogue:
- Samplesheet: /project/cohort_wgs.csv
- Target directory: /project/results/catalogue
- Reference: hg38 (genome.fa at /refs/hg38.fa)
- Contact: admin@lab.org
- Report name: 'Cohort Variant Catalogue'
Extract the pipeline parameters.

**ASSISTANT:** Based on the provided details, the extracted parameters for `nf-core/variantcatalogue` are:
- `input`: "/project/cohort_wgs.csv"
- `outdir`: "/project/results/catalogue"
- `genome`: "hg38"
- `fasta`: "/refs/hg38.fa"
- `email`: "admin@lab.org"
- `multiqc_title`: "Cohort Variant Catalogue"

---

## [1277] source=multitask_sft_big

**USER:** I am setting up a Fasta Manipulation run with Sequence trimmer. Please note: I want to trim sequences that have varying quality using the standard default window size.

**ASSISTANT:** Extracted parameter for Sequence trimmer:
- window_size: 1 (default)

---

## [1278] source=multitask_sft_big

**USER:** What naming conventions and character restrictions apply to the Toolshed repository name when setting up a tool with toolfactory?

**ASSISTANT:** In toolfactory, the Toolshed repository name must contain only lower case letters, digits, and underscores. It should be chosen thoughtfully to avoid namespace clashes with other tool writers.

---

## [1279] source=multitask_sft_big

**USER:** Run mpfe on my dataset located at 'data/bisulfite_counts_cohort1.txt'.

**ASSISTANT:** I have extracted the input parameter for the mpfe workflow:
- `table_of_counts.txt`: "data/bisulfite_counts_cohort1.txt"

---

## [1280] source=multitask_sft_big

**USER:** What are the input requirements for running the 'xeva' workflow?

**ASSISTANT:** The workflow requires: 1) 'brca', a non-optional RDS file containing a XevaSet object with breast cancer PDX data; and 2) 'repdx', a XevaSet object containing replicate-based PDX experiments.

---

## [1281] source=multitask_sft_big

**USER:** I am preparing inputs for apalyzer_cds_gene_expression_analysis. Which parameters handle the RNA-seq alignments and the reference annotation database?

**ASSISTANT:** The workflow includes: 
- `flsall`: A list of RNA-seq BAM files (`type: list`, optional).
- `mm9.chr19.refGene.R.DB`: The reference gene annotation database object.

---

## [1282] source=multitask_sft_big

**USER:** I am running Combine Variants on several input VCFs where the sample identifiers overlap across files, and I want them combined into a single record while uniquifying the sample names.

**ASSISTANT:** Based on your criteria, the selected mode is:
- Operation mode: Merge (combines multiple records into a single record and uniquifies overlapping sample names).

---

## [1283] source=multitask_sft_big

**USER:** What are the input specifications for the organism_dplyr workflow?

**ASSISTANT:** The `organism_dplyr` workflow requires `count_data` supplied through the input slot `input_files` (type: data), which is a non-optional input read directly by the workflow.

---

## [1284] source=multitask_sft_big

**USER:** In the genomicdistributions_feature_distance_analysis workflow, is the queryFile.bed parameter optional, and what data does it expect?

**ASSISTANT:** No, `queryFile.bed` is not optional (`optional: false`). It expects a data file in BED format containing the genomic ranges of interest.

---

## [1285] source=multitask_sft_big

**USER:** In the `otubase_taxonomy_based_analysis` workflow, which of the input files are mandatory, and which are optional?

**ASSISTANT:** Mandatory inputs are:
- `sogin.groups` (Mothur groups file)
- `sogin.unique.fix.tax` (RDP fixed taxonomy file)
- `sogin.names` (Mothur names file for unique sequences)
- `sample_metadata.txt` (Sample metadata)

The only optional input is `sogin.fasta` (Optional FASTA file).

---

## [1286] source=multitask_sft_big

**USER:** I want to run ivive_hepatic_clearance with microsomal CLint of 18.5 uL/min/mg and standard MPPGL scaling. Can you format the required input structure?

**ASSISTANT:** The workflow accepts a JSON input format. Based on your parameters, the input configuration is:

```json
{
  "clearance_type": "microsomal",
  "cl_int": 18.5,
  "cl_int_unit": "uL/min/mg",
  "scaling_method": "MPPGL"
}
```
This JSON input will be processed by `ivive_hepatic_clearance` using the well-stirred liver model, and outputs will be provided in JSON and CSV formats.

---

## [1287] source=multitask_sft_big

**USER:** What parameters do I need to specify when running `qiime2 rescript get-unite-data`?

**ASSISTANT:** When running `qiime2 rescript get-unite-data`, you must supply a `version` number and a `taxon_group`. Additionally, you have options to set a `cluster_id` and choose whether to include singletons.

---

## [1288] source=multitask_sft_big

**USER:** What inputs and parameters do I need to supply to execute the Director workflow?

**ASSISTANT:** The Director workflow accepts 'count_data' through the mandatory data input 'input_files' (a declared .nf input slot). It does not require any additional configurable workflow parameters.

---

## [1289] source=multitask_sft_big

**USER:** Set up a target engagement kinetics analysis for our lead molecule with SMILES 'c1ccccc1NC(=O)C2CCNCC2', measured IC50 of 45.2 nM, and default 1-compartment PK parameters.

**ASSISTANT:** Here is the extracted input configuration for `target_engagement_kinetics`:

```json
{
  "smiles": "c1ccccc1NC(=O)C2CCNCC2",
  "IC50_nM": 45.2
}
```

This will solve the receptor occupancy ODEs using the Copeland kinetics model and generate CSV and JSON reports summarizing $k_{on}$, $k_{off}$, residence time, and dosing regimen feasibility.

---

## [1290] source=multitask_sft_big

**USER:** I am preparing the inputs for Netisce Step 10. Could you list the exact required inputs specified for this tool?

**ASSISTANT:** Netisce Step 10 requires two inputs:
1. Perturbation Attractors
2. Perturbation Attractors IDs that shifted to a different state

---

## [1291] source=multitask_sft_big

**USER:** I need to run 'Get Haplotypes From Phased VCF'. My phased variants are stored in `cohort_phased.vcf`, and I want all generated files to have the prefix `chr22_phased_haps`.

**ASSISTANT:** Here are the extracted parameters for `Get Haplotypes From Phased VCF`:
- **Input file (Phased VCF file)**: `cohort_phased.vcf`
- **Output file basename (Prefix for the output VCF file)**: `chr22_phased_haps`

---

## [1292] source=multitask_sft_big

**USER:** I want to run symmetry expansion in CryoSPARC on my reconstructed icosahedral virus particles. What inputs and parameters does the Symmetry Expansion workflow accept?

**ASSISTANT:** The workflow accepts inputs tagged with `symmetry`, `expand_symmetry`, and `use_cryosparc` to configure the symmetry group and expansion behavior, executing via the tool `SYMMETRY_EXPANSION`.

---

## [1293] source=multitask_sft_big

**USER:** I want to run find_sequence_mutations on my isolate sequence isolate_01.fa against ref_genome.fa. What inputs does the tool expect?

**ASSISTANT:** The tool expects two sequences: the query sequence (isolate_01.fa) and the reference sequence (ref_genome.fa) to compare and identify mutations.

---

## [1294] source=multitask_sft_big

**USER:** What output is produced by the loci2path_tissue_specificity_enrichment workflow?

**ASSISTANT:** The workflow generates `gwas_summary_statistics` as its primary output.

---

## [1295] source=multitask_sft_big

**USER:** How should I format the file path arguments for fasta and raw files when configuring Maxquant Lfq?

**ASSISTANT:** Paths to the fasta and raw files need to be marked by "PLACEHOLDER".

---

## [1296] source=multitask_sft_big

**USER:** I am configuring `msPurity.purityA` for metabolomics processing. I want to calculate precursor purity using the most intense peak in the isolation window rather than the mzML precursor metadata. How should I set this option?

**ASSISTANT:** You should set the corresponding flag to 'Yes' (true). This instructs `msPurity.purityA` to ignore the recorded precursor in the mzML file and evaluate purity based on the most intense peak detected inside the isolation window.

---

## [1297] source=multitask_sft_big

**USER:** I want to run VCFrandomSample to downsample my variant dataset, but I need the sampling probability to be scaled uniformly across allele frequencies based on the AF tag. How should I set this?

**ASSISTANT:** You can configure this by setting the advanced control parameter `--scale-by AF`. This scales the sampling probability by the AF field to provide uniform sampling across allele frequencies.

---

## [1298] source=multitask_sft_big

**USER:** What inputs do I need to supply to execute the Pharmacogenomics Pgx Report workflow?

**ASSISTANT:** The workflow requires three inputs: 'diplotypes', 'drug_list', and 'guidelines'.

---

## [1299] source=multitask_sft_big

**USER:** What are the input data parameters specified for greylistchip_bsgenome_workflow?

**ASSISTANT:** The workflow accepts a data input named `myBamFile.bam`, which is an optional data parameter representing the BAM file of the ChIP-seq input/control library.

---

## [1300] source=multitask_sft_big

**USER:** I have an integrated SingleCellExperiment object named `combined_integrated.rds` containing corrected embeddings, as well as a list of pre-integration SingleCellExperiment objects split by batch in `pre_batch_list.rds`. How do these map to `cellmixs_evaluate_and_compare_integration`?

**ASSISTANT:** They map to the workflow's required input parameters as follows:
- `sce20`: `combined_integrated.rds` (the SingleCellExperiment object containing integrated embeddings or corrected assays)
- `sce_pre_list`: `pre_batch_list.rds` (the list of individual SingleCellExperiment objects for each batch before integration, named by batch levels)

---

## [1301] source=multitask_sft_big

**USER:** Please set up the inputs for gmoviz_incremental_track_plotting using my files: align_out.bam for coverage and ideograms, and annotations_v1.gff3 for the genomic features.

**ASSISTANT:** Based on your provided files, here are the extracted inputs for `gmoviz_incremental_track_plotting`:
- `genome.bam`: `align_out.bam`
- `features.gff3`: `annotations_v1.gff3`

---

## [1302] source=multitask_sft_big

**USER:** For the total abundances input matrix in 'dimet bivariate analysis', what should the rows and columns represent?

**ASSISTANT:** In the matrix, the first column must contain unique Metabolite IDs, the subsequent columns correspond to the samples, and the rows correspond to the individual metabolites.

---

## [1303] source=multitask_sft_big

**USER:** I am evaluating acetaminophen toxicity in hepatocytes with Cmax of 150 uM, glucose at 5 mM, glutamine at 2 mM, 95% oxygen saturation, and IC50s: Complex I = 100 uM, Complex III = 250 uM, BSEP = 40 uM, and fatty acid oxidation = 80 uM. Prepare the inputs for virtual_cell/metabolic_flux_fba.

**ASSISTANT:** Here are the extracted parameters for `virtual_cell/metabolic_flux_fba`:

- `drug_name`: "acetaminophen"
- `cell_type`: "hepatocytes"
- `drug_smiles`: null
- `complex_i_ic50_uM`: 100
- `complex_iii_ic50_uM`: 250
- `bsep_ic50_uM`: 40
- `fat_oxidation_ic50_uM`: 80
- `cmax_uM`: 150
- `glucose_mM`: 5
- `glutamine_mM`: 2
- `oxygen_saturation`: 0.95

---

## [1304] source=multitask_sft_big

**USER:** I want to run the collapse tool on my ATAC-seq peak intervals. I need intervals matching the same position merged, but please also take strandness into account when collapsing them.

**ASSISTANT:** Based on your request, the parameters for `collapse` are:
- Genomic intervals: Provided ATAC-seq intervals
- Position matching: Collapsed on identical position
- Strandness: Specified (collapse only intervals sharing both the same position and strandness).

---

## [1305] source=multitask_sft_big

**USER:** Please set up Monocle3 plotCells to visualize my single-cell RNA dataset and color the cells according to their pseudotime ordering.

**ASSISTANT:** Extracted parameter for `Monocle3 plotCells`:
- Color mapping attribute: `pseudotime`

---

## [1306] source=multitask_sft_big

**USER:** Set up the demand workflow with my files: expression matrix at 'data/microarray_normalized.tsv', gene annotation map at 'annotations/probe_to_symbol.tsv', and PPI interactome at 'networks/string_interactions.tsv'.

**ASSISTANT:** The input parameters for the 'demand' workflow are configured as follows:
- exp.ext: 'data/microarray_normalized.tsv'
- anno.ext: 'annotations/probe_to_symbol.tsv'
- network.ext: 'networks/string_interactions.tsv'

---

## [1307] source=multitask_sft_big

**USER:** I am planning to run motiftestr_motif_enrichment_analysis. Which input datasets and objects do I need to prepare?

**ASSISTANT:** You need to provide the following inputs:
1. `ar_er_peaks`: A GRanges object of genomic peaks.
2. `zr75_enh`: A GRanges object of candidate enhancers.
3. `hg19_mask`: A GRanges object of masked genomic regions.
4. `BSgenome.Hsapiens.UCSC.hg19`: A BSgenome object.
5. `ex_pfm`: A list of position frequency matrices.

---

## [1308] source=multitask_sft_big

**USER:** Run the bounded online FDR workflow on my table stored at /data/pvalues_log.csv.

**ASSISTANT:** Extracted parameter for 'onlinefdr_online_fdr_bounded':
- sample.df: "/data/pvalues_log.csv" (must contain 'id', 'date', and 'pval' columns).

---

## [1309] source=multitask_sft_big

**USER:** In Scanpy PlotEmbed, my gene symbols are stored in adata.var['gene_symbols'] rather than the default index. How should I specify this parameter?

**ASSISTANT:** Set the gene symbols parameter field to `'gene_symbols'`. Leaving it blank would use the AnnData object's index by default.

---

## [1310] source=multitask_sft_big

**USER:** I need to run Ligand3DGenerator on my small molecule. I want to keep the existing 3D coordinates while re-protonating the compound based on pH. Which flag controls this behavior?

**ASSISTANT:** The flag preceded by `-k` retains the existing 3D coordinates while re-protonating the compound in a pH-dependent manner.

---

## [1311] source=multitask_sft_big

**USER:** Please unpack my dataset 'study_cohort_raw.pbed' using the decompiler tool and give the generated files the prefix label 'cohort_eur_2024'.

**ASSISTANT:** Here are the extracted parameters for **PBED decompiler**:

- **Input composite dataset**: `study_cohort_raw.pbed`
- **Output label**: `cohort_eur_2024`

The tool will generate `cohort_eur_2024.bed`, `cohort_eur_2024.bim`, and `cohort_eur_2024.fam`.

---

## [1312] source=multitask_sft_big

**USER:** I need to configure the 'Online data' extraction utility to download structures. By default, what file extensions does it extract, and how should custom formats be specified?

**ASSISTANT:** By default, 'Online data' extracts the following chemical file extensions:
- `sdf`
- `mol`
- `smi`
- `inchi`

If you provide a custom list of file extensions, each extension must be placed on a separate new line.

---

## [1313] source=multitask_sft_big

**USER:** What data input is required to run the mirnatap workflow, and what outputs does it generate?

**ASSISTANT:** The mirnatap workflow requires `mirna_name.txt` (a text file containing the miRNA name, such as 'miR-10b') as its input. It produces two outputs: `enrichment_results` and `pathway_results`.

---

## [1314] source=multitask_sft_big

**USER:** Set up an MLIP molecular dynamics simulation for my input coordinates 'protein_ligand.pdb' using the 'mace-mp-0' MLIP model at 310 K for 25000 steps. We're using the standard mlip_container image 'ghcr.io/lab/openmm-mlip:latest' and this is a production run, not a mock.

**ASSISTANT:** Here are the extracted parameters for the `mlip_md_simulation` workflow:

- **input_structure**: `"protein_ligand.pdb"`
- **mlip**: `"mace-mp-0"`
- **temperature_k**: `310`
- **n_steps**: `25000`
- **mlip_container**: `"ghcr.io/lab/openmm-mlip:latest"`
- **mock**: `false`

---

## [1315] source=multitask_sft_big

**USER:** What outputs can I expect to receive from running limma_filtering_unexpressed_probes?

**ASSISTANT:** The workflow outputs a differential expression table (`de_table`) and graphical plots (`visualizations`).

---

## [1316] source=multitask_sft_big

**USER:** I want to visualize oxygen distribution from my PhysiCell simulation using pcdl_plot_contour. Please set up the call for substrate 'oxygen'.

**ASSISTANT:** To visualize the oxygen substrate with `pcdl_plot_contour`, specify the substrate parameter as `'oxygen'`. The tool will generate a matplotlib contour (or contourf) plot with an included color bar for this chemical field.

---

## [1317] source=multitask_sft_big

**USER:** What outputs should I expect after running syncraft on a batch of SMILES strings?

**ASSISTANT:** The syncraft workflow produces outputs in `json`, `txt`, and `csv` formats, specifically returning a synthesis route JSON structure along with a human-readable text plan.

---

## [1318] source=multitask_sft_big

**USER:** What outputs can I expect from running the twilight_permutation_filtering workflow with my expression matrix and binary condition labels?

**ASSISTANT:** The workflow generates two primary outputs: `de_table` (differential expression results table) and `visualizations`.

---

## [1319] source=multitask_sft_big

**USER:** I need to run the `slalom` Nextflow workflow on my single-cell matrix located at `/data/sc_counts.tsv`. What parameter slots must be configured?

**ASSISTANT:** For the `slalom` workflow, you need to configure the required data input slot:
- `input_files`: `/data/sc_counts.tsv` (type: data, non-optional count data matrix).

---

## [1320] source=multitask_sft_big

**USER:** What outputs and software packages are associated with the `scbfa` pipeline?

**ASSISTANT:** The `scbfa` workflow produces three outputs: `singlecellexperiment`, `counts_matrix`, and `visualizations`. It utilizes the Bioconductor packages `scbfa`, `singlecellexperiment`, `ggplot2`, and `zinbwave`.

---

## [1321] source=multitask_sft_big

**USER:** I need to run sync_reads on forward.fq and reverse.fq, and I want to make sure unmatched singleton reads from both files are saved to separate outputs rather than discarded.

**ASSISTANT:** For `sync_reads`, provide the paired forward and reverse FASTQ files (`forward.fq` and `reverse.fq`) as inputs and enable the option to output singletons from each input file.

---

## [1322] source=multitask_sft_big

**USER:** What input parameters or data inputs are required by the fastLiquidAssociation workflow?

**ASSISTANT:** The `fastLiquidAssociation` workflow requires a mandatory data input named `input_files` (declared as `.nf input slot`, type: `data`, `optional: false`). It does not define any additional configurable parameters.

---

## [1323] source=multitask_sft_big

**USER:** In OpenSwathAssayGenerator, what specific unspecific neutral losses are permitted for detection fragment ions when enabling the neutral loss flag?

**ASSISTANT:** When setting the flag to allow unspecific neutral losses for detection fragment ions in OpenSwathAssayGenerator, the supported neutral losses are H2O1, H3N1, C1H2N2, and C1H2N1O1.

---

## [1324] source=multitask_sft_big

**USER:** What rationale and rule does hicAggregateContacts provide for configuring the minimum range parameter?

**ASSISTANT:** The rule for `hicAggregateContacts` is that the minimum range must be farther from the diagonal than the median TAD size. The scientific rationale is to minimize local background interaction noise.

---

## [1325] source=multitask_sft_big

**USER:** How does the Downsample SAM/BAM tool decide whether an individual primary read is kept?

**ASSISTANT:** Each read is evaluated against a probability P of being retained. If kept, its mate pair is also retained, whereas non-primary alignments are discarded.

---

## [1326] source=multitask_sft_big

**USER:** Please set up the guitar workflow using the transcript annotation database located at '/data/annotations/hg38_txdb.sqlite' and the feature files 'sampleA_peaks.bed' and 'sampleB_peaks.bed'.

**ASSISTANT:** I have extracted the parameters for the `guitar` workflow:
- `txdb_file`: "/data/annotations/hg38_txdb.sqlite"
- `stBedFiles`: ["sampleA_peaks.bed", "sampleB_peaks.bed"]

---

## [1327] source=multitask_sft_big

**USER:** In kmafft, what are the allowed options and default value for the nucleotide scoring matrix?

**ASSISTANT:** For nucleotide sequences in kmafft, the available scoring matrix options are '1PAM', '20PAM', and '200PAM', with '200PAM' being the default.

---

## [1328] source=multitask_sft_big

**USER:** What inputs do I need to prepare to run `randrotation_contrast_analysis_batch_correction`?

**ASSISTANT:** You need to provide two required inputs:
1. `edata`: A matrix of gene expression data with features (genes) as rows and samples as columns.
2. `pdata`: A dataframe containing phenotype annotations and batch information for each corresponding sample.

---

## [1329] source=multitask_sft_big

**USER:** I want to map AlphaMissense scores for UniProt entry P04637 to its predicted 3D structure using alphamissenser_protein_structure_visualization. Can you prepare the inputs?

**ASSISTANT:** Here is the configured input for the `alphamissenser_protein_structure_visualization` workflow:

```json
{
  "uniprot_id": "P04637"
}
```
This sets the required UniProt accession string to target protein P04637.

---

## [1330] source=multitask_sft_big

**USER:** What confidence threshold determines if a peptide group is included in the Distinct Peptide Summary export in ProteinPilot - GroupFileExtractor?

**ASSISTANT:** A peptide group is included if it has at least one hypothesis with at least 15% confidence.

---

## [1331] source=multitask_sft_big

**USER:** When configuring the coordinates for Dimont Data Extractor, how should the second coordinate value be supplied?

**ASSISTANT:** You should define the second genomic coordinate as either the relative position of the peak summit with respect to the Start coordinate, or as the peak's end position.

---

## [1332] source=multitask_sft_big

**USER:** What input datasets and outputs are defined for the `methimpute_binned_methylation_calling` workflow?

**ASSISTANT:** For `methimpute_binned_methylation_calling`:
- Inputs: `arabidopsis_bsseeker.txt.gz` (BSSeeker methylation extractor output file) and `arabidopsis_sequence.fa.gz` (FASTA reference genome file).
- Outputs: `table/csv`, `plot/pdf`, and `object/rds`.

---

## [1333] source=multitask_sft_big

**USER:** In the `multiple_rarefactions` tool, what does the required step size parameter control?

**ASSISTANT:** The required step size parameter defines the size of each step between the minimum and maximum sequences per sample (for example, generating levels at min, min+step, etc., for every level less than or equal to max).

---

## [1334] source=multitask_sft_big

**USER:** What outputs are generated upon executing rtopper_gse_then_integration?

**ASSISTANT:** The workflow produces two outputs: `enrichment_results` and `copy_number_segments`.

---

## [1335] source=multitask_sft_big

**USER:** I am running the 'Convert flowtext file to SCE' tool on my flow cytometry dataset. I only want to include CD3, CD4, and CD8 markers from my data. How should I configure the marker columns parameter?

**ASSISTANT:** In 'Convert flowtext file to SCE', specify your target markers as a comma-separated list for the columns parameter: `CD3,CD4,CD8`. Note that if left at default, the tool automatically includes all columns except FSC, SSC, time, and Live-dead.

---

## [1336] source=multitask_sft_big

**USER:** What are the required input parameters and data inputs for running feast_model_selection_and_visualization?

**ASSISTANT:** The inputs for feast_model_selection_and_visualization are:
- 'Y': a raw count expression matrix with genes as rows and cells as columns
- 'k': an integer specifying the number of clusters
- 'trueclass': a vector of true cell type labels for visualization.

---

## [1337] source=multitask_sft_big

**USER:** Here are my inputs for the flowpeaks pipeline: barcode = 'flow_matrix.tsv' (measurements matrix) and barcode.cid = 'gold_standard_ids.txt' (vector of cluster IDs). Please confirm these inputs.

**ASSISTANT:** Both required inputs are properly specified:
- 'barcode': numeric matrix or data frame of flow cytometry measurements ('flow_matrix.tsv')
- 'barcode.cid': vector of gold standard cluster IDs for evaluation ('gold_standard_ids.txt').

---

## [1338] source=multitask_sft_big

**USER:** Please set up apalyzer_three_utr_apa_analysis for my RNA-seq BAM files: sampleA.bam and sampleB.bam, using reference data file mm9_REF.RData.

**ASSISTANT:** I have extracted the parameters for 'apalyzer_three_utr_apa_analysis':
- flsall: ["sampleA.bam", "sampleB.bam"]
- mm9_REF.RData: "mm9_REF.RData"

---

## [1339] source=multitask_sft_big

**USER:** I want to launch the dual RNA-seq workflow with host genome host_hg38.fa, pathogen genome salmonella.fa, host annotation host.gff, single-end sequencing enabled, and outputs directed to /data/results. Please parse these into pipeline parameters.

**ASSISTANT:** Here are the extracted parameters for `nf-core/dualrnaseq`:
- `fasta_host`: host_hg38.fa
- `fasta_pathogen`: salmonella.fa
- `gff_host_genome`: host.gff
- `single_end`: true
- `outdir`: /data/results

---

## [1340] source=multitask_sft_big

**USER:** What inputs are required to run the indeed workflow?

**ASSISTANT:** The `indeed` workflow requires three inputs:
1. `data`: a matrix of expression levels with features as rows and subjects as columns.
2. `class_label`: a vector of group labels for each subject.
3. `id`: a vector of feature IDs.

---

## [1341] source=multitask_sft_big

**USER:** How should I format a list containing items with spaces when using QCShrinker, and what occurs if the list is left empty?

**ASSISTANT:** For QCShrinker, provide a space-separated list and surround items containing spaces with single quotes. If the list is left empty, the usual suspects will be removed.

---

## [1342] source=multitask_sft_big

**USER:** I want to configure r3cpet. Here are the files I have: 'HepG2_interactions.txt' for interactions, 'HepG2_TF.txt.gz' for TF peaks, and an optional expression table 'RPKMS'. Map these to the workflow inputs and tell me what outputs will be produced.

**ASSISTANT:** Here is the mapped input configuration for `r3cpet`:
- `HepG2_interactions.txt`: ChIA-PET interactions file (BED format, required)
- `HepG2_TF.txt.gz`: TFBS ChIP-Seq peaks file (4-column format, required)
- `RPKMS`: Gene expression data frame (optional)

The workflow will generate the following outputs:
- `network_graph`: The inferred protein-protein interaction network maintaining the chromatin loops.
- `visualizations`: Visual plots and figures representing the network.

---

## [1343] source=multitask_sft_big

**USER:** Configure the CTAT Centrifuge Indexes Data Manager to fetch the index automatically from the FTP site.

**ASSISTANT:** To trigger the automatic fetch of the index from the FTP link, configure the parameter:

- download: true

---

## [1344] source=multitask_sft_big

**USER:** What format should my array data be in for the vegamc workflow, and what output does it produce?

**ASSISTANT:** The input data should be a tab-delimited file (such as breast_Affy500K.txt or gist.txt) containing probe names, chromosomes, genomic positions, and LRR/BAF values per sample. The resulting output is copy_number_segments.

---

## [1345] source=multitask_sft_big

**USER:** I am configuring rMats turbo using the paired stats model. Does the differential splicing null hypothesis cutoff parameter apply to this run?

**ASSISTANT:** No, the cutoff used in the null hypothesis test for differential splicing does not apply to the paired stats model.

---

## [1346] source=multitask_sft_big

**USER:** In qiime2 rescript dereplicate, which parameter determines how duplicated sequences and taxonomic assignments are handled?

**ASSISTANT:** The handling of duplicated sequences and taxonomies is controlled by the `mode` parameter.

---

## [1347] source=multitask_sft_big

**USER:** Please set up lymphoseq for my project. The ImmunoSEQ output tables are stored in /data/immunoseq_runs/batch1/ and I have a metadata sheet at /data/immunoseq_runs/cohort_meta.csv.

**ASSISTANT:** The parameters extracted for the `lymphoseq` workflow are:
- `sample_folder`: "/data/immunoseq_runs/batch1/"
- `metadata.csv`: "/data/immunoseq_runs/cohort_meta.csv"

---

## [1348] source=multitask_sft_big

**USER:** Run sistr_cmd on my draft assembly to predict Salmonella serovar, but please make sure to use the full cgMLST database for the prediction.

**ASSISTANT:** Extracted parameter:
- Use full cgMLST database for serovar prediction: True (Note: this option is roughly 10X slower than the reduced centroid allele database with equivalent results).

---

## [1349] source=multitask_sft_big

**USER:** I have gnomad.genomes.vcf.gz as my reference set and want to verify variant expectations in my sequencing run. Can Htsnimtools Vcfcheck handle whole exome reference sets too?

**ASSISTANT:** Yes. Htsnimtools Vcfcheck is designed to take a background VCF like gnomAD with full genome coverage, but it also accommodates whole exome coverage depending on whether you are assessing exome or genome data.

---

## [1350] source=multitask_sft_big

**USER:** Here are my input parameters for `methtargetedngs_profile_hmm_analysis`: alignment file path is 'alignments/ref_msa.fasta' and query sequence path is 'samples/Tumor.fasta'. Please map these to the workflow inputs.

**ASSISTANT:** The inputs map to the workflow parameters as follows:
- `msa.fasta`: `alignments/ref_msa.fasta` (FASTA file of multiple sequence alignment)
- `Tumor.fasta`: `samples/Tumor.fasta` (FASTA file of query sequences)

---

## [1351] source=multitask_sft_big

**USER:** From which sources can the 'Load GenomicSuperSignature RAVmodels' tool retrieve reference models?

**ASSISTANT:** The 'Load GenomicSuperSignature RAVmodels' tool can fetch reference RAVmodels from Google Cloud, a direct URL, Galaxy History, or a server file.

---

## [1352] source=multitask_sft_big

**USER:** If I execute the rsubread workflow, what output formats and tool will it use?

**ASSISTANT:** The workflow uses the `bioconductor/rsubread` tool and generates three types of outputs: a tabular summary (`table/csv`), a visualization (`plot/pdf`), and an R data object (`object/rds`).

---

## [1353] source=multitask_sft_big

**USER:** How does the coverage cut-off ratio parameter work in the 'Filter SPAdes repeats' tool?

**ASSISTANT:** The coverage cut-off ratio parameter defines an average coverage ratio threshold. For instance, if the average assembly coverage is 100 and you set a coverage cut-off ratio of 0.5, any contigs with coverage below 50 (100 * 0.5) will be eliminated.

---

## [1354] source=multitask_sft_big

**USER:** In miRDeep2, what does the minimum read stack height option do, and how does it affect default estimation?

**ASSISTANT:** The minimum read stack height option sets the threshold that triggers miRDeep2 analysis. Manually setting this option disables the automatic estimation of the optimal value.

---

## [1355] source=multitask_sft_big

**USER:** I want to run geneplast evolutionary rooting. I have my orthology mapping table in cog_table.tsv, a species phylogenetic tree in tree.nwk (loaded as a phylo object), and human (NCBI taxon ID 9606) as the reference species.

**ASSISTANT:** The workflow parameters extracted from your inputs are:
- `cogdata`: "cog_table.tsv" (mapping genes to orthologous groups and species)
- `phyloTree`: "tree.nwk" (class 'phylo' phylogenetic tree)
- `spid`: "9606" (NCBI taxonomy ID for human reference)

---

## [1356] source=multitask_sft_big

**USER:** I am preparing an execution call for nf-core/evexplorer. Based on the pipeline's supported options, which configuration and input parameters can I provide?

**ASSISTANT:** According to the pipeline definition, nf-core/evexplorer supports the following parameters:
- `input`
- `outdir`
- `email`
- `multiqc_title`
- `genome`
- `fasta`
- `igenomes_ignore`
- `custom_config_version`
- `custom_config_base`
- `config_profile_name`

---

## [1357] source=multitask_sft_big

**USER:** What are the exact declared input and output components of the ggspavis_quality_control_plotting workflow?

**ASSISTANT:** The workflow accepts one required data input: 'spe' (type: rds, a SpatialExperiment object with calculated QC metrics in colData and rowData) and produces 'visualizations' as its output.

---

## [1358] source=multitask_sft_big

**USER:** What input data files are required to run the `qusage` workflow?

**ASSISTANT:** The `qusage` workflow requires two inputs:
1. `eset`: A matrix or ExpressionSet containing log2-normalized gene expression data (mandatory).
2. `gene_sets.gmt`: A GMT file containing the gene sets of interest.

---

## [1359] source=multitask_sft_big

**USER:** What data inputs and structures are required to execute the metaseq workflow?

**ASSISTANT:** The `metaseq` workflow requires three main inputs:
1. `BreastCancer`: A matrix of RNA-seq counts with genes as rows and samples as columns.
2. `flag1`: A vector specifying experimental conditions.
3. `flag2`: A vector specifying study identifiers.

---

## [1360] source=multitask_sft_big

**USER:** Configure REINVENT4 Generative Lead Design with the following settings: run scaffold hopping in scaffold_deco mode on GPU with 8 CPUs, starting from seed 'c1ccccc1O', running 500 steps, batch size of 64, learning rate 0.0005, and filtering out compounds exceeding MW of 450.

**ASSISTANT:** Here are the extracted parameters for the REINVENT4 Generative Lead Design workflow:

- mode: scaffold_deco
- seed_smiles: "c1ccccc1O"
- n_steps: 500
- batch_size: 64
- learning_rate: 0.0005
- max_mw: 450
- n_cpus: 8
- gpu: true

---

## [1361] source=multitask_sft_big

**USER:** What input data and tool packages are defined for the qsutils workflow?

**ASSISTANT:** For the qsutils workflow:
- Input data: 'Toy.GapsAndNs.fna' (a FASTA file of raw amplicon reads containing gaps or Ns).
- Tools: bioconductor/qsutils, bioconductor/biostrings, bioconductor/ape, bioconductor/ggplot2, and bioconductor/psych.
- Output formats: table/csv, plot/pdf, and object/rds.

---

## [1362] source=multitask_sft_big

**USER:** What output file formats can I expect upon completing the planet_ethnicity_prediction workflow?

**ASSISTANT:** The `planet_ethnicity_prediction` workflow produces three output types: tabular results (`table/csv`), visual plots (`plot/pdf`), and serialized R objects (`object/rds`).

---

## [1363] source=multitask_sft_big

**USER:** What inputs and parameters are declared for running the TargetDecoy workflow?

**ASSISTANT:** The TargetDecoy workflow accepts 'count_data' as input, provided via the mandatory data input slot named 'input_files' (read_by_workflow: true, optional: false). It does not declare additional workflow-specific tuning parameters.

---

## [1364] source=multitask_sft_big

**USER:** What input slots and parameters are configured for the genomics workflow `annotate`?

**ASSISTANT:** The `annotate` workflow accepts data inputs through the slot `input_files` (type: data, mandatory, read by the workflow). It accepts `count_data` as input, has no additional configurable parameters listed, and does not produce declared output files.

---

## [1365] source=multitask_sft_big

**USER:** I want to set up osat_prioritized_blocking_assignment using my metadata table stored at `/data/cohort_metadata.tsv` which lists our treatment groups and confounders.

**ASSISTANT:** For the `osat_prioritized_blocking_assignment` workflow, the required input is mapped as follows:
- `samples.txt`: `/data/cohort_metadata.tsv` (tab-delimited text file with biological and confounding variables)

Upon execution, the workflow will output `visualizations` of the balanced batch design.

---

## [1366] source=multitask_sft_big

**USER:** What is the required data input parameter for running the pdInfoBuilder workflow?

**ASSISTANT:** The required data input parameter for `pdInfoBuilder` is `input_files`, which supplies the count/design data needed by the workflow.

---

## [1367] source=multitask_sft_big

**USER:** What data inputs must be provided to run the rtpca_differential_tpca workflow?

**ASSISTANT:** The required data inputs are: tpp_control_data.RData (TPP dataset for the control condition), tpp_treatment_data.RData (TPP dataset for the treatment condition), and ppi_annotations.csv (a data frame containing known protein-protein interactions).

---

## [1368] source=multitask_sft_big

**USER:** I need to run segmentation using deformable shape models on my imaging dataset. I prioritize computational speed over global optimality, so I want to use the greedy pruning method with bounded error.

**ASSISTANT:** Based on your criteria, here is the selected pruning method configuration:
- Method: Deformable shape model segmentation
- Pruning algorithm: Robust graph pruning (greedy approach with provably bounded approximation error for faster runtime)

---

## [1369] source=multitask_sft_big

**USER:** What specific input data and outputs are defined for the scannotatr workflow?

**ASSISTANT:** The scannotatr workflow defines the following:
- Input: `tirosh_mel80_example` (a non-optional RDS file containing a Seurat object with single-cell RNA-seq data)
- Outputs: `singlecellexperiment` and `visualizations`

---

## [1370] source=multitask_sft_big

**USER:** Under what circumstance should I select the 'No packaged matrix output' option in Scanpy NormaliseData?

**ASSISTANT:** You should choose 'No packaged matrix output' when downstream processing generates auxiliary files (such as marker genes) and the normalized matrix itself does not need to be saved. However, you should avoid selecting this option if no other output files are being generated, as the tool would otherwise produce no output.

---

## [1371] source=multitask_sft_big

**USER:** What are the outputs and data structures expected by the inputs for 'carnival_inverse_carnival'?

**ASSISTANT:** The workflow produces 'pathway_results' as its output. It expects 'toy_measurements_ex2.RData' to be a named vector of measured TF/pathway activities, and 'toy_network_ex2.RData' to be a data frame containing prior knowledge network interactions.

---

## [1372] source=multitask_sft_big

**USER:** In 'Cell types - get empirical distribution', if I enable `include-sem-siml`, what criteria must the semantic similarity metric satisfy?

**ASSISTANT:** If `include-sem-siml` is set to True, you must ensure the selected semantic similarity metric is within the [0;1] interval (referencing the Onassis Bioconductor package documentation).

---

## [1373] source=multitask_sft_big

**USER:** I want to color my OTU network plot using the 'Treatment' and 'TimePoint' columns from my mapping file. How should these categories be formatted for make_otu_network?

**ASSISTANT:** For `make_otu_network`, the categories must match the column headers in the mapping file exactly and be separated by commas without spaces:
`Treatment,TimePoint`

---

## [1374] source=multitask_sft_big

**USER:** Please set up the mbqn workflow with my proteomics file located at 'data/log2_intensities.tsv', where proteins are rows and samples are columns.

**ASSISTANT:** I have extracted the required parameter for the mbqn workflow:
- `mtx`: 'data/log2_intensities.tsv'

---

## [1375] source=multitask_sft_big

**USER:** Set up stager_differential_transcript_usage with my gene q-values file 'dexseq_gene_qvals.rds', my transcript p-values 'tx_pvals.matrix', and gene mapping table 'transcripts_to_genes.tsv'.

**ASSISTANT:** Here are the extracted parameters for `stager_differential_transcript_usage`:
- `pScreen`: dexseq_gene_qvals.rds
- `pConfirmation`: tx_pvals.matrix
- `tx2gene`: transcripts_to_genes.tsv

---

## [1376] source=multitask_sft_big

**USER:** What organism codes are available as examples when configuring the KOBAS Annotate tool?

**ASSISTANT:** According to the KOBAS Annotate documentation, the supported example organism codes include:
- `ko` for KEGG Orthology
- `hsa` for Homo sapiens
- `mmu` for Mus musculus
- `dme` for Drosophila melanogaster
- `ath` for Arabidopsis thaliana
- `sce` for Saccharomyces cerevisiae
- `eco` for Escherichia coli K-12 MG1655

---

## [1377] source=multitask_sft_big

**USER:** Here is my configuration file content for pilot_parameters.txt: 'G0=10000, ER0=0.05, power=0.8, absMu1=1.0, sigmad=0.5, n=10'. Are all necessary parameters present for sizepower_matched_pairs_design?

**ASSISTANT:** Yes, all required parameters for sizepower_matched_pairs_design are present: G0 (10000), ER0 (0.05), power (0.8), absMu1 (1.0), sigmad (0.5), and n (10).

---

## [1378] source=multitask_sft_big

**USER:** Please set up a PBPK simulation for compound CC(=O)Oc1ccccc1C(=O)O. MW is 180.16, logP is 1.19, pKa is 3.5, fu_plasma is 0.15, fu_mic is 0.8, CLint is 4.5 uL/min/mg, renal clearance is 1.2 mL/min. It is not an OATP1B1 or Pgp substrate. Simulate an oral dose of 500 mg over 24 hours in an elderly population.

**ASSISTANT:** Here are the extracted parameters for the `Pbpk Simulation` workflow:
- `SMILES`: "CC(=O)Oc1ccccc1C(=O)O"
- `MW`: 180.16
- `logP`: 1.19
- `pKa`: 3.5
- `fu_plasma`: 0.15
- `fu_mic`: 0.8
- `CLint_uL_min_mg`: 4.5
- `renal_CL_mL_min`: 1.2
- `OATP1B1_substrate`: false
- `Pgp_substrate`: false
- `dose_mg`: 500
- `dose_route`: "oral"
- `simulation_hours`: 24
- `population`: "elderly"

---

## [1379] source=multitask_sft_big

**USER:** Which Bioconductor tools are integrated into the cytomds workflow?

**ASSISTANT:** The cytomds workflow integrates the following Bioconductor/R packages:
- `bioconductor/cytomds`
- `bioconductor/hdcytodata`
- `bioconductor/ggplot2`
- `bioconductor/patchwork`

---

## [1380] source=multitask_sft_big

**USER:** Configure InteractionConstraintDefiner so that docking ligands must interact with residue 57 on chain A and residue 120 on chain B.

**ASSISTANT:** Based on the required format `<chain-ID>:<residue-ID>`, the receptor residue IDs for InteractionConstraintDefiner are:
- `A:57`
- `B:120`

These constraints will enforce the minimal specified interactions between docking ligands and those specific receptor positions.

---

## [1381] source=multitask_sft_big

**USER:** What input file is specified for the `netsam_network_topological_analysis` workflow?

**ASSISTANT:** The workflow specifies `exampleNetwork.net`, which is a tab- or space-separated edge-list file representing a weighted network (defined as type `list`, optional).

---

## [1382] source=multitask_sft_big

**USER:** What input file formats does the ipo workflow accept for raw mass spectrometry data, and what output types does it generate?

**ASSISTANT:** The `ipo` workflow accepts raw LC-MS data files such as CDF, mzML, or mzXML format (passed as the `datafiles` character vector). It generates outputs in `table/csv`, `plot/pdf`, and `object/rds` formats.

---

## [1383] source=multitask_sft_big

**USER:** What required data inputs must I supply to execute the lea_ecological_association_lfmm2_least_squares workflow?

**ASSISTANT:** The workflow requires two mandatory matrix inputs:
1. 'Y': the genotype matrix.
2. 'X': the matrix representing environmental variables.

---

## [1384] source=multitask_sft_big

**USER:** Please set up the nanomethviz downstream export workflow using my saved object 'experiment_nanometh.rds'.

**ASSISTANT:** Extracted parameter for `nanomethviz_downstream_export_and_dim_reduction`:
- `nmr`: 'experiment_nanometh.rds' (NanoMethResult object in RDS format, required).

---

## [1385] source=multitask_sft_big

**USER:** What are the generated outputs from the `apl_step_by_step_apl` workflow upon completion?

**ASSISTANT:** The workflow produces two outputs: `enrichment_results` (containing GO enrichment results) and `visualizations` (including biplot visualizations).

---

## [1386] source=multitask_sft_big

**USER:** Can you configure the drug_discovery/patient_recruitment_feasibility workflow for our phase 2 trial in amyotrophic lateral sclerosis (Orphanet code 803)? We are planning a 24-month study aiming for 150 patients across 12 sites in France and Germany.

**ASSISTANT:** Here are the extracted parameters for `drug_discovery/patient_recruitment_feasibility`:
- `condition`: "amyotrophic lateral sclerosis"
- `orpha_code`: "803"
- `target_n`: 150
- `n_sites`: 12
- `trial_phase`: "Phase 2"
- `trial_duration_months`: 24
- `countries`: ["France", "Germany"]

---

## [1387] source=multitask_sft_big

**USER:** Please run the fastseg_expressionset_segmentation workflow using my input file at /data/arrays/chr_annotated_eset.rds.

**ASSISTANT:** I have extracted the required input parameter for the fastseg_expressionset_segmentation workflow:
- `eSet`: "/data/arrays/chr_annotated_eset.rds" (ExpressionSet RDS containing intensity data and chromosome/position annotations).

---

## [1388] source=multitask_sft_big

**USER:** I have a list of identifiers for a public dataset: PRJNA55555 (Study), SRX123456 (Experiment), and SRR789012 (Run). Can fastqdl accept these types of identifiers?

**ASSISTANT:** Yes. `fastqdl` is built to download FASTQ files associated with Study, Experiment, or Run accessions directly from public sequence archives.

---

## [1389] source=multitask_sft_big

**USER:** I want to run the meb workflow. I have a raw counts matrix `counts_matrix.tsv` (genes as rows, samples as columns) and a vector of indices `c(14, 52, 108, 250)` indicating my reference housekeeping genes. Can you extract the parameters for this workflow?

**ASSISTANT:** The extracted parameters for the `meb` workflow are:
- `countsTable`: `counts_matrix.tsv` (matrix of raw RNA-seq counts where rows are genes and columns are samples/replicates)
- `train_id`: `c(14, 52, 108, 250)` (vector of row indices representing known housekeeping genes)

---

## [1390] source=multitask_sft_big

**USER:** I am configuring a sequence masking step in VSearch. Which parameter must I set if I want to preserve soft masking for my query sequences instead of silently converting them to uppercase?

**ASSISTANT:** You should use the `--qmask soft` option. (Note that for database sequences, the corresponding option is `--dbmask`).

---

## [1391] source=multitask_sft_big

**USER:** What parameters does `qiime2 quality-control exclude-seqs` use to evaluate whether feature sequences hit or miss reference sequences?

**ASSISTANT:** It evaluates hits and misses using three alignment parameters: `perc_identity`, `evalue`, and `perc_query_aligned`.

---

## [1392] source=multitask_sft_big

**USER:** Here are my objects for the globaltest workflow: 'patient_survival_time' as a numeric vector representing clinical outcome, and 'gene_expression_matrix' containing covariate measurements. How should these be passed?

**ASSISTANT:** You can assign them to the workflow's mandatory data inputs:
- `Y`: patient_survival_time (numeric vector of response values)
- `X`: gene_expression_matrix (matrix of covariate measurements)

---

## [1393] source=multitask_sft_big

**USER:** I have an scRNA-seq expression matrix stored as a DelayedMatrix and a cell label vector. Which parameters in `adverscarial_vulnerability_overview` do these map to?

**ASSISTANT:** The scRNA-seq expression matrix (or DelayedMatrix) maps to the `counts_matrix.ext` input parameter, and your vector of cell-type labels maps to `cell_annotations.ext`.

---

## [1394] source=multitask_sft_big

**USER:** Please set up the gmoviz_feature_diagram_plasmid_map workflow using 'construct_annotated_regions.gff3' for my plasmid feature annotations.

**ASSISTANT:** I have extracted the parameter for the workflow:
- `plasmid_features.gff3`: "construct_annotated_regions.gff3"

---

## [1395] source=multitask_sft_big

**USER:** I am configuring a virtual screening run with the Shape alignment tool. Which parameters determine the scoring logic and output reporting criteria?

**ASSISTANT:** The evaluation and reporting are governed by the 'scoring scheme' (which defines the scoring function) and the 'cutoff' (which sets the score threshold, reporting only molecules scoring higher than this value).

---

## [1396] source=multitask_sft_big

**USER:** I am configuring `nf-core/rnasplice`. I have my samples defined in `samplesheet.csv`, my genome fasta at `ref.fa`, gene annotations at `genes.gtf`, and comparison groups in `contrasts.csv`. I want outputs in `./splice_out`. How do these map to the pipeline parameters?

**ASSISTANT:** Based on the pipeline parameters for `nf-core/rnasplice`, your inputs map as follows:
- `--input`: `samplesheet.csv`
- `--fasta`: `ref.fa`
- `--gtf`: `genes.gtf`
- `--contrasts`: `contrasts.csv`
- `--outdir`: `./splice_out`

---

## [1397] source=multitask_sft_big

**USER:** For my circadian physiological curve fitting with cosinor_model, I want to fit a rhythm with a 24-hour period, estimated mesor of 37.0, amplitude of 0.8, and peak acrophase at 15.5 hours.

**ASSISTANT:** Extracted parameters for `cosinor_model`:
- `mesor`: 37.0
- `amplitude`: 0.8
- `acrophase`: 15.5
- `period`: 24

These correspond to the model equation: `y = 37.0 + 0.8 * cos(2 * pi * (t - 15.5) / 24)`.

---

## [1398] source=multitask_sft_big

**USER:** What input slots are required to run the Dune workflow?

**ASSISTANT:** The Dune workflow requires the `input_files` data input slot, which accepts count data (`count_data`). It does not declare any additional parameters.

---

## [1399] source=multitask_sft_big

**USER:** What are the details for the `TxDb.Mmusculus.UCSC.mm10.knownGene` input in the `monalisa_motif_scanning_and_annotation` workflow?

**ASSISTANT:** In the `monalisa_motif_scanning_and_annotation` workflow, `TxDb.Mmusculus.UCSC.mm10.knownGene` has the following specifications:
- **Type:** rds
- **Optional:** true
- **Read by workflow:** false
- **Description:** TxDb object for promoter coordinates

---

## [1400] source=multitask_sft_big

**USER:** In QIIME 2, how do I configure 'qiime2 stats mann-whitney-u' for a pairwise comparison using asymptotic p-value approximation with 'refdist.qza' and 'timedist.qza'?

**ASSISTANT:** Set the parameters as follows:
- Set "distribution" to: refdist.qza
- Set "compare" to: all-pairwise
- In the additional options section, set "against_each" to: timedist.qza
- Set "p_val_approx" to: asymptotic

---

## [1401] source=multitask_sft_big

**USER:** In my OpenPepXLLF search configuration, my target-decoy FASTA database labels decoys with 'REV_' at the beginning of each identifier. How should this be configured?

**ASSISTANT:** Configure the decoy string parameter with 'REV_' and set the 'prefix' flag accordingly, indicating that the decoy indicator string is prefixed rather than appended to the protein database accessions.

---

## [1402] source=multitask_sft_big

**USER:** Please set up rscudo using our training matrix stored at 'cohortA_expr.tsv' and our test matrix 'cohortB_expr.tsv'.

**ASSISTANT:** Here are the extracted parameters for `rscudo`:
- `trainData`: 'cohortA_expr.tsv'
- `testData`: 'cohortB_expr.tsv'

---

## [1403] source=multitask_sft_big

**USER:** Here are my files for the projection: target_expression.csv containing my tumor cohort expression matrix, and reference_expression.csv containing the baseline dataset with the reference gene. Please set up the inputs.

**ASSISTANT:** I have mapped your files to the workflow inputs:
- target_expression.csv: 'target_expression.csv' (Matrix of gene expression values for target samples)
- reference_expression.csv: 'reference_expression.csv' (Matrix of gene expression values containing the reference gene)

---

## [1404] source=multitask_sft_big

**USER:** Here is the path to my compressed NMR raw datasets: s3://metabolomics-bucket/run1_nmr.zip. How does the alpsnmr_untargeted_nmr_metabolomics_classic workflow register this input?

**ASSISTANT:** The workflow accepts this input under the parameter name `zip_files`, which is defined as a data type input for Bruker NMR data directories/zip files (flagged as optional in the configuration).

---

## [1405] source=multitask_sft_big

**USER:** I have prepared three files for my enrichment run: 'candidates_list.txt' with my candidate gene set, 'my_go_map.tsv' containing my custom gene-to-GO mapping table, and 'my_coords.bed' with custom gene coordinates. How should these map to the gofuncr_custom_annotations_and_coordinates inputs?

**ASSISTANT:** Based on the input specifications of the gofuncr_custom_annotations_and_coordinates workflow, map your files as follows:
- candidate_genes.tsv: candidates_list.txt (dataframe with candidate genes)
- custom_annotations.tsv: my_go_map.tsv (dataframe with custom gene-to-GO mappings)
- custom_coordinates.tsv: my_coords.bed (dataframe with custom gene coordinates)

---

## [1406] source=multitask_sft_big

**USER:** What is the default placeholder used by merge_mapping_files in metagenomics when a field is missing across files?

**ASSISTANT:** The default value to represent missing data when fields are not defined across all mapping files in `merge_mapping_files` is `no_data`.

---

## [1407] source=multitask_sft_big

**USER:** I have an RDS file named 'pfm_collection.rds' containing a list of PFM objects ready for motif cloud generation. How should I assign this to motifstack_motif_cloud_and_signatures?

**ASSISTANT:** You should provide 'pfm_collection.rds' to the required data input parameter `pfms`, which expects an RDS file containing a list of PFM objects.

---

## [1408] source=multitask_sft_big

**USER:** I am configuring read end trimming in runAssembly. Which flag should I use to supply a FASTA file or database containing adapter and primer sequences?

**ASSISTANT:** You should use the `[-vt]` option in runAssembly. This option specifies a vector trimming database or a FASTA file of sequences (such as cloning vectors, primers, adapters, or other end sequences) to trim the ends of input reads.

---

## [1409] source=multitask_sft_big

**USER:** What options are available for specifying the method for computing master trees in jackknifed_beta_diversity, and what is the default?

**ASSISTANT:** In jackknifed_beta_diversity, the supported options for computing master trees are:
- 'consensus': calculates the consensus of trees from jackknifed OTU tables (this is the default).
- 'full': calculates the tree generated directly from the input (unsubsambled) OTU table.

---

## [1410] source=multitask_sft_big

**USER:** I am configuring RNAMassCalculator and I need the output to be formatted specifically as a CSV-like table. What value should I pass to the output format parameter?

**ASSISTANT:** You should set the output format parameter to 'table' to generate a CSV-like table.

---

## [1411] source=multitask_sft_big

**USER:** In the mosaics_one_sample_with_genomic_features workflow, what are the roles of 'chip_chr21.txt' and 'M_chr21.txt'?

**ASSISTANT:** In the `mosaics_one_sample_with_genomic_features` workflow:
- `chip_chr21.txt` represents ChIP bin-level data (data input).
- `M_chr21.txt` represents the genomic feature data (such as mappability scores) used to improve MOSAiCS statistical modeling.

---

## [1412] source=multitask_sft_big

**USER:** Run the Phase 0 docking validation for receptor 7RFS with nirmatrelvir SMILES 'CC1(C2C1C(N(C2)C(=O)C(C(C)(C)C)NC(=O)C(F)(F)F)C(=O)NC(CC3CCNC3=O)C#N)C', box center [10.5, -0.2, 22.1], box dimensions [20.0, 20.0, 20.0], exhaustiveness set to 16, producing 10 poses with an RMSD cutoff of 2.0 and seed 42.

**ASSISTANT:** Extracted parameters for the P0 Docking Validation workflow:
- pdb_id: '7RFS'
- ligand_smiles: 'CC1(C2C1C(N(C2)C(=O)C(C(C)(C)C)NC(=O)C(F)(F)F)C(=O)NC(CC3CCNC3=O)C#N)C'
- box_center: [10.5, -0.2, 22.1]
- box_size: [20.0, 20.0, 20.0]
- exhaustiveness: 16
- n_poses: 10
- rmsd_threshold: 2.0
- randomSeed: 42

---

## [1413] source=multitask_sft_big

**USER:** I want to extract feature genes using the Garnett tool. What exact input object does 'Garnett - get feature genes' require?

**ASSISTANT:** The tool requires the path to an object of class `garnett_classifier`, which must either be trained via `garnett_train_classifier.R` or obtained elsewhere.

---

## [1414] source=multitask_sft_big

**USER:** What input data parameters are declared in the Nextflow definition for MsBackendMsp?

**ASSISTANT:** The workflow declares a single data input slot named `count_data`, which is marked as optional (`optional: true`) and is not read by the workflow (`read_by_workflow: false`).

---

## [1415] source=multitask_sft_big

**USER:** What are the default window parameters used by fasta_to_gspan when breaking down input fragments?

**ASSISTANT:** By default, `fasta_to_gspan` considers window sizes of 40nt and 150nt with a window shift of 30% for each input fragment.

---

## [1416] source=multitask_sft_big

**USER:** What data input parameters are defined for the `icetea_tss_analysis_from_bams` workflow?

**ASSISTANT:** The `icetea_tss_analysis_from_bams` workflow defines the following data inputs in `data_inputs`:
- `embryo1.bam`: type `data`, optional `true`, read_by_workflow `false`, description 'Filtered BAM for sample 1'
- `embryo2.bam`: type `data`

---

## [1417] source=multitask_sft_big

**USER:** Is the `count_data` input required when running the gypsum workflow?

**ASSISTANT:** No, `count_data` is marked as optional (`optional: true`) and is not read directly by the workflow (`read_by_workflow: false`).

---

## [1418] source=multitask_sft_big

**USER:** Execute the vanillaice CNV calling workflow with the following parameters: cnSetExample: 'data/cohort_cnset_preprocessed.rds'.

**ASSISTANT:** Extracted parameter configuration for `vanillaice_cnv_calling_from_crlmm_cnset`:

```json
{
  "cnSetExample": "data/cohort_cnset_preprocessed.rds"
}
```

This `.rds` file will be coerced to a SnpArrayExperiment, wave-corrected, and segmented using the HMM to produce `copy_number_segments`.

---

## [1419] source=multitask_sft_big

**USER:** Set up the apalyzer_intronic_apa_analysis workflow using these files: my aligned BAM files are `sample1.bam`, `sample2.bam`, and `sample3.bam`, and my reference annotation file is `mouse_ref_mm9.RData`.

**ASSISTANT:** Here are the extracted parameters mapped to the workflow's inputs:
- `flsall`: `["sample1.bam", "sample2.bam", "sample3.bam"]` (list of RNA-seq BAM files)
- `mm9_REF.RData`: `mouse_ref_mm9.RData`

---

## [1420] source=multitask_sft_big

**USER:** Configure the genomicdistributions_signal_specificity_analysis workflow using my target regions file located at '/data/peaks/H3K27ac_regions.bed'.

**ASSISTANT:** The extracted input parameter for `genomicdistributions_signal_specificity_analysis` is:
- `queryFile.bed`: `/data/peaks/H3K27ac_regions.bed` (BED file containing genomic ranges of interest).

---

## [1421] source=multitask_sft_big

**USER:** I have prepared my gene expression matrix file `target_expression.csv` and my cluster definitions in `cluster_assignments.csv`. Please set these up for the projectr_clustering_projection workflow.

**ASSISTANT:** I have configured the input parameters for `projectr_clustering_projection`:
- `target_expression.csv`: "target_expression.csv" (Matrix of gene expression values)
- `cluster_assignments.csv`: "cluster_assignments.csv" (Cluster definitions or assignments for the genes/samples)

---

## [1422] source=multitask_sft_big

**USER:** Can you list the exact input files expected by the kmcut_cox_risk_prediction pipeline?

**ASSISTANT:** The pipeline requires three input files:
1. `expression_data_1.txt`: Tab-delimited training expression file.
2. `expression_data_2.txt`: Tab-delimited test expression file.
3. `survival_data.txt`: Tab-delimited survival file.

---

## [1423] source=multitask_sft_big

**USER:** I'm setting up the CTAT lncrna annotations Data Manager job and I want the tool to actively download the annotations from the website rather than just pointing to a local path. What parameter do I set?

**ASSISTANT:** Set the parameter `download` to `true`. When download is true, the tool downloads the CTAT lncRNA annotations directly from the website.

---

## [1424] source=multitask_sft_big

**USER:** What is the default threshold for the maximum base call error probability to consider a base high-quality in split_libraries_illumina?

**ASSISTANT:** The default value for the max base call error probability to consider high-quality in split_libraries_illumina is 1e-05.

---

## [1425] source=multitask_sft_big

**USER:** In Seal Recab Table, what specific configuration property defines the default read group for alignments missing an RG tag?

**ASSISTANT:** The configuration property is seal.recab.rg-covariate.default-rg, which sets the read group to assign to mappings without an RG tag.

---

## [1426] source=multitask_sft_big

**USER:** I am configuring AddMissingAtoms for protein structure preparation. Which parameter enables AMBER-based energy minimization for hydrogen atoms?

**ASSISTANT:** To enable AMBER force field energy minimization for hydrogen atoms in AddMissingAtoms, use the optional parameter `optimize_hydrogens` (flag `-opt_hyd`).

---

## [1427] source=multitask_sft_big

**USER:** What are the default filtering parameters for retention time range and m/z tolerance in the 'xcms plot raw' tool?

**ASSISTANT:** The 'xcms plot raw' tool uses a default m/z tolerance of 10 ppm and a default retention time range of 5 seconds.

---

## [1428] source=multitask_sft_big

**USER:** Please configure 'Get the descendent terms' to find all downstream terms under 'GO:0008150' using the ontology file 'go-basic.obo'.

**ASSISTANT:** Here are the extracted parameters for 'Get the descendent terms':
- Given term (existing ID): 'GO:0008150'
- Given OBO ontology: 'go-basic.obo'

The tool will return a list of descendant term IDs.

---

## [1429] source=multitask_sft_big

**USER:** Set up the input for the biosigner_multi_assay_experiment_analysis workflow using my file 'nci60_multiassay.rds'.

**ASSISTANT:** The input mapping for `biosigner_multi_assay_experiment_analysis` is:

- `nci.mae`: "nci60_multiassay.rds" (MultiAssayExperiment object containing multiple experiments and sample metadata).

---

## [1430] source=multitask_sft_big

**USER:** Please set up the inputs for tdbasedufeadv_multi_omics_sharing_features with our multi-omics list `omics_list_exp`, clinical dataframes `clin_dfs`, and sample barcodes `sample_barcodes`.

**ASSISTANT:** Here are the extracted workflow inputs for 'tdbasedufeadv_multi_omics_sharing_features':
- Multi: `omics_list_exp` (list of omics matrices sharing features)
- Clinical: `clin_dfs` (list of clinical metadata dataframes)
- Multi_sample: `sample_barcodes` (list of sample barcode dataframes)

---

## [1431] source=multitask_sft_big

**USER:** What are the valid choices for the OTU picking method in pick_otus, and what is the default setting?

**ASSISTANT:** The valid choices for the OTU picking method are: mothur, trie, uclust_ref, prefix_suffix, blast, cdhit, and uclust. The default choice is uclust.

---

## [1432] source=multitask_sft_big

**USER:** Configure the inputs for anota2seq_summarized_experiment_analysis using my file located at '/data/experiments/polysome_se.rds'.

**ASSISTANT:** Here is the configured input parameter for the workflow:

```json
{
  "mySummarizedExperiment": "/data/experiments/polysome_se.rds"
}
```

This maps your RDS file containing the SummarizedExperiment to the required `mySummarizedExperiment` input.

---

## [1433] source=multitask_sft_big

**USER:** I need to configure PrecursorNetwork to export my network graph. I prefer a format like JsonGraph or GML instead of the standard tabular edge list. Can it do that?

**ASSISTANT:** Yes. PrecursorNetwork supports GML and JsonGraph export options in addition to its default tabulated edge list and tabulated node list formats.

---

## [1434] source=multitask_sft_big

**USER:** Please configure the Repeated Dose Tox Prediction workflow for compound CC(=O)Nc1ccc(O)cc1 in rat via oral gavage. Set projected Cmax to 450 nM and alert severity threshold to high.

**ASSISTANT:** I have extracted the following parameters for the Repeated Dose Tox Prediction workflow:
- smiles_list: ["CC(=O)Nc1ccc(O)cc1"]
- species: "rat"
- dose_route: "oral gavage"
- projected_Cmax_nM: 450
- alert_severity_threshold: "high"

---

## [1435] source=multitask_sft_big

**USER:** For the `celaref_scrnaseq_to_microarray_comparison` workflow, identify the input files and their roles from this inventory:
- Directory: /data/10X_pbmc4k
- Microarray expression: /data/watkins_expression.txt
- Metadata: /data/watkins_samples.txt

**ASSISTANT:** The extracted workflow inputs are:
- Query scRNA-seq data: `10X_pbmc4k (directory containing 10X cellranger output)`
- Reference expression matrix: `watkins_expression.txt (normalized microarray expression matrix)`
- Reference metadata: `watkins_samples.txt (microarray sample sheet metadata)`

---

## [1436] source=multitask_sft_big

**USER:** What input parameters or data input slots need to be configured for the Rcollectl workflow?

**ASSISTANT:** The `Rcollectl` workflow declares an input slot named `count_data`, which is marked as optional (`optional: true`) and is not read directly by the workflow (`read_by_workflow: false`). There are no required parameters.

---

## [1437] source=multitask_sft_big

**USER:** For the `qubic_query_based_biclustering` pipeline, verify if `weight_matrix.csv` is optional and explain its expected format and biological purpose.

**ASSISTANT:** According to the workflow specification, `weight_matrix.csv` is not optional (`optional: false`). It must be provided as a matrix (CSV format) representing an adjacency matrix of interaction weights between genes, which provides external biological information (such as protein-protein interaction network weights) to guide the biclustering process.

---

## [1438] source=multitask_sft_big

**USER:** Here are my files for integration: 'CLL_data' containing a list of omics matrices for our cohort, and 'CLL_covariates' with sample clinical metadata. Are these the expected parameters for tdbasedufeadv_multi_omics_sharing_samples?

**ASSISTANT:** Yes, those match the workflow requirements exactly: 'CLL_data' (type: list, omics matrices sharing samples) and 'CLL_covariates' (sample metadata/covariates).

---

## [1439] source=multitask_sft_big

**USER:** I want to extract multiple alignments using mafFetch. What are the minimum format requirements for the input BED file?

**ASSISTANT:** The input BED file must have a minimum of 3 columns: `chrom`, `start`, and `end`.

---

## [1440] source=multitask_sft_big

**USER:** What input slots and data requirements are declared for the SIM workflow?

**ASSISTANT:** The `SIM` workflow declares one input slot: `count_data` (type: `data`), which is marked as optional (`optional: true`) and is not directly read by the workflow script (`read_by_workflow: false`). It produces no defined output slots.

---

## [1441] source=multitask_sft_big

**USER:** Here are my input paths: the HDF5 bsseq object directory is at `/data/bsseq_hdf5/` and the alignment M-bias file is at `/data/align/sample_mbias.txt`. Please map these to the `scmeth_step_by_step_qc_analysis` inputs.

**ASSISTANT:** Here is the mapped parameter configuration for `scmeth_step_by_step_qc_analysis`:
- `directory`: `/data/bsseq_hdf5/`
- `methylationBiasFile`: `/data/align/sample_mbias.txt`

---

## [1442] source=multitask_sft_big

**USER:** Which parameters define the target region in a Beacon2 Range query?

**ASSISTANT:** The target sequence range in a Beacon2 Range query is specified using three parameters: `reference_name`, `start`, and `end`.

---

## [1443] source=multitask_sft_big

**USER:** I need to set up `import_movies` for my CryoSPARC run with MRC files acquired at 300 kV, 0.832 Å/pixel, Cs of 2.7 mm, and a dose of 45 e-/Å². What parameters do these correspond to?

**ASSISTANT:** The extracted parameters for `import_movies` are:
- Format: MRC
- Voltage: 300 kV
- Pixel size: 0.832 Å/pixel
- Spherical aberration: 2.7 mm
- Total dose: 45 e-/Å²

---

## [1444] source=multitask_sft_big

**USER:** I am configuring the Compound Identification tool in metabolomics. What library parameter do I need to specify for compound names?

**ASSISTANT:** You need to specify the name of the column in your library file that contains the compound/adduct names to be used for identification.

---

## [1445] source=multitask_sft_big

**USER:** In Samtools merge, how can I specify a custom header file to replace the header that would normally be copied from the first BAM file?

**ASSISTANT:** You can provide a SAM-formatted file via the custom header parameter (FILE). Samtools merge will use the lines of FILE that start with `@` as the headers to be copied to `out.bam`, replacing any header lines that would otherwise be copied from `in1.bam`. Any alignment records in that FILE are ignored.

---

## [1446] source=multitask_sft_big

**USER:** Run the P0 Pharmacophore Validation workflow using PDB structure 7KI0 and set the AUC threshold to 0.70.

**ASSISTANT:** The parameters extracted for the `P0 Pharmacophore Validation` workflow are:
- `pdb_id`: "7KI0"
- `auc_threshold`: 0.70

---

## [1447] source=multitask_sft_big

**USER:** Configure PIMA: draw AMR matrix with best_hits='amr_hits.tsv', gene_drug_map='drug_map.txt', and include the deletions bed file 'del.bed'. We don't have a mutations file.

**ASSISTANT:** Here are the extracted parameters:
- best AMR feature hits: 'amr_hits.tsv'
- AMR gene drug mappings file: 'drug_map.txt'
- AMR deletions BED file: 'del.bed'
- AMR mutations TSV file: None

---

## [1448] source=multitask_sft_big

**USER:** What key parameters are required to run CalculateSolvationFreeEnergy on a PDB structure?

**ASSISTANT:** The key parameters for CalculateSolvationFreeEnergy are the dielectric constants used when solving the Poisson-Boltzmann equation for the electrostatic non-bonded energy.

---

## [1449] source=multitask_sft_big

**USER:** Please set up our siRNA off-target assessment for target gene BCL2 in Homo sapiens. The guide strand is 5'-UGAGUUCAUGUUCUUCUCCUU-3' and passenger strand is 5'-GGAGAAGAACAUGAACUCAUU-3'. Allow up to 1 seed mismatch, report the top 50 hits, and check strand bias.

**ASSISTANT:** Extracted parameters for the Sirna Offtarget Analysis workflow:
- `guide_strand`: "5'-UGAGUUCAUGUUCUUCUCCUU-3'"
- `passenger_strand`: "5'-GGAGAAGAACAUGAACUCAUU-3'"
- `target_gene`: "BCL2"
- `target_species`: "Homo sapiens"
- `seed_mismatch_tol`: 1
- `n_top_offtargets`: 50
- `strand_bias_check`: true

---

## [1450] source=multitask_sft_big

**USER:** I want to enable the option to add an index column in 'Remove counterions and fragments'. What input formats are required for this option to work?

**ASSISTANT:** The option to add an index column to the output file will work only when the input format is InChI or SMILES. For any other input format, this option is ignored.

---

## [1451] source=multitask_sft_big

**USER:** I want to run the PubChem Assay Downloader across several screening datasets, but I need to filter the assay results to keep only records where PUBCHEM_ACTIVITY_OUTCOME is set to 'Active'. Could you extract the relevant parameter settings from this request?

**ASSISTANT:** Based on your request, the extracted parameter is:
- **PUBCHEM_ACTIVITY_OUTCOME**: `Active`

---

## [1452] source=multitask_sft_big

**USER:** Please set up the Herg Cardiac Safety Qsar workflow for our candidate compound. The SMILES string is 'CC(=O)NC1=CC=C(O)C=C1', measured hERG IC50 is 12.5 uM, plasma free fraction is 0.15, dose is 250 mg, administered orally.

**ASSISTANT:** Here are the extracted parameters mapped to the workflow inputs:
- smiles_list: ["CC(=O)NC1=CC=C(O)C=C1"]
- measured_herg_ic50_uM: 12.5
- free_fraction_plasma: 0.15
- dose_mg: 250
- dose_route: "oral"

---

## [1453] source=multitask_sft_big

**USER:** Which tools and output types are defined in the snprelate workflow?

**ASSISTANT:** The `snprelate` workflow utilizes `bioconductor/snprelate` and `bioconductor/mass`. Its defined outputs are `gwas_summary_statistics` and `cluster_assignments`.

---

## [1454] source=multitask_sft_big

**USER:** What are the required input data slots for running the netZooR workflow?

**ASSISTANT:** The netZooR workflow requires count data supplied to the non-optional data input slot named 'input_files'.

---

## [1455] source=multitask_sft_big

**USER:** I want to run InclusionExclusionListCreator in my proteomics pipeline with `inclusion_strategy` set to `PreotinBased_LP`. What additional file parameter is required?

**ASSISTANT:** When `inclusion_strategy` is set to `PreotinBased_LP`, you must provide the `PTModel` file, which is used for the pt prediction of peptides in FASTA files.

---

## [1456] source=multitask_sft_big

**USER:** I want to harmonize the marker headers 'CD4_FITC', 'CD4-FITC', and 'CD4' across my flow cytometry batches using Remove, rearrange and/or rename columns.

**ASSISTANT:** For `Remove, rearrange and/or rename columns`, set the execution mode to batch mode and specify the 'Column headings' parameter as: `CD4_FITC, CD4-FITC, CD4`.

---

## [1457] source=multitask_sft_big

**USER:** Please set up the sampleclassifier_rnaseq_classification workflow with 'baseline_ref_matrix.tsv' as the reference expression data and 'patient_cohort_query.tsv' as our test set.

**ASSISTANT:** Here is the parameter assignment for `sampleclassifier_rnaseq_classification`:
- `rnaseq_refmat`: 'baseline_ref_matrix.tsv' (reference matrix with genes as rows and samples as columns)
- `rnaseq_testmat`: 'patient_cohort_query.tsv' (query matrix to be classified)

The workflow will output `visualizations` of the classification results.

---

## [1458] source=multitask_sft_big

**USER:** In homer_makeTagDirectory, how do I configure the minimum mapping quality threshold for unique reads, and what is its default value?

**ASSISTANT:** The parameter is `-mapq <#>`. Its default value is `10`. Setting it to a negative value configures HOMER to evaluate alignment tags using `AS:i:` and `XS:i:` instead.

---

## [1459] source=multitask_sft_big

**USER:** Here is my input for differential expression analysis: a count matrix named 'paired_patient_counts.tsv' containing paired counts across replicates. Which parameter should this be mapped to in bayseq_paired_data_beta_binomial?

**ASSISTANT:** The count matrix should be mapped to the mandatory parameter 'pairData', which expects a matrix of paired counts.

---

## [1460] source=multitask_sft_big

**USER:** I want to copy my dataset to Hadoop using the default environment variable path. What does the tool look for?

**ASSISTANT:** The tool will check the `HADOOP_GALAXY_PUT_DIR` environment variable to determine the path under which the data will be copied to a new directory.

---

## [1461] source=multitask_sft_big

**USER:** I want to run Bioentity Set Get Over Representation for genes 6295, 1258, and 3614.

**ASSISTANT:** The entity IDs parameter extracted for `Bioentity Set Get Over Representation` is: `NCBIGene:6295,NCBIGene:1258,NCBIGene:3614`.

---

## [1462] source=multitask_sft_big

**USER:** Here are my input files for gene zygosity prediction:
- Indexed alignment: tumor_aligned.bam
- Phasing variants: snp_calls.vcf
- Somatic CNA ranges: scna_segments.rds
- Somatic SNVs: som_vars.rds
- Germline SNVs: germ_vars.rds
- Gene annotations: ensembl_model.rds
- Haploblocks: blocks.rds

How do these map to the workflow inputs?

**ASSISTANT:** The files map to the `zygositypredictor_gene_zygosity_prediction` inputs as follows:
- `FILE_BAM`: tumor_aligned.bam
- `VCF`: snp_calls.vcf
- `GR_SCNA`: scna_segments.rds
- `GR_SOM_SMALL_VARS`: som_vars.rds
- `GR_GERM_SMALL_VARS`: germ_vars.rds
- `GR_GENE_MODEL`: ensembl_model.rds
- `GR_HAPLOBLOCKS`: blocks.rds

---

## [1463] source=multitask_sft_big

**USER:** I want to run mBPCR estimation on my dataset saved at '/data/sample_oligoset.rds'. Can you parse the necessary input configuration for mbpcr_oligosnpset_profile_estimation?

**ASSISTANT:** Here is the parameter configuration extracted for the workflow:

```json
{
  "oligoSet": "/data/sample_oligoset.rds"
}
```

This maps your RDS file to the required `oligoSet` input.

---

## [1464] source=multitask_sft_big

**USER:** In Fastqc Site, I need to supply a custom list of adapter sequences. What format must the file follow, and how are comments handled?

**ASSISTANT:** The custom adapter file for Fastqc Site must contain tab-delimited named adapter pairs formatted as `name[tab]sequence`. Any lines prefixed with a hash (`#`) are treated as comments and will be ignored.

---

## [1465] source=multitask_sft_big

**USER:** I have raw metabolite measurements from study subjects stored in 'exp_abundance.csv' with batch tags, and technical QC pool runs in 'qc_pool.csv' with run order. Map these to `metabomxtr_mixture_model_normalization` inputs.

**ASSISTANT:** The mapping to the `metabomxtr_mixture_model_normalization` input files is:
- `experimental_samples.csv`: `exp_abundance.csv` (contains raw experimental metabolite abundances and batch/phenotype covariates)
- `control_samples.csv`: `qc_pool.csv` (contains raw quality control pool abundances, batch, and run order covariates)

---

## [1466] source=multitask_sft_big

**USER:** I need to run CCQTL refine_region. My cross data is in 'cross.rds', kinship matrix is 'k_loco.rds', genotype probabilities are in 'pr_clean.rds', peaks file is 'peaks.csv', annotations are in '/data/annot/', and I want a peak width of 3 with top 5 SNPs.

**ASSISTANT:** Here are the extracted parameters formatted for `ccqtl refine_region`:

```bash
ccqtl refine_region \
  --crossdata cross.rds \
  --kloco k_loco.rds \
  --clean_pr pr_clean.rds \
  --peaks peaks.csv \
  --width_p 3 \
  --k_top_snps 5 \
  --annotations_path /data/annot/
```

---

## [1467] source=multitask_sft_big

**USER:** Please set up the Polymorph Stability Screening workflow for the candidate molecule 'Cmpd-101' with SMILES 'CC(=O)NC1=CC=C(O)C=C1', intended for the 'oral' route with excipients 'microcrystalline cellulose, magnesium stearate'.

**ASSISTANT:** Here are the extracted parameters for the Polymorph Stability Screening workflow:
- `drug_name`: "Cmpd-101"
- `smiles`: "CC(=O)NC1=CC=C(O)C=C1"
- `intended_route`: "oral"
- `excipients`: "microcrystalline cellulose, magnesium stearate"

---

## [1468] source=multitask_sft_big

**USER:** I want to run ebseq_gene_de_multi_conditions. Here are my files: 'raw_counts_all_groups.csv' containing my raw counts across 4 conditions, and 'sample_condition_vector.csv' defining the condition labels for each sample. Please map these to the workflow inputs.

**ASSISTANT:** Based on your provided files, the mapping for `ebseq_gene_de_multi_conditions` is:
- `multi_condition_gene_counts.csv`: raw_counts_all_groups.csv
- `multi_conditions.csv`: sample_condition_vector.csv

---

## [1469] source=multitask_sft_big

**USER:** Please set up matrixrider using my promoter region file 'promoter_enhancer.fasta' and the JASPAR database counts 'pfm_jaspar_core.rds'.

**ASSISTANT:** Here is the parameter assignment for the `matrixrider` workflow:

- `sequence.fasta`: `promoter_enhancer.fasta` (DNA sequence of interest)
- `jaspar_db`: `pfm_jaspar_core.rds` (JASPAR database or custom PFM counts)

Both mandatory data inputs are defined and ready for execution.

---

## [1470] source=multitask_sft_big

**USER:** Please configure knowyourcg_gene_linkage_and_go using probe list cpg_ids.txt containing CpG probe IDs.

**ASSISTANT:** Extracted parameter for `knowyourcg_gene_linkage_and_go`:
- `character`: "cpg_ids.txt" (character vector of CpG probe IDs)

---

## [1471] source=multitask_sft_big

**USER:** Does the MultiAssayExperiment workflow strictly require `count_data` as a mandatory input file to run?

**ASSISTANT:** No, the `count_data` input slot is marked as optional (`"optional": true`) in the workflow definition.

---

## [1472] source=multitask_sft_big

**USER:** I need to run `bayesknockdown_bayes_knockdown_diff_exp`. Here are my two files: `treated_expression.csv` (condition 1 matrix with genes as rows and samples as columns) and `control_expression.csv` (condition 2 matrix with genes as rows and samples as columns). How should these map to the workflow inputs?

**ASSISTANT:** The workflow requires the following mapping:
- `condition1_matrix.csv`: `treated_expression.csv` (matrix of gene expression levels for condition 1, genes as rows, samples as columns)
- `condition2_matrix.csv`: `control_expression.csv` (matrix of gene expression levels for condition 2, genes as rows, samples as columns)

---

## [1473] source=multitask_sft_big

**USER:** Please convert my VCF dataset to a tab-delimited file using VCFtoTab-delimited, and make sure you report data per sample so each sample gets its own line with genotype information.

**ASSISTANT:** I will configure VCFtoTab-delimited with the option 'Report data per sample' enabled (parameter flag `-g`) so that the tool outputs one line per sample containing genotype information, replacing empty values with a null string.

---

## [1474] source=multitask_sft_big

**USER:** What format does the input `peaks_E2F4` require in the `chipenrich_proximity_to_regulatory_regions` workflow, and is it required?

**ASSISTANT:** In `chipenrich_proximity_to_regulatory_regions`, `peaks_E2F4` is an optional table input (`optional: true`). It expects a data.frame or a file path pointing to a `.narrowPeak` or `.bed` file containing narrow peak calls.

---

## [1475] source=multitask_sft_big

**USER:** In MyriMatchAdapter, what mathematical criterion defines when peak picking stops during noise filtering?

**ASSISTANT:** Peak picking stops once the ratio of the cumulative ion current of the selected high-intensity peaks to the total ion current (TIC) is greater than or equal to the designated cutoff parameter.

---

## [1476] source=multitask_sft_big

**USER:** I have my insertions in 'insertion_data.gff' and chromosome boundaries in 'genome_ideogram.gff'. I also have an optional 'coverage.bam' file. How do these map to gmoviz_multiple_insertion_diagram inputs?

**ASSISTANT:** For the 'gmoviz_multiple_insertion_diagram' workflow:
- Required insertion data: 'insertion_data.gff' (mapped to the insertion event GRanges/data.frame input, e.g., 'insertions.rds')
- Required chromosome structure: 'genome_ideogram.gff' (containing chromosome names and lengths)
- Optional coverage data: 'coverage.bam' (for coverage visualization)
- Optional labels: 'labels.gff3' (if applicable)
The workflow will output the generated 'visualizations'.

---

## [1477] source=multitask_sft_big

**USER:** I want to run jackhmmer using my query sequences in 'queries.fasta' and searching against 'uniprot_sprot.fasta'. What are the positional inputs?

**ASSISTANT:** Based on jackhmmer's syntax, the extracted input parameters are:
- `<seqfile>`: queries.fasta
- `<seqdb>`: uniprot_sprot.fasta

---

## [1478] source=multitask_sft_big

**USER:** I want to apply a 5x5 minimum filter on my image using the 'Filter - Min' tool. What parameter needs to be set?

**ASSISTANT:** For 'Filter - Min', set the filter dimension parameter:
- size: 5 (this creates a (5, 5) neighborhood window around each pixel).

---

## [1479] source=multitask_sft_big

**USER:** In the 'Build Deep learning Batch Training Models' tool, how does specifying an integer versus a float determine class_weight?

**ASSISTANT:** The tool is intended for binary classification only. If an integer is supplied (such as 5), it converts to class_weight {0: 1, 1: 5}. If a float is supplied (such as 0.2), it converts to class_weight {0: 1/0.2, 1: 1}.

---

## [1480] source=multitask_sft_big

**USER:** I am configuring mgsa_custom_sets. What are the expected output targets once the workflow finishes?

**ASSISTANT:** The `mgsa_custom_sets` workflow produces two outputs:
1. `de_table`
2. `enrichment_results`

---

## [1481] source=multitask_sft_big

**USER:** I want to run sample classification using 'cohort_train_norm.csv' as my training expression, 'classes.csv' as the training labels, and 'cohort_test.csv' for the new samples. How do these map to the inputs of `gaga_class_prediction`?

**ASSISTANT:** The mapped inputs for `gaga_class_prediction` are:
- `training_expression.csv`: cohort_train_norm.csv
- `training_groups.csv`: classes.csv
- `new_expression.csv`: cohort_test.csv

---

## [1482] source=multitask_sft_big

**USER:** Set up the heron workflow using my peptide intensity matrix 'pep_intensities.rds', sample sheet 'sample_metadata.csv' (has SampleName, ptid, and visit), and probe definitions in 'probe_annotations.tsv'.

**ASSISTANT:** Here are the extracted parameters and inputs for the `heron` workflow:
- `seq_mat`: 'pep_intensities.rds' (peptide binding intensity matrix)
- `colData`: 'sample_metadata.csv' (sample annotations with SampleName, ptid, visit)
- `probe_meta`: 'probe_annotations.tsv' (mapping PROBE_SEQUENCE to PROBE_ID)

---

## [1483] source=multitask_sft_big

**USER:** I want to set up `puma_exon_array_summarisation`. I have my Affymetrix Exon CEL files located at `/data/arrays/sample_exon.CEL` and a sample annotation sheet at `/data/meta/samples.tsv`. How do these map to the workflow inputs?

**ASSISTANT:** Based on the workflow parameters, the files map as follows:
- `exonFilenames`: `/data/arrays/sample_exon.CEL` (Affymetrix Exon CEL files)
- `SampleNameTable`: `/data/meta/samples.tsv` (Sample name table)

---

## [1484] source=multitask_sft_big

**USER:** I am configuring a sequence alignment run using kkalign for some amino acid FASTA files. What options can I pass for the molecular sequence type parameter?

**ASSISTANT:** For kkalign, the molecular (sequence) type parameter accepts the following options:
- `'auto'`: Auto-detection based on the input sequence
- `'N'`: Nucleotide sequence
- `'P'`: Protein sequence

For your amino acid FASTA files, you should set this parameter to `'P'` (or `'auto'`).

---

## [1485] source=multitask_sft_big

**USER:** We are setting up PACU for phylogenetic bootstrapping with the following inputs: `sample1_illumina.bam`, `sample2_illumina.bam`, and `sample3_ont.bam`. Does this satisfy PACU's input count requirements?

**ASSISTANT:** No, it does not. The extracted input list contains only 3 BAM files (`sample1_illumina.bam`, `sample2_illumina.bam`, and `sample3_ont.bam`). PACU issues a warning that at least four input BAM files (which can be a mix of Illumina and ONT datasets) are required for bootstrapping.

---

## [1486] source=multitask_sft_big

**USER:** What mandatory inputs and outputs are defined for `mumosa_feature_correlation_analysis`?

**ASSISTANT:** The mandatory input is `sce2` (a SingleCellExperiment RDS object containing RNA-seq data and an alternative experiment for ADT/protein data). The primary output generated by the workflow is `cluster_assignments`.

---

## [1487] source=multitask_sft_big

**USER:** Please set up the data inputs for blacksheepr_raw_counts_normalization_and_formatting using raw counts from 'rnaseq_raw.tsv' and sample metadata from 'cohort_multiclass.csv'.

**ASSISTANT:** Here is the mapped data input configuration for 'blacksheepr_raw_counts_normalization_and_formatting':
- raw_counts.tsv: rnaseq_raw.tsv
- multiclass_annotations.csv: cohort_multiclass.csv

These will produce the expected workflow outputs: 'counts_matrix' and 'normalized_data'.

---

## [1488] source=multitask_sft_big

**USER:** In the QIIME 2 tool 'qiime2 demux filter-samples', what does the exclude_ids parameter do?

**ASSISTANT:** In `qiime2 demux filter-samples`, the `exclude_ids` parameter enables filtering out all samples that are not specified, effectively inverting the selection.

---

## [1489] source=multitask_sft_big

**USER:** What tools and declared data inputs are bundled in the enhancerHomologSearch Nextflow workflow?

**ASSISTANT:** The workflow bundles `bioconductor/enhancerhomologsearch`, `bioconductor/biocmanager`, and `bioconductor/motifdb`. Its declared input slot is an optional data parameter named `count_data` (not read by the workflow).

---

## [1490] source=multitask_sft_big

**USER:** What data input file is required for the interaccircos workflow?

**ASSISTANT:** The workflow requires `histogram_data.csv`, which is a data frame containing genomic coordinates and values for the histogram track.

---

## [1491] source=multitask_sft_big

**USER:** I want to run the bio-ontology recommender on my abstract. Here are my details:
API Key: bp-token-98741
Text: 'Analysis of acute myeloid leukemia progression via somatic mutations.'
Target Ontologies: NCIT, DOID, SNOMEDCT
Format: JSON

**ASSISTANT:** I have extracted the parameters for the 'Recommends a bio-ontology depending on annotations of a text' tool:
- Bioportal API key: bp-token-98741
- Text: "Analysis of acute myeloid leukemia progression via somatic mutations."
- List of bioontologies Ids: NCIT, DOID, SNOMEDCT
- Output format: JSON

---

## [1492] source=multitask_sft_big

**USER:** I have prepared 'ER.limma' with my differential expression results table and 'hs.inter' as an igraph object of the reference interactome. Can you extract the data inputs for the reder workflow from this?

**ASSISTANT:** The extracted data inputs for the reder workflow are:
- 'ER.limma': data.frame containing differential expression results (required table input).
- 'hs.inter': igraph object representing the reference interactome (required network input).

---

## [1493] source=multitask_sft_big

**USER:** What data inputs are listed in the parameter definitions of tximeta_linked_transcriptomes?

**ASSISTANT:** The defined data inputs for 'tximeta_linked_transcriptomes' are 'quant.sf' (type: data, optional: true, description: 'Salmon quantification files') and 'custom_transcriptome.fa'.

---

## [1494] source=multitask_sft_big

**USER:** Run a Flux Simulation on my reconstructed metabolic model using the Corner-based sampling method.

**ASSISTANT:** Extracted parameter for Flux Simulation:
- Algorithm: CBS (Corner-based sampling)
- Input: Metabolic model

---

## [1495] source=multitask_sft_big

**USER:** How do I configure the SaQC tool for my dataset?

**ASSISTANT:** To configure `SaQC`, you select the target module and method appropriate for your time series quality control analysis, and then supply the specific parameter settings required by that method.

---

## [1496] source=multitask_sft_big

**USER:** What are the required input datasets and expected file types for the batchelor_cluster_mnn_correction workflow?

**ASSISTANT:** The workflow requires two non-optional inputs:
- `sce1`: A `rds_sce` file containing the SingleCellExperiment of batch 1 with cluster annotations.
- `sce2`: A `rds_sce` file containing the SingleCellExperiment of batch 2 with cluster annotations.

---

## [1497] source=multitask_sft_big

**USER:** Please look up the NCBI gene record for human TP53 using Biomni: Search Gene.

**ASSISTANT:** Extracted parameter for `Biomni: Search Gene`:
- Gene query: `TP53` (Database: NCBI)

---

## [1498] source=multitask_sft_big

**USER:** What output files and tools are associated with the cogps workflow?

**ASSISTANT:** The `cogps` workflow utilizes the tools `bioconductor/cogps` and `bioconductor/limma`. It produces three outputs: `de_table`, `enrichment_results`, and `copy_number_segments`.

---

## [1499] source=multitask_sft_big

**USER:** Set up knowseq_automated_report using normalized_counts.tsv for the normalized gene expression values and sample_groups.csv for the sample labels.

**ASSISTANT:** Here are the extracted parameters for `knowseq_automated_report`:
- `expressionMatrix`: "normalized_counts.tsv"
- `labels`: "sample_groups.csv"

---

## [1500] source=multitask_sft_big

**USER:** Please set up the subseq workflow using my raw read counts file 'hammer_counts.rds' and the protocol conditions found in 'hammer_design_protocol.csv'.

**ASSISTANT:** Extracted parameters for the `subseq` workflow:
- `hammer.counts`: hammer_counts.rds (matrix of raw RNA-seq counts)
- `hammer.design$protocol`: hammer_design_protocol.csv (vector of treatment groups)

---

## [1501] source=multitask_sft_big

**USER:** I am running the prince VNTR tool. Please set target file to sample1.fasta, templates to tb_vntr.fa, target output to res_target.txt, and k-mer size to 21.

**ASSISTANT:** Here are the extracted parameters for `prince`:
- `-tf`: sample1.fasta
- `-tmp`: tb_vntr.fa
- `-to`: res_target.txt
- `-k`: 21

---

## [1502] source=multitask_sft_big

**USER:** I need to remove a set of obsolete genes from my wgMLST database using the tool 'Remove strain/gene to cg/wgMLST database'. The list is stored in 'filter_genes.txt'. What options should I supply?

**ASSISTANT:** You should use the `--genes` flag to specify gene removal, along with `-f filter_genes.txt` (or `--file filter_genes.txt`) to provide the file containing the list of genes.

---

## [1503] source=multitask_sft_big

**USER:** Here is my transcriptomic configuration: I have an expression matrix file 'exampleExpressionData.cct' containing gene expression profiles as rows for correlation network analysis. Please extract the required input data parameter for netsam_correlation_network_analysis.

**ASSISTANT:** The extracted parameter for `netsam_correlation_network_analysis` is:
- `data_inputs`: `exampleExpressionData.cct` (type: matrix, read_by_workflow: true).

---

## [1504] source=multitask_sft_big

**USER:** What input data files and underlying software tools are required to run the GMRP workflow?

**ASSISTANT:** The GMRP workflow requires the non-optional data input 'input_files' (or 'input_file') declared as the workflow input slot. Under the hood, it executes the 'bioconductor/gmrp' and 'bioconductor/knitr' tools.

---

## [1505] source=multitask_sft_big

**USER:** Which workflow parameters are available in nf-core/phageannotator for reference virus containment and sketching?

**ASSISTANT:** Based on the workflow definition, the relevant parameters are:
- `run_reference_containment`
- `reference_virus_fasta`
- `reference_virus_sketch`
- `save_reference_virus_sketch`

---

## [1506] source=multitask_sft_big

**USER:** Here is my execution call for cepo_batch_aware_differential_stability: input object 'pancreas_sce.rds' with counts and colData containing 'batch' and 'cellTypes'. What parameter does this map to, and what output is produced?

**ASSISTANT:** Your input file 'pancreas_sce.rds' maps to the mandatory parameter `sce_pancreas` (type `rds_sce`). When executed, the workflow will generate `normalized_data` as its output.

---

## [1507] source=multitask_sft_big

**USER:** I am configuring Shovill to assemble my paired-end Illumina data, and I'd like to remove common adaptors with Trimmomatic before running the assembly, as well as retain the full execution log. Which parameters should I set?

**ASSISTANT:** To enable adapter removal, set the "Trim reads" parameter to enable Trimmomatic (by default, it is set to OFF). To retain the execution log, set "Output log file" to "Yes" so that Shovill's log file is provided in the final output.

---

## [1508] source=multitask_sft_big

**USER:** I am setting up RCAS for my RNA query regions and I want to downsample to 1000 regions. What parameter setting should I apply?

**ASSISTANT:** Set the parameter to sample down query regions to 1000. This positive integer value will activate downsampling, provided it is smaller than your total number of query regions.

---

## [1509] source=multitask_sft_big

**USER:** I am running RNAz Cluster on predicted RNA structure alignments. I only want the locus-level information reported in the final output, not the individual windows. Which argument should I specify?

**ASSISTANT:** You should use the `-l` or `--loci` flag. By default, both single windows and combined loci are printed, but setting this flag restricts the printed output to loci.

---

## [1510] source=multitask_sft_big

**USER:** What input parameters and resource configurations can be passed to `Seacr Peak Calling`?

**ASSISTANT:** The workflow accepts the following inputs and parameters:
- Data & peak parameters: `input`, `mode`, `norm`, `genome`, `genome_size`, `binsize`, `effective_genome_size`
- Computational resources: `max_memory`, `max_cpus`, `max_time`.

---

## [1511] source=multitask_sft_big

**USER:** In the sample sheet for aurora_deseq2_site, what information is expected in column 1 versus the rest of the columns?

**ASSISTANT:** Column 1 is expected to contain the sample names corresponding to the count data columns, while all subsequent columns are expected to contain the experimental treatment variables.

---

## [1512] source=multitask_sft_big

**USER:** In the following command, what parameter sets the subsampling proportion?
`qiime2 demux subsample-paired --i-sequences paired-demux.qza --p-fraction 0.25 --o-subsampled-sequences subsampled.qza`

**ASSISTANT:** The parameter that controls the subsampling proportion is `fraction` (passed here as `--p-fraction 0.25`), which specifies the approximate fraction of input sequences to randomly retain.

---

## [1513] source=multitask_sft_big

**USER:** Please set up Scanpy ParameterIterator to evaluate t-SNE perplexity from 10 to 50 with an increment of 10.

**ASSISTANT:** The extracted parameters for Scanpy ParameterIterator are:
- Parameter type: perplexity (for t-SNE)
- start: 10
- step: 10
- end: 50

---

## [1514] source=multitask_sft_big

**USER:** What behavior is triggered by passing the `-b` option to Show-Coords?

**ASSISTANT:** The `-b` option tells `Show-Coords` to merge overlapping alignments regardless of match direction or frame, and it omits displaying any identity information.

---

## [1515] source=multitask_sft_big

**USER:** Here are my input datasets: paired-end sequencing alignment file `tumor_sample_tagged.bam` (includes XM/XG tags) and target interval definitions `target_panel.bed`. Please map these to the inputs for epialleler.

**ASSISTANT:** The input mapping for the `epialleler` workflow is:
- `capture.bam`: `tumor_sample_tagged.bam`
- `capture.bed`: `target_panel.bed`

---

## [1516] source=multitask_sft_big

**USER:** I am setting up DropletUtils emptyDrops for my single-cell RNA data. I want all droplets with 100 or fewer total UMIs to be treated as empty. What value should I pass?

**ASSISTANT:** You should set the lower bound numeric scalar parameter to `100`. In `DropletUtils emptyDrops`, barcodes with total UMI counts at or below this value are assumed to correspond to empty droplets.

---

## [1517] source=multitask_sft_big

**USER:** What input dataset and format does the 'flowmeans' workflow expect, and what outputs does it provide?

**ASSISTANT:** The workflow requires a single mandatory input, `flow_data.csv`, which must be a matrix or data frame of flow cytometry measurements across marker channels. Upon execution, it generates two outputs: `cluster_assignments` and `visualizations`.

---

## [1518] source=multitask_sft_big

**USER:** What is the default assembly distance threshold used by Kaptive for merging separate parts of an assembly?

**ASSISTANT:** The default distance parameter in Kaptive for merging separate parts of the assembly is 100.

---

## [1519] source=multitask_sft_big

**USER:** What are the required input files and expected formats for the phenopath workflow?

**ASSISTANT:** The `phenopath` workflow requires two inputs:
1. `expression_matrix.csv`: A matrix of logged counts (e.g., log2(TPM+1)) where samples are rows and genes are columns.
2. `covariates.csv`: A vector or matrix of sample-specific covariates.

---

## [1520] source=multitask_sft_big

**USER:** Please configure the `scruff_tenx_bam_qc` workflow with my data: the alignment file is `sample1_possorted_genome_bam.bam` and the barcode file is `sample1_barcodes.tsv`.

**ASSISTANT:** Here is the extracted configuration for the `scruff_tenx_bam_qc` workflow:
- `bamfile10x`: `sample1_possorted_genome_bam.bam` (10X Genomics BAM file)
- `filteredBc`: `sample1_barcodes.tsv` (Filtered cell barcodes TSV file)

The workflow will output `qc_report` and `visualizations`.

---

## [1521] source=multitask_sft_big

**USER:** Which specific structural feature types must be present in the tab-delimited GFF3 file used by SMAP-selector?

**ASSISTANT:** The GFF3 file must contain `gene`, `CDS`, and `exon` features with genomic positions mapped relative to the FASTA sequence.

---

## [1522] source=multitask_sft_big

**USER:** Run the nanoparticle biodistribution model for my formulation. The diameter is 80 nm.

**ASSISTANT:** Extracted parameter for `nanoparticle_pk_biodistribution`:
- `particle_diameter_nm`: 80

The workflow accepts inputs in JSON format and produces predictions (circulation half-life, tumor EPR accumulation, and MPS uptake at 24h) in JSON and CSV formats.

---

## [1523] source=multitask_sft_big

**USER:** I want to protonate my protein structure at pH 5.5 using ProteinProtonator. What setting should I apply, and will my existing hydrogens be preserved?

**ASSISTANT:** You should specify the pH parameter as 5.5. Be aware that all hydrogen atoms already present in your input file will be ignored during protonation.

---

## [1524] source=multitask_sft_big

**USER:** I am running FingerprintSimilaritySearch with an SD file query and want nearest neighbor hits saved inside the SD file itself. Which format feature supports this?

**ASSISTANT:** To save the results directly in the SD file, enable the flag for SD format queries that activates writing nearest neighbours as a new CSV tag in a copy of the query SD file.

---

## [1525] source=multitask_sft_big

**USER:** Here are our study parameters for modeling target engagement:
Target: EGFR
Compound: CC(=O)Nc1ccc(cc1)S(=O)(=O)N
IC50: 25 nM
Kd: 10 nM
Half-life: 4.5 h
Cmax: 1200 nM
Tmax: 1.5 h
Occupancy threshold: 80%
Simulation duration: 48 h

Please extract these into the workflow inputs.

**ASSISTANT:** Here are the extracted parameters for `drug_discovery/target_engagement_kinetics`:
- `target_name`: "EGFR"
- `smiles_list`: ["CC(=O)Nc1ccc(cc1)S(=O)(=O)N"]
- `IC50_nM`: 25
- `Kd_nM`: 10
- `pk_t_half_h`: 4.5
- `pk_Cmax_nM`: 1200
- `pk_tmax_h`: 1.5
- `occupancy_threshold_pct`: 80
- `simulation_hours`: 48

---

## [1526] source=multitask_sft_big

**USER:** Please configure the `geneselectmmd` workflow using my prepared dataset located at `/data/cohort_eSet.rds`.

**ASSISTANT:** Here is the extracted parameter configuration for `geneselectmmd`:

```json
{
  "data_inputs": {
    "eSet1": "/data/cohort_eSet.rds"
  }
}
```

---

## [1527] source=multitask_sft_big

**USER:** For running the depinfer workflow, I have my drug affinity matrix in Kd values saved as targetsGDSC and cell line drug sensitivity measured by IC50 in drug_response_GDSC. How are these mapped into the workflow?

**ASSISTANT:** The inputs map directly to the required workflow parameters:
- `targetsGDSC`: data frame of drug-protein affinity values (e.g., Kd)
- `drug_response_GDSC`: data frame of drug response values across samples (e.g., AUC or IC50).

---

## [1528] source=multitask_sft_big

**USER:** What are the required input data slots and parameters defined for the phantasusLite workflow?

**ASSISTANT:** The workflow defines a single non-optional input slot named `input_files` (accepting `count_data`). It does not specify any additional parameters.

---

## [1529] source=multitask_sft_big

**USER:** I want to run monalisa_randomized_lasso_stability_selection. What are the required input files and the mandatory data input parameter specified for this workflow?

**ASSISTANT:** The workflow expects the following inputs:
- Input files: `atac_peaks.bed` (genomic coordinates of enhancers), `accessibility_changes.tsv` (log2 fold changes of accessibility), and `motifs.jaspar` (transcription factor binding motifs).
- Mandatory data input parameter: `atac_liver_vs_lung.rds` (type: `rds_granges`, non-optional), which is a GRanges object containing peak coordinates and accessibility data read by the workflow.

---

## [1530] source=multitask_sft_big

**USER:** What output format does the 'IUPAC scan and output each match' tool produce?

**ASSISTANT:** The tool outputs results in GFF format, recording the identified non-overlapping IUPAC pattern matches.

---

## [1531] source=multitask_sft_big

**USER:** I have the sequence 'AGTCU' that I need transformed using 'Create binary barcodes'. What is the expected binary barcode output?

**ASSISTANT:** Following the tool's conversion rules:
- A -> R
- G -> R
- T -> Y
- C -> Y
- U -> Y

The resulting binary barcode sequence is `RRYYY`.

---

## [1532] source=multitask_sft_big

**USER:** I need to configure the 'Call specific mutations in reads' tool. What input files must I supply?

**ASSISTANT:** You need to provide four input files:
1. A VCF file containing mutations.
2. A BAM file containing aligned raw reads.
3. A JSON file generated by 'DCS mutations to tags/reads'.
4. A JSON file generated by 'DCS mutations to SSCS stats'.

---

## [1533] source=multitask_sft_big

**USER:** Which hyperparameter settings do I need to define before running TTMap?

**ASSISTANT:** None. TTMap is parameter-free, so you do not need to configure tuning parameters.

---

## [1534] source=multitask_sft_big

**USER:** Set up seqgsea_one_step_seqgsea for my project. The exon count files are located in `/data/project/exon_counts/` and my gene set file is `/reference/pathways/c2.all.v2023.symbols.gmt`.

**ASSISTANT:** Here are the extracted parameters and inputs for the `seqgsea_one_step_seqgsea` workflow:
- `data.dir`: `/data/project/exon_counts/`
- `geneset.file`: `/reference/pathways/c2.all.v2023.symbols.gmt`

---

## [1535] source=multitask_sft_big

**USER:** Here is my configuration for running chipenrich_hybrid_enrichment:
- Peaks file: /data/chipseq/E2F4_binding_sites.narrowPeak
Please extract the expected workflow data input parameters.

**ASSISTANT:** The extracted parameter is:
- `peaks_E2F4`: `/data/chipseq/E2F4_binding_sites.narrowPeak` (type: table, path to `.narrowPeak` file containing narrow peak calls).

---

## [1536] source=multitask_sft_big

**USER:** I am configuring ToolFactory to generate a new Galaxy tool wrapper. What are the formatting constraints for the Toolshed repository name?

**ASSISTANT:** The Toolshed repository name must contain only lowercase letters, digits, and underscores. You should choose it thoughtfully to prevent namespace collisions with other tool authors.

---

## [1537] source=multitask_sft_big

**USER:** I want to run fccac on my merged peaks file 'consensus_peaks.bed' alongside three mapped read replicate tracks: 'rep1.bw', 'rep2.bw', and 'rep3.bw'. Please map these to the workflow inputs.

**ASSISTANT:** Here is the mapped parameter configuration for the 'fccac' workflow:
- `peakFile.bed` (or `peaks.bed`): `consensus_peaks.bed` (genomic regions of interest)
- `bigwig1.bw, bigwig2.bw, bigwig3.bw`: `rep1.bw`, `rep2.bw`, `rep3.bw` (bigWig files of mapped reads for each dataset/replicate)

---

## [1538] source=multitask_sft_big

**USER:** I am preparing the inputs for gofuncr_wilcoxon_test. What format and columns are expected in the input file?

**ASSISTANT:** The workflow expects `gene_scores.tsv`, which is a tab-separated table/dataframe containing gene symbols alongside their corresponding continuous scores.

---

## [1539] source=multitask_sft_big

**USER:** Configure scddboost using my normalized counts file 'norm_sc_counts.tsv' and my cell grouping assignment vector 'cell_treatment_labels.rds'.

**ASSISTANT:** The parameters for the `scddboost` workflow are mapped as follows:

- `normalized_counts_matrix`: `norm_sc_counts.tsv` (matrix of normalized single-cell RNA-seq counts)
- `condition_vector`: `cell_treatment_labels.rds` (vector of biological conditions/groupings for each cell)

Outputs will be generated as `table/csv`, `plot/pdf`, and `object/rds`.

---

## [1540] source=multitask_sft_big

**USER:** Please map my files to the inputs for bumphunter_full_bumphunter_analysis: methylation matrix is `meth_matrix.rds`, design matrix is `design_cov.rds`, chromosome vector is `chr_vec.rds`, coordinates are `pos_vec.rds`, and cluster maker IDs are `cluster_ids.rds`.

**ASSISTANT:** Here is the input mapping for `bumphunter_full_bumphunter_analysis`:
- `y`: `meth_matrix.rds`
- `X`: `design_cov.rds`
- `chr`: `chr_vec.rds`
- `pos`: `pos_vec.rds`
- `cl`: `cluster_ids.rds`

---

## [1541] source=multitask_sft_big

**USER:** What format and constraints must the input matrix `mlmatr` meet for the `gaprediction` workflow?

**ASSISTANT:** For `gaprediction`, the input parameter `mlmatr` must be a data frame or matrix containing Illumina HumanMethylation450 CpG beta values constrained between 0 and 1, structured with samples as rows and CpGs as columns.

---

## [1542] source=multitask_sft_big

**USER:** Set up a run for syncraft_synthesizability with the compound 'CC(=O)Oc1ccccc1C(=O)O', capping modifications at 3 edits across 50 iterations, keeping the scaffold intact, and setting our SA threshold to 3.5.

**ASSISTANT:** Here are the extracted parameters for `syncraft_synthesizability`:
- `input_smiles`: "CC(=O)Oc1ccccc1C(=O)O"
- `max_edits`: 3
- `iterations`: 50
- `sa_threshold`: 3.5
- `preserve_scaffold`: true

---

## [1543] source=multitask_sft_big

**USER:** I want to configure nf-core/circdna with already sorted BAM files, write the output to './results', and use the reference genome FASTA '/data/ref.fa'. Which parameters correspond to these settings?

**ASSISTANT:** The parameters corresponding to your request are:
- 'bam_sorted': specifies that the input BAM files are already sorted
- 'outdir': './results'
- 'fasta': '/data/ref.fa'

---

## [1544] source=multitask_sft_big

**USER:** Here is my input configuration for aCGH analysis: I have pre-processed phenotype and array data stored at `path/to/colorectal_data.rds`. Please set up the mandatory data input.

**ASSISTANT:** I have extracted the required input parameter:
- `colorectal`: `path/to/colorectal_data.rds` (RDS format containing pre-existing aCGH object with phenotype data).

---

## [1545] source=multitask_sft_big

**USER:** I am configuring LowMemPeakPickerHiResRandomAccess for high-res MS data, and I want peak width recorded as parts-per-million in the peak metadata. What parameter should I set?

**ASSISTANT:** Set the parameter `report_FWHM_unit` to configure the metadata output. This will cause the tool to add peak width metadata as a floatDataArray named 'FWHM_ppm' rather than 'FWHM'.

---

## [1546] source=multitask_sft_big

**USER:** I am configuring `gpls_multi_group_classification`. What are the required input data parameters?

**ASSISTANT:** The workflow requires two mandatory data inputs:
1. `x`: A matrix of training predictors.
2. `y`: A multi-class training response vector (labels 1, 2, 3).

---

## [1547] source=multitask_sft_big

**USER:** What are the configuration attributes of the data input `short_18B_C24_C24_trim.fastq_CG_methCalls.gz` in the `segmentseq_dna_methylation_loci_and_dm` workflow?

**ASSISTANT:** In the `segmentseq_dna_methylation_loci_and_dm` workflow, `short_18B_C24_C24_trim.fastq_CG_methCalls.gz` is configured with type: `data`, optional: `true`, and read_by_workflow: `false`.

---

## [1548] source=multitask_sft_big

**USER:** Run repeated-dose toxicity screening for compound batch SMILES: 'CC(=O)Nc1ccc(O)cc1', 'CN1C=NC2=C1C(=O)N(C(=O)N2C)C' with a projected Cmax of 15.5 uM.

**ASSISTANT:** Extracted parameters for `repeated_dose_tox_prediction`:
- `smiles`: ['CC(=O)Nc1ccc(O)cc1', 'CN1C=NC2=C1C(=O)N(C(=O)N2C)C']
- `projected_Cmax`: 15.5

---

## [1549] source=multitask_sft_big

**USER:** What output file types does the cellnoptr_cross_validation workflow generate?

**ASSISTANT:** The workflow generates outputs in three formats: 'table/csv', 'plot/pdf', and 'object/rds'.

---

## [1550] source=multitask_sft_big

**USER:** What outputs does the `bcseq_barcode_alignment_edit` workflow generate, and does it support indel alignment?

**ASSISTANT:** The workflow outputs `visualizations`. It does support indels by using an edit-distance alignment algorithm that accommodates insertions and deletions via customizable penalty parameters.

---

## [1551] source=multitask_sft_big

**USER:** Here are my files for peak extraction: spectra at '/data/ms/sample1.mzML', '/data/ms/sample2.mzML' and the feature table at '/data/targets/feature_windows.csv'. Please map these to the `peakpanther` workflow inputs.

**ASSISTANT:** The parameters are mapped to the `peakpanther` workflow inputs as follows:
- `input_spectraPaths`: `['/data/ms/sample1.mzML', '/data/ms/sample2.mzML']`
- `input_targetFeatTable`: `'/data/targets/feature_windows.csv'`

---

## [1552] source=multitask_sft_big

**USER:** I have my normalized single-cell dataset saved at 'data/pbmc_logcounts.rds'. Configure the input for the tricycle_custom_reference_projection workflow.

**ASSISTANT:** Here is the extracted parameter configuration for the workflow:

```json
{
  "sce_normalized.rds": "data/pbmc_logcounts.rds"
}
```

---

## [1553] source=multitask_sft_big

**USER:** What are the exact inputs and outputs specified for the `mlinterfaces` workflow?

**ASSISTANT:** The specified input is `fus` (type: data, mandatory), which is an `ExpressionSet` containing gene expression data and phenotype labels. The designated output is `feature_selection`.

---

## [1554] source=multitask_sft_big

**USER:** What tools and default output file formats are produced by the ribodipa workflow?

**ASSISTANT:** The workflow runs the `bioconductor/ribodipa` wrapper function with default parameters and produces outputs in three formats: `table/csv`, `plot/pdf`, and `object/rds`.

---

## [1555] source=multitask_sft_big

**USER:** Here is my data table header: `Cell_ID, GeneA, GeneB, nCount_RNA, batch`. Is the mandatory UMI count column present for 'Combine multiple 1D Models'?

**ASSISTANT:** Yes. The required 'nCount_RNA' column representing total UMI counts per cell is present, along with cell-level raw counts and optional metadata ('batch'), matching the input requirements.

---

## [1556] source=multitask_sft_big

**USER:** What parameter setting in DeepARG short reads controls the discard threshold based on the total overlap of all hits aligned to a gene?

**ASSISTANT:** The overlap threshold parameter controls this behavior. It examines the full gene and all aligned hits, discarding the gene if the total overlap is below the threshold (default value is 1).

---

## [1557] source=multitask_sft_big

**USER:** I want to run `karyoploter_custom_low_level_plotting` to visualize genomic points. Here is my setup: I have a table of all genomic coordinates with numeric values called `chr_all_metrics.tsv` and a filtered subset called `highlighted_peaks.tsv`. How should these be assigned to the workflow inputs?

**ASSISTANT:** For the `karyoploter_custom_low_level_plotting` workflow, map your inputs as follows:
- `rand.data`: `chr_all_metrics.tsv` (data.frame or GRanges containing genomic coordinates and numeric values)
- `sel.data`: `highlighted_peaks.tsv` (subset of rand.data representing specific points of interest to highlight)

---

## [1558] source=multitask_sft_big

**USER:** What data transformation methods are supported by the Normalization tool?

**ASSISTANT:** The Normalization tool supports the following values for the 'Data transformation method' parameter:
- "log"
- "DESeq2"
- "Rlog"
- "Standard_score"
- "TSS"
- "TSS_CLR"

---

## [1559] source=multitask_sft_big

**USER:** Please run Biomni: Extract Pdf Content on the document located at https://www.example.org/genomics_paper.pdf.

**ASSISTANT:** Extracted parameter for `Biomni: Extract Pdf Content`:
- URL: `https://www.example.org/genomics_paper.pdf`

---

## [1560] source=multitask_sft_big

**USER:** What input format does `chipenrich_narrow_peak_enrichment_polyenrich` accept for its peak data input parameter?

**ASSISTANT:** The workflow accepts the parameter `peaks_E2F4`, which can be provided as a table/data.frame or as a path to a `.narrowPeak` or `.bed` file containing narrow peaks. Note that this parameter is marked as optional.

---

## [1561] source=multitask_sft_big

**USER:** Please set up the `mmseqs2_sequence_search` workflow. My input query file is `/data/queries/target_proteins.fasta` and the target database is located at `/opt/databases/uniref50`.

**ASSISTANT:** Here are the extracted parameters for `mmseqs2_sequence_search`:
- `query_fasta`: "/data/queries/target_proteins.fasta"
- `mmseqs_db`: "/opt/databases/uniref50"

---

## [1562] source=multitask_sft_big

**USER:** Run the beta_diversity tool on my 16S amplicon data, but restrict distance matrix generation to only sample rows 's1,s3' rather than the full table.

**ASSISTANT:** Extracted parameter for `beta_diversity`:
- Target sample rows: `'s1,s3'`

By passing `'s1,s3'`, the tool will compute only those specified rows instead of the default full n x n distance matrix.

---

## [1563] source=multitask_sft_big

**USER:** Configure the 'Change title' tool so that it extracts the molecule identifier from the SDF metadata field 'PUBCHEM_SHAPE_VOLUME'.

**ASSISTANT:** For the 'Change title' tool, set the key name of the SDF metadata molecule identifier to:
- key: 'PUBCHEM_SHAPE_VOLUME'

---

## [1564] source=multitask_sft_big

**USER:** I want to extract the 3'-most alignments from my paired-end alignment file located at `/data/samples/sample1_paired.bam` and save the outputs to `/results/apa_prep/`. Which workflow should I use and what are the parameter values?

**ASSISTANT:** You should use the `apalyzer_paired_end_3most_extraction` workflow. The extracted parameters are:
- `Bamfile`: `/data/samples/sample1_paired.bam`
- `Outdir`: `/results/apa_prep/`

This workflow extracts the 3'-most alignment from the paired-end BAM file to prepare the data for accurate APA analysis.

---

## [1565] source=multitask_sft_big

**USER:** Please set up cytopipeline for my flow cytometry samples located at: sampleFiles = c('run1/sampleA.fcs', 'run1/sampleB.fcs').

**ASSISTANT:** Extracted parameter for cytopipeline:
- `sampleFiles`: `c('run1/sampleA.fcs', 'run1/sampleB.fcs')` (vector of paths to raw .fcs files).

---

## [1566] source=multitask_sft_big

**USER:** Please set up the xde pipeline using my combined dataset file located at `/data/studies/eset_list_combined.rds`.

**ASSISTANT:** Here are the extracted parameters for the **xde** workflow:

- **Multiple**: `/data/studies/eset_list_combined.rds` (RDS format containing an `ExpressionSetList` of multiple `ExpressionSet` objects with matching `featureNames` and a shared binary phenotype covariate).

---

## [1567] source=multitask_sft_big

**USER:** Set up an Ode Signaling Simulation for trametinib targeting MEK in the MAPK/ERK pathway. We have an IC50 of 0.92 nM, Cmax of 35 nM, Hill coefficient of 1.1, stimulus EGF at 10 nM, run time 24 hours, and enable the EC50 scan.

**ASSISTANT:** Here are the extracted parameters for `virtual_cell/ode_signaling_simulation`:
- `drug_name`: "trametinib"
- `target_node`: "MEK"
- `pathway`: "MAPK/ERK"
- `drug_ic50_nM`: 0.92
- `cmax_nM`: 35.0
- `hill_coefficient`: 1.1
- `simulation_time_h`: 24.0
- `stimulus`: "EGF"
- `stimulus_conc_nM`: 10.0
- `ec50_scan`: true

---

## [1568] source=multitask_sft_big

**USER:** For our analysis, please set up coveb_cov_estimation_known_blocks with our empirical matrix 'gene_cov_mat.csv' (which has gene names on rows and columns) and predefined pathways 'kegg_blocks.rds'.

**ASSISTANT:** Here are the extracted input parameters for `coveb_cov_estimation_known_blocks`:
- `samplecov`: "gene_cov_mat.csv" (sample covariance matrix with row and column names)
- `groups`: "kegg_blocks.rds" (list of character vectors defining the variable groups/blocks)

The workflow will output a `network_graph` upon completion.

---

## [1569] source=multitask_sft_big

**USER:** How should my input file be formatted when submitting data to RNAdistance?

**ASSISTANT:** RNAdistance requires a single input file structured as follows:
- Line 1: Comment line starting with '>' (Fasta-style header)
- Line 2: RNA sequence
- Line 3: First secondary structure in dot-bracket notation
- Line 4: Second secondary structure in dot-bracket notation

---

## [1570] source=multitask_sft_big

**USER:** In segemehl, how does the setting controlling the maximum width of a suffix array interval affect read seeding?

**ASSISTANT:** The maximum width of a suffix array interval determines whether a query seed is retained; if a query seed matches more than n times (the specified maximum width), it will be omitted during alignment.

---

## [1571] source=multitask_sft_big

**USER:** What optional database input file does the eisar_step_by_step_eisa_with_alignment workflow accept for transcript definitions?

**ASSISTANT:** It accepts `hg19sub.sqlite`, which is an optional TxDb SQLite database file parameter.

---

## [1572] source=multitask_sft_big

**USER:** I am configuring `dss_bsseq_twogroup_dml_dmr`. Here are my per-sample text files containing chr, pos, N, and X: sample_files.txt. Please set up the required input.

**ASSISTANT:** I have extracted the input for `dss_bsseq_twogroup_dml_dmr`:
- `sample_files.txt`: "sample_files.txt" (multiple text files, one per sample, containing columns: chr, pos, N [total reads], and X [methylated reads]).

---

## [1573] source=multitask_sft_big

**USER:** What input data slots are declared in the GladiaTOX workflow?

**ASSISTANT:** The GladiaTOX workflow declares one data input slot: `count_data` (type: data), which is marked as optional.

---

## [1574] source=multitask_sft_big

**USER:** Which mandatory columns must be included in the `screen_results.csv` input file for the synlet workflow?

**ASSISTANT:** The `screen_results.csv` table must include these mandatory columns: `PLATE`, `MASTER_PLATE`, `WELL_CONTENT_NAME`, `EXPERIMENT_TYPE`, `EXPERIMENT_MODIFICATION`, `ROW_NAME`, `COL_NAME`, and `READOUT`.

---

## [1575] source=multitask_sft_big

**USER:** I am configuring OpenSwathWorkflow for my SWATH-MS run and want to limit the RT extraction window to +/- 300 seconds around the expected elution peak. What value should I pass?

**ASSISTANT:** You should pass a value of `600` for the RT extraction parameter, which configures OpenSwathWorkflow to extract around +/- 300 seconds of the expected elution.

---

## [1576] source=multitask_sft_big

**USER:** I want to run Repurposing Signature Reversal with disease 'Alzheimers', query file 'input_sig.tsv', reference database 'cmap_ref.h5', up threshold 1.5, down threshold -1.5, requiring at least 10 matched genes, and getting the top 50 hits. Map these to the workflow inputs.

**ASSISTANT:** Here is the parameter mapping for **Repurposing Signature Reversal**:
- `query_file`: "input_sig.tsv"
- `reference_file`: "cmap_ref.h5"
- `disease`: "Alzheimers"
- `up_threshold`: 1.5
- `down_threshold`: -1.5
- `min_matched`: 10
- `top_n`: 50

---

## [1577] source=multitask_sft_big

**USER:** Set up scdataviz with filelist = c('pbmc_sample1.fcs', 'pbmc_sample2.fcs') and metadata = sample_annot_df.

**ASSISTANT:** The parameters have been extracted for `scdataviz`:
- `filelist`: `c('pbmc_sample1.fcs', 'pbmc_sample2.fcs')` (character vector of FCS file paths)
- `metadata`: `sample_annot_df` (data frame of sample metadata)

---

## [1578] source=multitask_sft_big

**USER:** Configure puma_hta_20_array_summarisation with CEL archive 'sample_batch1.cel' mapped to celFiles.

**ASSISTANT:** Parameter configuration for `puma_hta_20_array_summarisation`:
- celFiles: "sample_batch1.cel"

---

## [1579] source=multitask_sft_big

**USER:** I want to run the mnem workflow on single-cell perturbation log odds stored in 'perturbation_matrix.csv'. How should I map this parameter?

**ASSISTANT:** You should map your file to the following input parameter:
- `data.csv`: `"perturbation_matrix.csv"` (type: `matrix`, an $m \times n$ matrix of log odds where rows are E-genes and columns are cells/samples with S-gene perturbations).

---

## [1580] source=multitask_sft_big

**USER:** I want to run the triplex workflow on a query sequence stored in my DNAString object together with my BSgenome database. Can you confirm the inputs and tools?

**ASSISTANT:** The required inputs for the `triplex` workflow are:
- `DNAString`: DNA sequence to search (type: data)
- `BSgenome`: genomic sequence database (type: data)

The workflow executes using `bioconductor/triplex` and `bioconductor/rtracklayer`, producing `visualizations` and exporting results to GFF3 and FASTA formats.

---

## [1581] source=multitask_sft_big

**USER:** I want to run tximport_rsem_import with my RSEM gene results archive named sample.genes.results.gz. Could you identify the inputs for this execution?

**ASSISTANT:** The extracted parameter and data input for `tximport_rsem_import` is:
- `sample.genes.results.gz`: RSEM gene results data file (assigned to `input_files`).
This will generate the output `de_table`.

---

## [1582] source=multitask_sft_big

**USER:** Does the TIN workflow require any mandatory input datasets according to its declared parameters?

**ASSISTANT:** No. The workflow declares a data input slot named 'count_data', but it is marked as optional (optional: true) and is not directly read by the workflow.

---

## [1583] source=multitask_sft_big

**USER:** Please set up the input arguments for the trackviewer_lollipop_plot workflow using our R data files: `variants.gr` located at `/data/snps_scores.rds` and `features.gr` stored at `/data/protein_domains.rds`.

**ASSISTANT:** Here are the extracted parameters for `trackviewer_lollipop_plot`:

- `variants.gr`: "/data/snps_scores.rds" (rds_granges containing variants/SNPs with scores/colors)
- `features.gr`: "/data/protein_domains.rds" (rds_granges representing gene/protein features and domains)

Both mandatory inputs are configured for execution.

---

## [1584] source=multitask_sft_big

**USER:** Please extract the input requirements and expected output category for the compass_simple_compass workflow.

**ASSISTANT:** For `compass_simple_compass`:
- Required Data Input: `SimpleCOMPASSExamples.csv` (CSV file with metadata and counts for boolean cell subsets; required).
- Output: `visualizations`.

---

## [1585] source=multitask_sft_big

**USER:** Please set up the cardiac ODE simulation for compound 'BVT-101' at 70 bpm for 200 beats. The plasma Cmax is 150 nM with an unbound fraction of 0.05. Channel IC50 values: hERG is 320 nM, Nav1.5 is 2500 nM, Cav1.2 is 1800 nM, IKs is 9500 nM, and IK1 is 12000 nM.

**ASSISTANT:** Here are the extracted parameters for `Cipa Cardiac Safety Ode`:
- `drug_name`: "BVT-101"
- `herg_ic50_nM`: 320
- `nav15_ic50_nM`: 2500
- `cav12_ic50_nM`: 1800
- `iks_ic50_nM`: 9500
- `ik1_ic50_nM`: 12000
- `cmax_nM`: 150
- `fu_plasma`: 0.05
- `heart_rate_bpm`: 70
- `n_beats`: 200

---

## [1586] source=multitask_sft_big

**USER:** What input file and format are required by the escher_binned_spatial_visualization workflow?

**ASSISTANT:** It requires `spe.rds`, an RDS file containing a SpatialExperiment object that includes spatial coordinates or dimensionality reduction embeddings.

---

## [1587] source=multitask_sft_big

**USER:** Can I supply pre-existing protein predictions to PhaBOX votu instead of letting it predict proteins from scratch?

**ASSISTANT:** Yes, PhaBOX votu allows you to optionally provide your own predicted protein sequences rather than relying on its default prediction workflow.

---

## [1588] source=multitask_sft_big

**USER:** I am configuring nf-core/hgtseq. I have BAM files as input, need to target a specific host genome, set taxonomy filtering, and run Kraken QC. Which pipeline parameters correspond to these settings?

**ASSISTANT:** You can configure these settings in `nf-core/hgtseq` using the following parameters:
- `isbam`: set to true when input files are in BAM format
- `genome`: specifies the host reference genome
- `taxonomy_id`: defines the taxonomy ID for filtering
- `multiqc_runkraken`: enables Kraken-related QC reporting
Additional pipeline parameters include `input`, `outdir`, `aligner`, `email`, `multiqc_title`, and `istest`.

---

## [1589] source=multitask_sft_big

**USER:** Run RNAsubopt to compute all suboptimal conformations within 4.5 kcal/mol of the minimum free energy.

**ASSISTANT:** Extracted parameter: `-e 4.5` (defines the energy range of 4.5 kcal/mol above the minimum free energy for reporting suboptimal structures).

---

## [1590] source=multitask_sft_big

**USER:** In quality_scores_plot, what is the default threshold used to indicate poor quality reads on the generated histogram?

**ASSISTANT:** The default threshold parameter for quality_scores_plot is 25. It draws a dotted line on the histogram at this minimum acceptable quality score to help visualize poor-quality scores.

---

## [1591] source=multitask_sft_big

**USER:** Configure the inputs for the daglogo workflow using my dataset file 'experiment_peptides.csv'.

**ASSISTANT:** Here is the parameter configuration for the daglogo workflow based on your input:

```json
{
  "data_inputs": [
    {
      "name": "peptides4dagLogo.csv",
      "value": "experiment_peptides.csv"
    }
  ]
}
```

---

## [1592] source=multitask_sft_big

**USER:** I am looking at the inputs for the epialleler_short_read_methylation_calling workflow. Can you tell me what the 'bwameth' input accepts and whether it is required?

**ASSISTANT:** The 'bwameth' parameter is an optional data input of type `rds_se`. Its description specifies `bwameth-se-unsort-yd.bam (BAM file lacking XG/XM tags)`, and it is marked with `read_by_workflow: false`.

---

## [1593] source=multitask_sft_big

**USER:** What are the required input files and formats for the rmagpie_nsc_classification workflow?

**ASSISTANT:** The workflow requires two data inputs: 1) 'ExpressionSet', which is a microarray dataset with labeled classes, and 2) 'vV_newSamples.txt', which is a tab-separated text file containing gene expression values for the new samples to classify.

---

## [1594] source=multitask_sft_big

**USER:** In Larch Athena for materials science, what is the default project output behavior when providing a zip archive of datasets?

**ASSISTANT:** By default, each dataset or file contained in a zip archive will result in a separate output project, unless you enable the option to merge all input data into one Athena project.

---

## [1595] source=multitask_sft_big

**USER:** Please set up `Screen.seqs` so that it retains sequences where at least 90% match the optimized cutoff.

**ASSISTANT:** For `Screen.seqs`, set the parameter as follows:

```json
{
  "criteria": 90
}
```

This ensures that 90% of the sequences must match the optimize value to be kept.

---

## [1596] source=multitask_sft_big

**USER:** In the assembly tool `runAssembly cDNA`, what does the `-icc` parameter specify, and what is its maximum allowable setting?

**ASSISTANT:** In `runAssembly cDNA`, the `-icc` flag specifies the maximum number of contigs in an isotig. Its maximum value is 200, which directly corresponds to the recursion depth during graph traversal.

---

## [1597] source=multitask_sft_big

**USER:** What parameter options control the filtering threshold in the Hydra pipeline?

**ASSISTANT:** Filtering in the Hydra pipeline is controlled by the score type (which determines whether the median or mean quality score is assessed) and the score cutoff value (which defaults to 30).

---

## [1598] source=multitask_sft_big

**USER:** When configuring the File Splitter (Proteomics) tool, how do users configure the splitting rules and output file naming?

**ASSISTANT:** Users configure the splitting behavior using 'Expression to split on' and 'Expression for file name'. These options provide user-friendly descriptions based on community feedback so that custom regular expressions do not need to be written manually.

---

## [1599] source=multitask_sft_big

**USER:** What units are used for the energy values printed by RNAsubopt?

**ASSISTANT:** RNAsubopt reports the energy values for suboptimal structures in kcal/mol.

---

## [1600] source=multitask_sft_big

**USER:** I need to set up BASiCStan for quick exploratory analysis rather than full posterior sampling. Which inference engine option described in BASiCStan is suited for fast variational approximations versus MAP estimation?

**ASSISTANT:** For fast variational approximations, BASiCStan provides ADVI (Automatic Differentiation Variational Inference). If you prefer maximum a posteriori point estimation instead, you can select the BFGS engine. For full Bayesian posterior sampling, NUTS (No-U-Turn Sampler MCMC) is available.

---

## [1601] source=multitask_sft_big

**USER:** I am preparing inputs for `partcnv_part_cnvh_hmm`. Can you list the required input parameters and their formats?

**ASSISTANT:** The workflow requires two non-optional inputs:
- `scRNA_seq_counts.rds`: A matrix containing the normalized scRNA-seq count matrix.
- `cytogenetics_info.txt`: A text file containing prior cytogenetics region definitions and expected proportions.

---

## [1602] source=multitask_sft_big

**USER:** In process_radtags, which command-line flag controls the minimum average quality score within the sliding window, and what is its default value?

**ASSISTANT:** The flag is `-s <lim>`, which sets the quality score threshold for the sliding window. Its default value is `10`. If the average score drops below this threshold, the read is discarded.

---

## [1603] source=multitask_sft_big

**USER:** I want to set up the MOE Covalent Docking Pipeline. Here are my parameters: receptor is 'target.pdb', ligands file is 'inhibitors.sdf', targeting CYS145 with an acrylamide warhead. Run covalent protocol using 8 CPUs, generating 50 poses, refining poses, and saving the top 10.

**ASSISTANT:** Here are the extracted parameters for the MOE Covalent Docking Pipeline:
- receptor: 'target.pdb'
- ligands: 'inhibitors.sdf'
- reactive_residue: 'CYS145'
- warhead_type: 'acrylamide'
- docking_protocol: 'covalent'
- n_cpus: 8
- n_poses: 50
- refine_poses: true
- top_n: 10

---

## [1604] source=multitask_sft_big

**USER:** What is the expected input parameter for genomic data in the grafgen workflow?

**ASSISTANT:** The primary input parameter is 'geno.file', which accepts either a VCF file or a PLINK bed file containing Helicobacter pylori genotypes.

---

## [1605] source=multitask_sft_big

**USER:** What outputs are generated by the pipecomp_scrna_seq_clustering_benchmarking workflow?

**ASSISTANT:** The `pipecomp_scrna_seq_clustering_benchmarking` workflow produces the following outputs:
- `cluster_assignments`
- `feature_selection`
- `normalized_data`

---

## [1606] source=multitask_sft_big

**USER:** What outputs are generated upon completing the ggtreeextra_same_position_multiple_layers workflow?

**ASSISTANT:** The workflow produces two outputs: `phylogenetic_tree` and `visualizations`.

---

## [1607] source=multitask_sft_big

**USER:** In Purge Haplotigs Cov, how does the 'junk' parameter work, and what should I set it to if I want to disable auto-assigning contigs as junk?

**ASSISTANT:** The 'junk' parameter auto-assigns a contig as 'j' (junk) if that percentage or greater of the contig has low or high coverage. Its default value is 80. To prevent contigs from being marked as junk, set 'junk' to a value greater than 100 (> 100).

---

## [1608] source=multitask_sft_big

**USER:** What inputs are required to run the 'ibh' systems biology workflow, and are there any optional files?

**ASSISTANT:** The workflow requires 'gene_list.txt' (a mandatory list of gene identifiers). It also accepts 'custom_interactions.csv' as an optional custom interaction network file if you are not using the default BioGRID interaction network.

---

## [1609] source=multitask_sft_big

**USER:** I want to run PADOG pathway analysis. I have my normalized expression data in 'expression_data.tsv', sample group assignments in 'classes.txt', and I am using annotation package 'hgu133plus2.db'. Map these to the workflow inputs.

**ASSISTANT:** The inputs map to the padog workflow as follows:
- `esetm`: expression_data.tsv
- `group`: classes.txt
- `annotation`: hgu133plus2.db

---

## [1610] source=multitask_sft_big

**USER:** In AquaINFRA OGC API Processes, can I provide a direct .shp file directly on the command line to specify the study region?

**ASSISTANT:** No. The tool requires a URL pointing to the study region shapefile, and that URL must be stored inside a `.txt` file.

---

## [1611] source=multitask_sft_big

**USER:** I want to execute goseq_count_bias_corrected_analysis. I have my assayed DE binary vector saved in `de_vector.rds` and my raw count matrix in `raw_counts.tsv`. Please map these to the workflow inputs.

**ASSISTANT:** Here is the parameter mapping for the **goseq_count_bias_corrected_analysis** workflow:

- `genes`: `de_vector.rds` (named binary vector of assayed genes and DE status)
- `counts`: `raw_counts.tsv` (matrix of raw read counts per gene)

---

## [1612] source=multitask_sft_big

**USER:** I am configuring oasesoptimiser for assembly and chose a hash length of 25. Could this cause issues?

**ASSISTANT:** Yes. In oasesoptimiser, using a hash length of 25 (which is less than 31 bp) risks causing out-of-memory problems during assembly word hashing. Consider increasing the hash length to 31 bp or greater.

---

## [1613] source=multitask_sft_big

**USER:** I am standardizing my flow cytometry channels. Please set the columns to CD3 and CD8.

**ASSISTANT:** Extracted parameter for 'Edit markers or channels':
- Markers/channels: 'CD3,CD8'

Please ensure that 'CD3' and 'CD8' are formatted as comma-separated values and exist as column names in your input flowFrame / FCS file.

---

## [1614] source=multitask_sft_big

**USER:** Here are my files for running direct modBAM methylation plotting: sample sheet located at ./metadata/sample_anno.csv and the alignment file ./alignments/peg3.bam.

**ASSISTANT:** I have mapped your inputs to the 'nanomethviz_modbam_direct_plotting' workflow:
- `peg3.bam`: ./alignments/peg3.bam (modBAM file containing modification tags)
- `sample_anno.csv`: ./metadata/sample_anno.csv (sample annotation table)

Both mandatory inputs are set and ready to generate annotated genes and visualizations.

---

## [1615] source=multitask_sft_big

**USER:** Run the Evo2 variant effect workflow for my variants in `chr21_snvs.vcf` against `hg38.fa`. I need zero-shot log-likelihood scoring (`score_type: delta_log_likelihood`) formatted as TSV with a context window of 8192 bp, batch size of 16, and use API key `tg_live_998124`.

**ASSISTANT:** Here are the extracted parameters for the Evo2 Variant Effect workflow:

- `input_vcf`: chr21_snvs.vcf
- `reference_genome`: hg38.fa
- `score_type`: delta_log_likelihood
- `output_format`: tsv
- `context_window_bp`: 8192
- `batch_size`: 16
- `together_api_key`: tg_live_998124

---

## [1616] source=multitask_sft_big

**USER:** I am training PTModel. My training input sets contain redundant peptides, and I specifically want those redundant peptides to appear more than once during training. How should I configure the tool?

**ASSISTANT:** You must enable the redundancy flag in `PTModel`. Setting this flag ensures that redundant peptides are allowed to occur more than once in the training set.

---

## [1617] source=multitask_sft_big

**USER:** Which specific data attribute is added to the SPRING cross reference by SPRING Map?

**ASSISTANT:** SPRING Map adds columns containing the chain identifier of the homologues sourced from the template library.

---

## [1618] source=multitask_sft_big

**USER:** What are the designated inputs, outputs, and underlying software packages for the geneclassifiers workflow?

**ASSISTANT:** The workflow inputs include 'expression_set.RData' (an ExpressionSet object containing pre-normalized gene expression data). Its outputs are 'expression_matrix' and 'normalized_data'. It utilizes the tools 'bioconductor/geneclassifiers' and 'bioconductor/biobase'.

---

## [1619] source=multitask_sft_big

**USER:** I am configuring the methylpipe workflow. My input folder with sorted BISMARK SAM files is at '/runs/bismark_sams' and my methylation call table is at '/data/methylation/calls.txt'. Please extract the input parameter mapping and list the expected output types.

**ASSISTANT:** Here is the parameter extraction for `methylpipe`:
- `test_methcall`: `/runs/bismark_sams` (folder containing sorted SAM files from BISMARK aligner)
- `H1_chr20_CG_10k.txt`: `/data/methylation/calls.txt` (tabular text file of methylation calls)

Expected outputs generated by this workflow:
- `table/csv`
- `plot/pdf`
- `object/rds`

---

## [1620] source=multitask_sft_big

**USER:** Can you check the input parameter configuration for `ToyData_FWReads.fna` in `qsutils_strand_intersection`? Is it mandatory?

**ASSISTANT:** According to the workflow parameters, `ToyData_FWReads.fna` is a FASTA file of forward strand reads (`type: fasta`), and it is marked as `optional: true`.

---

## [1621] source=multitask_sft_big

**USER:** I am configuring Hicup Truncater for a Hi-C experiment where both BglII (restriction cut site A^GATCT) and HindIII (cut site A^AGCTT) were used. How should I enter the restriction enzyme parameter?

**ASSISTANT:** In Hicup Truncater, separate multiple restriction enzymes using a colon (`:`). For your experiment, enter the parameter as:
`A^GATCT,BglII:A^AGCTT,HindIII`

---

## [1622] source=multitask_sft_big

**USER:** I want to extract CDS annotations matching the products 'kinase' and 'phosphatase' using select_product. How should I specify these keywords?

**ASSISTANT:** In `select_product`, you should pass comma-separated keywords to the `-k` argument: `-k kinase,phosphatase`. The tool will search for CDS entries that match these keywords in their product descriptions.

---

## [1623] source=multitask_sft_big

**USER:** We are preparing our CyTOF inputs for `sconify`. We have `markers.csv` categorizing our static and functional markers, and `cell_data.csv` containing concatenated single-cell expression measurements. How do these map to the workflow inputs?

**ASSISTANT:** The inputs map to the `sconify` workflow as follows:
- `markers.csv`: Provided to the required `markers.csv` input parameter (CSV file containing static and functional marker classifications).
- `cell_data.csv`: Provided to the required `cell_data.csv` input parameter (CSV file or R data frame of concatenated single-cell expression data across conditions).

---

## [1624] source=multitask_sft_big

**USER:** What information must be included in the `paired_design.csv` input for `gsalightning_paired_gsa`?

**ASSISTANT:** `paired_design.csv` must be a metadata file containing paired subject indicators and condition signs for the samples.

---

## [1625] source=multitask_sft_big

**USER:** Which Bioconductor packages are integrated into the motifstack workflow, and what is its primary output?

**ASSISTANT:** The motifstack workflow utilizes the Bioconductor tools 'bioconductor/motifstack', 'bioconductor/jaspar2020', 'bioconductor/motifdb', 'bioconductor/rcolorbrewer', 'bioconductor/tfbstools', and 'bioconductor/ade4'. Its primary output is 'cluster_assignments'.

---

## [1626] source=multitask_sft_big

**USER:** Is the file `pbmc3k_filtered_gene_bc_matrices.tar.gz` marked as required or optional in nebulosa_seurat_density, and is it read directly by the workflow?

**ASSISTANT:** In the `nebulosa_seurat_density` workflow parameters, `pbmc3k_filtered_gene_bc_matrices.tar.gz` has `optional: true` and `read_by_workflow: false`.

---

## [1627] source=multitask_sft_big

**USER:** I am configuring colorGff and want to set the track color to a shade of purple with Red=128, Green=0, and Blue=128. How should I provide this parameter?

**ASSISTANT:** In `colorGff`, colors are specified as three space-separated integer values from 0 to 255 representing Red, Green, and Blue. For your requested color, provide: `128 0 128`.

---

## [1628] source=multitask_sft_big

**USER:** What are the allowed choices for the peak overlap method in 'damidseq find peaks', and what is the current setting?

**ASSISTANT:** The allowed options are 'min' (call minimum overlapping peak area) and 'max' (call maximum overlap as peak). The current value is 'max'.

---

## [1629] source=multitask_sft_big

**USER:** I am preparing files for the marray workflow. I have raw Spot intensity files in my folder, a Gene Pix Array List file fish.gal, and SwirlSample.txt describing dye swaps. Which input files does marray take?

**ASSISTANT:** The `marray` workflow takes the following inputs:
1. `SwirlSample.txt`: targets file describing samples and dye assignments.
2. `fish.gal`: Gene Pix Array List file containing array layout and gene names.
3. `Spot/raw intensity files`: raw data files located in the specified directory.

Running this will generate `normalized_data`.

---

## [1630] source=multitask_sft_big

**USER:** Prepare the input parameter mapping for variantannotation_vcf_filtering using our file 'chr7-sub.vcf.gz'.

**ASSISTANT:** Based on the workflow specification, the required parameter mapping is:
```json
{
  "chr7": "chr7-sub.vcf.gz"
}
```
Note that the companion Tabix index file (`chr7-sub.vcf.gz.tbi`) must also be available alongside the input VCF.

---

## [1631] source=multitask_sft_big

**USER:** I am configuring `qiime2 diversity filter-distance-matrix` to discard all samples that meet my metadata query rather than keeping them. Which parameter controls this behavior?

**ASSISTANT:** To discard matching samples instead of retaining them, set the parameter `exclude_ids` to `True`.

---

## [1632] source=multitask_sft_big

**USER:** I want to filter alignments in Gecko based on score ratio. Which parameter definition handles similarity thresholding?

**ASSISTANT:** The relevant setting is the percentage of similarity threshold, which Gecko defines and computes as the attained score divided by the maximum possible score.

---

## [1633] source=multitask_sft_big

**USER:** Please set up the input for survcomp_survival_curve_visualization using my clinical transcriptomics file containing survival times, survival events, and stratified gene expression risk groups.

**ASSISTANT:** Based on the workflow requirements, here is the extracted input mapping:
- `Survival`: Survival times, survival events, and group indicators (e.g., dataset names or stratified gene expression levels).

---

## [1634] source=multitask_sft_big

**USER:** I'm setting up the 'Generate a word cloud' tool. Which default font does it use if I don't select one?

**ASSISTANT:** By default, the tool uses the 'DroidSansMono' font if no alternative prebuilt font is selected.

---

## [1635] source=multitask_sft_big

**USER:** What input datasets and file types are required to execute the 'motifstack_advanced_grouped_layouts' workflow?

**ASSISTANT:** The workflow requires two data inputs:
1. 'pfms': An RDS file containing a list of PFM (Position Frequency Matrix) objects.
2. 'df': A data file associated with the motif grouping/layout configuration.

---

## [1636] source=multitask_sft_big

**USER:** Please set up discorhythm_batch_rhythm_analysis for my dataset `temporal_data.csv` which has all unique IDs in column 1 and prefixed metadata across the timepoints.

**ASSISTANT:** Extracted parameter configuration for `discorhythm_batch_rhythm_analysis`:
- `data_inputs`:
  - `temporal_data.csv`: "temporal_data.csv" (matrix with unique feature IDs in column 1 and column headers formatted as Prefix_Time_UniqueID_ReplicateID).

---

## [1637] source=multitask_sft_big

**USER:** I am configuring antaRNA for an RNA design experiment where I need to handle pseudoknots. Which flag should I pass to apply optimized pseudoknot parameters?

**ASSISTANT:** To apply optimized parameters for pseudoknot handling in antaRNA, use the `-pkPar` flag. Note that enabling `-pkPar` will cause further parameter inputs to be ignored.

---

## [1638] source=multitask_sft_big

**USER:** Here are the files for our Bambu run:
Training alignments: /data/train/human.bam
Training annotations: /data/train/gencode.gtf
Training genome: /data/train/hg38.fa
Target alignments: /data/target/nonmodel.bam
Target reference: /data/target/nonmodel_genome.fa
Map them to the inputs of bambu_model_training_and_denovo_discovery.

**ASSISTANT:** Here is the parameter mapping for `bambu_model_training_and_denovo_discovery`:
- `sample1.bam`: "/data/train/human.bam"
- `annotations`: "/data/train/gencode.gtf"
- `fa.file`: "/data/train/hg38.fa"
- `sample2.bam`: "/data/target/nonmodel.bam"
- `fa.file2`: "/data/target/nonmodel_genome.fa"

---

## [1639] source=multitask_sft_big

**USER:** I have a compound with smiles "CC(=O)Oc1ccccc1C(=O)O", a Cmax of 1.5 uM, and I want to screen OATP1B1, P-gp, and BCRP. How should I set the inputs for Transporter Ddi Prediction?

**ASSISTANT:** Map your parameters to the Transporter Ddi Prediction inputs as follows:
- smiles_list: ["CC(=O)Oc1ccccc1C(=O)O"]
- Cmax_uM: 1.5
- transporters: ["OATP1B1", "P-gp", "BCRP"]

---

## [1640] source=multitask_sft_big

**USER:** Please set up the isanalytics_clonal_sharing_analysis workflow inputs using my saved files: integration_matrices at '/data/matrices.rds' and metadata association at '/data/metadata.rds'.

**ASSISTANT:** Here are the extracted parameters for `isanalytics_clonal_sharing_analysis`:
- `integration_matrices`: '/data/matrices.rds'
- `association_file`: '/data/metadata.rds'

---

## [1641] source=multitask_sft_big

**USER:** What input files are required to execute the isocorrector workflow, and what outputs does it generate?

**ASSISTANT:** The `isocorrector` workflow accepts three input files in CSV or XLS/XLSX format:
- `MeasurementFile` (uncorrected measurements)
- `ElementFile` (element information)
- `MoleculeFile` (molecule information)

It generates outputs in three formats: `table/csv`, `plot/pdf`, and `object/rds`.

---

## [1642] source=multitask_sft_big

**USER:** I want to run `categorized_dist_scatterplot` on my 16S amplicon data, filtering the plotted samples to only those where TreatmentGroup is Control. How do I format this required filter parameter?

**ASSISTANT:** Specify the matching state as `TreatmentGroup:Control`, following the required metadata syntax (similar to `AgeCategory:Child`).

---

## [1643] source=multitask_sft_big

**USER:** What data inputs are defined for the snprelate_pca_and_ld_pruning workflow?

**ASSISTANT:** The workflow defines two data inputs: `genofile` (type: data, optional: true, description: 'Open GDS file handle') and `input_files` (type: data).

---

## [1644] source=multitask_sft_big

**USER:** Configure nf-core/omicsgenetraitassociation for my summary statistics where the gene identifier column is 'GENE_ID', p-value column is 'P_VAL', and I want to set a significance threshold alpha of 0.01 with 5000 tests.

**ASSISTANT:** Here are the extracted parameters mapped to the workflow configuration:
- `gene_col_name`: "GENE_ID"
- `pval_col_name`: "P_VAL"
- `alpha`: 0.01
- `numtests`: 5000

---

## [1645] source=multitask_sft_big

**USER:** In the raw dataset for 'Conversion GCMS PostRun Analysis to IsoCor', what data must be stored in the 'Name' and 'Area' columns?

**ASSISTANT:** The 'Name' column must be filled with each carbon isotopologue of each fragment considered, and the 'Area' column must contain the quantitative peak area for those fragments.

---

## [1646] source=multitask_sft_big

**USER:** I need to process a dataset generated with 10x Genomics Feature Barcoding technology via kb_python. What is the exact workflow option for this?

**ASSISTANT:** The exact workflow option to use in kb_python for 10x Genomics Feature Barcoding technology is `kite:10xFB`.

---

## [1647] source=multitask_sft_big

**USER:** I am configuring Kinatest-ID 7_to_7 to run on src kinase and jak2. How should these kinase names be entered?

**ASSISTANT:** Kinase names must be written in ALL CAPS for the R script to recognize them. For your selections, you must enter them as `SRC` and `JAK2`.

---

## [1648] source=multitask_sft_big

**USER:** Set up an execution of the Et Full Pipeline workflow with tilt series at '/data/ts_01.mrc', mdoc at '/data/ts_01.mdoc', pixel size of 1.35 Å, 300 kV voltage, spherical aberration 2.7 mm, total dose of 60 e/Å², tilt range from -60 to 60 with a 3 degree increment, using AreTomo2 for alignment, tilt axis angle of 85.3, patch alignment enabled, WBP reconstruction, tomogram thickness 200 nm, binning factor 4, extracting 5000 particles with C1 symmetry, targeting 8.0 Å resolution over 3 STA rounds, and template PDB '/data/ribosome.pdb'.

**ASSISTANT:** Here are the extracted parameters for the `Et Full Pipeline` workflow:
- tiltseries_path: "/data/ts_01.mrc"
- mdoc_path: "/data/ts_01.mdoc"
- pixel_size: 1.35
- voltage: 300
- spherical_aberration: 2.7
- total_dose: 60
- tilt_range_min: -60
- tilt_range_max: 60
- tilt_increment: 3
- alignment_method: "AreTomo2"
- tilt_axis_angle: 85.3
- patch_alignment: true
- reconstruction_method: "WBP"
- tomogram_thickness_nm: 200
- binning_factor: 4
- num_particles: 5000
- symmetry: "C1"
- sta_resolution_target: 8.0
- num_sta_rounds: 3
- template_pdb: "/data/ribosome.pdb"

---

## [1649] source=multitask_sft_big

**USER:** We are preparing our adverse event records for automated grading. Here is the info: canine subject, vomiting episodes, severity score 3, categorized as gastrointestinal. Which parameters map to the Apply Vcog Grade workflow inputs?

**ASSISTANT:** The input parameters for the 'Apply Vcog Grade' workflow map as follows:
- species: canine
- symptom: vomiting
- severity_value: 3
- event_type: gastrointestinal

---

## [1650] source=multitask_sft_big

**USER:** Which stopping criterion or threshold parameter in hifive determines convergence during learning?

**ASSISTANT:** The criterion is the cutoff for the absolute gradient values, which terminates the learning process once every gradient value falls below this specified threshold.

---

## [1651] source=multitask_sft_big

**USER:** I want to run `altcdfenvs_subset_and_modify_cdf_env`. I have the package 'plasmodiumanophelescdf' ready along with a list of IDs saved at 'Plasmodium-Probeset-IDs.txt'. Can you identify the required inputs?

**ASSISTANT:** The required data inputs for `altcdfenvs_subset_and_modify_cdf_env` are:
- `plasmodiumanophelescdf`: the existing CDF package/environment.
- `Plasmodium-Probeset-IDs.txt`: a text file containing the specific probe set IDs of interest to retain.

---

## [1652] source=multitask_sft_big

**USER:** I plan to run scmerge_sc_merge_v2. What outputs will be generated by this workflow?

**ASSISTANT:** The scmerge_sc_merge_v2 workflow produces two outputs:
1. `cluster_assignments`
2. `singlecellexperiment` (the integrated SingleCellExperiment object).

---

## [1653] source=multitask_sft_big

**USER:** What parameters and input arguments are required to construct an index with smalt index?

**ASSISTANT:** `smalt index` requires the following positional arguments:
- `<wordlen>`: A fixed integer specifying the k-mer word length.
- `<stepsiz>`: The equidistant step size (in bases) between sampled k-mer words.
- `<reference_file>`: A single file containing the reference sequences in FASTA or FASTQ format.

---

## [1654] source=multitask_sft_big

**USER:** We need to set up multi-locus sequence typing for Escherichia spp using the Achtman scheme from pubMLST. Please extract the configuration details.

**ASSISTANT:** From your request, the parameters for the 'Import MLST database' tool are:
- Target organism: Escherichia spp
- MLST scheme: achtman (mlst=achtman)
- Source: pubMLST

---

## [1655] source=multitask_sft_big

**USER:** I want to run meb_scmeb_single_cell. My scRNA-seq data is in an RDS file named 'pbmc_counts.rds' as a SingleCellExperiment object, and I have identified housekeeping genes listed in 'housekeeping_indices.rds'. Please configure the inputs.

**ASSISTANT:** Here is the configured input mapping for the meb_scmeb_single_cell workflow:
- `sce`: 'pbmc_counts.rds' (SingleCellExperiment object containing scRNA-seq counts)
- `stable_idx`: 'housekeeping_indices.rds' (vector of stable/housekeeping gene names or indices)

---

## [1656] source=multitask_sft_big

**USER:** I want to run subcellular resolution assessment on my file exp_msnset.rds. Please configure the data inputs for proloc_subcellular_resolution_assessment.

**ASSISTANT:** For `proloc_subcellular_resolution_assessment`, the required parameter is:
- `data_inputs`: `[{"name": "spatial_proteomics_data.rds", "type": "rds"}]` (set to your `exp_msnset.rds` file).

---

## [1657] source=multitask_sft_big

**USER:** Here is my pipeline setup: I have raw CyTOF data in 'sample_run1.fcs' and want to run automated event labeling via cytofqc. Can you configure the primary data inputs?

**ASSISTANT:** Based on the `cytofqc` workflow specification, the inputs are mapped as follows:
- `raw_cytof.fcs`: 'sample_run1.fcs' (raw CyTOF data in FCS format)
- Core processing tool: `bioconductor/cytofqc` (executing the all-in-one `labelQC` function)
- Expected outputs: `table/csv`, `plot/pdf`, and `object/rds`.

---

## [1658] source=multitask_sft_big

**USER:** I'm setting up proactiv with STAR junction files. Which parameter name receives these files, and what output formats will the workflow produce?

**ASSISTANT:** The input files are mapped to the 'junction_or_bam_files' parameter. The workflow produces outputs in table/csv, plot/pdf, and object/rds formats.

---

## [1659] source=multitask_sft_big

**USER:** I want to run `herg_cardiac_safety_qsar` on my candidate molecules with SMILES strings 'CC(=O)Oc1ccccc1C(=O)O' and 'CN1CCC[C@H]1c2cccnc2'. What are the inputs and expected outputs?

**ASSISTANT:** For `herg_cardiac_safety_qsar`:
- Input: `smiles` (containing your compound structures: `['CC(=O)Oc1ccccc1C(=O)O', 'CN1CCC[C@H]1c2cccnc2']`)
- Output formats: `json` and `csv` files containing the predicted hERG IC50 (µM), QTc prolongation risk, ICH E14/S7B safety margin and risk tier, and Nav1.5 structural alert flags.

---

## [1660] source=multitask_sft_big

**USER:** I am updating an SBML model with chemical formulas from a tab-delimited file, but my SBML metabolite identifiers include a prefix 'M_' and a suffix '_c' that are missing from the table. How can I handle this with SetChemicalFormulas?

**ASSISTANT:** You can handle identifier discrepancies using the `-p` and `-s` options in `SetChemicalFormulas`. Use `-p` to specify the prefix (e.g., `-p M_`) and `-s` to specify the suffix (e.g., `-s _c`) present in the SBML file so the tool can properly map the identifiers to your tabulated formula file.

---

## [1661] source=multitask_sft_big

**USER:** What script name and input file structures are manipulated by the 'Collapse samples' tool in metagenomics?

**ASSISTANT:** The tool executes `collapse_samples.py` and operates directly on a BIOM table and a metadata mapping file to collapse sample entries.

---

## [1662] source=multitask_sft_big

**USER:** What are the required input data files for running the gtrellis workflow?

**ASSISTANT:** The gtrellis workflow requires a non-optional data input slot named 'input_files', which expects count_data.

---

## [1663] source=multitask_sft_big

**USER:** Here is my data schema for drug response analysis: columns include 'concentration', 'cell_count', 'cell_count__time0', 'cell_count__ctrl', 'cell_line', 'agent', 'replicate', and 'time'. Can this be parsed into the `grmetrics` workflow parameters?

**ASSISTANT:** Yes. This schema matches the required input for `grmetrics`:
- `inputCaseA`: mapped to your data frame containing `concentration`, `cell_count`, `cell_count__time0`, `cell_count__ctrl`, and grouping columns `cell_line`, `agent`, `replicate`, and `time`.

---

## [1664] source=multitask_sft_big

**USER:** I am configuring Mummerplot and need to highlight alignments that have breakpoints located further than 200 bp from the nearest sequence end. Which parameter should I set?

**ASSISTANT:** You should use the `-b` option with a value of 200 (i.e., `-b 200`) to highlight alignments with breakpoints further than the specified breaklen nucleotides from the nearest sequence end.

---

## [1665] source=multitask_sft_big

**USER:** Here is my setup for TranscriptFormer: I have an AnnData file at `data/pbmc.h5ad`, I want to test knock-out of `TP53` in human cells, using GPU device `cuda:0` with a batch size of 64, running perturbation prediction with model files in `/models/tf_v06`. Please extract the workflow parameters.

**ASSISTANT:** Here are the extracted parameters mapped for `virtual_cell/transcriptformer_gpu`:
- `adata_h5ad`: "data/pbmc.h5ad"
- `perturbation_gene`: "TP53"
- `species`: "human"
- `device`: "cuda:0"
- `batch_size`: 64
- `model_dir`: "/models/tf_v06"
- `task`: "perturbation prediction"

---

## [1666] source=multitask_sft_big

**USER:** Which image file extensions and formats does the FTP Link for Bioimage Archive tool support downloading?

**ASSISTANT:** The tool supports downloading image files in TIFF, PNG, and JPG formats compatible with Galaxy.

---

## [1667] source=multitask_sft_big

**USER:** Run sixgill filter on sample_peptides.metapeptides with a minimum amino acid sequence length of 9, a minimum read count of 5, and set the minimum metagenescore to 50.

**ASSISTANT:** The parameters extracted for sixgill filter are:
- positional argument: `sample_peptides.metapeptides` (metapeptidefile)
- `--minaaseqlength`: 9
- `--minreadcount`: 5
- `--minmetagenescore`: 50

---

## [1668] source=multitask_sft_big

**USER:** I am configuring mosdepth to evaluate sequencing coverage across specific genomic intervals rather than just getting the default output. How can I configure this in the tool interface?

**ASSISTANT:** You can configure regional depth calculations by selecting your desired target settings in the "Compute depth by region" selector and configuring the relevant options under the Advanced options section.

---

## [1669] source=multitask_sft_big

**USER:** I am configuring OptiType for paired-end sequencing and want to completely exclude read pairs where only one end maps. What weight value should I set?

**ASSISTANT:** You should set the weight value to 0. A value of 0 specifies that reads with only one mapped end are discarded for typing.

---

## [1670] source=multitask_sft_big

**USER:** Set up a CPA drug combination synergy run: Drug A is Doxorubicin targeting TOP2A with Cmax of 150 nM at a dose ratio of 0.6. Drug B is Paclitaxel targeting TUBB1 with Cmax of 80 nM at dose ratio 0.4. Use cell line MCF7 and the additive synergy model.

**ASSISTANT:** Here are the extracted parameters for `virtual_cell/cpa_drug_combination_synergy`:
- `drug_a_name`: "Doxorubicin"
- `drug_a_targets`: ["TOP2A"]
- `drug_a_cmax_nM`: 150
- `drug_b_name`: "Paclitaxel"
- `drug_b_targets`: ["TUBB1"]
- `drug_b_cmax_nM`: 80
- `cell_line`: "MCF7"
- `synergy_model`: "additive"
- `dose_ratio_a`: 0.6
- `dose_ratio_b`: 0.4

---

## [1671] source=multitask_sft_big

**USER:** What inputs does the `mzR` workflow declare in its configuration?

**ASSISTANT:** The `mzR` workflow declares an optional data input named `count_data` (type: data, `optional: true`, `read_by_workflow: false`).

---

## [1672] source=multitask_sft_big

**USER:** What input file types are required to run nf-core/fastq_align_hisat2, and what output file types does it generate?

**ASSISTANT:** Based on the workflow specification for 'nf-core/fastq_align_hisat2':
- **Inputs:** `reads`, `ht2` (HISAT2 index files), `txt`, and `fasta` (reference genome).
- **Outputs:** `bam`, `log`, `fastq`, `bai`, `stats`, `flagstat`, and `idxstats`.

---

## [1673] source=multitask_sft_big

**USER:** What input parameters or directories do I need to supply to execute the spaniel workflow?

**ASSISTANT:** The `spaniel` workflow requires the `pathToTenXOuts` parameter, which is the path to the directory containing 10X Genomics Space Ranger output files (including the filtered feature-barcode matrix and the spatial imaging folder).

---

## [1674] source=multitask_sft_big

**USER:** How do I configure rrBLUP to perform model evaluation via cross-validation instead of fitting a standard prediction model?

**ASSISTANT:** Set the model/evaluation selection parameter to 1. Setting this value to 1 switches the tool to evaluation mode, which also requires specifying the 'folds' argument. Any other value simply produces a model.

---

## [1675] source=multitask_sft_big

**USER:** I have preclinical pharmacokinetic data formatted as a JSON array with clearance and volume parameters across rat, dog, and monkey. Can the allometric_scaling workflow handle this, and what does it extract?

**ASSISTANT:** Yes. The `allometric_scaling` workflow accepts a JSON array of per-species preclinical PK data (specifically rat, dog, and monkey). From this input, it extracts the pharmacokinetic parameters clearance (CL), volume of distribution (Vd), and half-life (t½) to perform cross-species scaling.

---

## [1676] source=multitask_sft_big

**USER:** What inputs does fishalyser_manual_threshold_and_particle_cleaning accept, and is the image input strictly mandatory?

**ASSISTANT:** The workflow accepts `SampleFISHgray.jpg` (described as a grayscale image of cell culture) and `input_file`. In the workflow parameters, `SampleFISHgray.jpg` is flagged as an optional data input (`optional: true`).

---

## [1677] source=multitask_sft_big

**USER:** Please run Plink2 Filter on my dataset with a minimum maf threshold and variant-level filtering enabled.

**ASSISTANT:** Extracted filter parameters for `Plink2 Filter`:
- Input types: PLINK bfiles or pfiles
- Filters specified: `maf` (minor allele frequency) and `var` (variant filtering).

---

## [1678] source=multitask_sft_big

**USER:** I am configuring QIIME's `parallel_blast` job and need to define the path to the polling script. What is the default path used by the tool?

**ASSISTANT:** The default path for the poller script in `parallel_blast` is `/usr/local/lib/python2.6/site-packages/scripts/poller.py` (specifying the full path to `qiime/parallel/poller.py`).

---

## [1679] source=multitask_sft_big

**USER:** What input data slot is declared for the panelcn_mops Nextflow workflow?

**ASSISTANT:** The workflow declares a mandatory data input parameter named `input_files` (type: `data`), which receives the required `count_data`.

---

## [1680] source=multitask_sft_big

**USER:** Run the aldex2_complex_design_glm workflow on my count matrix `raw_counts.tsv` and metadata table `sample_factors.csv`.

**ASSISTANT:** I have mapped your inputs to the `aldex2_complex_design_glm` workflow parameters:
- `selex.sub`: `raw_counts.tsv` (matrix of features by samples)
- `covariates`: `sample_factors.csv` (data frame of covariates)

The workflow will execute GLM-based differential abundance analysis and return differential abundance tables and visualizations.

---

## [1681] source=multitask_sft_big

**USER:** I am configuring `cner_pairwise_whole_genome_alignment` and need to specify the target genome sequence. What input parameter handles this file and in what format?

**ASSISTANT:** The target genome is specified using the `single_sequences.2bit` parameter, which expects a 2bit-formatted sequence file of the target genome.

---

## [1682] source=multitask_sft_big

**USER:** I have sequencing data from a mixed bacterial population evolved from a common ancestor and need to capture subclonal variants. Which mode of breseq should be configured?

**ASSISTANT:** You should configure breseq in **polymorphism mode**, which is specifically designed to analyze mixed populations derived from a common ancestor and can detect variants across frequencies ranging from 0% to 100%.

---

## [1683] source=multitask_sft_big

**USER:** Configure the rfastp paired-end QC workflow using /seq_data/libA_R1.fq.gz for read 1 and /seq_data/libA_R2.fq.gz for read 2.

**ASSISTANT:** Here are the extracted parameters for `rfastp_paired_end_qc_trimming_merging`:
- `reads1.fastq.gz`: /seq_data/libA_R1.fq.gz
- `reads2.fastq.gz`: /seq_data/libA_R2.fq.gz

---

## [1684] source=multitask_sft_big

**USER:** Here is my transcriptomic dataset for advanced fRMA processing: count_matrix.tsv located at /data/counts/count_matrix.tsv. Please configure the inputs for the frmaTools workflow.

**ASSISTANT:** Here is the input mapping for the `frmaTools` workflow based on your specification:

- `input_files`: `/data/counts/count_matrix.tsv` (type: data, fulfilling the required `count_data` input).

---

## [1685] source=multitask_sft_big

**USER:** What are the data input slots specified for the MotifDb workflow?

**ASSISTANT:** The workflow lists `count_data` as its input, with an underlying declared input parameter slot named `input_files`.

---

## [1686] source=multitask_sft_big

**USER:** What input parameters are required to run the intact workflow?

**ASSISTANT:** The `intact` workflow requires two data inputs:
1. `GLCP_vec`: A numeric vector containing gene-level colocalization probabilities.
2. `z_vec`: A numeric vector containing TWAS scan z-scores.

---

## [1687] source=multitask_sft_big

**USER:** Please run a parallel batch GESS search with my query list containing up- and down-regulated gene sets stored in R object `my_signatures` against the reference database file at `/data/refdb/lincs_hg.h5`.

**ASSISTANT:** Extracted parameters for `signaturesearch_batch_gess_processing`:
- `batch_queries`: `my_signatures` (list containing upset and downset gene lists)
- `refdb`: `"/data/refdb/lincs_hg.h5"` (path to the reference HDF5 database file)

These inputs will be used to execute the batch query processing across parallel cores or cluster nodes to generate visualizations.

---

## [1688] source=multitask_sft_big

**USER:** What data inputs are defined for the mait_external_peak_data_analysis workflow?

**ASSISTANT:** The workflow defines `peaks`, which is a required matrix of peak intensities/scores (`optional: false`, `read_by_workflow: true`), and `masses`.

---

## [1689] source=multitask_sft_big

**USER:** I am configuring PAPAA: PanCancer map mutation class (Graphics) and want to specify the pathway genes TP53, BRCA1, and EGFR. What parameter should I set?

**ASSISTANT:** You should use the `--path_genes` parameter. It accepts a comma-separated string of HUGO symbols (e.g., `--path_genes TP53,BRCA1,EGFR`) or a pathway genes list file.

---

## [1690] source=multitask_sft_big

**USER:** What input parameters and file paths need to be specified for the ioniser workflow?

**ASSISTANT:** The workflow takes the input pattern `/path/to/data/*.fast5`, representing the directory containing your Oxford Nanopore raw or basecalled FAST5 read files.

---

## [1691] source=multitask_sft_big

**USER:** I am configuring `collate_alpha`. How does it determine which samples and metrics to include if I don't explicitly provide an example alpha diversity analysis file?

**ASSISTANT:** By default, the example alpha_diversity analysis file containing all samples and metrics to be included is chosen automatically as specified in the tool's usage string.

---

## [1692] source=multitask_sft_big

**USER:** I am preparing alignment files for Cuffdiff for cummeRbund across a 4-point developmental timecourse: day0.sam, day2.sam, day4.sam, day7.sam. How should I arrange these inputs to perform a time-series evaluation instead of standard pairwise comparisons?

**ASSISTANT:** To run Cuffdiff in time-series mode rather than all-pairwise comparisons, instruct Cuffdiff to analyze the samples as a time series and provide the alignment files in increasing chronological order on the command line: first `day0.sam`, second `day2.sam`, third `day4.sam`, and fourth `day7.sam`.

---

## [1693] source=multitask_sft_big

**USER:** Please configure the input for the liquidassociation_genome_wide_triplet_screening workflow using my expression matrix file named 'pilot_cohort_matrix.tsv'.

**ASSISTANT:** Here is the configured input for the workflow:

```json
{
  "lae": "pilot_cohort_matrix.tsv"
}
```
Ensure that 'pilot_cohort_matrix.tsv' contains samples as rows and genes as columns as required by the 'lae' input specification.

---

## [1694] source=multitask_sft_big

**USER:** Set up my AMBER MD run with a timestep of 0.002 ps, 1000000 steps, running at 310 K and 1.0 bar pressure on a GPU.

**ASSISTANT:** Extracted workflow parameters:
- dt: 0.002
- n_steps: 1000000
- temperature: 310
- pressure: 1.0
- gpu: true

---

## [1695] source=multitask_sft_big

**USER:** What output files and underlying tools are configured in the flowclean workflow?

**ASSISTANT:** The `flowclean` workflow uses the tool `bioconductor/flowclean` and generates `visualizations` as its output after processing the input `user_data.fcs` file.

---

## [1696] source=multitask_sft_big

**USER:** I want to run nhmmer searching 'transcripts.fa' against 'reference_genome.fa'. Map these to the nhmmer arguments.

**ASSISTANT:** Based on the nhmmer usage syntax (`nhmmer <queryfile> <seqdb>`):
- `<queryfile>`: transcripts.fa
- `<seqdb>`: reference_genome.fa

---

## [1697] source=multitask_sft_big

**USER:** Which Bioconductor packages are used by the MEAT workflow, and what is its primary input parameter?

**ASSISTANT:** The MEAT workflow utilizes the Bioconductor packages bioconductor/meat, bioconductor/summarizedexperiment, and bioconductor/minfi. Its primary input data slot is declared as 'input_files'.

---

## [1698] source=multitask_sft_big

**USER:** How does OTB.BandMath accept the mathematical formula to process image bands?

**ASSISTANT:** OTB.BandMath accepts the formula via a muParser mathematical expression applied to input images, for example using syntax like 'im1b3,im1b2,im1b1'.

---

## [1699] source=multitask_sft_big

**USER:** What input files are required by blastx_to_scaffold to scaffold contigs?

**ASSISTANT:** blastx_to_scaffold requires two inputs: DNA contigs provided in FASTA format, and a tabular blastx output containing the 12 standard columns plus a 13th column denoting the blastx subject sequence length.

---

## [1700] source=multitask_sft_big

**USER:** I am configuring MetaProSIP with a featureXML reference file. What value should I set for it?

**ASSISTANT:** If featureXML from a reference file is used in MetaProSIP, it should be disabled by setting it to -1, as no mono-isotopic peak is expected to be present.

---

## [1701] source=multitask_sft_big

**USER:** Configure the RNAz windows tool to discard any window alignments that have fewer than 5 sequences.

**ASSISTANT:** The parameter configuration based on your requirement is:
- Minimum number of sequences in an alignment: 5 (windows with less than 5 sequences will be discarded).

---

## [1702] source=multitask_sft_big

**USER:** What input format does ParseBlastForUniqueMatch accept from Galaxy history?

**ASSISTANT:** ParseBlastForUniqueMatch accepts a BLAST file from your history that has either 25 columns or 5 custom columns formatted as: qseqid, qstart, qend, ssseq, sseq.

---

## [1703] source=multitask_sft_big

**USER:** Can you check the parameter settings for crisprscore_cas12a_on_target_scoring and tell me if user_sequences.txt is optional?

**ASSISTANT:** In the `crisprscore_cas12a_on_target_scoring` workflow configuration, `user_sequences.txt` has `optional: false`, meaning it is strictly required and read directly by the workflow.

---

## [1704] source=multitask_sft_big

**USER:** Which input file formats can I pass to the `-i` parameter in HHsearch?

**ASSISTANT:** The `-i` parameter of HHsearch accepts a single sequence or multiple sequence alignment (MSA) in a3m, a2m, or FASTA format, or a profile HMM in hhm format.

---

## [1705] source=multitask_sft_big

**USER:** How do I provide an NCBI API key to MITOHIFI_FINDMITOREFERENCE when running it in Nextflow?

**ASSISTANT:** An optional NCBI API key can be supplied to MITOHIFI_FINDMITOREFERENCE using Nextflow's secrets feature by running:
`nextflow secrets set NCBI_API_KEY <key>`.

---

## [1706] source=multitask_sft_big

**USER:** I am configuring KOBAS Identify for samples from mouse and baker's yeast. What species abbreviations should I specify?

**ASSISTANT:** For mouse (*Mus musculus*), specify `mmu`, and for baker's yeast (*Saccharomyces cerevisiae*), specify `sce`.

---

## [1707] source=multitask_sft_big

**USER:** When running 'Cell types - get tool performance table', what constraint must be satisfied if I enable `include-sem-siml`?

**ASSISTANT:** If `include-sem-siml` is set to `True`, the semantic similarity metric you select must produce values within the `[0; 1]` interval. Refer to the Bioconductor Onassis package documentation for metric specifics.

---

## [1708] source=multitask_sft_big

**USER:** What licensing inputs and tools are defined for the `simcyp_pbpk` workflow?

**ASSISTANT:** For BYOL (Bring Your Own License), you must provide either `SIMCYP_LICENSE_FILE` or `SIMCYP_LICENSE_SERVER`. The workflow relies on the tools `Simcyp CLI`, `BioMate native PBPK fallback`, and `log-normal IIV`.

---

## [1709] source=multitask_sft_big

**USER:** I am configuring ChiRA map for my RNA sequencing data. Which aligners can I select within this tool?

**ASSISTANT:** Within `ChiRA map`, you can choose between two alignment tools: `bwa-mem` and `CLAN`.

---

## [1710] source=multitask_sft_big

**USER:** Please set up the sc3_step_by_step_sc3_pipeline using my files at '/data/normalized_counts.csv' and metadata at '/data/sample_annotations.csv'.

**ASSISTANT:** Here is the mapped parameter configuration for `sc3_step_by_step_sc3_pipeline`:
- `expression_matrix.csv`: "/data/normalized_counts.csv" (QCed and normalized single-cell expression matrix)
- `cell_metadata.csv`: "/data/sample_annotations.csv" (Cell annotations/phenotypes)

---

## [1711] source=multitask_sft_big

**USER:** I want to retrieve the predicted 3D structure for human p53 using its UniProt accession P04637 through the query_alphafold tool. What target identifier should be extracted for the API call?

**ASSISTANT:** The target identifier to pass to the `query_alphafold` tool descriptor is the UniProt accession: `P04637`.

---

## [1712] source=multitask_sft_big

**USER:** Here is my setup: raw case files are stored in '/data/methylation/cases/' which contains the IDAT files and SampleSheet.csv. Which workflow parameter accepts this directory in 'epimutacions'?

**ASSISTANT:** The directory containing the raw case IDAT files and SampleSheet.csv corresponds to the 'baseDir' parameter in the 'epimutacions' workflow.

---

## [1713] source=multitask_sft_big

**USER:** What are the configured input slots and parameters for the VCFArray workflow?

**ASSISTANT:** The VCFArray workflow has no configurable parameters (`parameters: []`). It defines a single declared input slot named `count_data`, which is of type 'data', marked as optional (`optional: true`), and not read by the workflow (`read_by_workflow: false`).

---

## [1714] source=multitask_sft_big

**USER:** I am converting my GTF annotation to BED12 using fromgtftobed12. I want the 4th column identifier to be gene_id rather than the default transcript_name.

**ASSISTANT:** Understood. For 'fromgtftobed12', configure the 4th column identifier option to `'gene_id'` to override the default `transcript_name`/`gene_name` behavior.

---

## [1715] source=multitask_sft_big

**USER:** I want to run `flowclust_flowcore_integration` on my local single-cell cytometry file located at `/data/cytometry/rituximab2_filtered.rds`. Can you set up the inputs?

**ASSISTANT:** Here is the extracted input configuration for `flowclust_flowcore_integration`:

```json
{
  "rituximab2": "/data/cytometry/rituximab2_filtered.rds"
}
```

---

## [1716] source=multitask_sft_big

**USER:** Please configure the data inputs for `sctensor` using my files: my counts are in `gene_expression_matrix.csv` with NCBI Gene IDs as row names, and cell annotations with UMAP coordinates are in `cell_metadata.csv`.

**ASSISTANT:** The data inputs for `sctensor` are configured as follows:
- `gene_expression_matrix.csv`: `gene_expression_matrix.csv` (dense matrix with NCBI Gene IDs as row names)
- `cell_metadata.csv`: `cell_metadata.csv` (cell metadata containing cell type labels and 2D coordinates)

---

## [1717] source=multitask_sft_big

**USER:** Configure PySCENIC CTX for a single-cell RNA-seq experiment where memory is constrained and we need to run GRN inference using a sparse matrix representation.

**ASSISTANT:** For PySCENIC CTX on single-cell RNA-seq data with memory constraints, enable the option to load expression data as a sparse matrix. Note that this sparse matrix setting will apply specifically to the GRN (gene regulatory network) inference step.

---

## [1718] source=multitask_sft_big

**USER:** Here is my command line invocation for read trimming: kraken_filter --p /db/ete3_tax.db kraken_run.report 9606 sample_R1.fastq sample_R2.fastq. What positional arguments were passed?

**ASSISTANT:** Based on the kraken_filter command structure, the extracted positional arguments are:
- ETE3 taxonomy database: `/db/ete3_tax.db`
- kraken report: `kraken_run.report`
- taxid: `9606`
- fastq: `sample_R1.fastq`
- fastq_reverse: `sample_R2.fastq`
- Optional flag: `--p`

---

## [1719] source=multitask_sft_big

**USER:** What are all the required inputs and outputs of the scthi workflow?

**ASSISTANT:** The `scthi` workflow requires two inputs: `expMat` (a matrix of single-cell RNA-seq counts/normalized counts with Hugo Symbols as rows and cells as columns) and `cell_metadata` (annotation of each cell to define cluster groups). Its generated output is `visualizations`.

---

## [1720] source=multitask_sft_big

**USER:** I want to execute the degseq workflow with my counts table named 'sample_read_counts.tsv'. What parameter should I set, and what output should I expect?

**ASSISTANT:** You should map 'sample_read_counts.tsv' to the required data input parameter `geneExpFile.txt`. The workflow will process this input and generate the differential expression output table named `de_table`.

---

## [1721] source=multitask_sft_big

**USER:** I need to run the kegglincs pipeline on pathway identifier hsa04068. Can you extract the necessary input parameters?

**ASSISTANT:** Based on the kegglincs workflow specification, the required parameter extracted is:
- `hsa04068`: "hsa04068" (type: data, description: KEGG pathway ID string, optional: false).

---

## [1722] source=multitask_sft_big

**USER:** What are the input parameters associated with motifs in the difflogo_pwm_alignment workflow?

**ASSISTANT:** The workflow accepts motif data inputs including 'pwm_long.pwm' (described as 'A long PWM motif') and 'pwm_short.pwm'.

---

## [1723] source=multitask_sft_big

**USER:** Please convert my variant callset 'cohort_calls.vcf' to pgSnp format using VCF to pgSnp, but I only want to extract the single individual in column 'Sample_03' rather than pooling everyone.

**ASSISTANT:** I have extracted the following parameters from your request for **VCF to pgSnp**:
- **Input dataset**: `cohort_calls.vcf`
- **Conversion mode**: Single selected column
- **Target column/individual**: `Sample_03`

---

## [1724] source=multitask_sft_big

**USER:** I need to prepare my input list of taxids for 'Get acc number from MEGABLAST_TAB_get_acc_taxid and taxid user'. How should the text file be structured?

**ASSISTANT:** The input text file must contain a list of NCBI Taxonomy IDs formatted with exactly one taxid per line, which will be used to select (in) or remove (out) corresponding nodes or accession numbers from the tabular file.

---

## [1725] source=multitask_sft_big

**USER:** Set up the SLqPCR workflow for my project using the dataset file located at 'experiments/qpcr_plate_counts.tsv'.

**ASSISTANT:** Here is the extracted configuration for the SLqPCR workflow:
- input_files: experiments/qpcr_plate_counts.tsv

No additional workflow parameters are required.

---

## [1726] source=multitask_sft_big

**USER:** I am configuring Phyloseq Abundance Taxonomy for my 16S amplicon study. I want the plot legend color to correspond to my sample metadata column 'TreatmentGroup'. How should this be configured?

**ASSISTANT:** For Phyloseq Abundance Taxonomy, configure the parameter `Column used as legend` to `TreatmentGroup`. This selects that metadata group to fill colors representing the group each sample belongs to.

---

## [1727] source=multitask_sft_big

**USER:** I am configuring the principal_coordinates tool for my metagenomics pipeline and want to run multiple diversity metrics at the same time. Which input setting should I use?

**ASSISTANT:** In the principal_coordinates tool, you should set the input file selection to 'multiple files' to process multiple diversity metrics simultaneously.

---

## [1728] source=multitask_sft_big

**USER:** I want to map long reads against themselves using Winnowmap. How should I set up the reference options in the tool?

**ASSISTANT:** To perform self-mapping with Winnowmap, select `history` for the reference source, and then select your input reads file as the reference dataset.

---

## [1729] source=multitask_sft_big

**USER:** How can I speed up segment calculation when running CNVkit Segment, and are there any method constraints to be aware of?

**ASSISTANT:** You can parallelize the execution across chromosome arms by setting the `processes` option. However, note that parallelization via `processes` is supported for segmentation algorithms except for the HMM methods.

---

## [1730] source=multitask_sft_big

**USER:** Set up the Physicell Tumor TGI model for paclitaxel on breast carcinoma. Initial tumor size is 250 mm3, k1 growth rate is 0.08 per day, kill rate k2 is 0.015, EC50 is 2.5 mg/L with Hill coefficient 1.5. Cmax is 12 mg/L, AUC is 85 mg*h/L. We dose every 7 days for 28 days total, with a tumor penetration factor of 0.6.

**ASSISTANT:** Here are the extracted parameters for `virtual_cell/physicell_tumor_tgi`:
- drug_name: paclitaxel
- tumor_type: breast carcinoma
- initial_tumor_vol_mm3: 250
- k1_growth_per_day: 0.08
- k2_kill_rate: 0.015
- ec50_mg_L: 2.5
- hill_n: 1.5
- cmax_mg_L: 12
- auc_mg_h_L: 85
- dosing_interval_days: 7
- treatment_days: 28
- tumor_penetration: 0.6
- tgi_model: Simeoni

---

## [1731] source=multitask_sft_big

**USER:** What input formats are accepted by the mofa2 workflow for training a multi-omic factor analysis model?

**ASSISTANT:** The `mofa2` workflow accepts either:
1. `data`: a list of matrices where features are rows and samples are columns.
2. `dt`: a long data.frame containing the columns `sample`, `feature`, `view`, and `value`.

---

## [1732] source=multitask_sft_big

**USER:** How can I extract representative FASTA sequences alongside my BIOM file when using FROGS TSV_to_BIOM?

**ASSISTANT:** Ensure your TSV table contains a column named 'seed_sequence'. When this column is present, FROGS TSV_to_BIOM can extract the seed sequences directly into a separate FASTA file.

---

## [1733] source=multitask_sft_big

**USER:** Configure the Bispecific Antibody Design workflow for oncology targeting HER2 and CD3. We have antigen sequences HER2_seq and CD3E_seq, arm A VH 'EVQL...' and VL 'DIQM...', arm B VH 'QVQL...' and VL 'DIVM...'. Set format to BiTE, cd3_arm to true, linker_type to (G4S)3, generate 5 designs, and enable developability_filter and immunogenicity_screen.

**ASSISTANT:** Here are the extracted parameters for the Bispecific Antibody Design workflow:

- `antigen_a_seq`: HER2_seq
- `antigen_b_seq`: CD3E_seq
- `arm_a_vh`: "EVQL..."
- `arm_a_vl`: "DIQM..."
- `arm_b_vh`: "QVQL..."
- `arm_b_vl`: "DIVM..."
- `format`: "BiTE"
- `cd3_arm`: true
- `linker_type`: "(G4S)3"
- `n_designs`: 5
- `target_indication`: "oncology"
- `developability_filter`: true
- `immunogenicity_screen`: true

---

## [1734] source=multitask_sft_big

**USER:** What output formats can VCFCarto produce for marker data?

**ASSISTANT:** VCFCarto supports two output format modes: it can either conserve the original input format or convert the markers into a 3-letter format.

---

## [1735] source=multitask_sft_big

**USER:** I am configuring TMTAnalyzer for my isobaric tag quantification study and want to enable the ID pool using the standard OpenMS IDPool.txt path.

**ASSISTANT:** To use the standard IDPool.txt path (`/home/ubuntu/miniconda3/envs/py2test/share/OpenMS/IDPool/IDPool.txt`), configure the parameter:
- `-id_pool`: 'main'

---

## [1736] source=multitask_sft_big

**USER:** What output does the rcm_constrained_rcm workflow generate after processing the Zeller phyloseq object?

**ASSISTANT:** The `rcm_constrained_rcm` workflow generates `visualizations` as its output.

---

## [1737] source=multitask_sft_big

**USER:** I have several HDF5 molecule information files from multiplexed single-cell droplet libraries. Which parameter accepts these in dropletutils_remove_swapping_and_chimeric_effects?

**ASSISTANT:** You should supply them via the `mult.mol.info` parameter, which accepts a character vector of molecule information HDF5 files.

---

## [1738] source=multitask_sft_big

**USER:** Configure the inputs for pagerank_accessibility_grn_generation using my peak coordinates file located at '/data/atac/peaks_coords.csv' and my list of transcription factors at '/data/motifs/tf_regulators.csv'.

**ASSISTANT:** Here are the extracted input parameter bindings for the workflow:
- `peaks.csv`: `/data/atac/peaks_coords.csv`
- `regulators.csv`: `/data/motifs/tf_regulators.csv`

---

## [1739] source=multitask_sft_big

**USER:** We need to run a pediatric PBPK model for an oral formulation of a compound (MW 420.5 Da). In adults, CL is 12.5 L/h, Vd is 75 L, hepatic extraction is 0.35, renal clearance fraction is 0.65, and unbound protein fraction is 0.15. We want to test a 5 mg/kg dose in the 'infant' age group for epilepsy.

**ASSISTANT:** Extracted parameters for `drug_discovery/pbpk_pediatric`:
- `adult_cl_L_h`: 12.5
- `adult_vd_L`: 75
- `adult_mw_da`: 420.5
- `route`: "oral"
- `dose_mg_kg`: 5
- `age_group`: "infant"
- `renal_clearance_fraction`: 0.65
- `hepatic_extraction`: 0.35
- `protein_binding_fraction`: 0.85
- `indication`: "epilepsy"

---

## [1740] source=multitask_sft_big

**USER:** I am configuring MACS14 for sequence analysis. Can you extract the criteria used for region filtering in the model-building step?

**ASSISTANT:** Based on the tool specification, the model building relies on the MFOLD range criteria: it requires selecting regions where the high-confidence enrichment ratio against background is higher than the lower limit and lower than the upper limit.

---

## [1741] source=multitask_sft_big

**USER:** I want to run dnafusion on my deduplicated paired-end sample stored at '/data/alignments/sample1_dedup.bam'. What inputs are defined?

**ASSISTANT:** The workflow configures the input parameter 'file.bam' with your paired-end deduplicated BAM file ('/data/alignments/sample1_dedup.bam').

---

## [1742] source=multitask_sft_big

**USER:** I want to split my ligand SDF library into two subsets with EvenSplit so that both halves span the same molecular weight range. The property in my file is tagged as 'MolWeight'. Which argument do I pass?

**ASSISTANT:** You should use the `-prop` flag to specify the target property name. For your case, provide `-prop MolWeight` to EvenSplit.

---

## [1743] source=multitask_sft_big

**USER:** Which Bioconductor software packages are utilized within the hicontacts workflow?

**ASSISTANT:** The `hicontacts` workflow utilizes the following tools: `bioconductor/hicontacts`, `bioconductor/genomicranges`, `bioconductor/hicexperiment`, `bioconductor/hicontactsdata`, `bioconductor/interactionset`, and `bioconductor/dplyr`.

---

## [1744] source=multitask_sft_big

**USER:** Here is my execution plan for ppcseq:
- Differential expression results table: /data/experiment1/de_tidy_counts.tsv
Can you extract the workflow parameters and inputs for ppcseq?

**ASSISTANT:** Based on your configuration, the parameters and inputs for the `ppcseq` workflow are:
- `counts.tsv`: `/data/experiment1/de_tidy_counts.tsv` (data input containing sample IDs, transcript/gene symbols, abundance values, and differential expression statistics like P-value and FDR)
Outputs generated will include `de_table` and `visualizations`.

---

## [1745] source=multitask_sft_big

**USER:** What input files are required to run the `scdataviz_import_from_seurat` pipeline?

**ASSISTANT:** The workflow requires a mandatory input named `pbmc` (type: rds), which is the Seurat object read directly by the workflow. It also lists `input_files` of type data under its input definitions.

---

## [1746] source=multitask_sft_big

**USER:** I need entry summaries and ligand binding annotations for structure 4hhb. What parameters does the PDBe REST tool require?

**ASSISTANT:** The PDBe REST tool requires a 4-character PDB ID (in your case, `4hhb`) to retrieve entry summaries and residue or ligand binding annotations.

---

## [1747] source=multitask_sft_big

**USER:** Please set up drugclip_virtual_screening for receptor target.pdb against compounds.smi. Set the batch size to 32, find the top 100 compounds, and focus on pocket residues 12,13,14,50.

**ASSISTANT:** Extracted parameters for the drugclip_virtual_screening workflow:
- receptor_pdb: target.pdb
- compounds_smi: compounds.smi
- top_k: 100
- batch_size: 32
- pocket_residues: 12,13,14,50

---

## [1748] source=multitask_sft_big

**USER:** I am running `make_rarefaction_plots` on my 16S amplicon sequencing alpha diversity data, but I need to set the maximum y-axis value so the plots match an earlier study. Which parameter controls this, and what is its default setting?

**ASSISTANT:** The parameter to adjust is `ymax`. By default, its value is `none`. Setting a specific numerical value for `ymax` standardizes the y-axis across runs so you can directly compare rarefaction plots from different analyses.

---

## [1749] source=multitask_sft_big

**USER:** Please set up the input path for flowcatchr using my time-lapse microscopy directory located at '/data/microscopy/flow_assay_1/'.

**ASSISTANT:** Extracted parameter for flowcatchr:
- image.files (/path/to/folder/containi): "/data/microscopy/flow_assay_1/"

---

## [1750] source=multitask_sft_big

**USER:** I am configuring X!Tandem for a proteomics run using trypsin digestion. What value should I provide for the maximum number of missed cleavage sites?

**ASSISTANT:** For trypsin, an aggressive and specific enzyme, you should set the maximum number of missed cleavage sites allowed within a peptide to 1 or 2.

---

## [1751] source=multitask_sft_big

**USER:** Does parallel_multiple_rarefactions automatically retain taxonomic lineage in the resulting rarefied OTU tables?

**ASSISTANT:** No, by default it does not (the default is False). It will include taxonomic (lineage) information for each OTU only if configured and if that information is present in the input OTU table.

---

## [1752] source=multitask_sft_big

**USER:** Configure the bionero_module_preservation workflow with my files: maize_data.rds (SummarizedExperiment for maize), rice_data.rds (SummarizedExperiment for rice), and maize_rice_orthogroups.tsv (orthogroup mappings).

**ASSISTANT:** Here is the parameter mapping for the `bionero_module_preservation` workflow based on your files:

- `zma.se`: maize_data.rds
- `osa.se`: rice_data.rds
- `og.zma.osa`: maize_rice_orthogroups.tsv

---

## [1753] source=multitask_sft_big

**USER:** What is the expected file type and description for the parameter 'ref.rds' in xcms_alignment_to_external_reference?

**ASSISTANT:** The parameter 'ref.rds' requires an RDS file (`type: rds`) and represents the 'Reference XcmsExperiment object'.

---

## [1754] source=multitask_sft_big

**USER:** In the 'Compute the autocovariance' tool, what parameter defines the specific regions where the autocorrelation will be calculated?

**ASSISTANT:** The parameter is 'List of intervals', which provides the list of genomic intervals for each of which the autocorrelation will be computed.

---

## [1755] source=multitask_sft_big

**USER:** What is the default evalue threshold used by virAnnot Rps2tsv?

**ASSISTANT:** The standard maximum evalue threshold for `virAnnot Rps2tsv` has a default value of 0.0001.

---

## [1756] source=multitask_sft_big

**USER:** From the configuration line 'trimAl filtering: position overlap threshold = 0.85 with sequence overlap enabled', extract the relevant position overlap parameter.

**ASSISTANT:** Extracted parameter:
- Minimum overlap of a position: 0.85 (within valid range [0-1], to be used in combination with Sequence overlap).

---

## [1757] source=multitask_sft_big

**USER:** What outputs does the qubic workflow produce upon completion?

**ASSISTANT:** The `qubic` workflow produces three primary outputs: `cluster_assignments`, `expression_matrix`, and `network_graph`.

---

## [1758] source=multitask_sft_big

**USER:** Prepare the input for deltagseg_differentiation_subpopulation_estimation using our trend time series matrix labeled 'norm_protein_series.tsv'.

**ASSISTANT:** The extracted parameter configuration is:
- `y`: `norm_protein_series.tsv` (type: matrix, required: true, description: user-provided matrix or list representing a trend-like time series).

---

## [1759] source=multitask_sft_big

**USER:** Here is my configuration description for running nf-core/readsimulator:
- Input samplesheet: samples.csv
- Forward primer: GTGCCAGCMGCCGCGGTAA
- Reverse primer: GGACTACHVGGGTWTCTAAT
- Simulation type: amplicon
- Output directory: ./sim_output

Please extract the workflow parameters.

**ASSISTANT:** Here are the extracted parameters for `nf-core/readsimulator`:
- `input`: "samples.csv"
- `outdir`: "./sim_output"
- `amplicon`: true
- `amplicon_fw_primer`: "GTGCCAGCMGCCGCGGTAA"
- `amplicon_rv_primer`: "GGACTACHVGGGTWTCTAAT"

---

## [1760] source=multitask_sft_big

**USER:** Which input files are defined for the mariner_loop_enrichment_analysis workflow?

**ASSISTANT:** The defined inputs for the 'mariner_loop_enrichment_analysis' workflow are 'WT_5kbLoops.txt' (a non-optional BEDPE file of loops) and the Hi-C interaction file 'LEUK_HEK_PJA27_inter_30.h'.

---

## [1761] source=multitask_sft_big

**USER:** I want to run nf-core/tbanalyzer on my assembly 'tb_isolate.fasta' with the mode set to 'illumina'. How should these be configured?

**ASSISTANT:** The parameters for `nf-core/tbanalyzer` should be configured as follows:
- `fasta`: "tb_isolate.fasta"
- `mode`: "illumina"

Execution of this pipeline will output the findings to `results_dir`.

---

## [1762] source=multitask_sft_big

**USER:** Please set up the escher_dataframe_visualization workflow using PBMC metadata from 'project_data/pbmc_meta.rds' and 2D coordinates from 'project_data/pbmc_2pc.rds'.

**ASSISTANT:** Here are the extracted input parameters for escher_dataframe_visualization:
- pbmc_meta.rds: 'project_data/pbmc_meta.rds' (data.frame containing metadata)
- pbmc_2pc.rds: 'project_data/pbmc_2pc.rds' (matrix or data.frame containing 2D coordinates like PCA embeddings)

---

## [1763] source=multitask_sft_big

**USER:** What format and gene identifier type are required for the DE_Colorectal input in the spia workflow?

**ASSISTANT:** The `DE_Colorectal` input requires a named numeric vector of log2 fold changes for differentially expressed genes, where the vector names are Entrez IDs.

---

## [1764] source=multitask_sft_big

**USER:** I want to query LINCS using MCF7 cells with top 20 candidates, restricting results only to approved compounds. My up-regulated gene list is in up.txt and down-regulated in down.txt. How do these map to the workflow inputs?

**ASSISTANT:** Based on your configuration, the parameters map as follows:
- `up_genes`: "up.txt"
- `down_genes`: "down.txt"
- `cell_line`: "MCF7"
- `top_k`: 20
- `include_fda_only`: true
Additional expected input parameters for this workflow are `drug_name`, `query_mode`, and `input_type`.

---

## [1765] source=multitask_sft_big

**USER:** I am setting up Hicup Digester for my Hi-C data. My protocol uses two enzymes: BglII (cleaving at A^GATCT) and HindIII (cleaving at A^AGCTT). How should I specify the restriction enzyme parameter?

**ASSISTANT:** In Hicup Digester, multiple enzymes should be separated by a colon (`:`). For BglII and HindIII, specify the restriction enzyme parameter as:
`A^GATCT,BglII:A^AGCTT,HindIII`

---

## [1766] source=multitask_sft_big

**USER:** I have prepared a metadata file for DESeq2 where column 1 is 'sample_id', column 2 is 'file_name', and column 3 is 'condition'. Does this match the required format?

**ASSISTANT:** Yes, this matches the required layout: the first column provides sample names, the second column lists the corresponding count file names (which must match the uploaded files' order), and the remaining column(s) specify the treatment factors.

---

## [1767] source=multitask_sft_big

**USER:** I am configuring the metabolomics Quality Metrics module. I need to visualize the data matrix and flag any unstable variables where the pool CV or pool CV over sample CV ratio exceeds our cutoff threshold. Which tool parameters address this?

**ASSISTANT:** To apply this quality filter, configure the optional 'Coefficient of Variation' arguments (specifically targeting the pool CV and the pool CV over sample CV ratio thresholds) within the Quality Metrics tool.

---

## [1768] source=multitask_sft_big

**USER:** Which option is used to provide the tag for sequence filtering in the TraDIS tool?

**ASSISTANT:** The `-t` option is used to pass the tag for filtering the sequence data.

---

## [1769] source=multitask_sft_big

**USER:** What mandatory inputs are required to run the missmethyl_region_level_gsa workflow?

**ASSISTANT:** The workflow requires two non-optional matrix inputs:
1. 'M': matrix of M-values
2. 'design': design matrix

---

## [1770] source=multitask_sft_big

**USER:** Here are my files for the ipath analysis:
- Gene data: normalized_counts_samples.csv (genes as rows, samples as cols)
- Pathways: hallmarks.gmt
- Patient info: survival_status_time.csv
- Sample types: tumor_normal_labels.csv (0 for normal, 1 for tumor)

Please map these to the required inputs.

**ASSISTANT:** The provided files map to the `ipath` workflow inputs as follows:
- `expression_matrix.csv`: normalized_counts_samples.csv
- `gene_set_database.gmt`: hallmarks.gmt
- `clinical_data.csv`: survival_status_time.csv
- `phenotype_vector.csv`: tumor_normal_labels.csv

---

## [1771] source=multitask_sft_big

**USER:** I have two paired-end sequencing runs to analyze with LncRAnalyzer: run A has sample1_R1.fq.gz and sample1_R2.fq.gz, and run B has sample2_R1.fq.gz and sample2_R2.fq.gz. How should these be passed to the read parameters?

**ASSISTANT:** In LncRAnalyzer, R1 and R2 reads must be formatted as comma-separated filenames:
- Reads R1: `sample1_R1.fq.gz,sample2_R1.fq.gz`
- Reads R2: `sample1_R2.fq.gz,sample2_R2.fq.gz`

---

## [1772] source=multitask_sft_big

**USER:** Please extract the parameter setting used here: 'We filtered the shared OTU table using Filter.shared by dropping any OTUs that accounted for less than 1 percent total relative abundance (minpercent=1).'

**ASSISTANT:** Extracted parameter:
- `minpercent`: `1` (indicating a minimum relative abundance threshold of 1% across all samples).

---

## [1773] source=multitask_sft_big

**USER:** Inspect the data inputs for `teqc_detailed_qc_analysis` and tell me the name, data type, and description of the target regions input.

**ASSISTANT:** Based on the workflow specification, the target region data input has:
- **Name**: `ExampleSet_Targets.bed`
- **Type**: `data`
- **Optional**: `true`
- **Description**: `targeted genomic regions`

---

## [1774] source=multitask_sft_big

**USER:** Here are my input files for the regioneR permutation run: a target list called 'my.special.genes.txt' containing 150 differentially methylated genes, and a background set called 'all.genes.txt'. Please identify these inputs.

**ASSISTANT:** The extracted workflow inputs are:
- my.special.genes.txt: 'my.special.genes.txt' (subset of genes of interest)
- all.genes.txt: 'all.genes.txt'

---

## [1775] source=multitask_sft_big

**USER:** I want to run the decipher workflow. I have my training FASTA file at `/data/ref_trained.fasta`, my query FASTA sequences at `/data/queries.fasta`, and a taxid rank file at `/data/tax_ranks.txt`.

**ASSISTANT:** I have extracted the following inputs for the `decipher` workflow:
- `seqs_path`: `/data/ref_trained.fasta`
- `fas`: `/data/queries.fasta`
- `rank_path`: `/data/tax_ranks.txt`

---

## [1776] source=multitask_sft_big

**USER:** Please run the alphamissenser genomic track plot workflow for protein P04637.

**ASSISTANT:** Extracted parameter for `alphamissenser_genomic_track_plot`:
- `uniprot_id`: "P04637"

---

## [1777] source=multitask_sft_big

**USER:** I want to run genomicdistributions_sequence_composition_analysis on my peak file located at 'data/peaks/h3k4me3_promoters.bed'.

**ASSISTANT:** Extracted parameter for genomicdistributions_sequence_composition_analysis:
- queryFile.bed: 'data/peaks/h3k4me3_promoters.bed'

---

## [1778] source=multitask_sft_big

**USER:** What input data is required for the `epimutacions_leave_one_out_epimutation_analysis` workflow?

**ASSISTANT:** The workflow requires a single mandatory input named `GRset`, which must be an RDS file containing a `GenomicRatioSet` object with the cohort's DNA methylation profiles.

---

## [1779] source=multitask_sft_big

**USER:** Can I run the kegggraph_chemical_reaction_network_analysis workflow without providing my own KGML file?

**ASSISTANT:** Yes. In the workflow definition, the input slot `map00260.xml` (the KGML file for Glycine, serine, and threonine metabolism) is marked as `optional: true`, so it can be omitted or replaced depending on whether you want to analyze the default metabolic pathway or supply a custom one.

---

## [1780] source=multitask_sft_big

**USER:** What input data is required to run the pandaR workflow?

**ASSISTANT:** The `pandaR` workflow requires `count_data` supplied to the mandatory input slot `input_files` (`type: data`, `optional: false`).

---

## [1781] source=multitask_sft_big

**USER:** What configurable parameters can I set when executing the omicade4 workflow?

**ASSISTANT:** The `omicade4` workflow defines no additional tunable parameters (`parameters: []`). It only requires the non-optional data input `input_files`.

---

## [1782] source=multitask_sft_big

**USER:** What inputs are accepted by the ntw workflow, and how should the expression data be structured?

**ASSISTANT:** The 'ntw' workflow takes:
1. 'gene_expression.csv': A required matrix of gene expression values where genes are arranged as rows and perturbations as columns.
2. 'prior_network.csv': An optional matrix containing prior gene-gene interactions.

---

## [1783] source=multitask_sft_big

**USER:** Please set up the proteome_selectivity_profiling workflow for Erlotinib represented by 'COCCOc1cc2ncnc(Nc3cccc(C#C)c3)c2cc1OCCOC' specifically evaluated against GPCR targets.

**ASSISTANT:** Here are the extracted parameters for `proteome_selectivity_profiling`:
- `smiles`: "COCCOc1cc2ncnc(Nc3cccc(C#C)c3)c2cc1OCCOC"
- `target_class`: "GPCR"

---

## [1784] source=multitask_sft_big

**USER:** Extract the configuration setting used by PeptideIndexer to resolve missing relative FASTA database paths from this note: 'Non-existing relative filenames are looked up via OpenMS.ini:id_db_dir select fasta data sets(s)'

**ASSISTANT:** The setting used to look up non-existing relative database paths is 'OpenMS.ini:id_db_dir'.

---

## [1785] source=multitask_sft_big

**USER:** We have alignment outputs from targeted genomic sequencing. We also generated a custom FASTA file of alternative reference segments to check clipped reads. Is the SAM alignment input mandatory for this realignment step?

**ASSISTANT:** No. In the `Tag alignment files (SAM)` step, the SAM file is optional. If provided, clipped sequences are extracted from it and realigned against the provided FASTA reference.

---

## [1786] source=multitask_sft_big

**USER:** What input data files are required by the cardinal_supervised_classification workflow?

**ASSISTANT:** The workflow requires `labeled_msi.rds`, which must be an RDS file containing a processed `MSImagingExperiment` object with class labels.

---

## [1787] source=multitask_sft_big

**USER:** Which Bioconductor packages are integrated into the MethylAid workflow execution?

**ASSISTANT:** The workflow incorporates `bioconductor/methylaid`, `bioconductor/biocparallel`, `bioconductor/geoquery`, `bioconductor/methylaiddata`, `bioconductor/minfidata`, and `bioconductor/minfidataepic`.

---

## [1788] source=multitask_sft_big

**USER:** I am setting up the dreamlet workflow and have my single-cell count matrix ready. Which input parameter slot should I assign this dataset to?

**ASSISTANT:** You should assign your count matrix to the mandatory input slot named `input_files`, which is designed to receive the required `count_data` for the dreamlet workflow.

---

## [1789] source=multitask_sft_big

**USER:** I am configuring gatefinder. My cytometry data is stored in an object called 'fcs_frame' and I have a boolean vector 'is_cd8_effector' specifying my target cells. How do these map to the workflow inputs?

**ASSISTANT:** Here is the parameter mapping for the `gatefinder` workflow:
- `rawdata`: `fcs_frame` (flowFrame containing single-cell expression data)
- `targetpop`: `is_cd8_effector` (logical vector indicating target cell population membership)

---

## [1790] source=multitask_sft_big

**USER:** Set up the boltz_structure_prediction pipeline with fasta file 'target.fasta', YAML config 'params.yaml', enable the MSA server, set sampling steps to 50, recycling steps to 5, and specify 'pdb' as the output format.

**ASSISTANT:** The extracted parameters for the boltz_structure_prediction workflow are:
- input_fasta: "target.fasta"
- input_yaml: "params.yaml"
- use_msa_server: true
- sampling_steps: 50
- recycling_steps: 5
- output_format: "pdb"

---

## [1791] source=multitask_sft_big

**USER:** What is the default setting and behavior of the RE_REVERSE flag in SamToFastq?

**ASSISTANT:** The default mode is `RE_REVERSE=True`. In this mode, if an input read is aligned to the reverse strand on the genome, SamToFastq restores the read's original sequence orientation rather than leaving it in the reverse strand alignment orientation.

---

## [1792] source=multitask_sft_big

**USER:** Which criteria or metrics does the automated 'Select 2D Classes' cryo-EM tool evaluate to separate good classes from junk classes?

**ASSISTANT:** The tool uses three automated threshold metrics to select good 2D classes and discard junk: **resolution**, **particle count**, and **SNR (signal-to-noise ratio)**.

---

## [1793] source=multitask_sft_big

**USER:** What input files are required to execute mirtarrnaseq_mirna_mrna_correlation_multi_timepoint, and what outputs does it produce?

**ASSISTANT:** The workflow `mirtarrnaseq_mirna_mrna_correlation_multi_timepoint` requires two mandatory compressed data inputs:
- `mRNA_timepoints.txt.gz`: mRNA fold change files across time points.
- `miRNA_timepoints.txt.gz`: miRNA fold change files across time points.

It produces three primary outputs:
- `de_table`
- `expression_matrix`
- `visualizations`

---

## [1794] source=multitask_sft_big

**USER:** What input parameter must be provided to run the alabaster_string pipeline?

**ASSISTANT:** The pipeline requires the non-optional data input parameter `input_files`, which supplies the input count data for the workflow.

---

## [1795] source=multitask_sft_big

**USER:** Which input slots and parameters need to be configured to run Rtreemix?

**ASSISTANT:** The Rtreemix workflow requires one mandatory data input slot named `input_files` (type: data, non-optional), which is read directly by the Nextflow workflow. It does not require any additional custom runtime parameters.

---

## [1796] source=multitask_sft_big

**USER:** I have my scRNA-seq experiment stored as `annotated_pbmc_seurat.rds` with sample metadata and cell types. How should this be mapped to sccomp_differential_variability_analysis?

**ASSISTANT:** Map `annotated_pbmc_seurat.rds` to the workflow's required input parameter `user_seurat_obj.rds`.

---

## [1797] source=multitask_sft_big

**USER:** I am configuring PAPAA for a pathway-level somatic mutation analysis. How do I pass my target gene list to the tool?

**ASSISTANT:** You can supply the target pathway genes using the `--path_genes` parameter. This parameter accepts either a comma-separated string of HUGO symbols for all genes in the pathway or the path to a `path_genes.txt` file containing them.

---

## [1798] source=multitask_sft_big

**USER:** What required input matrices must be provided to the rgsea_sd_features workflow, and what outputs does it yield?

**ASSISTANT:** The required inputs for `rgsea_sd_features` are:
- `query_matrix.csv`: Expression matrix for query samples (type: matrix, non-optional).
- `reference_matrix.csv`: Expression matrix for reference samples with known classes (type: matrix, non-optional).

Outputs generated by the workflow are:
- `enrichment_results`
- `feature_selection`

---

## [1799] source=multitask_sft_big

**USER:** I am running the Hicup Pipeline for a Hi-C experiment using both BglII (cutting site A^GATCT) and HindIII (cutting site A^AGCTT). How should I format the restriction enzyme parameter?

**ASSISTANT:** In the Hicup Pipeline, multiple restriction enzymes are specified separated by a colon (`:`). For BglII and HindIII, format the parameter as: `A^GATCT,BglII:A^AGCTT,HindIII`.

---

## [1800] source=multitask_sft_big

**USER:** What are the input specifications for the `pmat` argument in the ggpa workflow?

**ASSISTANT:** The `pmat` input is a mandatory matrix where rows represent SNPs and columns represent phenotypes, containing GWAS p-values.

---

## [1801] source=multitask_sft_big

**USER:** What does the `--sample-size` parameter specify in the Transcript Integrity Number tool?

**ASSISTANT:** In Transcript Integrity Number, the `--sample-size` parameter specifies the number of equal-spaced nucleotide positions picked from the mRNA. If this value is larger than the mRNA length (L), it is automatically halved repeatedly until it is smaller than L.

---

## [1802] source=multitask_sft_big

**USER:** I want to run greylistchip. I have my control file stored as myBamFile.bam and chromosome lengths configured in karyotype_chr21.txt.

**ASSISTANT:** I have mapped your inputs for the greylistchip workflow:
- myBamFile.bam: 'myBamFile.bam' (ChIP-seq input/control BAM file)
- karyotype_chr21.txt: 'karyotype_chr21.txt' (text file containing chromosome names and lengths)

---

## [1803] source=multitask_sft_big

**USER:** I need to configure nf-core/fastquorum. Here are my reference files and parameters: reference fasta is 'genome.fa', fai is 'genome.fa.fai', dictionary is 'genome.dict', BWA index prefix is 'genome_bwa', and UMI strategy is 'Adjacency'. Map these to the workflow inputs.

**ASSISTANT:** The mapped inputs for `nf-core/fastquorum` are:
- `fasta`: "genome.fa"
- `fasta_fai`: "genome.fa.fai"
- `dict`: "genome.dict"
- `bwa`: "genome_bwa"
- `groupreadsbyumi_strategy`: "Adjacency"

---

## [1804] source=multitask_sft_big

**USER:** I am setting up the workflow `eximir_summarize_limma_normalized_data`. Which data input parameters are mandatory, and what formats do they require?

**ASSISTANT:** The workflow requires two data inputs:
1. `RGList`: Type `rds` (a limma RGList object, `optional: false`, `read_by_workflow: true`).
2. `input_files`: Type `data` (`read_by_workflow: true`).

---

## [1805] source=multitask_sft_big

**USER:** Here are my input parameters for cell type annotation:
- Seurat RDS: seurat_pbmc3k.rds
- SingleCellExperiment RDS: sce_pbmc3k.rds
- Reference expression profile: cbmc_reference_matrix.tsv
Can you map these to the inputs for clustifyr_direct_object_annotation?

**ASSISTANT:** The provided inputs map to the `clustifyr_direct_object_annotation` workflow inputs as follows:
- `so`: `seurat_pbmc3k.rds` (Seurat object, type: `rds`)
- `sce`: `sce_pbmc3k.rds` (SingleCellExperiment object, type: `rds_sce`)
- `cbmc_ref`: `cbmc_reference_matrix.tsv` (Reference matrix of RNA-seq expression data for each cell type)

---

## [1806] source=multitask_sft_big

**USER:** I am using Filter BAM or SAM to restrict my alignments to chromosome 2 between 1,000,000 and 2,000,000 base pairs. How should I specify the region?

**ASSISTANT:** You can specify the region parameter as 'chr2:1,000,000-2,000,000'. The tool uses 1-based coordinates and includes both endpoints.

---

## [1807] source=multitask_sft_big

**USER:** In the `asics_custom_library_creation` workflow, what parameter is used to provide the reference spectra, and is it mandatory?

**ASSISTANT:** The parameter is `example_library`. It is of type `data`, described as a directory containing Bruker files of pure metabolite spectra, and is marked as optional (`"optional": true`).

---

## [1808] source=multitask_sft_big

**USER:** I need to set up the data inputs for the genomicalignments workflow. I have my BAM files at '/data/sample1.bam' and '/data/sample2.bam', and my annotations are loaded in an R GRanges object called 'gene_ranges'. How should these be mapped to the workflow parameters?

**ASSISTANT:** You should map them to the following workflow parameters:
- `fls`: `['/data/sample1.bam', '/data/sample2.bam']` (character vector of paths to BAM files)
- `features`: `gene_ranges` (genomic features provided as a GRanges or GRangesList object).

---

## [1809] source=multitask_sft_big

**USER:** In Control-FREEC, what happens to reads that do not match the specified read orientation when calculating copy number profiles?

**ASSISTANT:** If you specify the orientation of your reads in Control-FREEC, only reads mapping in that corresponding orientation will be used for the calculation of copy number profiles; other reads will not be utilized for that calculation.

---

## [1810] source=multitask_sft_big

**USER:** Please set up Seurat RunPCA for my single-cell RNA transcriptomics run. I want to compute and store 40 PCs instead of the standard amount.

**ASSISTANT:** I have extracted the parameter for Seurat RunPCA:
- Total Number of PCs to compute and store: 40

---

## [1811] source=multitask_sft_big

**USER:** What is the expected primary output of the cssq_differential_binding_pipeline_wrapper workflow?

**ASSISTANT:** The workflow produces `normalized_data` as its primary output after completing preprocessing, normalization, and differential binding analysis.

---

## [1812] source=multitask_sft_big

**USER:** Here are my files for deconvolution: bulk matrix 'bulk_methylation.csv', reference profile matrix 'pure_cell_profiles.tsv', and a mapping of cell types to reference columns 'type_indices.json'. Can you assign these to toast_partial_reference_free_deconvolution inputs?

**ASSISTANT:** Based on your inputs, the mapping for `toast_partial_reference_free_deconvolution` is:
- `CBS_mix`: bulk_methylation.csv (bulk gene expression or methylation matrix)
- `LM_5`: pure_cell_profiles.tsv (pure cell type reference profiles for marker selection)
- `CellType`: type_indices.json (list mapping cell types to column indices in reference)

---

## [1813] source=multitask_sft_big

**USER:** In the genomicalignments_splice_junction_overlap_encoding workflow, what is the BAM input parameter designated as?

**ASSISTANT:** The BAM file input parameter is designated as 'untreated3_chr4', described as a path to a BAM file (untreated3_chr4()).

---

## [1814] source=multitask_sft_big

**USER:** What input does the RCX workflow expect for processing network data?

**ASSISTANT:** The `RCX` workflow expects count data provided via the mandatory input slot `input_files` (type: data, optional: false).

---

## [1815] source=multitask_sft_big

**USER:** In the metagenomics tool 'identify_chimeric_seqs', what is the role and default value of the min divergence ratio setting?

**ASSISTANT:** In 'identify_chimeric_seqs', the 'min divergence ratio' parameter is passed directly to ChimeraSlayer. Its default value is None, which instructs the tool to use ChimeraSlayer's internal default value.

---

## [1816] source=multitask_sft_big

**USER:** I am running dmrseq to find differentially methylated regions. In my sample metadata, the test covariate column is 'treatment_status' containing 'treated' and 'wildtype'. I want 'wildtype' to be the baseline for assessing hypo- and hyper-methylation. What should I supply as the reference group?

**ASSISTANT:** You should specify `wildtype` as the reference group name. In `dmrseq`, this must match the name exactly as it appears in your chosen test covariate column (`treatment_status`) to define baseline reference levels for hypo- and hyper-methylation.

---

## [1817] source=multitask_sft_big

**USER:** Are there example alignment datasets specified in the parameters of `coverageview_interval_coverage_analysis`?

**ASSISTANT:** Yes, the workflow metadata lists alignment BAM inputs such as `H3K4me3.chr19.bam` (described as a BAM alignment file) and `H3K4me3_Control.chr19.bam`.

---

## [1818] source=multitask_sft_big

**USER:** I am configuring split_libraries. Is the mapping file optional, and what are the required leading columns?

**ASSISTANT:** The mapping file is REQUIRED. Its header must specify 'SampleID' as the first column, 'BarcodeSequence' as the second, and 'LinkerPrimerSequence' as the third.

---

## [1819] source=multitask_sft_big

**USER:** Is `example_genes.txt` strictly mandatory for the kmcut workflow according to its data inputs configuration?

**ASSISTANT:** According to the parameter metadata for `kmcut`, `example_genes.txt` is listed with `"optional": true` under `data_inputs`.

---

## [1820] source=multitask_sft_big

**USER:** Which feature weighting methods are available in the Drug-likeness tool?

**ASSISTANT:** The Drug-likeness tool provides two weighting options for molecular features: QEDw,mo and QEDw.

---

## [1821] source=multitask_sft_big

**USER:** I am configuring the singleCellTK workflow. My scRNA-seq count matrix file is located at `/data/counts/pbmc_raw_counts.tsv`. Please extract the required workflow parameters for this run.

**ASSISTANT:** Based on the singleCellTK workflow specifications, the extracted parameter is:
- `input_files`: `/data/counts/pbmc_raw_counts.tsv` (type: data, mandatory input slot).

---

## [1822] source=multitask_sft_big

**USER:** Here are the files for reference preparation: reference_data = /data/headneck_sc.rds, filter_list = /data/ribo_genes.txt. Please map these to the inputs for chetah_reference_qc_and_preparation.

**ASSISTANT:** The parameters for the 'chetah_reference_qc_and_preparation' workflow are:
- `headneck_ref`: /data/headneck_sc.rds
- `ribosomal.txt`: /data/ribo_genes.txt

---

## [1823] source=multitask_sft_big

**USER:** In UMI-tools extract, how should I configure the barcode pattern if my sequence has a 16 bp cell barcode followed by a 12 bp random UMI?

**ASSISTANT:** In UMI-tools extract, use 'X' for cell barcode positions and 'N' for random UMI positions. For a 16 bp cell barcode followed by a 12 bp UMI, specify the pattern as 16 Xs followed by 12 Ns: `XXXXXXXXXXXXXXXXNNNNNNNNNNNN`.

---

## [1824] source=multitask_sft_big

**USER:** I need to run the matchms metadata merge tool. My spectral library is 'standards.msp', my metadata table is 'annotations.csv', and both share the identifier column 'compound_id'. How should the parameters be set?

**ASSISTANT:** For `matchms metadata merge`, the extracted parameters are:
- MSP input file: `standards.msp`
- Metadata CSV file: `annotations.csv`
- Matching merge column: `compound_id`

---

## [1825] source=multitask_sft_big

**USER:** I want to run feast on my dataset stored at counts.tsv (genes across rows, cells across columns) and partition the cells into 6 clusters.

**ASSISTANT:** The parameters extracted for the feast workflow are:
- `Y`: 'counts.tsv' (raw count expression matrix with genes as rows and cells as columns)
- `k`: 6 (integer, number of clusters)

---

## [1826] source=multitask_sft_big

**USER:** Set up the genetonic workflow with my files: expression data at 'data/macrophage_se.rds', human annotation package 'org.Hs.eg.db', and enrichment output from topGO saved at 'enrichment/topgo_results.rds'.

**ASSISTANT:** The inputs for the genetonic workflow are mapped as follows:
- `gse`: data/macrophage_se.rds
- `org.Hs.eg.db`: org.Hs.eg.db
- `topgoDE_macrophage_IFNg_vs_naive`: enrichment/topgo_results.rds

---

## [1827] source=multitask_sft_big

**USER:** What inputs and tools are included in the transcriptomics workflow sparrow?

**ASSISTANT:** The `sparrow` workflow specifications include:
- **Input Data**: `count_data` (specified via the parameter `input_files`).
- **Tools / Packages Used**: `bioconductor/sparrow`, `bioconductor/complexheatmap`, `bioconductor/circlize`, `bioconductor/dplyr`, `bioconductor/edger`, and `bioconductor/ggplot2`.

---

## [1828] source=multitask_sft_big

**USER:** I want to download reference data using qiime2 rescript get-midori2-data. What settings/inputs do I need to specify?

**ASSISTANT:** Based on the tool requirements, you need to provide: the database version, the mitochondrial gene of interest, and the reference sequence type (including whether reference sequences are desired).

---

## [1829] source=multitask_sft_big

**USER:** I want to simulate pediatric and pregnancy PK for a basic drug with a molecular weight of 320 Da, LogP of 2.1, pKa of 8.4, and intrinsic clearance of 45 uL/min/mg. The volume of distribution is 1.8 L/kg, target dose is 5 mg/kg, plasma fraction unbound is 0.12, gut fraction unbound is 0.85, and it is a CYP3A4 substrate. Map these to the workflow inputs.

**ASSISTANT:** Here are the extracted parameters mapped to the `Pbpk Pediatric Pregnancy` workflow inputs:
- `mw_da`: 320
- `logp`: 2.1
- `pka_base`: 8.4
- `clint_ul_min_mg`: 45
- `vss_l_kg`: 1.8
- `dose_mg_kg`: 5
- `fup`: 0.12
- `fu_gut`: 0.85
- `cyp_substrate`: "CYP3A4"

---

## [1830] source=multitask_sft_big

**USER:** I want to run Calculate Network Attributes on my network file 'interactions.sif' using Betweenness centrality and the Louvain community detection algorithm. What inputs and settings are identified here?

**ASSISTANT:** From your request, the parameters identified are:
- Input file: 'interactions.sif' (network SIF format)
- Centrality metric: Betweenness
- Community detection algorithm: Louvain

---

## [1831] source=multitask_sft_big

**USER:** What mandatory data input is required by the lbe workflow, and what tools are executed within it?

**ASSISTANT:** The `lbe` workflow requires the mandatory data input `golub.pval`, which is a vector of p-values from differential expression analysis (`optional: false`). The workflow executes `bioconductor/lbe` and `bioconductor/qvalue`.

---

## [1832] source=multitask_sft_big

**USER:** Which data inputs do I need to prepare before running the signaturesearch workflow?

**ASSISTANT:** You need to provide four inputs: `query_mat` (a matrix of quantitative gene expression changes), `upset` (a character vector of up-regulated gene IDs), `downset` (a character vector of down-regulated gene IDs), and `db_path` (the path to the reference HDF5 database file).

---

## [1833] source=multitask_sft_big

**USER:** I am setting up a BD Rhapsody scRNA run using targeted panel data. Fastqs are in '/data/rhapsody_reads', targeting the 'Immune_Response' panel against the 'GRCh38' genome. We anticipate 15,000 cells, filtering out barcodes below 500 UMIs, fewer than 300 genes, and mito percent over 15. We also included AbSeq markers.

**ASSISTANT:** Here are the extracted parameters for the `bd_rhapsody_scrna` workflow:
- `fastq_dir`: "/data/rhapsody_reads"
- `panel`: "Immune_Response"
- `genome`: "GRCh38"
- `expected_cells`: 15000
- `min_umis`: 500
- `min_genes`: 300
- `max_mito_pct`: 15
- `abseq`: true

---

## [1834] source=multitask_sft_big

**USER:** When is it appropriate to select the 'No packaged matrix output' option in Scanpy DPT?

**ASSISTANT:** Choosing 'No packaged matrix output' is appropriate when auxiliary files are being generated (such as marker genes). However, you should not use this option when there are no other output files produced by the tool.

---

## [1835] source=multitask_sft_big

**USER:** Run Chip-Cluster on my multi-condition ChIP-seq peak sets and partition the merged peak MTL scores into 4 distinct clusters.

**ASSISTANT:** Extracted parameter for Chip-Cluster:
- Clustering algorithm: K-means
- k: 4

---

## [1836] source=multitask_sft_big

**USER:** Set up the data inputs for the limma workflow using targets.txt from '/data/study_targets.txt' and spot intensity files in '/data/raw_gpr/'.

**ASSISTANT:** Here are the extracted parameters for the `limma` workflow data inputs:

```json
{
  "targets.txt": "/data/study_targets.txt",
  ".gpr": "/data/raw_gpr/"
}
```
Both inputs are required by `limma` to map array metadata and read the two-color microarray intensity files.

---

## [1837] source=multitask_sft_big

**USER:** I want to apply a power transformation to metabolite intensities in column 3. What operations does the 'table arithmetics' tool support for this choice?

**ASSISTANT:** The 'table arithmetics' tool allows you to select from the following arithmetic operations: Multiply, Subtract, Divide, Add, or Power.

---

## [1838] source=multitask_sft_big

**USER:** What inputs must I prepare for the ctrap_compare_cmap_perturbations workflow?

**ASSISTANT:** You must provide 'diffExprStat', which is a non-optional named numeric vector of t-statistics from differential expression analysis, where the names are gene symbols.

---

## [1839] source=multitask_sft_big

**USER:** Here are my input definitions for a gene set run:
- expression matrix: 'norm_counts.RData'
- sample metadata: 'sample_pheno.csv'
Extract the corresponding input bindings for the `gsri` workflow.

**ASSISTANT:** Based on the specification for `gsri`, here are the extracted input bindings:
- `expression_data.RData`: `norm_counts.RData` (an ExpressionSet or matrix of expression intensities)
- `phenotypes.csv`: `sample_pheno.csv` (phenotypic metadata containing group/class factors)

---

## [1840] source=multitask_sft_big

**USER:** I am configuring ribosomeprofilingqc_rpf_only_differential_analysis for a study with wild-type and knockdown replicates. What BAM files should be passed to the inputs?

**ASSISTANT:** You can supply BAM files representing wild-type and knockdown replicates, such as 'RPF.WT.1.bam', 'RPF.WT.2.bam', 'RPF.KD1.1.bam', and 'RPF.KD1.2.bam'.

---

## [1841] source=multitask_sft_big

**USER:** I am setting up BioPython SeqIO Converter to filter records. How should the filtering expression be structured?

**ASSISTANT:** In BioPython SeqIO Converter, record filtering is configured via a **JMESPath** expression. The root of the expression represents the list of records, and the JMESPath query must evaluate and return a list of records to keep.

---

## [1842] source=multitask_sft_big

**USER:** What are the inputs and outputs for flowfp_gating_quality_control?

**ASSISTANT:** The workflow takes three inputs: `fs1` (a flowSet containing multi-tube flow cytometry data), `fs2` (a flowSet containing multi-tube flow cytometry data with potential outliers), and `plate` (a flowSet containing 96-well plate flow cytometry data). Its outputs are `cluster_assignments` and `visualizations`.

---

## [1843] source=multitask_sft_big

**USER:** What does the hash length parameter define in Oases_optimiser, and what happens if I configure it below 31?

**ASSISTANT:** In Oases_optimiser, the hash length defines the k-mer length in base pairs of the words being hashed. Setting hash lengths shorter than 31 may lead to out-of-memory problems.

---

## [1844] source=multitask_sft_big

**USER:** Run the CNS penetration prediction on compound 'CC(=O)NC1=CC=C(O)C=C1'.

**ASSISTANT:** Extracted parameter for the `cns_penetration_prediction` workflow:
- `smiles`: "CC(=O)NC1=CC=C(O)C=C1"

---

## [1845] source=multitask_sft_big

**USER:** Configure the CITE-seq preprocessing pipeline for my 10x Chromium run. The RNA fastqs are at '/data/runs/RNA/', ADT fastqs at '/data/runs/ADT/', antibody barcodes at '/metadata/totalseq_ab.csv', barcode whitelist at '/ref/10x_737K-august-2016.txt', reference genome is 'GRCh38', expecting 5000 cells, filter out RNA under 200 counts and ADT under 50 counts, max mitochondrial percentage 15%, enable DSB normalization and WNN integration with default protocol.

**ASSISTANT:** Extracted parameters for 'single_cell/cite_seq_preprocessing':
- rna_fastq_dir: "/data/runs/RNA/"
- adt_fastq_dir: "/data/runs/ADT/"
- feature_barcode_csv: "/metadata/totalseq_ab.csv"
- whitelist_10x: "/ref/10x_737K-august-2016.txt"
- genome: "GRCh38"
- expected_cells: 5000
- min_rna_counts: 200
- min_adt_counts: 50
- max_mito_pct: 15
- dsb_normalize: true
- wnn_integration: true
- protocol: "default"

---

## [1846] source=multitask_sft_big

**USER:** Please set up the profam_fitness_prediction pipeline with my files: input sequence 'target_protein.fasta', mutant list 'mutations.csv', wild-type sequence 'MKTIIALSYIFCLVFA', and mode set to 'standard'.

**ASSISTANT:** Here are the extracted parameters for `profam_fitness_prediction`:
- `input_fasta`: "target_protein.fasta"
- `variants_csv`: "mutations.csv"
- `wildtype`: "MKTIIALSYIFCLVFA"
- `scoring_mode`: "standard"

---

## [1847] source=multitask_sft_big

**USER:** I am configuring the Nucleosome Dynamics tool for my yeast chromatin analysis. I have set the chromosome size to 'sacCer3' from the reference list.

**ASSISTANT:** The extracted parameter for the `Nucleosome Dynamics` tool is:
- Reference genome chromosome size: `sacCer3`

---

## [1848] source=multitask_sft_big

**USER:** Run crispr_screen_mageck for my negative selection screen with reads in /data/crispr_fq/, sample sheet samples.tsv, and library file geckov2.csv. Set the FDR cutoff to 0.01 and normalization method to median.

**ASSISTANT:** I have extracted the following parameters for the `genomics/crispr_screen_mageck` workflow:
- `fastq_dir`: `/data/crispr_fq/`
- `sample_sheet`: `samples.tsv`
- `library_file`: `geckov2.csv`
- `screen_type`: `negative selection` (loss-of-function)
- `norm_method`: `median`
- `fdr_threshold`: `0.01`

---

## [1849] source=multitask_sft_big

**USER:** I need to set up a taxonomic classification job for metagenomics reads. Which primary functional tags/parameters are associated with the Kraken2 tool entry?

**ASSISTANT:** Based on the tool metadata, Kraken2 operates using the following key elements:
- Function: `classify`
- Omics/domain: `metagenomics`
- Input format: `fastq`
- Resource requirement: `db` (reference database)

---

## [1850] source=multitask_sft_big

**USER:** What is the default model type used for training in the Scpred train tool?

**ASSISTANT:** The default model type for training in Scpred train is 'svmRadial'.

---

## [1851] source=multitask_sft_big

**USER:** Check whether testNetwork1.sif is mandatory or optional for causalr_sequential_causal_analysis_of_networks_scan.

**ASSISTANT:** In the workflow parameter specifications, 'testNetwork1.sif' has 'optional: true', indicating it is an optional data input.

---

## [1852] source=multitask_sft_big

**USER:** Which machine learning model does the infinityflow workflow utilize by default, and what is its output?

**ASSISTANT:** The `infinityflow` workflow uses the default XGBoost regression model to predict exploratory marker expression, and its primary output is visualizations.

---

## [1853] source=multitask_sft_big

**USER:** I need to format a mothur shared file for LEfSe biomarker discovery, and I want to convert the counts to relative abundances scaled to 1,000,000. Which tool and parameter should I configure?

**ASSISTANT:** You should use `Make.lefse` from the Metagenomics suite. The relevant parameter is `scale`, which allows you to define the scale factor used to convert counts in your shared abundance file into relative abundances.

---

## [1854] source=multitask_sft_big

**USER:** What input file and specific contents are required to run the ihw transcriptomics workflow?

**ASSISTANT:** The ihw workflow requires the input file `deRes.csv`, which must be a data frame containing a complete list of p-values and a continuous covariate, such as `baseMean` from differential expression analysis.

---

## [1855] source=multitask_sft_big

**USER:** What data inputs and parameters are declared for running the splots Nextflow workflow?

**ASSISTANT:** The `splots` workflow requires a mandatory data input slot named `input_files` (accepting `count_data`). It does not declare any configurable execution parameters.

---

## [1856] source=multitask_sft_big

**USER:** Please prepare the execution payload for the dart_toxicity_prediction pipeline using this SMILES: 'CC(=O)Oc1ccccc1C(=O)O'.

**ASSISTANT:** Here is the parameter payload for `dart_toxicity_prediction`:

```json
{
  "smiles": "CC(=O)Oc1ccccc1C(=O)O"
}
```

This will trigger the RDKit-based ICH S5 alert screening and placental transfer model evaluation, returning the results in CSV and JSON formats.

---

## [1857] source=multitask_sft_big

**USER:** How should the URL to the input data points be supplied to the AquaINFRA OGC API Processes tool?

**ASSISTANT:** The URL to the input table must be stored inside a .txt file.

---

## [1858] source=multitask_sft_big

**USER:** In the rxDock cavity definition tool, what does the large sphere radius parameter define during cavity mapping?

**ASSISTANT:** The large sphere radius parameter specifies the mapper radius in angstroms; rxDock will search for cavities within the small sphere but will exclude regions extending to the large sphere.

---

## [1859] source=multitask_sft_big

**USER:** Here is my input dataset configuration: I have a file named `ALL` containing an ExpressionSet mapped to gene IDs with zero missing entries. Can this be passed as the required input?

**ASSISTANT:** Yes. The workflow `snagee_sample_quality_assessment` requires a single mandatory input parameter named `ALL` of type matrix or ExpressionSet with no missing values and mapped gene IDs, which matches your dataset configuration.

---

## [1860] source=multitask_sft_big

**USER:** I am running IDR on ChIP-seq biological replicates. Which ranking measure should I select if my input peak files were generated by MACS versus SPP?

**ASSISTANT:** If your input peak files were generated by MACS, select the p-value. If they were generated by SPP, select the q-value.

---

## [1861] source=multitask_sft_big

**USER:** In mkyrobe predict, how does the percentage value between 0 and 100 determine --min_variant_conf?

**ASSISTANT:** The value (a number between 0 and 100) determines `--min_variant_conf` by simulating variants and choosing the cutoff threshold that retains that specified percentage (x%) of variants.

---

## [1862] source=multitask_sft_big

**USER:** What input coordinates are needed to query Biomni: Region To Ccre Screen?

**ASSISTANT:** The tool requires the starting and ending genomic coordinates of the target region to retrieve intersecting cCRE records.

---

## [1863] source=multitask_sft_big

**USER:** What inputs are necessary to perform a file conversion with Bedgovcf?

**ASSISTANT:** Bedgovcf requires an input BED file containing your genomic intervals or variant data and a YAML configuration file specifying how the conversion to VCF should be executed.

---

## [1864] source=multitask_sft_big

**USER:** I am preparing inputs for the `intact_multi_intact` workflow. What data files must I supply, and what specific columns are expected in the multi_simdat input?

**ASSISTANT:** The `intact_multi_intact` workflow requires the following input data:
- `z_sumstats`: TWAS/PWAS z-scores
- `exprwt_sumstats`: expression prediction weights
- `protwt_sumstats`: protein prediction weights
- `ld_sumstats`: LD correlation matrix
- `multi_simdat`: a data frame specifically containing columns `GLCP_1`, `GLCP_2`, `z_1`, `z_2`, and `chisq`.

---

## [1865] source=multitask_sft_big

**USER:** What input files are required to run the `nf-core/fasta_build_add_kraken2` workflow?

**ASSISTANT:** The workflow requires five inputs:
- `fasta`: Reference sequence data
- `names`: Taxonomy names file
- `nodes`: Taxonomy nodes file
- `accession2taxid`: Accession-to-taxid mapping
- `seqid2taxid`: Sequence-ID-to-taxid mapping.

---

## [1866] source=multitask_sft_big

**USER:** I am configuring ChemSimilarityWeighting for my metabolic model, but the SBML file lacks chemical structure annotations. How should I format the external structure file?

**ASSISTANT:** If chemical structures are not present in the SBML annotations, you should provide a tabulated text file with no header where:
- The first column contains the compound ID.
- The second column contains the SMILES string.

Note that this file will be ignored if an InChI file is supplied instead.

---

## [1867] source=multitask_sft_big

**USER:** In MaAsLin 2, how should I specify the reference level for variables with more than two levels?

**ASSISTANT:** For a variable with more than two levels in MaAsLin 2, specify the reference as a string formatted as `'variable,reference'`. If configuring multiple variables, separate them with commas (e.g., `'var1,ref1,var2,ref2'`).

---

## [1868] source=multitask_sft_big

**USER:** What are the declared data inputs and parameter options for the microbiomeDASim workflow?

**ASSISTANT:** `microbiomeDASim` accepts `count_data` via a mandatory input slot named `input_files` (`optional: false`). It defines no additional configurable parameters in its parameters list.

---

## [1869] source=multitask_sft_big

**USER:** I am setting up a mashmap run to align a newly assembled human genome directly against GRCh38. What identity threshold should I configure?

**ASSISTANT:** You should configure the identity threshold to 95, which is the recommended mashmap setting for mapping a human genome assembly to a human reference.

---

## [1870] source=multitask_sft_big

**USER:** How should my tabular input files be organized for the 'Plot actual vs predicted curves and residual plots' tool?

**ASSISTANT:** The tool expects tabular files where the true values are located in the last column of your input data file, and the corresponding predicted values are located in the last column of your predicted data file.

---

## [1871] source=multitask_sft_big

**USER:** Configure csvtk-filter to filter my dataset so that only records where depth is strictly above 10 are retained.

**ASSISTANT:** For `csvtk-filter`, the parameter expression to evaluate is:
- Numeric expression: `'depth>10'`

---

## [1872] source=multitask_sft_big

**USER:** Please retrieve the PDB structure for 1HEW to use in our computational chemistry pipeline.

**ASSISTANT:** Identified parameters for 'Get PDB file':
- Accession code: 1HEW
- Output format: PDB format

---

## [1873] source=multitask_sft_big

**USER:** Is the `input_files` parameter in the RCyjs workflow optional, and does it define any specific configurable pipeline parameters?

**ASSISTANT:** No, `input_files` is not optional (`optional: false`). The workflow defines no additional configurable parameters (`parameters: []`), relying solely on the mandatory `input_files` data slot.

---

## [1874] source=multitask_sft_big

**USER:** What are the required and optional inputs and outputs for the 'muscle' workflow?

**ASSISTANT:** The primary input is 'sequences.fasta' (a FASTA file containing unaligned nucleotide or amino acid sequences), and there is an optional FASTA data input parameter named 'someORF.fa'. The workflow produces a 'phylogenetic_tree' as its output.

---

## [1875] source=multitask_sft_big

**USER:** How do I configure RepeatMasker to run with the RepBase database?

**ASSISTANT:** To use RepBase in RepeatMasker, choose 'Custom library of repeats' and select a FASTA version of the non-free RepBase database.

---

## [1876] source=multitask_sft_big

**USER:** Configure OGS extractSurface for my mesh: normal vector [0, 0, 1], tolerance angle of 15 degrees, using MSH format and outputting ASCII.

**ASSISTANT:** Extracted parameters for `OGS extractSurface`:
- Normal vector: [0, 0, 1]
- Angle of tolerance: 15 degrees
- Input/Output format: MSH
- ASCII format: enabled

---

## [1877] source=multitask_sft_big

**USER:** I want to run pharmacogx_perturbation_connectivity. I have my reference table file 'hdac_sig.tsv' and my PharmacoSet RDS object 'cmap_subset.rds'. How should these be mapped to the workflow inputs?

**ASSISTANT:** The inputs should be mapped as follows:
- `CMAPsmall`: 'cmap_subset.rds' (PharmacoSet RDS object)
- `HDAC_genes`: 'hdac_sig.tsv' (reference gene signature table)

---

## [1878] source=multitask_sft_big

**USER:** I need to set up the preferences file for `make_distance_histograms`. What structure must the dictionary have?

**ASSISTANT:** The preferences file must contain a dictionary with a `'Fields'` key that maps to a list of your desired fields. If not supplied, the default is `('NO', 'DEFAULT')`.

---

## [1879] source=multitask_sft_big

**USER:** I want to configure the Send Email tool to notify analyst@biomart.org with the subject 'Run Complete' for my incoming dataset file.

**ASSISTANT:** Based on your request, here are the extracted parameters for the Send Email tool:
- `$to`: `analyst@biomart.org`
- `$subject`: `Run Complete`
- `$data`: Incoming dataset file passed to the tool input

---

## [1880] source=multitask_sft_big

**USER:** What outputs and optional inputs does the scmet workflow handle?

**ASSISTANT:** The scmet workflow accepts an optional input named 'covariates.csv' (a matrix of feature-specific covariates, such as CpG density) alongside the required 'single_cell_methylation.csv'. It produces two outputs: 'singlecellexperiment' and 'visualizations'.

---

## [1881] source=multitask_sft_big

**USER:** If I specify a custom `neighbors_key` in muon when clustering multimodal data, where will the tool search for connectivities?

**ASSISTANT:** When specified, muon looks for connectivities in `.obsp[.uns[neighbors_key]['connectivities_key']]` within each modality.

---

## [1882] source=multitask_sft_big

**USER:** Please set up the treg workflow using my preprocessed single-nucleus dataset located at '/data/snRNA/cortex_sce.rds', which contains the count matrix and cell type metadata in colData.

**ASSISTANT:** Here is the parameter mapping for the `treg` workflow:

- `sce.dlpfc.tran`: `/data/snRNA/cortex_sce.rds` (rds_sce, SingleCellExperiment object with count data and colData cell type annotations)

All required inputs are satisfied to identify candidate Total RNA Expression Genes.

---

## [1883] source=multitask_sft_big

**USER:** I am configuring flowgraph_fast_flowgraph_subset_analysis. My count table is stored in 'counts_matrix.tsv' (sample x cell population matrix) and my sample labels are in 'meta_df.csv' which has an 'id' column matching the rows of the count matrix. Can you assign these to the workflow inputs?

**ASSISTANT:** Here are the extracted input mappings for `flowgraph_fast_flowgraph_subset_analysis`:
- `count`: 'counts_matrix.tsv' (sample x cell population numeric matrix of cell counts)
- `meta`: 'meta_df.csv' (metadata data frame containing an 'id' column matching the row names of `count`)

---

## [1884] source=multitask_sft_big

**USER:** I am setting up pyBarcodeFilter to process paired-end sequencing reads. How do I specify the forward and reverse sequencing reaction paths?

**ASSISTANT:** To process paired-end data in pyBarcodeFilter, specify the path to the forward sequencing reaction with the `-f` flag and the path to the reverse sequencing reaction with the `-r` flag.

---

## [1885] source=multitask_sft_big

**USER:** What input data files and reference objects are required for the genestructuretools workflow?

**ASSISTANT:** The workflow requires three inputs:
1. `whippet_file_directory`: Directory containing Whippet output files (`.psi.gz`, `.jnc.gz`, and `.diff.gz`).
2. `example_gtf.gtf`: GTF annotation file.
3. `BSgenome.Mmusculus.UCSC.mm10`: BSgenome package or object.

---

## [1886] source=multitask_sft_big

**USER:** I am configuring the 'clusterize by sliding windows' tool for my genomic analysis. What are the key parameters I need to provide?

**ASSISTANT:** The two important parameters required for the sliding window clustering are the size of the window and the size of the overlap.

---

## [1887] source=multitask_sft_big

**USER:** I am configuring Map with minimap2 for self-mapping. Which option must I select for the reference source?

**ASSISTANT:** You must select 'history' and then specify your input file to serve as the reference.

---

## [1888] source=multitask_sft_big

**USER:** How does modifying the bin size parameter affect the output in the "BigWig to Wig" conversion tool?

**ASSISTANT:** The bin size controls the resolution of the output fixed-step Wiggle file: setting a higher bin size results in lower resolution, whereas a smaller bin size produces higher resolution.

---

## [1889] source=multitask_sft_big

**USER:** Here is my setup for monalisa_binned_kmer_enrichment: I have my coordinates and associations precomputed in an RDS GRanges file called 'brain_cortex_lmr.rds'. Please map this to the workflow parameter.

**ASSISTANT:** The parameter is mapped as follows:
- `data_inputs`: `lmrfile.rds` = "brain_cortex_lmr.rds" (type: `rds_granges`).

---

## [1890] source=multitask_sft_big

**USER:** What input data does Entrezdirect Esummary expect in order to pull dataset summaries from NCBI?

**ASSISTANT:** Entrezdirect Esummary requires one or more NCBI Unique Identifier(s) (UIDs) and the target NCBI database to perform the metadata query.

---

## [1891] source=multitask_sft_big

**USER:** Please run NetworkSummary using our model file e_coli_core.xml and exclude side compounds listed in currency_metabolites.txt.

**ASSISTANT:** I have extracted the following parameters for NetworkSummary:
- Metabolic network (SBML file): `e_coli_core.xml`
- Side compounds list (optional): `currency_metabolites.txt`

---

## [1892] source=multitask_sft_big

**USER:** I need to run MACS2 randsample to downsample my treated sample BAM file. Please configure it to randomly pick exactly 15 million reads from 'sample_rep1.bam'.

**ASSISTANT:** For MACS2 randsample, the parameters extracted from your request are:
- Input file: `sample_rep1.bam`
- Sampling method: Number of reads
- Read count target: `15,000,000` (15M reads)

---

## [1893] source=multitask_sft_big

**USER:** I want to run kcsmart with our patient cohort data saved at `tumor_cgh_object.rds` containing chrom, maploc, and sample log2 ratios, and chromosome boundary markers at `mirror_coords.rds`.

**ASSISTANT:** Extracted inputs for the `kcsmart` workflow:
- `hsSampleData`: `tumor_cgh_object.rds` (aCGH data frame or DNAcopy/CGHbase object with 'chrom', 'maploc', and sample log2 ratio columns)
- `hsMirrorLocs`: `mirror_coords.rds` (list containing start, centromere, and end coordinates for each chromosome)

---

## [1894] source=multitask_sft_big

**USER:** How do I invoke `kwip` on the command line for three samples: s1.ct, s2.ct, and s3.ct?

**ASSISTANT:** You specify the sample oxli Countgraphs as positional arguments following any flags:
`kwip [options] s1.ct s2.ct s3.ct`

---

## [1895] source=multitask_sft_big

**USER:** What input parameters and Bioconductor tools are configured for the 'rols' workflow?

**ASSISTANT:** The 'rols' workflow includes:
- Input files: 'input_files' (type: data, required/non-optional declared Nextflow input slot)
- Tools/packages: 'bioconductor/rols', 'bioconductor/biocstyle', and 'bioconductor/dt'

---

## [1896] source=multitask_sft_big

**USER:** In the workflow abseqr_custom_sample_comparison, what is the parameter name used to pass the directory containing the first set of abseqPy outputs?

**ASSISTANT:** The parameter name is 'dataPath', which is a data-type input representing the directory containing the first set of abseqPy outputs.

---

## [1897] source=multitask_sft_big

**USER:** I am configuring the Nucleosome Predictions tool. I need the raw nucleosome binding log-ratio per basepair instead of the occupancy probabilities. Which setting should I use?

**ASSISTANT:** Set the 'Raw Binding' parameter to 'yes'. When set to 'yes', the tool outputs the raw nucleosome binding log-ratio per basepair instead of the default average occupancy probabilities.

---

## [1898] source=multitask_sft_big

**USER:** What outputs are produced by the `scdotplot` workflow, and which Bioconductor/R packages does it utilize?

**ASSISTANT:** The `scdotplot` workflow produces three outputs: `cluster_assignments`, `singlecellexperiment`, and `normalized_data`. It utilizes the following tools: `bioconductor/scdotplot`, `bioconductor/annotationdbi`, `bioconductor/seurat`, `bioconductor/seuratobject`, `bioconductor/dplyr`, and `bioconductor/ggsci`.

---

## [1899] source=multitask_sft_big

**USER:** I want to use 'matchms add key' to set an attribute 'compound_class' to 'lipid' across my spectra file. What parameters are expected?

**ASSISTANT:** The tool takes the MSP file as input alongside two main parameters: the name of the attribute (e.g., 'compound_class') and its value (e.g., 'lipid'), which will be assigned to all spectra records in the MSP.

---

## [1900] source=multitask_sft_big

**USER:** I am configuring timeomics. What data inputs does it expect, which tools are utilized, and what outputs does it generate?

**ASSISTANT:** The configuration details for `timeomics` are:
- **Data Inputs**:
  - `sim.data` (mandatory, type: matrix/data.frame, expression/abundance with samples in rows, features in columns)
  - `time` (mandatory, type: numeric vector, sample time point information)
- **Tools**:
  - `bioconductor/timeomics`
  - `bioconductor/tidyverse`
- **Outputs**:
  - `feature_selection`
  - `visualizations`

---

## [1901] source=multitask_sft_big

**USER:** What input parameters are defined for the 'ribodipa_exon_level_analysis' workflow?

**ASSISTANT:** The defined data input parameter is 'bam_path', which represents Ribo-seq BAM alignment files (type: data, optional: true).

---

## [1902] source=multitask_sft_big

**USER:** What are the declared mandatory inputs for the InteractiveComplexHeatmap workflow?

**ASSISTANT:** The workflow requires the input parameter `input_files` (type: data, format: `count_data`), which is read by the workflow and is not optional (`optional: false`).

---

## [1903] source=multitask_sft_big

**USER:** What input data slots and parameters are specified for the OrganismDbi workflow?

**ASSISTANT:** The OrganismDbi workflow defines an optional data input slot named 'count_data' (which is marked as not read by the workflow, `read_by_workflow: false`), and it contains no additional parameters.

---

## [1904] source=multitask_sft_big

**USER:** Set up a QCxMS neutral run for mass spectrometry simulation using the GFN2-xTB quantum chemistry method.

**ASSISTANT:** Here are the extracted parameters for the QCxMS Neutral Run tool:
- **Tool**: QCxMS neutral run
- **Quantum chemistry method**: GFN2-xTB
- **Run stage**: Neutral run (preparation for production mass spectrometry simulation)

---

## [1905] source=multitask_sft_big

**USER:** When configuring an RNA-RNA duplex prediction using RNAaliduplex, what structural energy aspect is specifically handled regarding adjacent bases on helices?

**ASSISTANT:** RNAaliduplex handles how to treat dangling end energies for bases adjacent to helices in free ends and multi-loops.

---

## [1906] source=multitask_sft_big

**USER:** What inputs must I provide to the raresim workflow, and what information do they contain?

**ASSISTANT:** The `raresim` workflow requires two data inputs:
1. `nvariant_target.csv`: Contains the observed number of variants per Kb for various sample sizes.
2. `afs_target.csv`: Contains the observed proportion of variants within defined minor allele count (MAC) bins.

---

## [1907] source=multitask_sft_big

**USER:** What graph export formats are supported by PrecursorNetwork, and what is exported by default?

**ASSISTANT:** By default, PrecursorNetwork exports a tabulated edge list with the format `source id edge type target id`. Other supported export formats include GML, JsonGraph, and a tabulated node list formatted as `label node id node type`.

---

## [1908] source=multitask_sft_big

**USER:** What are valid examples of source database and entry inputs when querying with the GAP Cross-reference with KEGG databases tool?

**ASSISTANT:** In the GAP Cross-reference with KEGG databases tool, an example of a source database (`dbsource`) is `genome`, and an example of a database entry (`db entry`) is `map00010`.

---

## [1909] source=multitask_sft_big

**USER:** Set up the Subtomogram Averaging workflow with 5000 particles, C3 symmetry, a target resolution of 4.5 angstroms, 5 iterations, and the reference model 'ribosome_init.pdb'.

**ASSISTANT:** The extracted parameters for the Subtomogram Averaging workflow are:
- num_particles: 5000
- template_pdb: ribosome_init.pdb
- symmetry: C3
- sta_resolution_target: 4.5
- num_sta_rounds: 5

---

## [1910] source=multitask_sft_big

**USER:** Does `cfdnapro_modal_fragment_size` accept any Picard BAM inputs, and are they mandatory?

**ASSISTANT:** Yes, it accepts an input named `groups_picard` of type `bam`. It is optional (`optional: true`) and represents a directory containing sub-folders named by cohort.

---

## [1911] source=multitask_sft_big

**USER:** I am configuring the matchbox workflow. Here is my input data: a list of data.frames containing gene symbols, ranking statistics, and log fold changes stored in my variable study_rankings.

**ASSISTANT:** For the 'matchbox' workflow, the extracted input parameter is:
- matchBoxExpression: study_rankings (list of data.frames containing feature identifiers, ranking statistics, and optional columns like fold change).

---

## [1912] source=multitask_sft_big

**USER:** I am running RSEM calculate expression on paired-end sequencing reads without quality scores. What options alter RSEM's default single-end with quality assumptions?

**ASSISTANT:** To override the default assumptions in RSEM, use `--paired-end` for paired-end sequencing data and `--no-qualities` if your reads lack quality scores.

---

## [1913] source=multitask_sft_big

**USER:** What are the allowed choices and default value for the mode parameter in SeqSero2 v1.1.1?

**ASSISTANT:** The mode parameter in SeqSero2 v1.1.1 accepts 'mem' (for mem) or 'sam' (for samse/sampe). It is optional and defaults to 'mem'.

---

## [1914] source=multitask_sft_big

**USER:** List the required input data types and tools utilized by the Fasta Newick Epang Gappa workflow.

**ASSISTANT:** Based on the workflow definition:
- **Inputs:** `data`, `alignmethod`, `queryseqfile`, `file`, `refseqfile`, `refphylogeny`, `hmmfile`, and `model`.
- **Tools:** `hmmer/hmmbuild`, `hmmer/hmmalign`, `hmmer/eslalimask`, `hmmer/eslreformat`, `clustalo/align`, `mafft/align`, `epang/place`, `epang/split`, `gappa/examinegraft`, `gappa/examineassign`, and `gappa/examineheattree`.

---

## [1915] source=multitask_sft_big

**USER:** In the norce_biotype_filtering_and_extraction pipeline, what is the role and optionality of the annotation.gtf input?

**ASSISTANT:** In `norce_biotype_filtering_and_extraction`, `annotation.gtf` is defined as an optional input file (`optional: true`) containing GTF-formatted gene annotations.

---

## [1916] source=multitask_sft_big

**USER:** Which mandatory data inputs do I need to supply to execute the subseq_extract_subsampled_matrix workflow?

**ASSISTANT:** You need to provide two mandatory inputs:
1. `hammer.counts`: a matrix of raw RNA-seq counts.
2. `seed`: a random seed retrieved from a previous subsamples object.

---

## [1917] source=multitask_sft_big

**USER:** What are the naming rules for the Toolshed repository name when configuring toolfactory?

**ASSISTANT:** When configuring the Toolshed repository name in toolfactory, you must choose thoughtfully to avoid namespace clashes with other tool authors, and the name must consist only of lowercase letters, digits, and underscores.

---

## [1918] source=multitask_sft_big

**USER:** I want to run sseq_paired_experimental_design. My count matrix is countsTable, my condition vector is conds2, and my pairing map is coLevels.

**ASSISTANT:** The parameters for the `sseq_paired_experimental_design` workflow have been extracted:
- `countsTable`: `countsTable` (matrix/data frame of raw RNA-seq counts)
- `conds2`: `conds2` (character vector of conditions)
- `coLevels`: `coLevels` (data frame mapping samples to subjects/pairs)

---

## [1919] source=multitask_sft_big

**USER:** In 'METAMS-LC/MS Pick, Align and Group', what is the difference between the `matchedFilter` and `centWave` feature detection methods?

**ASSISTANT:** In `METAMS-LC/MS Pick, Align and Group`:
- `matchedFilter` performs feature detection in the chromatographic time domain.
- `centWave` is designed for feature detection on high-resolution LC/MS data.

---

## [1920] source=multitask_sft_big

**USER:** I want to trim my multiple sequence alignment with trimAl using an automated method that determines trimming solely by looking at the distribution of gaps across columns. Which parameter flag should I supply?

**ASSISTANT:** You should use the `-gappyout` flag. This mode enables automatic selection based solely on the distribution of gaps across the alignment.

---

## [1921] source=multitask_sft_big

**USER:** I am preparing inputs for the GeneExpressionSignature Nextflow pipeline. What input slot must be provided?

**ASSISTANT:** The workflow declares a mandatory data input slot named `input_files` (corresponding to count or expression data inputs) which is required to execute the pipeline.

---

## [1922] source=multitask_sft_big

**USER:** What are the inputs and outputs of the transcriptomics workflow 'adverscarial_random_walk_minimum_change_attack'?

**ASSISTANT:** The workflow takes:
- Input: 'sce_object.ext' (a required SingleCellExperiment RDS object with logcounts and cell-type annotations)
- Output: 'expression_matrix'

---

## [1923] source=multitask_sft_big

**USER:** Please set up the massarray workflow with the candidate amplicon sequence 'ATGCGTCGATCGATCGAACGT'.

**ASSISTANT:** Extracted parameter for the `massarray` workflow:
- `sequence`: "ATGCGTCGATCGATCGAACGT"

---

## [1924] source=multitask_sft_big

**USER:** I want to feed my RNA-seq count matrix `raw_counts.tsv` into the pipeFrame pipeline. What slot receives this file?

**ASSISTANT:** The file `raw_counts.tsv` will be mapped to the declared input slot `input_files` (corresponding to the `count_data` input requirement) for the pipeFrame workflow.

---

## [1925] source=multitask_sft_big

**USER:** What options are available for the summary basis in Biom.info, and what is the default setting?

**ASSISTANT:** In Biom.info, the summary file representation options are 'otu' and 'sequence'. The default setting is 'otu'.

---

## [1926] source=multitask_sft_big

**USER:** I have metabolites.txt containing measured retention times and rti.txt with retention indexing standards. Which inputs does the metabocoreutils workflow require?

**ASSISTANT:** The metabocoreutils workflow requires both 'metabolites.txt' (measured retention times of metabolites) and 'rti.txt' (measured retention times and reference indices of indexing standards) as inputs.

---

## [1927] source=multitask_sft_big

**USER:** What input data and output formats are associated with the gbscleanr workflow?

**ASSISTANT:** The `gbscleanr` workflow accepts `sample.vcf` (raw VCF genotype data) as input. It produces outputs in `table/csv`, `plot/pdf`, and `object/rds` formats using the `bioconductor/gbscleanr` tool.

---

## [1928] source=multitask_sft_big

**USER:** Which underlying tools are utilized by the depecher workflow?

**ASSISTANT:** The depecher workflow relies on the following Bioconductor tools: 'bioconductor/depecher', 'bioconductor/biocstyle', 'bioconductor/rtsne', and 'bioconductor/knitr'.

---

## [1929] source=multitask_sft_big

**USER:** I want to supply sample metadata to velocyto CLI. How must this table be formatted?

**ASSISTANT:** The metadata must be supplied as a CSV-formatted table where rows represent samples and columns represent metadata entries.

---

## [1930] source=multitask_sft_big

**USER:** I want to launch the mageckflute_mageck_mle_analysis workflow. Here is my MLE beta score file: /data/screen/gene_summary.txt. Please configure the workflow input.

**ASSISTANT:** The input for `mageckflute_mageck_mle_analysis` has been configured:
- `gene_summary.txt`: "/data/screen/gene_summary.txt" (MAGeCK MLE gene summary file containing beta scores for multiple conditions, required: true).

---

## [1931] source=multitask_sft_big

**USER:** What outputs and underlying Bioconductor tools are involved when running the omicspca workflow?

**ASSISTANT:** The `omicspca` workflow utilizes the following tools:
- `bioconductor/omicspca`
- `bioconductor/multiassayexperiment`
- `bioconductor/omicspcadata`
- `bioconductor/cluster`
- `bioconductor/factoextra`
- `bioconductor/ggplot2`

It produces three output types: `table/csv`, `plot/pdf`, and `object/rds`.

---

## [1932] source=multitask_sft_big

**USER:** Set up saser_differential_usage_deseq2_edger with sample file 'A_C_0.bam' and genome annotation 'genes.mini.gtf'.

**ASSISTANT:** The inputs have been mapped to the workflow's data inputs:
- `A_C_0.bam`: type `bam`
- `genes.mini.gtf`: type `data` (genome annotation, optional: true)

---

## [1933] source=multitask_sft_big

**USER:** Looking at the specond workflow parameters, is `expression_set.RData` mandatory, and what constitutes the main output?

**ASSISTANT:** No, `expression_set.RData` is optional. The mandatory input is `expression_matrix.txt`. The primary workflow output is categorized as `visualizations`, alongside HTML and text reports.

---

## [1934] source=multitask_sft_big

**USER:** I ran Mutect2 in `--mitochondria` mode. Which parameter in `gatk4 FilterMutectCalls` should I configure to enable filtering against nuclear mitochondrial DNA segments (NuMTs)?

**ASSISTANT:** You should configure the advanced `--autosomal-coverage` parameter. By default, it is set to 0 (which leaves the filter inactive); providing your sample's autosomal coverage value activates the NuMT filter.

---

## [1935] source=multitask_sft_big

**USER:** What input parameters or data inputs are required by the illuminaio workflow?

**ASSISTANT:** The `illuminaio` workflow requires the data input `input_files` (type: data, `optional: false`, read by the workflow as a declared `.nf` input slot) representing count data files.

---

## [1936] source=multitask_sft_big

**USER:** What tools and required input files are specified in the tricycle cell cycle projection workflow?

**ASSISTANT:** The workflow requires the mandatory input file `sce_normalized.rds` (type: `rds_sce`), which is a SingleCellExperiment object containing normalized logcounts. The tools utilized within the workflow include `bioconductor/tricycle`, `bioconductor/annotationdbi`, `bioconductor/seurat`, `bioconductor/cowplot`, `bioconductor/ggplot2`, and `bioconductor/scater` to generate visualization outputs.

---

## [1937] source=multitask_sft_big

**USER:** Where can I check the current recommended database version for the phrokka DB fetcher tool, and what setting should I use?

**ASSISTANT:** You can check the current version at: https://github.com/gbouras13/pharokka/blob/c822b4c3b8cf642512a5c236fc4036ad53f48587/bin/databases.py#L102. The default value specified by the tool is recommended.

---

## [1938] source=multitask_sft_big

**USER:** Which data input files are configured for the knowyourcg_sequencing_yame_enrichment workflow?

**ASSISTANT:** The workflow lists two data inputs: 'input_cpgs.bed' (an optional BED-formatted CpG data file) and 'cpg_nocontig.cr'.

---

## [1939] source=multitask_sft_big

**USER:** I need to split a composite ID column in my TSV using csvtk-separate. The header name is 'Length'. How should I specify that column?

**ASSISTANT:** In csvtk-separate, you can specify the target column by its name ('Length') or by its 1-based column number (for example, '1' if it is the first column).

---

## [1940] source=multitask_sft_big

**USER:** I want OntologyVis to retain terms belonging to the subsets 'metabolite_pathways' and 'lipid_subclasses', along with any generic terms. How should I specify this parameter?

**ASSISTANT:** You should pass them as a comma-separated list for the ontology subsets parameter: `metabolite_pathways,lipid_subclasses`. This ensures that only entries in these specified subsets as well as generic entries (not assigned to any subset) are included in the results.

---

## [1941] source=multitask_sft_big

**USER:** What input files are required to run the projectr_differential_feature_drivers workflow?

**ASSISTANT:** The `projectr_differential_feature_drivers` workflow requires three input files:
1. `group1_expression.csv`: Expression matrix for cell group 1.
2. `group2_expression.csv`: Expression matrix for cell group 2.
3. `pattern_loadings.csv`: Feature-by-pattern loadings matrix defining the latent space.

---

## [1942] source=multitask_sft_big

**USER:** From this normalyzerde error, what parameter value was specified for the sample column name?
`Error in loadDesign(designPath, sampleCol = sampleColName, groupCol = groupColName) : Both sampleCol value and groupCol value must be present in the design matrix header. | sampleCol: sample`

**ASSISTANT:** The parameter value specified for `sampleCol` was `'sample'`.

---

## [1943] source=multitask_sft_big

**USER:** I am preparing the inputs for the `dks` workflow. How should I format the input matrix P?

**ASSISTANT:** The input parameter `P` must be a matrix of simulated null p-values where rows represent null hypotheses and columns represent independent simulated studies. It is a required input for the workflow.

---

## [1944] source=multitask_sft_big

**USER:** What input parameters are required to run the rmspc_granges_input workflow?

**ASSISTANT:** The `rmspc_granges_input` workflow expects peak inputs as GRanges objects saved in RDS format, including `GR1` (an `rds_granges` object representing replicate 1 peaks) and subsequent replicate peak files such as `GR2`.

---

## [1945] source=multitask_sft_big

**USER:** Configure the MoleculeExperiment vendor workflow to read data located at `/data/spatial/xenium_run1/`.

**ASSISTANT:** Parameter extracted for `moleculeexperiment_vendor_import_subset_and_visualize`:
- `raw_data_dir`: `/data/spatial/xenium_run1/`

---

## [1946] source=multitask_sft_big

**USER:** Please set up GiveInfoFasta to analyze my sequences in 'transcripts.fa', show stats for each individual sequence, enable verbose mode, and save the output to 'transcripts_summary.stats'.

**ASSISTANT:** Here are the extracted parameters for GiveInfoFasta:
- `-i`: transcripts.fa
- `-l`: (flag enabled to give stats for each input sequence)
- `-v`: 1 (verbose enabled)
- `-o`: transcripts_summary.stats

Command execution:
`GiveInfoFasta -i transcripts.fa -l -v 1 -o transcripts_summary.stats`

---

## [1947] source=multitask_sft_big

**USER:** In Monocle3 diffExp, how is the number of nearest neighbors parameter utilized during differential expression testing?

**ASSISTANT:** The number of nearest neighbors parameter defines the k-value used for building the kNN graph, which is then passed to the `knn2nb` function during the Moran's I (or Geary's C) spatial autocorrelation test procedure.

---

## [1948] source=multitask_sft_big

**USER:** What outputs are generated upon completing the katdetectr_non_standard_sequence_detection workflow?

**ASSISTANT:** The workflow generates two outputs: `mutational_signatures` and `visualizations`.

---

## [1949] source=multitask_sft_big

**USER:** I am writing a script to preprocess FASTA assemblies. Please explain the primary transformation performed by seqtk_cutN when given a sequence like `>test AACTGATCGATCGATCGNNNNNNNNNNNACATG`.

**ASSISTANT:** `seqtk_cutN` scans the input sequence for contiguous stretches of Ns and splits the single sequence at those ambiguous regions, outputting distinct sub-sequences corresponding to the high-confidence segments flanking the N-run.

---

## [1950] source=multitask_sft_big

**USER:** I want to set up `genvisr_copy_number_profiling`. I have two data frame files ready: `cohort_segments.tsv` containing the segment intervals and `sample_raw_cn.tsv` containing raw calls for sample A. How do these map to the workflow inputs?

**ASSISTANT:** Map the inputs as follows:
- `LucCNseg`: `cohort_segments.tsv` (data frame of copy number segments)
- `data`: `sample_raw_cn.tsv` (data frame of raw copy number calls for a single sample)

---

## [1951] source=multitask_sft_big

**USER:** What input data parameters does the REBET workflow require to execute?

**ASSISTANT:** The REBET workflow requires a single mandatory input parameter: 'input_files', which accepts 'count_data' (type: data, optional: false, read_by_workflow: true).

---

## [1952] source=multitask_sft_big

**USER:** Here are the files for our multi-omics survival study: 'expr_matrix.tsv' (expression matrix: genes x patients), 'expr_metadata.csv' (sample annotations for expression), 'methylation_beta.tsv' (DNA methylation loci x patients), 'clinical_outcomes.csv' (patient IDs, survival time, status, risk tier), and 'cpg_gene_map.tsv' (maps loci to genes). Can you map these to the 'inetgrate' workflow inputs?

**ASSISTANT:** Here is the parameter mapping for the 'inetgrate' workflow:
- `genExpr`: 'expr_matrix.tsv'
- `genExprSampleInfo`: 'expr_metadata.csv'
- `rawDnam`: 'methylation_beta.tsv'
- `clinical`: 'clinical_outcomes.csv'
- `locus2gene`: 'cpg_gene_map.tsv'

---

## [1953] source=multitask_sft_big

**USER:** I want to create a file containing the string 'SAMPLE_ID_PLACEHOLDER' repeated exactly 50 times using the Create text file tool. What settings do I configure?

**ASSISTANT:** You should configure the following:
- String/sentence: 'SAMPLE_ID_PLACEHOLDER'
- Repetition count (X): 50 (provided as a number)
The tool will generate a text file with that line printed 50 times, separated by line breaks.

---

## [1954] source=multitask_sft_big

**USER:** I want to execute the alabaster_ranges workflow. What input slots are expected and what data should I supply?

**ASSISTANT:** The `alabaster_ranges` workflow expects `count_data` as its input stream, configured via the declared data input slot `input_files`. This parameter is mandatory (`optional: false`) and points to the data structures or files containing the range-associated data to be serialized.

---

## [1955] source=multitask_sft_big

**USER:** I'm configuring the ggtree workflow. My input dataset file is located at `/data/trees/phylo_counts.tsv`. How should this be specified in the workflow data inputs?

**ASSISTANT:** For the `ggtree` workflow, configure the data input slot as follows:
- `input_files`: `/data/trees/phylo_counts.tsv` (type: `data`, mandatory input slot for the workflow).

---

## [1956] source=multitask_sft_big

**USER:** For our histopathology image analysis, please configure 'Perform color deconvolution or transformation' to isolate channel 2.

**ASSISTANT:** Parameter extracted for `Perform color deconvolution or transformation`:
- Channel: 2 (valid input between 1 and 3; all other channels will be set to zero prior to the transformation).

---

## [1957] source=multitask_sft_big

**USER:** I am setting up `make_qiime_py_file`. How should I pass my name if it has spaces, and what is the default value if left unspecified?

**ASSISTANT:** In `make_qiime_py_file`, the author's name default value is `AUTHOR_NAME`. If your name contains spaces, it should typically be enclosed in quotation marks so it can be correctly populated into the header variables.

---

## [1958] source=multitask_sft_big

**USER:** Please set up the Predictor run using the compounds file 'test_set_compounds.csv' and the model file 'qsar_model_toxicity.pkl'.

**ASSISTANT:** Extracted the following inputs for the Predictor tool:
- Compound data-file: 'test_set_compounds.csv'
- Specified QSAR model: 'qsar_model_toxicity.pkl'

---

## [1959] source=multitask_sft_big

**USER:** I have two BAM files: 'tumor_rep1.bam' for my test condition and 'matched_normal.bam' for my control. How should these be assigned as inputs for the deepsnv_shearwater_ml_variant_calling workflow?

**ASSISTANT:** For the `deepsnv_shearwater_ml_variant_calling` workflow, you should assign the parameters as follows:
- `test.bam`: `tumor_rep1.bam` (alignment file for the test sample)
- `control.bam`: `matched_normal.bam` (alignment file for the control sample)

---

## [1960] source=multitask_sft_big

**USER:** What happens if I turn off the header option in the 'Convert coordinates to label map' tool?

**ASSISTANT:** Turning this option off will cause the tool to ignore the first row and assume that the X and Y coordinates correspond to the first and second columns, respectively. However, this is ignored if GeoJSON is used as input.

---

## [1961] source=multitask_sft_big

**USER:** What input data files does the qsutils_complexity_and_diversity_analysis workflow define?

**ASSISTANT:** The workflow defines an optional FASTA input file (e.g., 'ToyData_10_50_1000.fna') containing haplotypes and their frequencies.

---

## [1962] source=multitask_sft_big

**USER:** If chemical structures are missing from the SBML annotations in ChemSimilarityWeighting, how should the alternative structure file be formatted?

**ASSISTANT:** The structure should be provided as a tabulated file without a header, where the first column contains the compound ID and the second column contains the SMILE string. Note that this file is ignored if an InChI file is provided.

---

## [1963] source=multitask_sft_big

**USER:** I am running csvtk-unique to deduplicate my sample annotation table based on the first and second columns. How should I specify that?

**ASSISTANT:** In `csvtk-unique`, multiple columns can be separated by a comma. To target the first and second columns, set the column parameter to `'1,2'`.

---

## [1964] source=multitask_sft_big

**USER:** What are the primary input channels, output directories, and model-specific parameters available in `nf-core/spinningjenny`?

**ASSISTANT:** The workflow accepts `input` as its primary data input and outputs to `results_dir`. Key parameters and tools include `template`, `nlogo`, `batches`, `outdir`, `email`, `multiqc_title`, `custom_config_version`, `custom_config_base`, and `config_profile_name`.

---

## [1965] source=multitask_sft_big

**USER:** Please configure the allometric scaling tool with preclinical PK data from 'pk_study_rat_dog_monkey.csv', human body weight set to 70 kg, oral administration, NOEL of 15 mg/kg, and applying Rule of Exponents correction.

**ASSISTANT:** Here are the extracted parameters for the `Allometric Scaling` workflow:
- `species_pk_data`: 'pk_study_rat_dog_monkey.csv'
- `human_BW_kg`: 70
- `correction_method`: 'Rule of Exponents'
- `dose_route`: 'oral'
- `toxicokinetic_NOEL_mg_kg`: 15

---

## [1966] source=multitask_sft_big

**USER:** I am configuring the `immune_deconvolution` workflow for my bulk RNA-seq cohort. What inputs, method parameters, and outputs are defined for this workflow?

**ASSISTANT:** The `immune_deconvolution` workflow defines the following parameters and inputs:
- **Inputs/Parameters**:
  - `counts_matrix` (type: matrix, mandatory)
  - `signature_matrix` (type: matrix)
  - `clinical_metadata`
  - `method`
  - `scale_counts`
  - `checksig`
- **Outputs**:
  - `counts_matrix`
  - `tsv_clonotypes`
  - `pdf_report`

---

## [1967] source=multitask_sft_big

**USER:** Please set up the CYP450 DDI Panel + Hepatic Clearance workflow for our lead compound 'Candidate-4a' with SMILES 'CC(=O)Nc1ccc(O)cc1'. Use a liver weight of 1650 g, unbound plasma fraction of 0.22, blood-to-plasma ratio of 0.95, and configure oral administration with a maximum clinical dose of 250 mg.

**ASSISTANT:** Here are the extracted parameters grounded in the CYP450 DDI Panel + Hepatic Clearance workflow schema:

- `compound_name`: "Candidate-4a"
- `smiles`: "CC(=O)Nc1ccc(O)cc1"
- `liver_weight_g`: 1650
- `fu_plasma`: 0.22
- `blood_to_plasma_ratio`: 0.95
- `dose_route`: "oral"
- `max_clinical_dose_mg`: 250

---

## [1968] source=multitask_sft_big

**USER:** I am configuring Get.oturep for my OTU analysis. I want the representative sequence for each OTU to be the one that appears most frequently. Which method should I specify?

**ASSISTANT:** You should specify the abundance method, which chooses the most abundant sequence in the OTU as the representative.

---

## [1969] source=multitask_sft_big

**USER:** What data input files are configured for the `rsubread_read_quality_assessment` workflow?

**ASSISTANT:** The workflow accepts two primary data inputs: `reads.txt.gz` (an optional sequencing reads file) and `input_files` (data).

---

## [1970] source=multitask_sft_big

**USER:** I have an RNA-seq count matrix `raw_counts.tsv`, gene identifiers in `gene_list.txt`, exon counts per gene in `exon_bins.txt`, and treatment groups in `treatment_conditions.csv`. Map these to the regsplice workflow parameters.

**ASSISTANT:** Here is the parameter mapping for the `regsplice` workflow:
- `counts`: `raw_counts.tsv` (matrix or data frame of RNA-seq read counts)
- `gene_IDs`: `gene_list.txt` (vector of gene IDs)
- `n_exons`: `exon_bins.txt` (vector of number of exon bins per gene)
- `condition`: `treatment_conditions.csv` (vector of experimental conditions)

---

## [1971] source=multitask_sft_big

**USER:** Please state the input file requirements and constraints specified for the metabolomics tool 'Normalization and Re-Scaling'.

**ASSISTANT:** The requirements for the design input are:
- File format: Tab-separated
- Required column: 'sampleID'

---

## [1972] source=multitask_sft_big

**USER:** Which parameter in RAVE controls the filtering of variants based on minor allele frequency, and what is its default setting?

**ASSISTANT:** In RAVE, the parameter is `--maf`. It filters out all variants with a minor allele frequency below the specified cutoff, and its default threshold is 0.01.

---

## [1973] source=multitask_sft_big

**USER:** I need to ensure Illumina paired-end reads are dropped if neither read has at least 35 known bases using Prq. What property do I configure?

**ASSISTANT:** Set the property 'seal.prq.min-bases-per-read' to 35.

---

## [1974] source=multitask_sft_big

**USER:** I want to run goligomersearch and get a hash mapping positions as keys to the oligomers found as values. Which setting should I configure?

**ASSISTANT:** You should use the 'both' setting, which returns a hash with sequence positions as keys and the found oligomers as values.

---

## [1975] source=multitask_sft_big

**USER:** I want to run qiime2 demux subsample-single to downsample my 16S amplicon single-end reads to 25% of the original depth. Which parameter controls this?

**ASSISTANT:** The parameter that controls the subsampling ratio is `fraction`. For a 25% downsample, set `fraction: 0.25`.

---

## [1976] source=multitask_sft_big

**USER:** I need to run the Trinity assembly tool via ctat_trinity_rnaseq using 4 CPUs, 31 GB of memory, for paired-end RNA-seq files named sample_R1.fq and sample_R2.fq. What command should I construct?

**ASSISTANT:** Based on the tool specification, the command is:
`Trinity --max_memory 31G --CPU 4 --seqType fq --left sample_R1.fq --right sample_R2.fq`

---

## [1977] source=multitask_sft_big

**USER:** What does the `cutoff` parameter in Consensus.seqs control, and what is its allowed range?

**ASSISTANT:** The `cutoff` parameter in Consensus.seqs specifies the minimum percentage support required to call a base (for example, `cutoff=95` returns the base supported by at least 95% of sequences). It is optional and must be an integer or value between 1 and 100.

---

## [1978] source=multitask_sft_big

**USER:** What parameters can I set to point rqc to my gzipped sequencing files in a specific directory?

**ASSISTANT:** You can provide `folder` to specify the path to the directory containing your FASTQ files, and `pattern` to provide a regular expression matching your files (for example, `".fastq.gz"`).

---

## [1979] source=multitask_sft_big

**USER:** Here are the files I have for running enmix_downstream_epigenetic_analysis:
- `beta_norm.rds`: preprocessed beta value matrix
- `raw_rg.RData`: raw rgDataSet object
- `meth_mdat.rds`: preprocessed methDataSet
- `sample_metadata.tsv`: sample data frame with sample ID, age, and sex
- `pvals_regions.bed`: BED-formatted data frame of association P-values

Please map these to the required workflow inputs.

**ASSISTANT:** The mapping to the `enmix_downstream_epigenetic_analysis` inputs is:
- `beta`: `beta_norm.rds` (preprocessed methylation beta value matrix)
- `rgSet`: `raw_rg.RData` (raw rgDataSet)
- `mdat`: `meth_mdat.rds` (preprocessed methDataSet)
- `pheno`: `sample_metadata.tsv` (data frame with sample ID, age, and sex)
- `dat`: `pvals_regions.bed` (BED-formatted data frame of association P-values)

---

## [1980] source=multitask_sft_big

**USER:** We are preparing reference-based OTU picking with parallel_pick_otus_uclust_ref on high-memory nodes and want both strands evaluated. Which parameter setting reflects this requirement and what is the memory implication?

**ASSISTANT:** You should enable reverse strand matching (set it to True, whereas the default is False). Please be aware that this will double the amount of memory used during the uclust OTU picking execution.

---

## [1981] source=multitask_sft_big

**USER:** I want to run influx_si using the files in experiment_data.zip, and the experiment was an instationary labeling assay.

**ASSISTANT:** Extracted parameters for influx_si:
- Input archives: `experiment_data.zip` (MTF set archive)
- Labeling type: `instationary`

---

## [1982] source=multitask_sft_big

**USER:** What are the required data inputs and output artifacts of the affycoretools_interactive_venn_diagram_generation workflow?

**ASSISTANT:** The workflow requires the following data inputs:
- fit2 (type: rds, non-optional): MArrayLM object from limma after eBayes
- contrast: Contrast matrix
- design: Design matrix

It produces two outputs:
- de_table
- visualizations

---

## [1983] source=multitask_sft_big

**USER:** What happens to chimera removal outputs and sequence reporting when running SAM Refiner in Whole Genome Sequencing Mode?

**ASSISTANT:** When using Whole Genome Sequencing Mode in SAM Refiner, chimera removal outputs are disabled, and the tool reports sequences with start and end positions.

---

## [1984] source=multitask_sft_big

**USER:** Can I include gene names or symbols instead of raw IDs in the final correlation tables when running Metabolite - Gene Correlation?

**ASSISTANT:** Yes. You can optionally input a gene annotation information file containing gene names and identifiers, which will be used to label the output files.

---

## [1985] source=multitask_sft_big

**USER:** Can you check the parameter schema for SingleMoleculeFootprinting and tell me what tunable parameters and data input slots are declared?

**ASSISTANT:** Based on the workflow definition, the data input slot is 'input_files' (type: data, mandatory), while the workflow declares no additional tunable runtime parameters ('parameters': []).

---

## [1986] source=multitask_sft_big

**USER:** I am configuring 'Filter by keywords or numerical value' for my proteomics dataset. I want a row to be filtered only if every single filter condition I set is completely met. Which logical operator should be selected?

**ASSISTANT:** You should select the 'AND' operator, as it requires all your filters to be satisfied to filter a row.

---

## [1987] source=multitask_sft_big

**USER:** I want to run mofa2_mefisto_covariate_analysis. I have multi-omics profiling formatted as an R list object `multi_omics_list` containing my matrices, and a covariate matrix `sample_timepoints` where columns are sample IDs and the single row holds hours post-treatment. Map these to the workflow inputs.

**ASSISTANT:** The inputs for `mofa2_mefisto_covariate_analysis` are mapped as follows:
- `dd`: `multi_omics_list` (list of matrices containing multi-omic data)
- `time`: `sample_timepoints` (covariate matrix with samples in columns and one row containing the continuous covariate values)

---

## [1988] source=multitask_sft_big

**USER:** Configure cpa_synergy_gpu for evaluating Paclitaxel (SMILES: CC1=C2C(C(=O)C3(C(CC4C(C3C(C(C2(C)C)(CC1OC(=O)C(C(C5=CC=CC=C5)NC(=O)C6=CC=CC=C6)O)O)OC(=O)C7=CC=CC=C7)(CO4)OC(=O)C)O)C)O, target: TUBB, dose: 50 nM) and Cisplatin (SMILES: N.N.Cl[Pt]Cl, target: DNA, dose: 100 nM) in A549 cells using checkpoint 'cpa_base.pt' on cuda:0 with synergy model 'additive'.

**ASSISTANT:** Here are the extracted parameters for `virtual_cell/cpa_synergy_gpu`:
- `drug_a_name`: "Paclitaxel"
- `drug_a_smiles`: "CC1=C2C(C(=O)C3(C(CC4C(C3C(C(C2(C)C)(CC1OC(=O)C(C(C5=CC=CC=C5)NC(=O)C6=CC=CC=C6)O)O)OC(=O)C7=CC=CC=C7)(CO4)OC(=O)C)O)C)O"
- `drug_a_targets`: "TUBB"
- `drug_a_dose_nM`: 50
- `drug_b_name`: "Cisplatin"
- `drug_b_smiles`: "N.N.Cl[Pt]Cl"
- `drug_b_targets`: "DNA"
- `drug_b_dose_nM`: 100
- `cell_line`: "A549"
- `pretrained_model`: "cpa_base.pt"
- `device`: "cuda:0"
- `synergy_model`: "additive"

---

## [1989] source=multitask_sft_big

**USER:** In the ExperimentHub workflow, is the 'count_data' input mandatory for execution?

**ASSISTANT:** No, the 'count_data' input parameter is declared as optional (`optional: true`) and is not read by the workflow.

---

## [1990] source=multitask_sft_big

**USER:** Here are the candidate details for DDI risk assessment:
Compound SMILES: CC1=CN=C(C(=N1)N)C2=CC=CC=C2
Cmax: 0.85 uM
Please extract the necessary parameters for the transporter_ddi_prediction workflow.

**ASSISTANT:** The extracted parameters for the `transporter_ddi_prediction` workflow are:
- `smiles`: `CC1=CN=C(C(=N1)N)C2=CC=CC=C2`
- `Cmax_uM`: `0.85`

---

## [1991] source=multitask_sft_big

**USER:** Please set up the inputs for seq2pathway_rna_seq_expression_pathway using my normalized counts table `norm_counts_symbols.tsv` and the gene set object `c5_go_sets.rds`.

**ASSISTANT:** Here are the extracted parameters and inputs for `seq2pathway_rna_seq_expression_pathway`:
- `dat_RNA`: `norm_counts_symbols.tsv` (table containing gene expression values with gene symbols as row names)
- `MsigDB_C5`: `c5_go_sets.rds` (GSA.genesets object)

---

## [1992] source=multitask_sft_big

**USER:** Set up the inputs for the eventpointer_junction_array_pipeline using the following project paths: CEL data at `/data/sample1.cel`, exon definitions at `/ref/hg38_exon_pos.txt`, junction probe map at `/ref/hg38_junc_pos.txt`, and gene models at `/ref/gencode.v38.gtf`.

**ASSISTANT:** Here are the mapped inputs for `eventpointer_junction_array_pipeline`:
- `microarray_data.cel`: `/data/sample1.cel`
- `exon_probes.txt`: `/ref/hg38_exon_pos.txt`
- `junction_probes.txt`: `/ref/hg38_junc_pos.txt`
- `reference_transcriptome.gtf`: `/ref/gencode.v38.gtf`

---

## [1993] source=multitask_sft_big

**USER:** I am configuring nf-core/cutandrun. I want to save intermediate alignment files, trimmed reads, and spike-in alignments to my output directory. Which workflow parameters should I activate?

**ASSISTANT:** Based on the pipeline parameters for `nf-core/cutandrun`, you should set: `save_align_intermed` to save intermediate alignment files, `save_trimmed` to save trimmed reads, `save_spikein_aligned` to retain spike-in alignments, and define `outdir` for your output directory.

---

## [1994] source=multitask_sft_big

**USER:** Please set up the HTS plate QC workflow using 'screen_plate_01.json'. I want a minimum Z' cutoff of 0.5, a 3-sigma hit threshold, a hit threshold percentage of 40%, and evaluate for inhibition.

**ASSISTANT:** I have extracted the following parameters for the Hts Plate Qc Hit Calling workflow:
- plate_data_json: 'screen_plate_01.json'
- min_z_prime: 0.5
- n_sigma_threshold: 3.0
- hit_threshold_pct: 40.0
- hit_direction: 'inhibition'

---

## [1995] source=multitask_sft_big

**USER:** How must the expression matrix be structured to be accepted by the mantelcorr workflow?

**ASSISTANT:** The required input is 'expression_matrix.csv', which must be a numeric p x n matrix of gene expression values where rows represent genes (p) and columns represent samples (n), with gene and sample labels assigned via dimnames.

---

## [1996] source=multitask_sft_big

**USER:** I am configuring 'Cut degenerate primers from dataset' for my amplicon sequencing library. If I want to discard any reads that do not contain the adaptor sequence, how should I configure the tool's boolean parameter?

**ASSISTANT:** You should set the option to False. In 'Cut degenerate primers from dataset', setting the parameter to True keeps reads lacking the adaptor, while setting it to False deletes them from the dataset.

---

## [1997] source=multitask_sft_big

**USER:** Please set up `sincell_statistical_support_assessment` using my matrix file at `/data/timepoint0_log_expr.tsv` as the log-transformed single-cell expression matrix.

**ASSISTANT:** The input parameter has been extracted for `sincell_statistical_support_assessment`:
- `EMlog_t0`: "/data/timepoint0_log_expr.tsv" (log-transformed single-cell expression matrix for a specific condition/timepoint).

---

## [1998] source=multitask_sft_big

**USER:** Which underlying Bioconductor software packages or tools are integrated within the GSEABenchmarkeR workflow?

**ASSISTANT:** The workflow incorporates `bioconductor/gseabenchmarker` and `bioconductor/enrichmentbrowser`.

---

## [1999] source=multitask_sft_big

**USER:** Run GC Skew on my genomic sequence using a sliding window size of 500.

**ASSISTANT:** Extracted parameter:
- Window size: 500

The tool will calculate the GC skew ratios along your sequence based on this window size and the total sequence length.

---

## [2000] source=multitask_sft_big

**USER:** I am configuring the celda_decontx_decontamination workflow. What input data parameters must I provide, and is an empty droplet background object strictly required?

**ASSISTANT:** The workflow defines two inputs:
1. `sce`: A mandatory `rds_sce` object representing a SingleCellExperiment containing a raw count assay.
2. `sce.raw`: An optional `rds_sce` object containing raw/droplet background counts.

Providing `sce.raw` is optional; you only need to supply `sce` to run the decontamination.

---

## [2001] source=multitask_sft_big

**USER:** I am configuring `vcfsamplecompare` for non-genotype mode to compare variant observation ratios (AO/DP) across sample groups. What parameter value range is allowed for setting the minimum difference in observation ratio averages?

**ASSISTANT:** For `vcfsamplecompare`, the parameter value must be a decimal value between `0.0` and `1.0` (inclusive). This sets the minimum difference in observation ratio averages (e.g., 'AO/DP') between the compared sample groups. Note that this parameter is not used in genotype mode.

---

## [2002] source=multitask_sft_big

**USER:** What are the required input parameters and data slots specified for the HelloRanges workflow execution?

**ASSISTANT:** The workflow defines an input slot named `input_files`, which is a non-optional data input expected to provide count data (`count_data`). It does not declare additional parameters.

---

## [2003] source=multitask_sft_big

**USER:** I want to execute the vsclust_standard_matrix_workflow. Here is my dataset file: 'protein_expression_matrix_replicates.tsv', which contains quantitative protein abundance across our replicated conditions.

**ASSISTANT:** The workflow parameter has been extracted:
- `protein_expressions`: "protein_expression_matrix_replicates.tsv" (Data frame or matrix containing quantitative feature values across replicated conditions).

---

## [2004] source=multitask_sft_big

**USER:** What data input does the pirat_imputation_with_extensions workflow require, and what are its expected contents?

**ASSISTANT:** The workflow requires a mandatory list input named `subropers` (type: list). This list contains `peptides_ab`, `adj`, and optionally `rnas_ab` and `adj_rna_pg` if performing transcriptomic integration.

---

## [2005] source=multitask_sft_big

**USER:** In Quantifere, I have an MS/MS statistical measure for adjusted p-value named 'p_adj' which is a p-value type where lower values are better (min). How should this be formatted according to the tool's parameter specifications?

**ASSISTANT:** Quantifere requires statistical measures to follow the format `SM alias => SM name,type,mode[min/max]`. For your adjusted p-value, format it as:
`p_adj => p_adj,p-value,min` (or using your chosen alias, e.g., `padj => p_adj,p-value,min`).

---

## [2006] source=multitask_sft_big

**USER:** I am setting up a command for parsing Hi-C alignments with Pairtools parse. I want to specify the chromosome order so that interchromosomal mates are flipped consistently based on my reference assembly chrom_order.txt. Can you extract the core configuration logic required here?

**ASSISTANT:** For `Pairtools parse`, the primary parameter requirement identified from your request is the chromosome order specification (using your `chrom_order.txt`). This reference list dictates how interchromosomal mates are flipped, with the tool automatically ordering any unlisted scaffolds in lexicographical order.

---

## [2007] source=multitask_sft_big

**USER:** Here is my dataset configuration for cDNA microarray analysis:
- File: cdna_intensities.tsv (contains red and green intensities for sample and reference channels)

Can you verify if this input matches the required workflow parameters and tell me what outputs will be produced?

**ASSISTANT:** Yes, `cdna_intensities.tsv` matches the required non-optional input matrix (`type: matrix`, read by the workflow). Executing `rankprod_cdna_common_reference` with this file will generate two outputs: `de_table` (differentially expressed genes table) and `normalized_data`.

---

## [2008] source=multitask_sft_big

**USER:** Which underlying tools and packages are bundled inside the RImmPort workflow, and what input does it declare?

**ASSISTANT:** The RImmPort workflow incorporates the following tools:
- bioconductor/rimmport
- bioconductor/dbi
- bioconductor/plyr
- bioconductor/sqldf

It declares one data input slot: 'count_data' (type: data, optional: true).

---

## [2009] source=multitask_sft_big

**USER:** Extract the filtering criteria mentioned for Filter SAM or BAM: 'I want to filter my aligned BAM file to only keep reads mapped to chr1:1000-5000 with a MAPQ score of at least 30 and excluding duplicate FLAGs.'

**ASSISTANT:** Extracted filtering parameters:
- Region: chr1:1000-5000
- MAPQ (mapping quality): >= 30
- FLAG bits: filter/exclude duplicates

---

## [2010] source=multitask_sft_big

**USER:** What input data structures are needed to run `hireewas`?

**ASSISTANT:** The `hireewas` workflow requires two input matrices:
1. `Ometh`: Matrix of bulk methylation values (CpG sites by samples)
2. `X`: Matrix of covariates (covariate types by samples)

---

## [2011] source=multitask_sft_big

**USER:** Configure Cohort Qc Triage with metadata from 'study_meta.tsv', metrics from 'metrics.tsv', cohort ID 'COHORT_01', batch variable 'batch_id', phenotype column 'treatment_group', and minimum completeness of 0.9.

**ASSISTANT:** Here are the extracted parameters for `Cohort Qc Triage`:
- `metadata_file`: "study_meta.tsv"
- `qc_metrics_file`: "metrics.tsv"
- `dataset_id`: "COHORT_01"
- `batch_field`: "batch_id"
- `group_field`: "treatment_group"
- `min_completeness`: 0.9

---

## [2012] source=multitask_sft_big

**USER:** I want to run RNAheat between 15°C and 75°C with an ipoints value of 4.

**ASSISTANT:** Extracted parameters for RNAheat:
- t1 (start temperature): 15
- t2 (end temperature): 75
- ipoints: 4 (fits a parabola to 2 * 4 + 1 = 9 data points for numeric 2nd derivatives)

---

## [2013] source=multitask_sft_big

**USER:** Please set up the inputs for heatplus_annotated_heatmap using my files: my feature abundance table is in '/data/norm_matrix.csv' and my phenotype annotations are in '/data/meta_table.csv'.

**ASSISTANT:** Here is the parameter mapping for `heatplus_annotated_heatmap`:
- `exprs_matrix.csv`: `/data/norm_matrix.csv`
- `sample_metadata.csv`: `/data/meta_table.csv`

---

## [2014] source=multitask_sft_big

**USER:** In my OpenPepXL search against the target-decoy database, all decoy accessions start with 'DECOY_'. Please extract the relevant decoy identifier setting.

**ASSISTANT:** Based on your input, the decoy accession indicator string is 'DECOY_', and the 'prefix' flag should be enabled to indicate that this string precedes the protein accessions in the database.

---

## [2015] source=multitask_sft_big

**USER:** I am configuring Ped2Fasta with a PED file and want the output FASTA prefix to be 'cohortA'. What parameter should I set?

**ASSISTANT:** Set the "Output file name" parameter to 'cohortA', which will be used as the prefix for the generated FASTA output file.

---

## [2016] source=multitask_sft_big

**USER:** I have preprocessed placental methylation data saved as 'cohort_bmiq_matrix.rds'. How should this be supplied to `planet_preeclampsia_prediction`?

**ASSISTANT:** You should supply your matrix to the required `DNAm_betas_normalized.rds` data input parameter, ensuring that it is a BMIQ-normalized matrix of beta values oriented with samples across rows and CpGs across columns.

---

## [2017] source=multitask_sft_big

**USER:** I am configuring CCQTL permutation testing. Here are my settings: traits = 'glucose', covariates = ['sex', 'diet', 'batch', 'weight'], where weight is numeric and the others are categorical factors from my genome_scan step. Can you extract the valid covariates for running permutations?

**ASSISTANT:** Based on CCQTL requirements for running permutations, you may specify at most three covariates, and all of them must be categorical variables that were previously included as covariates at the genome_scan step. 

Extracted valid configuration:
- Stratification/Permutation Covariates: `['sex', 'diet', 'batch']` (select up to 3 categorical variables; `sex` is standard)
- Excluded: `'weight'` cannot be used because it is numeric/continuous rather than categorical, and the covariate count cannot exceed three.

---

## [2018] source=multitask_sft_big

**USER:** I am configuring CEAS for a ChIP-seq run where I want to perform genome background re-annotation using a WIG file. Which specific command-line flag must be supplied?

**ASSISTANT:** For genome background re-annotation in CEAS, you must set the `--bg` flag along with your WIG file input.

---

## [2019] source=multitask_sft_big

**USER:** What inputs must I provide to run the biocor_merge_similarity_sources workflow?

**ASSISTANT:** You must provide two non-optional inputs:
1. 'genesKegg': a list containing KEGG pathway-to-gene annotations.
2. 'genesReact': a list containing Reactome pathway-to-gene annotations.

---

## [2020] source=multitask_sft_big

**USER:** What input slot does the multiMiR workflow declare for providing count data?

**ASSISTANT:** The multiMiR workflow declares a required input slot named 'input_files' of type data (representing count_data) to be read by the workflow.

---

## [2021] source=multitask_sft_big

**USER:** Please parse my run parameters for the GEARS perturbation GPU workflow: 'Simulate knockouts for TP53 and PTEN in cell line A549 using our matrix at /data/sc_counts.h5ad. We want top 50 DEGs, running on device cuda:0 with epistasis_model set to non-linear.'

**ASSISTANT:** Here are the extracted parameters for `virtual_cell/gears_perturbation_gpu`:
- `adata_h5ad`: "/data/sc_counts.h5ad"
- `perturb_genes`: ["TP53", "PTEN"]
- `cell_line`: "A549"
- `perturbation_type`: "knockout"
- `top_k_degs`: 50
- `device`: "cuda:0"
- `epistasis_model`: "non-linear"

---

## [2022] source=multitask_sft_big

**USER:** What is the purpose of the `SOMA_nodelist2.fn` input in the `alphabeta_somatic_clonal_systems_epimutation_rate` workflow, and is it mandatory?

**ASSISTANT:** In the `alphabeta_somatic_clonal_systems_epimutation_rate` workflow, `SOMA_nodelist2.fn` provides node metadata containing branchpoint dates. It is marked as an optional data input (`"optional": true`).

---

## [2023] source=multitask_sft_big

**USER:** Can you list the required input datasets and their formats for the censcyt_censored_da_wrapper workflow?

**ASSISTANT:** The `censcyt_censored_da_wrapper` workflow requires three inputs:
1. `d_input`: A list of matrices containing marker expression data per sample.
2. `experiment_info`: A data.frame containing sample IDs, observed covariate values, and event indicators.
3. `marker_info`: A data.frame containing channel names, marker names, and marker classes.

---

## [2024] source=multitask_sft_big

**USER:** I want to run the `rbsurv` workflow. What is the mandatory data input requirement?

**ASSISTANT:** The workflow requires the data input `count_data` passed via the `input_files` parameter slot.

---

## [2025] source=multitask_sft_big

**USER:** Here is my setup for cytokernel:
- Expression data: expression_matrix.csv
- Conditions: group_labels.csv
Can you confirm which input files are marked as required in the workflow parameters?

**ASSISTANT:** Based on the workflow specification, `expression_matrix.csv` is marked with `optional: false` (required) and is read directly by the workflow as a matrix, data frame, or SummarizedExperiment. The companion input `group_labels.csv` is also required to provide the binary categorical condition vector for the samples.

---

## [2026] source=multitask_sft_big

**USER:** What are the output artifacts produced by the pipecomp workflow?

**ASSISTANT:** The `pipecomp` workflow produces three primary outputs: `de_table`, `cluster_assignments`, and `visualizations`.

---

## [2027] source=multitask_sft_big

**USER:** What input format must tabular query files adhere to when querying BloomTree Manager - Query?

**ASSISTANT:** Input tabular files for `BloomTree Manager - Query` must contain `(ID, TRANSCRIPT)` couples on each line. If multiple files are supplied, their content is merged to construct the query.

---

## [2028] source=multitask_sft_big

**USER:** For the subcellbarcode workflow, how should the replicate fractions be formatted in the protein abundance table?

**ASSISTANT:** In the `protein_abundance.tsv` input table, replicates across fractions should be formatted with `.A.` and `.B.` identifiers.

---

## [2029] source=multitask_sft_big

**USER:** I want to run spotclean_spatial_experiment_workflow on my raw Space Ranger folder located at '/data/visium/run1_outs/'. How should the input parameter be set?

**ASSISTANT:** You should set the parameter `spaceranger_output_dir` to '/data/visium/run1_outs/'. The workflow will process this raw directory and produce the decontamination output table `de_table`.

---

## [2030] source=multitask_sft_big

**USER:** Can Amulety Antiberta2 be used for T-cell receptor (TCR) nucleotide sequences, or is its scope strictly defined?

**ASSISTANT:** `Amulety Antiberta2` is specifically designed for antibody (B-cell receptor/BCR) amino acid sequences rather than nucleotide sequences or TCR profiles.

---

## [2031] source=multitask_sft_big

**USER:** Looking at this log output from quasr_smrna_seq_analysis:
"Error in preprocessReads(tab$FileName, tab2$FileName, Rpattern = 'TGGAATTCTCGGGTGCCAAGG') : non-existing input file(s): mirna_1.fa"
Can you extract the adapter pattern argument and the missing filename?

**ASSISTANT:** Based on the log output:
- **Adapter pattern (`Rpattern`)**: `'TGGAATTCTCGGGTGCCAAGG'`
- **Missing input file**: `mirna_1.fa`

---

## [2032] source=multitask_sft_big

**USER:** Here are my files for differential testing: measurement matrix `tail.csv.gz`, count weight matrix `tail_count.csv.gz`, and sample annotation sheet `samples`. Can you map these to the required inputs for weitrix?

**ASSISTANT:** The provided files map to the weitrix workflow inputs as follows:
- `tail.csv.gz`: assigned as the required continuous measurement matrix (`tail.csv.gz`)
- `tail_count.csv.gz`: assigned as the required weight/count matrix (`tail_count.csv.gz`)
- `samples`: assigned as the experimental design metadata (`samples`)

These will be processed by bioconductor/weitrix to yield the differential effects table (`de_table`) and visualizations.

---

## [2033] source=multitask_sft_big

**USER:** What data inputs are defined in the configuration for the normqpcr_qpcr_normalization workflow?

**ASSISTANT:** The workflow defines two data inputs:
1. 'example.txt': Optional data file containing TaqMan qPCR data (not read directly by the workflow engine).
2. 'input_files': Data input for the analysis files.

---

## [2034] source=multitask_sft_big

**USER:** Here are the files I have for my GSEA run: differential expression table 'deg_results.csv' from edgeR and gene set object 'gene_sets.rds'. Can you verify and configure the input parameters for `escape_gsea_on_precomputed_deg`?

**ASSISTANT:** The parameters are configured as follows:
- `deg_results.csv`: "deg_results.csv" (differential expression results with logFC and p-values)
- `gene_sets.rds`: "gene_sets.rds" (gene set list or GSEABase GeneSetCollection object)

Both mandatory inputs are satisfied for `escape_gsea_on_precomputed_deg`.

---

## [2035] source=multitask_sft_big

**USER:** I am configuring the Ensembl Variant Effect Predictor (Ensemblvep Vep) module in our pipeline and need the output to be generated in JSON format. How do I specify this?

**ASSISTANT:** For Ensemblvep Vep, the output file format is controlled via `task.ext.args`. You should add the `--json` flag inside `task.ext.args` in your module configuration.

---

## [2036] source=multitask_sft_big

**USER:** What length range, wing chemistries, and Tm targets are evaluated in the aso_gapmer_design workflow?

**ASSISTANT:** The aso_gapmer_design workflow designs gapmers of 16–22 nt in length with either 5'-MOE-wing/DNA-gap/3'-MOE-wing or LNA-wing configurations, targeting a Tm between 50 and 65 °C.

---

## [2037] source=multitask_sft_big

**USER:** I am configuring identify_chimeric_seqs using the ChimeraSlayer method. What reference sequence parameter must I provide?

**ASSISTANT:** When using the ChimeraSlayer method in identify_chimeric_seqs, providing the path to (Py)Nast aligned reference sequences is REQUIRED. By default, it is set to ('NO', 'DEFAULT').

---

## [2038] source=multitask_sft_big

**USER:** In the documentation of MultiplexCrisprDOE, what do the abbreviations 'gfd' and 'ged' stand for?

**ASSISTANT:** In MultiplexCrisprDOE, `gfd` stands for gRNA/Cas9 frequencies, and `ged` stands for gRNA/Cas9 editing efficiencies.

---

## [2039] source=multitask_sft_big

**USER:** Here is my pipeline specification:
```yaml
workflow: planet
inputs:
  methylation_matrix: DNAm_betas.rds
references:
  trimester: first
```
What input data file and tools are involved?

**ASSISTANT:** From the specification for the `planet` workflow, the required input file is `DNAm_betas.rds` (a matrix of DNA methylation beta values with CpGs as rows and samples as columns). The tools utilized by this workflow include `bioconductor/planet`, `bioconductor/epidish`, `bioconductor/dplyr`, `bioconductor/ggplot2`, `bioconductor/minfi`, and `bioconductor/tidyr`.

---

## [2040] source=multitask_sft_big

**USER:** In the HistorySummary tool, which parameters correspond to outputs generated by tophat2, cufflinks, and cuffquant?

**ASSISTANT:** In `HistorySummary`, the parameters map to tool outputs as follows:
- `input1` is used to rename output files from `tophat2`.
- `input` is used to rename output files from `cufflinks`.
- `samples.sample` is used to rename output files from `cuffquant`.

---

## [2041] source=multitask_sft_big

**USER:** I want to run the summix workflow. I have a data frame named `observed_ref_freqs.tsv` containing observed and reference group allele frequencies. How does this map to the workflow inputs?

**ASSISTANT:** Your dataset maps directly to the required input parameter:
- `ancestryData`: `observed_ref_freqs.tsv` (A data frame containing observed and reference group allele frequencies for genetic variants; non-optional, read directly by the workflow).

---

## [2042] source=multitask_sft_big

**USER:** What is the default threshold for the minimum percent sequence identity to the closest blast hit in parallel_align_seqs_pynast?

**ASSISTANT:** The default value for the minimum percent sequence identity to the closest blast hit in `parallel_align_seqs_pynast` is 75.0.

---

## [2043] source=multitask_sft_big

**USER:** Which Bioconductor tools and packages are utilized within the pathwaypca workflow?

**ASSISTANT:** The `pathwaypca` workflow uses the following Bioconductor packages:
- `bioconductor/pathwaypca`
- `bioconductor/summarizedexperiment`
- `bioconductor/xml`
- `bioconductor/parallel`
- `bioconductor/rwikipathways`
- `bioconductor/survival`

---

## [2044] source=multitask_sft_big

**USER:** What are the inputs and outputs defined for the `nf-core/fastq_download_prefetch_fasterqdump_sratools` pipeline?

**ASSISTANT:** The pipeline takes `cart` as its input and produces `fastq` sequencing reads as its output.

---

## [2045] source=multitask_sft_big

**USER:** I need to run `simulate_demographic_history` to model genetic variation. Does it use msprime under the hood, and what field of omics does it belong to?

**ASSISTANT:** Yes, `simulate_demographic_history` uses msprime to carry out simulations of DNA sequences under demographic and coalescent models. Its primary omics application is genetics.

---

## [2046] source=multitask_sft_big

**USER:** What are the formatting specifications for the ChIP1.bam input in the normr_differential_enrichment workflow?

**ASSISTANT:** The ChIP1.bam input parameter expects a coordinate-sorted and indexed BAM file representing condition 1. It is marked as optional in the workflow configuration.

---

## [2047] source=multitask_sft_big

**USER:** What input dataset parameter is required to run the PWMEnrich workflow?

**ASSISTANT:** The workflow requires the non-optional data input parameter 'input_files' to supply the count data for analysis.

---

## [2048] source=multitask_sft_big

**USER:** What are the required input files or parameters to execute the CTdata workflow?

**ASSISTANT:** The CTdata workflow requires a non-optional data input slot named `input_files`, which accepts count data (`count_data`). There are no additional declared parameters.

---

## [2049] source=multitask_sft_big

**USER:** Please set up the parameters for Phase2 Dose Justification for compound 'CMPD-402'. We have candidate doses of 25, 50, and 100 mg, target effect of 80%, population CV of 25%, MTD AUC of 1500 ug*h/L with 20% AUC CV, clearance of 4.5 L/h, bioavailability of 70%, and want 1000 Monte Carlo simulations using 'er_model.json'.

**ASSISTANT:** Here are the extracted parameters for `pharmacology/phase2_dose_justification`:
- `compound_name`: "CMPD-402"
- `candidate_doses_mg`: [25, 50, 100]
- `target_effect_pct`: 80
- `population_cv_pct`: 25
- `mtd_auc_ug_L_h`: 1500
- `auc_cv_pct`: 20
- `cl_L_h`: 4.5
- `bioavailability_pct`: 70
- `n_mc_sim`: 1000
- `er_params_json`: "er_model.json"

---

## [2050] source=multitask_sft_big

**USER:** I need to align additional sequences to my reference alignment and obtain the sequence.map correspondence table. Which parameter handles this in MAFFT add (RNA)?

**ASSISTANT:** Use the `mapout` option. It generates the `sequence.map` correspondence table showing positions before and after the calculation, and it automatically activates `keeplength` to preserve reference site positions.

---

## [2051] source=multitask_sft_big

**USER:** Here are my files for running the epistack pipeline: replicates peak calls are in 'data/peaks/rep_merged_peaks.bed', and the aligned read coverage is located at 'data/alignments/chip_sample.bigWig'. Please assign these to the workflow inputs.

**ASSISTANT:** Based on your inputs, the epistack parameters are assigned as follows:
- `path_peaks`: `data/peaks/rep_merged_peaks.bed`
- `path_reads`: `data/alignments/chip_sample.bigWig`

---

## [2052] source=multitask_sft_big

**USER:** I want to execute the nf-core/proteogenomicsdb pipeline for my project. I need to run human Ensembl data under 'homo_sapiens' and pull study data from cBioPortal with ID 'brca_tcga'. What inputs should be passed?

**ASSISTANT:** Based on the pipeline specifications, the extracted input parameters are:
- ensembl_name: 'homo_sapiens'
- cbioportal_study_id: 'brca_tcga'

---

## [2053] source=multitask_sft_big

**USER:** How does the 'robust_regression' method work in ConsensusMapNormalizer, and what parameter controls it?

**ASSISTANT:** In ConsensusMapNormalizer, the `robust_regression` method scales each map by a factor computed from the ratios of non-differential background features, which is determined by the `ratio_threshold` parameter.

---

## [2054] source=multitask_sft_big

**USER:** Here are my files for paired allelic analysis: agg_dna.txt contains the aggregated DNA counts, agg_rna.txt contains the RNA counts, eid.txt contains our regulatory element IDs, and eseq.txt holds the element sequences.

**ASSISTANT:** I have mapped your files to the inputs for mpra_allelic_comparison:
- agg_dna.txt: agg_dna.txt (aggregated DNA count matrix)
- agg_rna.txt: agg_rna.txt (aggregated RNA count matrix)
- eid.txt: eid.txt (element IDs)
- eseq.txt: eseq.txt (optional element sequences)

---

## [2055] source=multitask_sft_big

**USER:** What input parameters does the Topaz Extract workflow accept?

**ASSISTANT:** The Topaz Extract workflow accepts three inputs/parameters: `topaz_threshold`, `expected_particles_per_micrograph`, and `use_cryosparc`.

---

## [2056] source=multitask_sft_big

**USER:** I want to run geotcgadata_cnv_differential_analysis. I have my gene-level CNV values saved in 'cnv_scores.tsv' as a matrix and my sample classifications in 'conditions.csv' as a vector. Which parameter corresponds to each file?

**ASSISTANT:** Based on the specification of geotcgadata_cnv_differential_analysis:
- `aa`: Map this to 'cnv_scores.tsv' (matrix of gene-level copy number scores).
- `sampleGroup`: Map this to 'conditions.csv' (vector of sample group assignments).

---

## [2057] source=multitask_sft_big

**USER:** In amrfinderplus_db, what does setting the similarity cutoff parameter to -1 do?

**ASSISTANT:** Setting the parameter to -1 directs the tool to use a curated threshold if one exists, and defaults to 0.9 otherwise.

---

## [2058] source=multitask_sft_big

**USER:** Here is my pipeline request: load 'pbmc_singlecell.rds' into the ucell_seurat_workflow to compute cell state signature scores and output the modified Seurat object.

**ASSISTANT:** Extracted parameter configuration for `ucell_seurat_workflow`:
- `seurat.object`: `pbmc_singlecell.rds` (type: rds, Seurat object containing single-cell expression data)
- Expected output: `seurat_object` containing the signature scores and nearest-neighbor smoothing results.

---

## [2059] source=multitask_sft_big

**USER:** What input parameters and files are specified for the `methimpute_enrichment_analysis` workflow?

**ASSISTANT:** The workflow specifies the following data inputs:
- `model`: A required RDS file containing the fitted methimpute model object (`optional: false`, `read_by_workflow: true`).
- `annotations.RData`: An RData file providing genomic annotations.

---

## [2060] source=multitask_sft_big

**USER:** I am configuring the gotools pipeline. My dataset consists of a list of vectors with Affymetrix probe IDs assigned to my 'subset' variable. Does gotools require this parameter, and what does it yield?

**ASSISTANT:** Yes, 'subset' is a required input parameter representing a list of vectors containing Affymetrix probe IDs. When executed, the gotools workflow processes these probe IDs to produce visualizations comparing their functional profiles.

---

## [2061] source=multitask_sft_big

**USER:** What specific output files are generated by the 'omada_modular_step_by_step_clustering' workflow upon completion?

**ASSISTANT:** The workflow generates two outputs: 'cluster_assignments' and 'feature_selection'.

---

## [2062] source=multitask_sft_big

**USER:** I want to launch the svaretro workflow with my SV calls in diploidSV.vcf and the hg19 annotations in TxDb.Hsapiens.UCSC.hg19.knownGene.

**ASSISTANT:** The extracted parameters for the `svaretro` workflow are:
- `diploidSV.vcf`: 'diploidSV.vcf' (VCF file containing structural variant calls)
- `TxDb.Hsapiens.UCSC.hg19.knownGene`: 'TxDb.Hsapiens.UCSC.hg19.knownGene' (Transcript database for gene/exon annotations)

---

## [2063] source=multitask_sft_big

**USER:** Please configure make_pie_charts to display only the top 15 taxa individually, grouping everything else together.

**ASSISTANT:** The parameter configuration for `make_pie_charts` is:
- Maximum number of individual categories: `15`
All additional categories will be automatically grouped into the 'other' category.

---

## [2064] source=multitask_sft_big

**USER:** In csvtk-freq, how do I specify that I want frequency counts calculated across columns 1 and 2 together?

**ASSISTANT:** You can pass multiple columns separated by a comma. To target columns 1 and 2, specify '1,2'.

---

## [2065] source=multitask_sft_big

**USER:** Which configuration parameters does nf-core/eager expose for handling library chemistry, UDG treatment, and reference inputs?

**ASSISTANT:** Based on the pipeline specification, `nf-core/eager` supports parameters including `udg_type` (for uracil-DNA glycosylase treatment status), `single_stranded` and `single_end` (for library type), `colour_chemistry` (for sequencing platform chemistry), alongside reference inputs like `fasta`, `genome`, `bam`, and `snpcapture_bed`.

---

## [2066] source=multitask_sft_big

**USER:** I want to run hicPCA to calculate the first and second eigenvectors for my compartment analysis.

**ASSISTANT:** I have extracted the eigenvector parameters for `hicPCA`:
- Eigenvectors to compute: `1 2`

---

## [2067] source=multitask_sft_big

**USER:** The metabolite IDs in my SBML network have a prefix attached that is missing in my tabulated formulas file. Which parameter in SetChemicalFormulas handles this?

**ASSISTANT:** Use the `-p` option in `SetChemicalFormulas` to specify the prefix difference between the SBML file and the tabulated file.

---

## [2068] source=multitask_sft_big

**USER:** Please prepare the retrofit pipeline using my spatial count matrix at 'spatial_counts.tsv' and my single-cell reference matrix at 'sc_reference.tsv'.

**ASSISTANT:** Here are the extracted parameters and inputs for the `retrofit` workflow:
- `X`: "spatial_counts.tsv" (Spatial transcriptomics gene expression matrix of order G x S)
- `sc_ref`: "sc_reference.tsv" (Single-cell reference matrix of average gene expression values of order G x K)

---

## [2069] source=multitask_sft_big

**USER:** What input data parameters does the summix_allele_frequency_adjustment workflow accept?

**ASSISTANT:** The workflow requires the non-optional data input `ancestryData`, which is a data frame containing observed and reference group allele frequencies for genetic variants.

---

## [2070] source=multitask_sft_big

**USER:** Run the Oral Absorption BCS model for compound SMILES 'CC(=O)Oc1ccccc1C(=O)O' at a 500 mg dose under fasted conditions using an immediate-release tablet.

**ASSISTANT:** Here are the extracted parameters for the Oral Absorption Bcs Model workflow:
- `smiles_list`: ['CC(=O)Oc1ccccc1C(=O)O']
- `dose_mg`: 500
- `fed_fasted`: 'fasted'
- `formulation_type`: 'immediate-release tablet'

Note: `measured_solubility_ugmL`, `measured_Caco2_cm_s`, and `pKa` were not specified and will rely on model predictions or defaults.

---

## [2071] source=multitask_sft_big

**USER:** What outputs should I expect when running the arraymvout_outlier_detection_from_affybatch workflow on my Affymetrix array dataset?

**ASSISTANT:** The `arraymvout_outlier_detection_from_affybatch` workflow produces three output types: a CSV table (`table/csv`), diagnostic plots in PDF format (`plot/pdf`), and an updated R data object (`object/rds`).

---

## [2072] source=multitask_sft_big

**USER:** What input data does the rprimer_mixed_primer_design_masked_alignment workflow require, and is it mandatory?

**ASSISTANT:** The workflow takes 'example_alignment.txt', which is a multiple DNA sequence alignment in FASTA format. According to the workflow specification, this input parameter is marked as optional.

---

## [2073] source=multitask_sft_big

**USER:** Here are my input parameters for rcsl: I have an expression count matrix 'pbmc_raw_counts.tsv' and a benchmark annotation vector 'cell_types.csv' to validate the groupings. Please map these to the workflow inputs.

**ASSISTANT:** Here is the mapped input configuration for the 'rcsl' workflow:
- `origData`: 'pbmc_raw_counts.tsv' (matrix of raw single-cell RNA-seq expression values, required)
- `label`: 'cell_types.csv' (vector of true cell type annotations, optional for validation)

---

## [2074] source=multitask_sft_big

**USER:** I need to set up the wpm_summarized_experiment_to_plate_map workflow using my experiment file stored at 'data/proteomics_se.rds'. What parameters must be configured?

**ASSISTANT:** For the `wpm_summarized_experiment_to_plate_map` workflow, configure the required data input:
- `se`: `"data/proteomics_se.rds"` (type: `rds_se`, a SummarizedExperiment object containing sample assays and colData).

---

## [2075] source=multitask_sft_big

**USER:** In the rontotools workflow definition, what are the properties of the input dataset parameter?

**ASSISTANT:** The input dataset parameter is named `topTable.RData`, has `type: "data"`, is not optional (`optional: false`), has `read_by_workflow: true`, and is described as a data frame containing logFC, P.Value, adj.P.Val, and entrez gene IDs.

---

## [2076] source=multitask_sft_big

**USER:** Please set up the GEARS perturbation prediction pipeline for cell line K562, perturbing TP53 and CDKN1A using knockout, with top_k_degs set to 50, additive epistasis model, and LINCS cross-validation enabled.

**ASSISTANT:** Here are the extracted parameters for `virtual_cell/gears_perturbation_prediction`:
- `cell_line`: "K562"
- `perturb_genes`: ["TP53", "CDKN1A"]
- `perturbation_type`: "knockout"
- `top_k_degs`: 50
- `epistasis_model`: "additive"
- `lincs_crossval`: true

---

## [2077] source=multitask_sft_big

**USER:** What output is generated by the pharmacogx_drug_synergy_antagonism workflow?

**ASSISTANT:** The workflow produces `visualizations` (representing synergy landscapes).

---

## [2078] source=multitask_sft_big

**USER:** What inputs and outputs are defined for the coseq_edger_integrated_coexpression workflow?

**ASSISTANT:** Inputs:
- `counts`: A matrix or data.frame of gene-level counts.
- `conds`: A vector specifying experimental conditions.

Outputs:
- `de_table`: The differential expression results table.
- `cluster_assignments`: Cluster assignments from the co-expression analysis.
- `counts_matrix`: The gene counts matrix.

---

## [2079] source=multitask_sft_big

**USER:** I have an instrument run saved at '/data/sample1.h5'. How does this map to the input parameters of ptairms_single_raw_file_processing?

**ASSISTANT:** Your file '/data/sample1.h5' maps to the 'file.h5' parameter (described as a single raw PTR-TOF-MS data file in HDF5 format). The workflow also defines an 'input_files' data input slot.

---

## [2080] source=multitask_sft_big

**USER:** I need to model 24-hour core body temperature data using the Biomni Cosinor Model. What mathematical parameters will the model estimate?

**ASSISTANT:** The Biomni: Cosinor Model fits a cosine curve to your physiological data and estimates: 1) baseline (mesor), 2) amplitude, and 3) phase shift.

---

## [2081] source=multitask_sft_big

**USER:** I am configuring ExtractSubReactionNetwork for metabolic pathway analysis. What export formats are available for the resulting graph, and what is used by default?

**ASSISTANT:** By default, `ExtractSubReactionNetwork` exports a tabulated edge list (`source id edge type target id`). Other available export formats include GML, JsonGraph, and a tabulated node list (`label node id node type`).

---

## [2082] source=multitask_sft_big

**USER:** Please set up the graper workflow with my files: training predictors are in 'norm_counts_train.mat', continuous outcome is 'resp_train.vec', feature clusters are listed in 'gene_groups.vec', and evaluation features are in 'norm_counts_test.mat'.

**ASSISTANT:** The input parameters for the graper workflow have been extracted as follows:
- Xtrain: 'norm_counts_train.mat'
- ytrain: 'resp_train.vec'
- annot: 'gene_groups.vec'
- Xtest: 'norm_counts_test.mat'

---

## [2083] source=multitask_sft_big

**USER:** I have a query file named 'clones.fasta' with protein variants and a reference protein sequence file 'ref_protein.fa'. Set up the data inputs for ggseqalign.

**ASSISTANT:** Here is the parameter and data mapping for the `ggseqalign` workflow:
- `query_sequences.fa`: `clones.fasta` (FASTA file containing query AA sequences)
- `subject_sequence`: `ref_protein.fa` (Reference AA sequence FASTA file)

---

## [2084] source=multitask_sft_big

**USER:** I want to supply a custom TSV file called 'peptide_quants.tsv' containing my peptide abundance estimates to the IsoBayes user provided data pipeline. How should this be specified?

**ASSISTANT:** In the isobayes_user_provided_data_pipeline, supply your file to the optional table parameter `X`, which accepts a custom .tsv file or data.frame containing peptide abundances.

---

## [2085] source=multitask_sft_big

**USER:** I am curating an SBML metabolic model where all metabolite IDs follow the convention 'atp_c' and 'atp_m'. Which merge strategy parameter should I supply to SbmlWizard?

**ASSISTANT:** You should specify the `by_id` strategy. This option is designed specifically for compound identifiers following the suffix format `xxx_y` (such as `atp_c` and `atp_m`), allowing SbmlWizard to recognize the base metabolite identifier and merge compartments appropriately.

---

## [2086] source=multitask_sft_big

**USER:** What inputs are defined for the getDEE2 workflow?

**ASSISTANT:** The getDEE2 workflow accepts `count_data` (declared as `input_files` in the pipeline) as its data input.

---

## [2087] source=multitask_sft_big

**USER:** Please set up the input parameters for openstats_fishers_exact_test_workflow using my file located at '/data/pheno_cat_cohort1.csv'.

**ASSISTANT:** The workflow configuration for the required data input is:

- `test_categorical.csv`: "/data/pheno_cat_cohort1.csv" (CSV file containing categorical phenotypic measurements, genotype, and sex columns; non-optional).

---

## [2088] source=multitask_sft_big

**USER:** When configuring the CUSTOM format in AGouTI annotate, which column indices must I define?

**ASSISTANT:** When using the CUSTOM option in AGouTI annotate, you must specify 1-based column indices for the feature ID (`id`), chromosome (`chr`), start coordinate (`s`), and end coordinate (`e`). You can also optionally specify the column index for strand.

---

## [2089] source=multitask_sft_big

**USER:** I need to run the Generate pileup tool on my BAM file to produce a simple pileup dataset without consensus calling. How should I set the options?

**ASSISTANT:** To produce a simple pileup dataset, set the option 'Call consensus according to MAQ model?' to 'No'.

---

## [2090] source=multitask_sft_big

**USER:** What is the default setting for excluding taxonomic lineage information when running single_rarefaction?

**ASSISTANT:** The parameter to exclude taxonomic (lineage) information for each OTU in single_rarefaction defaults to False.

---

## [2091] source=multitask_sft_big

**USER:** What are the declared outputs and underlying tools for the synergyfinder workflow?

**ASSISTANT:** The workflow uses the tool `bioconductor/synergyfinder` and produces `visualizations` as its declared output from the required input table `drug_screening_data.csv`.

---

## [2092] source=multitask_sft_big

**USER:** Configure the probability binning comparison workflow with my normalized dataset located at 'data/normalized_samples.gs'.

**ASSISTANT:** Here is the extracted parameter configuration for `flowstats_probability_binning_comparison`:

- `gs`: "data/normalized_samples.gs" (GatingSet or flowSet containing normalized flow cytometry samples)

---

## [2093] source=multitask_sft_big

**USER:** Which input files are required to run the `vsn_rglist_normalization` workflow?

**ASSISTANT:** The `vsn_rglist_normalization` workflow requires two non-optional RDS inputs: `lymRG` (an RGList object containing red and green intensities) and `lymRGwbg` (an RGList object containing red and green intensities with background estimates).

---

## [2094] source=multitask_sft_big

**USER:** What is the recommended and default window size setting for Chimera.ccode, and what happens if a value less than 1 is provided?

**ASSISTANT:** In Chimera.ccode, the recommended window size is between 5% and 20% of your trimmed sequence length. The default setting is 10% of the sequence length, which is also automatically applied if a value less than 1 is specified.

---

## [2095] source=multitask_sft_big

**USER:** What options are available for metric evaluation in the metagenomics tool Cluster.split?

**ASSISTANT:** The available options for Cluster.split are:
- Matthews correlation coefficient (`mcc`)
- Sensitivity (`sens`)
- Specificity (`spec`)
- True positives + true negatives (`tptn`)
- False positives + false negatives (`fpfn`)
- True positives (`tp`)
- True negatives (`tn`)
- False positives (`fp`)
- False negatives (`fn`)
- `f1s`

---

## [2096] source=multitask_sft_big

**USER:** What input parameters and Bioconductor tools are configured for the recount workflow?

**ASSISTANT:** The `recount` workflow requires a mandatory data input slot named `input_files` (read_by_workflow: true) expecting count_data. It incorporates Bioconductor tools including `bioconductor/recount`, `bioconductor/deseq2`, `bioconductor/dt`, `bioconductor/genomeinfodb`, `bioconductor/genomicranges`, and `bioconductor/rcolorbrewer`.

---

## [2097] source=multitask_sft_big

**USER:** What are the required input parameters and data types for the flowstats workflow?

**ASSISTANT:** The flowstats workflow requires a single mandatory input parameter named 'ITN', which is of type data and must be a flowSet or GatingSet containing flow cytometry samples with FSC, SSC, and fluorescence channels.

---

## [2098] source=multitask_sft_big

**USER:** I have an input file `gut_microbiome_16S.fasta`. Which parameter in the rrdp workflow maps to this file?

**ASSISTANT:** You should map `gut_microbiome_16S.fasta` to the `sequences.fasta` parameter in `rrdp`, which expects a FASTA file containing 16S rRNA sequences.

---

## [2099] source=multitask_sft_big

**USER:** I want to execute variantfiltering with my input files located at `/data/vcfs/CEUtrio.vcf.bgz` and `/data/bams/NA12878.subset.bam`. Please extract the data input mapping.

**ASSISTANT:** Here is the extracted input configuration:
- `CEUtrio.vcf.bgz`: `/data/vcfs/CEUtrio.vcf.bgz`
- `NA12878.subset.bam`: `/data/bams/NA12878.subset.bam`

Other visualization BAMs (`NA12891.subset.bam`, `NA12892.subset.bam`) remain omitted as they are optional.

---

## [2100] source=multitask_sft_big

**USER:** When is it appropriate to choose the 'No packaged matrix output' option in Scanpy FilterCells, and when should it be avoided?

**ASSISTANT:** Choosing 'No packaged matrix output' is useful when auxiliary files are generated (such as in marker gene analysis). However, you should not use it when there are no other output files, as the tool will produce no usable output.

---

## [2101] source=multitask_sft_big

**USER:** In ivar trim, what happens if I enable the option to drop reads not fully contained in any amplicon?

**ASSISTANT:** When you select 'Yes' for that option, any reads that are not fully contained within an amplicon will be dropped prior to primer trimming. Note that this feature is marked as [Experimental] in ivar, though it is recommended.

---

## [2102] source=multitask_sft_big

**USER:** Can I supply standard GFF3 or BED6+ files to 'Circos: Interval to Circos Text Labels' to generate general heatmaps, or is it specifically formatted for text labels?

**ASSISTANT:** The tool specifically converts standard BED6+ and GFF3 interval files into formats suitable for Circos text tracks (data labels), rather than heatmap matrices.

---

## [2103] source=multitask_sft_big

**USER:** We want to configure RetroPath2.0 for a pathway search. We decided to constrain the reaction rule diameter to a minimum diameter of 2 and a maximum diameter of 6. Can you extract these parameters?

**ASSISTANT:** The extracted parameters for RetroPath2.0 are:
- `dmin`: 2
- `dmax`: 6

---

## [2104] source=multitask_sft_big

**USER:** What outputs are generated by `metagenomeseq_longitudinal_time_series`?

**ASSISTANT:** The workflow generates two primary outputs: `differential_abundance` results and `visualizations`.

---

## [2105] source=multitask_sft_big

**USER:** What input files, outputs, and Bioconductor tools are involved in the mariner workflow?

**ASSISTANT:** The `mariner` workflow utilizes:
- **Inputs:** `FS_5kbLoops.txt` (BEDPE file of loops for replicate FS) and `WT_5kbLoops.txt` (BEDPE file of loops for replicate WT)
- **Output:** `consensus_score`
- **Tools:** `bioconductor/mariner`, `bioconductor/interactionset`, `bioconductor/marinerdata`, and `bioconductor/strawr`

---

## [2106] source=multitask_sft_big

**USER:** I need to prepare a custom protein database before running BLAST searches to prevent non-specific matches from repetitive or low-complexity segments. Which tool should I use?

**ASSISTANT:** Use **NCBI BLAST+ segmasker**. It processes protein sequences or protein databases by applying the SEG algorithm to detect and mask out low-complexity regions, which is a standard pre-processing step for protein BLAST database preparation.

---

## [2107] source=multitask_sft_big

**USER:** What inputs must I provide to run the 'moanin' differential expression workflow?

**ASSISTANT:** You must provide two inputs: 'preData', which is a matrix of raw gene expression counts, and 'preMeta', which is a data frame containing sample metadata with group and time variables.

---

## [2108] source=multitask_sft_big

**USER:** I want to extract my repeat library from my RepeatExplorer archive using the Extract Repeat Library from RepeatExplorer Archive tool. Please filter out sequences that have a read depth lower than 10, and drop any contigs shorter than 300 base pairs.

**ASSISTANT:** The extracted parameters for 'Extract Repeat Library from RepeatExplorer Archive' are:
- Read depth threshold: 10 (sequences with read depth smaller than this threshold will be removed)
- Contig length threshold: 300 (contigs shorter than this threshold will be filtered out, noting that filtering does not affect TAREAN consensus sequences).

---

## [2109] source=multitask_sft_big

**USER:** What are the allowed thread settings and the default value for seqsero_v2?

**ASSISTANT:** For seqsero_v2, the thread range is 1 through 4, with a default value of 1. Only 4 threads will be used for assembly since the amount of extracted reads is small.

---

## [2110] source=multitask_sft_big

**USER:** Here is my pipeline setup:
- Expression matrix: normalized_counts.tsv (numeric matrix)
- Diagnostic cohorts: cohort_labels.rds (factor format)
Please map these to the inputs for the classifyr_parameter_tuning workflow.

**ASSISTANT:** Based on the classifyr_parameter_tuning workflow definition, the inputs are mapped as follows:
- measurements: normalized_counts.tsv (numeric matrix)
- classes: cohort_labels.rds (factor of class labels)

---

## [2111] source=multitask_sft_big

**USER:** I am using MergeSamFiles to merge BAM files where variable-length data (such as reads, qualities, and tags) do not need to be decoded. How can I configure it to improve processing performance?

**ASSISTANT:** You can improve performance by setting the stringency parameter to `SILENT`. This avoids decoding variable-length data (reads, qualities, tags) when it is not otherwise required.

---

## [2112] source=multitask_sft_big

**USER:** I am configuring Isoplot to visualize my IsoCor metabolomics data. I want to plot both the mean enrichment and the isotopologue fraction. What values should I pass to the --value flag?

**ASSISTANT:** You should supply the `--value` flag with "mean_enrichment" and "isotopologue_fraction". Because `--value` can be passed multiple times, you can set `--value mean_enrichment --value isotopologue_fraction`.

---

## [2113] source=multitask_sft_big

**USER:** What data input does the `qvalue` workflow expect?

**ASSISTANT:** The workflow expects an input vector of p-values from simultaneous hypothesis tests (such as `hedenfalk$p` or the `hedenfalk` dataset input).

---

## [2114] source=multitask_sft_big

**USER:** For the varianttools workflow, what are the accepted data input arguments and their specifications?

**ASSISTANT:** The data inputs for the `varianttools` workflow are:
- `sample.bam`: An aligned reads BAM file (data input).
- `genome_reference` (or `reference_genome`): A GMAP/gmapR genome object or reference sequence.

---

## [2115] source=multitask_sft_big

**USER:** How can I configure Bedtools Slop if I need to extend an interval by 200 bp upstream and 50 bp downstream instead of using a symmetric window?

**ASSISTANT:** You can specify directional expansion by passing distinct values to the `-l` parameter (for the left/upstream side) and the `-r` parameter (for the right/downstream side).

---

## [2116] source=multitask_sft_big

**USER:** What output files will be generated when I run the scmerge_sc_merge_v2_hierarchical workflow?

**ASSISTANT:** The workflow produces three types of output formats: tabular files ('table/csv'), graphical plots ('plot/pdf'), and R data objects ('object/rds').

---

## [2117] source=multitask_sft_big

**USER:** Configure Netisce step 9 for our network perturbation dataset where we want to classify attractors into 4 phenotype clusters using the default consensus logic.

**ASSISTANT:** For Netisce step 9, the parameters are set as follows:
- Number of clusters (k): 4
- Classifiers: SVM, Naive Bayes, Random Forest
- Selection criterion: Perturbations shifting to the target phenotype cluster by at least 2/3 classification methods.

---

## [2118] source=multitask_sft_big

**USER:** Please set up the CRO submission export workflow with the following specifications: compound file is 'screen_hits.csv', CRO target is 'EGFR', export top 25 compounds, hERG safety IC50 threshold must be greater than 10.0, assay name is 'hERG_PatchXpress', and project code is 'PRJ-ONCO-2024'.

**ASSISTANT:** I have extracted the parameters for the `drug_discovery/cro_submission_export` workflow:

- `compound_csv`: "screen_hits.csv"
- `cro_target`: "EGFR"
- `top_n`: 25
- `herg_safe_threshold`: 10.0
- `assay_name`: "hERG_PatchXpress"
- `project_code`: "PRJ-ONCO-2024"

---

## [2119] source=multitask_sft_big

**USER:** Here are my files for branch point analysis: chol_cell_matrix.csv for cholangiocyte attributes, chol_times.rds for its pseudotime, hep_cell_matrix.csv for hepatocyte attributes, and hep_times.rds for its pseudotime. Please configure the inputs.

**ASSISTANT:** I have extracted the parameters for `trajectorygeometry_branch_point_analysis`:
- `chol_attributes`: 'chol_cell_matrix.csv'
- `chol_pseudo_time`: 'chol_times.rds'
- `hep_attributes`: 'hep_cell_matrix.csv'
- `hep_pseudo_time`: 'hep_times.rds'

---

## [2120] source=multitask_sft_big

**USER:** What genomic variant inputs are accepted by the transmogr_coordinate_shifting_reference_extraction workflow?

**ASSISTANT:** The workflow accepts a VCF input file, such as `1000GP_subset.vcf.gz (ge`, which is an optional genomic variant dataset in VCF format.

---

## [2121] source=multitask_sft_big

**USER:** I am configuring the puma workflow. My input data consists of raw CEL files: celFiles = ['sampleA1.CEL', 'sampleA2.CEL', 'sampleB1.CEL']. Could you verify which parameter handles this and what outputs will be produced?

**ASSISTANT:** The parameter that takes your files is `celFiles` (raw Affymetrix 3' array CEL files). Once executed, the workflow will produce three outputs:
1. `de_table` (differential expression results)
2. `cluster_assignments`
3. `normalized_data`

---

## [2122] source=multitask_sft_big

**USER:** What are the output artifacts produced by the transcriptformer_cell_state workflow?

**ASSISTANT:** The `transcriptformer_cell_state` workflow produces the following outputs: `sdf`, `csv_scores`, `tsv_admet`, `tsv_pk`, and `pdf_report`.

---

## [2123] source=multitask_sft_big

**USER:** I am configuring the PyCaret Predictor/Evaluator tool in my pipeline. How do I specify which column contains the target values to predict?

**ASSISTANT:** In the PyCaret Predictor/Evaluator tool, specify your target column by entering its name into the `target_feature` input field after uploading your dataset.

---

## [2124] source=multitask_sft_big

**USER:** I want to set up the rnbeads pipeline. My raw intensity folder is located at `/data/methylation/idat_files` and the metadata table is stored at `/data/metadata/pheno_batch_info.csv`.

**ASSISTANT:** Here are the extracted input parameters for the `rnbeads` workflow:
- `idat`: `/data/methylation/idat_files`
- `sample_annotation.csv`: `/data/metadata/pheno_batch_info.csv`

---

## [2125] source=multitask_sft_big

**USER:** What are the inputs and expected outputs of the `demuxmix_pooling_non_labeled_with_labeled_cells` workflow?

**ASSISTANT:** The workflow takes a required data input named `csf` (a data frame containing HTO counts and detected gene counts per droplet) and produces `visualizations` as output.

---

## [2126] source=multitask_sft_big

**USER:** What are the required input data slots and expected outputs for the Streamer workflow?

**ASSISTANT:** The Streamer workflow requires a mandatory data input named 'input_files' (type: data) representing count_data. It declares no output files (out: []).

---

## [2127] source=multitask_sft_big

**USER:** I am configuring otu_category_significance. I want to test whether OTU abundance differs across my categorical experimental groups. Which test option should be passed?

**ASSISTANT:** You should set the test option to `ANOVA`, which is designed to determine whether OTU abundance is associated with a category.

---

## [2128] source=multitask_sft_big

**USER:** Filter out everything from my IsoDE2 results file `isode2_diff_expr.tsv` that doesn't have a fold change of at least 2.0.

**ASSISTANT:** Extracted parameters for `Fold Change Filter`:
- Input file: `isode2_diff_expr.tsv` (IsoDE2 output)
- Fold change threshold: `>= 2.0`

---

## [2129] source=multitask_sft_big

**USER:** I have a massive metagenomic dataset and want to batch my queries through blast_wrapper so that each BLAST call receives 5000 sequences instead of the default. Which parameter should I set?

**ASSISTANT:** Set the chunk/batch size parameter representing the number of sequences passed to each BLAST call to `5000` (the default value is `1000`).

---

## [2130] source=multitask_sft_big

**USER:** Please set up pengls using my dataset file `spatial_expression_data.csv`, which has our continuous outcome variable, high-dimensional predictors, and columns for spatial coordinates x and y.

**ASSISTANT:** Here is the extracted data input parameter for the `pengls` workflow:
- `df`: `spatial_expression_data.csv` (data frame containing the continuous outcome variable, high-dimensional regressors, and spatial coordinates x and y).

---

## [2131] source=multitask_sft_big

**USER:** I want to run dbAnnot to annotate the gene 'TP53' for human (taxon 9606) to retrieve Pathways and Genes in a table format. Can you parse these into the tool parameters?

**ASSISTANT:** Based on the dbAnnot specification, the parameters are extracted as follows:
- `inputValues`: 'TP53'
- `annotations`: 'Genes,Pathways'
- `fileType`: 'table'
- `TaxonId`: '9606'

---

## [2132] source=multitask_sft_big

**USER:** Please launch the rawdiag Shiny app on my raw data folder: '/storage/proteomics/orbitrap_run1/raw_files'.

**ASSISTANT:** The parameter extracted for 'rawdiag_launch_rawdiag_shiny_app' is:
- directory_path: '/storage/proteomics/orbitrap_run1/raw_files'

---

## [2133] source=multitask_sft_big

**USER:** What are the required input files and expected outputs for the meskit_phylogenetic_and_signature_analysis workflow?

**ASSISTANT:** Inputs:
- 'maf': An RDS file containing a Maf object generated from readMaf (mandatory).
- 'BSgenome.Hsapiens.UCSC.hg19': The reference genome package.

Outputs:
- 'mutational_signatures'
- 'phylogenetic_tree'
- 'visualizations'

---

## [2134] source=multitask_sft_big

**USER:** I have a configuration JSON containing: {"db_uri": "postgresql://user_name:password@host:port/path/to/database", "batch_size": 100}. How will 'Save Sequence Data In DB' extract the database connection?

**ASSISTANT:** The tool extracts the database connection string from the JSON file using the key 'db_uri', which provides the URI: 'postgresql://user_name:password@host:port/path/to/database'.

---

## [2135] source=multitask_sft_big

**USER:** What format and structure does the netboost workflow expect for the input tcga_aml_meth_rna_chr18?

**ASSISTANT:** The input 'tcga_aml_meth_rna_chr18' must be formatted as a matrix or data frame of omics features, where rows represent samples and columns represent features.

---

## [2136] source=multitask_sft_big

**USER:** I have prepared my files for damefinder_methyl_circle_visualization: 'sample1_aligned_bsseq.bam', 'sample1_het_snps.vcf', and 'hg38.fasta'. How should these be mapped to the workflow's data inputs?

**ASSISTANT:** The files map to the workflow data inputs as follows:
- `bam.file`: 'sample1_aligned_bsseq.bam'
- `vcf.file`: 'sample1_het_snps.vcf'
- `reference_file`: 'hg38.fasta'

---

## [2137] source=multitask_sft_big

**USER:** I want to run `pengls_temporal_autocorrelation_analysis`. My input dataset is stored in `patient_longitudinal_matrix.csv`, which has time step `t`, continuous biomarker `Y`, and 500 gene expression regressors. How should this be mapped?

**ASSISTANT:** Map your dataset to the workflow's input parameter as follows:
- `dfTime`: `patient_longitudinal_matrix.csv` (satisfies the requirement of containing a continuous outcome variable, high-dimensional regressors, and the time variable `t`).

---

## [2138] source=multitask_sft_big

**USER:** Please prepare the parameters for CryoSPARC Import Micrographs: path is '/data/cryoem/*.mrc', pixel size is 0.824 Å, acceleration voltage 300 kV, spherical aberration is 2.7 mm, total dose is 40.0 e-/Å², and enable cryosparc.

**ASSISTANT:** Extracted parameters for `Import Micrographs`:
- `micrographs_path`: "/data/cryoem/*.mrc"
- `pixel_size`: 0.824
- `voltage`: 300
- `spherical_aberration`: 2.7
- `total_dose`: 40.0
- `use_cryosparc`: true

---

## [2139] source=multitask_sft_big

**USER:** Extract the key inputs required by Split libraries from this description: 'This tool splits libraries according to barcodes specified in mapping file.'

**ASSISTANT:** Based on the description, the required inputs are:
- Multiplexed sequence library files
- Mapping file specifying the barcodes

---

## [2140] source=multitask_sft_big

**USER:** What input data slot is declared for the scanMiR Nextflow workflow?

**ASSISTANT:** The scanMiR workflow declares a required input data slot named `input_files` of type `data` (count_data), with no additional declared workflow parameters.

---

## [2141] source=multitask_sft_big

**USER:** In the 'Analyse CpGo/e ratios' tool, what option sets the maximum fraction of outlier ratios to exclude, and what is its default value?

**ASSISTANT:** The parameter is `-o` (or `--frac-outl`), which sets the maximum fraction of CpGo/e ratios excluded as outliers. Its default value is 0.01.

---

## [2142] source=multitask_sft_big

**USER:** I am configuring the logicfs_bagged_logic_regression_classification workflow. Here are my files: 'snp_matrix.rds' which contains SNP values (1, 2, 3) and 'pheno_labels.csv' which has the binary 0/1 outcome. Please set up the required inputs.

**ASSISTANT:** Here are the extracted parameters for the workflow:

```json
{
  "data_inputs": [
    {
      "name": "data.logicfs",
      "value": "snp_matrix.rds"
    },
    {
      "name": "cl.logicfs",
      "value": "pheno_labels.csv"
    }
  ]
}
```

---

## [2143] source=multitask_sft_big

**USER:** Please set up screcover for my single-cell data using my count matrix file 'sc_counts.rds' and cell type vector 'cell_annotations.rds'.

**ASSISTANT:** The parameters extracted for the `screcover` workflow are:
- `counts`: "sc_counts.rds" (scRNA-seq read counts matrix or SingleCellExperiment object)
- `labels`: "cell_annotations.rds" (optional vector specifying the cell type for each column)

---

## [2144] source=multitask_sft_big

**USER:** What are the input specifications for the `macsr` workflow?

**ASSISTANT:** The `macsr` workflow takes two primary alignment inputs (in BED or BAM format):
- `CHIP`: ChIP-seq treatment alignment file (BED/BAM format).
- `CTRL`: Control alignment file (BED/BAM format).

---

## [2145] source=multitask_sft_big

**USER:** When configuring the `Sink from SBML` tool for a BiGG model, which cellular compartment is targeted by default?

**ASSISTANT:** The default compartment extracted by `Sink from SBML` for BiGG models is the cytosol.

---

## [2146] source=multitask_sft_big

**USER:** What algorithms can I configure for the supervised_learning tool in this metagenomics pipeline, and what is the default?

**ASSISTANT:** Currently, the only supported method is 'random_forest', which is also the default value.

---

## [2147] source=multitask_sft_big

**USER:** What types of outputs will the ddpcrclust workflow generate once clustering finishes?

**ASSISTANT:** The workflow generates three output formats: 'table/csv' containing the numerical clustering and CPD results, 'plot/pdf' containing graphical plots produced via bioconductor/ggplot2, and an 'object/rds' file containing the R data objects.

---

## [2148] source=multitask_sft_big

**USER:** What are the required input file slots defined for the InterCellar workflow?

**ASSISTANT:** The workflow defines a required data input slot named `input_files` (optional: false, read_by_workflow: true).

---

## [2149] source=multitask_sft_big

**USER:** Configure the quasr_bis_seq_analysis workflow using my file 'my_bisulfite_samples.fasta' as the sample sheet listing bisulfite FASTA files.

**ASSISTANT:** Setting the data input for 'quasr_bis_seq_analysis':
- samples_bis_single.txt: 'my_bisulfite_samples.fasta' (type: fasta, description: sample sheet listing bisulfite FASTA files).

---

## [2150] source=multitask_sft_big

**USER:** What are the allowed value range and the default setting for the PPanGGOLiN rarefaction tool?

**ASSISTANT:** For PPanGGOLiN rarefaction, the default value is 30, with a minimum allowed value of 1 and a maximum allowed value of 100.

---

## [2151] source=multitask_sft_big

**USER:** What is the data input parameter configured for the `mungesumstats_quick_format_disk` workflow?

**ASSISTANT:** The workflow accepts `eduAttainOkbay.txt`, an optional data input described as a tabular GWAS summary statistics file.

---

## [2152] source=multitask_sft_big

**USER:** How do I configure the reference in basil if I want to perform self-mapping rather than using built-in indexes?

**ASSISTANT:** To perform self-mapping in basil, select 'history' for the reference setting and then choose your input file as the reference.

---

## [2153] source=multitask_sft_big

**USER:** In OptiType, how does setting the weight for single-end mapped reads affect paired-end HLA typing when one end falls outside the reference region?

**ASSISTANT:** In OptiType's paired-end mode, this setting controls whether reads with only one mapped end are retained:
- Setting the value to `0` completely discards single-end mapped reads from typing.
- Setting a positive weight (such as `0.2`) retains these reads but includes them with an optionally reduced weight during genotyping.

---

## [2154] source=multitask_sft_big

**USER:** I want to run hicFindRestSite to locate HindIII restriction cut sites using the motif pattern AAGCTT on my assembly. Extract the search pattern parameter.

**ASSISTANT:** The extracted search pattern parameter is `pattern = "AAGCTT"`.

---

## [2155] source=multitask_sft_big

**USER:** I want to configure FROGSSTAT Phyloseq Composition Visualisation to show taxonomy aggregated at the Phylum level, filtering only for Bacteria at the Kingdom rank. Which values should I assign to the taxonomic filtering and aggregation options?

**ASSISTANT:** You should set the subset taxon level to 'Kingdom' with the subset taxon 'Bacteria', and set the aggregation level to 'Phylum'.

---

## [2156] source=multitask_sft_big

**USER:** What output formats can I expect from executing the methtargetedngs pipeline?

**ASSISTANT:** The `methtargetedngs` workflow produces outputs in three distinct formats:
- `table/csv` (tabular summary results)
- `plot/pdf` (visualizations/plots)
- `object/rds` (serialized R data objects for downstream Bioconductor analysis).

---

## [2157] source=multitask_sft_big

**USER:** I want to run pagerank_multiplex_pagerank. I have base_graph.RData storing my igraph PPI network and supp_graph.RData containing the co-expression network. What inputs does the workflow expect?

**ASSISTANT:** The workflow expects two mandatory RDS/RData inputs:
1. 'base_graph.RData': igraph object representing the base network (optional: false)
2. 'supp_graph.RData': igraph object representing the supplemental network (optional: false)
Both files will be read by the workflow to output the resulting 'network_graph'.

---

## [2158] source=multitask_sft_big

**USER:** What input parameters and outputs are defined for the proteomics workflow 'process'?

**ASSISTANT:** The 'process' workflow accepts an optional data input parameter named 'testdir' (a directory containing raw mass spectrometry CSV files). Its primary output is 'normalized_data'.

---

## [2159] source=multitask_sft_big

**USER:** What inputs and outputs are defined for coseq_deseq2_integrated_coexpression?

**ASSISTANT:** The inputs and outputs for `coseq_deseq2_integrated_coexpression` are:
- **Inputs:**
  - `counts`: A matrix or data.frame of gene-level counts.
  - `conds`: A vector specifying experimental conditions.
- **Outputs:**
  - `de_table`: Table of differential expression results.
  - `cluster_assignments`: Co-expression cluster assignments for differentially expressed genes.

---

## [2160] source=multitask_sft_big

**USER:** I have an aligned read BAM file named `tumor_sample.bam` and an existing call set `raw_calls.vcf`. How should these be mapped to the `varianttools_wildtype_and_nocall_calling` workflow inputs?

**ASSISTANT:** Map the inputs as follows for the `varianttools_wildtype_and_nocall_calling` workflow:
- `sample.bam`: `tumor_sample.bam`
- `called_variants`: `raw_calls.vcf`

---

## [2161] source=multitask_sft_big

**USER:** Configure Schrodinger Glide Docking for receptor 'target_rec.mae' and ligands 'compound_library.sdf'. Use XP precision, set the grid center at coordinates (15.2, -8.4, 22.0) with an inner box of 10 and outer box of 25. Dock 5 poses per ligand, run LigPrep at pH 7.2 with a tolerance of 1.0, enable Epik, allow a maximum of 4 stereoisomers, and assign 16 CPUs.

**ASSISTANT:** Here are the extracted parameters for the Schrodinger Glide Docking workflow:
- receptor: target_rec.mae
- ligands: compound_library.sdf
- docking_precision: XP
- grid_center: [15.2, -8.4, 22.0]
- grid_inner_box: 10
- grid_outer_box: 25
- poses_per_ligand: 5
- ligprep_ph: 7.2
- ligprep_ph_tolerance: 1.0
- use_epik: true
- max_stereoisomers: 4
- n_cpus: 16

---

## [2162] source=multitask_sft_big

**USER:** In the lindna tool, I want to make the text labels for the group names on the left region smaller than their default size. What value should I input?

**ASSISTANT:** In `lindna`, you should enter a number less than 1.0 (<1.0) for the region left to the groups to decrease the size of the displayed group names.

---

## [2163] source=multitask_sft_big

**USER:** I want to run `methylkit_large_data_tabix_db`. I have my sample methylation call text files organized in `['/data/sample1_calls.txt', '/data/sample2_calls.txt']`. How does this map to the workflow inputs?

**ASSISTANT:** The input mapping is:
- `file.list`: `['/data/sample1_calls.txt', '/data/sample2_calls.txt']` (type: list, optional: false, description: list of text files containing methylation calls per sample).

---

## [2164] source=multitask_sft_big

**USER:** In the 'Extract values from an SD-file' tool, how should I specify the properties to extract, and how can I extract all available properties?

**ASSISTANT:** You should enter property names separated by commas (for example: `RMSD_UB,RMSD_LB,SCORE`). If you want to extract values for all properties in the SD-file, leave the field blank.

---

## [2165] source=multitask_sft_big

**USER:** I want to run `VCF to Hapmap` on `cohort_snps.vcf`. I have a reference genome in `genome.fasta` to get flanking variant regions and an annotation file `genes.gff` for gene alignments. What inputs are provided for this tool run?

**ASSISTANT:** From your request, the provided inputs for `VCF to Hapmap` are:
- **Input VCF file**: `cohort_snps.vcf` (contains all SNPs for conversion to Hapmap)
- **Fasta reference**: `genome.fasta` (enables generation of flanking sequences for variants)
- **GFF annotation**: `genes.gff` (enables creation of FASTA gene alignments)

---

## [2166] source=multitask_sft_big

**USER:** I want to run the Stiffness tool on chromosome 2 from base 1,500,000 to 2,500,000 for my chromatin structure study. How should I specify the genomic region parameter?

**ASSISTANT:** You should specify the genomic region as 'chr2:1500000-2500000'.

---

## [2167] source=multitask_sft_big

**USER:** Please set up the demixt workflow inputs using my files: my expression matrix is in 'expression_counts.tsv', the normal controls are listed in 'normal_samples.csv', and the tumor samples are in 'tumor_samples.csv'.

**ASSISTANT:** Here is the mapped parameter configuration for `demixt`:
- `PRAD`: expression_counts.tsv
- `Normal.id`: normal_samples.csv
- `Tumor.id`: tumor_samples.csv

---

## [2168] source=multitask_sft_big

**USER:** I want to configure nf-core/proteinfold for AlphaFold2 with GPU acceleration, pointing to my input samplesheet and database directory. Which pipeline parameters are available for this?

**ASSISTANT:** Based on the pipeline specification, you can use the following parameters:
- `--input`: Path to your input FASTA/samplesheet.
- `--outdir`: Output directory for storing `results_dir`.
- `--mode`: Prediction engine selection (e.g., AlphaFold2).
- `--use_gpu`: Boolean flag to enable GPU acceleration.
- `--alphafold2_db`: Path to the AlphaFold2 database.
- `--full_dbs`: Boolean flag indicating full vs. reduced database usage.
- `--alphafold2_mode`: Specific AlphaFold2 run mode (e.g., monomer or multimer).
- `--max_template_date`: Cutoff date for PDB structural templates.

---

## [2169] source=multitask_sft_big

**USER:** I want to run the mbkmeans workflow on my dataset saved at '/data/pbmc_filtered_counts.rds'. Can you parse the required inputs for this pipeline?

**ASSISTANT:** Here is the extracted input parameter for the mbkmeans workflow:

- `sce_object.rds`: `/data/pbmc_filtered_counts.rds` (type: rds_sce, SingleCellExperiment object containing raw or normalized counts)

This is a mandatory input required to execute the mini-batch k-means clustering workflow.

---

## [2170] source=multitask_sft_big

**USER:** I want to run `mosaics_convenient_two_sample_run_all` with my ChIP aligned reads file 'STAT1_ChIP_eland_results.txt'. Could you extract the input configuration?

**ASSISTANT:** Here is the extracted input configuration for `mosaics_convenient_two_sample_run_all`:
- `STAT1_ChIP_eland_results.txt`: ChIP aligned reads (optional data input)

---

## [2171] source=multitask_sft_big

**USER:** I am setting up 'Compare SAM Files and Create ASE Counts Tables'. I have an annotation file called 'genes_annotation.bed' with gene IDs in column 1. Is this compatible as the required feature input?

**ASSISTANT:** Yes. The required parameter is a BED file containing features to assign reads to (which can be a .bed or .tsv file), and 'genes_annotation.bed' fulfills the requirement as long as the feature ID names are in the first column.

---

## [2172] source=multitask_sft_big

**USER:** In csvtk-collapse, how should I format the input if I want to group or collapse by the first two columns?

**ASSISTANT:** You can specify the target columns as a comma-separated list of column numbers, for example: '1,2'.

---

## [2173] source=multitask_sft_big

**USER:** What outputs does the ccimpute_decomposed_imputation workflow generate?

**ASSISTANT:** The `ccimpute_decomposed_imputation` workflow produces two outputs: `cluster_assignments` and `consensus_score`.

---

## [2174] source=multitask_sft_big

**USER:** In Decontam, how should I encode the metadata column that identifies negative control samples in my phyloseq object?

**ASSISTANT:** In the phyloseq metadata column specifying whether a sample is a negative control, you should code normal samples as 0 and negative control samples as 1.

---

## [2175] source=multitask_sft_big

**USER:** What clustering algorithms can be specified when running DockPoseClustering?

**ASSISTANT:** The supported algorithms for DockPoseClustering are: `CLINK_DEFAYS`, `CLINK_ALTHAUS`, `NEAREST_NEIGHBOR_CHAIN_WARD`, `SLINK_SIBSON`, and `TRIVIAL_COMPLETE_LINKAGE`.

---

## [2176] source=multitask_sft_big

**USER:** For the 'Format cd-hit outputs' tool, what inputs are needed if I want to extract category distribution inside clusters?

**ASSISTANT:** To extract the category distribution inside clusters, the tool requires the CD-HIT cluster information and cluster representative sequence outputs, along with a mapping file defining the categories.

---

## [2177] source=multitask_sft_big

**USER:** I am running Get.lineage on my metagenomics data without an input taxon file. I want to filter for Bacteria;Firmicutes; and Bacteria;Actinobacteria;. How should I format these taxons for the tool?

**ASSISTANT:** When entering taxons directly in Get.lineage without a file, separate the taxons with dashes, for example: `Bacteria;Firmicutes;-Bacteria;Actinobacteria;`.

---

## [2178] source=multitask_sft_big

**USER:** Please configure Filter mapped reads (SAM) on my genomics alignment to discard reads with mismatches within 6 bp of the 5' end and within 12 bp of the 3' end.

**ASSISTANT:** Extracted parameters for Filter mapped reads (SAM):
- 5' window (n): 6 bp
- 3' window (m): 12 bp

---

## [2179] source=multitask_sft_big

**USER:** Set up Parse Split Seq Scrna on my FASTQs in '/data/parse_fastqs'. Target genome is 'GRCh38', expected cell count is 50000, using the 'WT' kit, filtering out barcodes with fewer than 500 UMIs and fewer than 200 genes.

**ASSISTANT:** Extracted parameters for `single_cell/parse_split_seq_scrna`:
- `fastq_dir`: "/data/parse_fastqs"
- `genome`: "GRCh38"
- `expected_cells`: 50000
- `kit`: "WT"
- `min_umis`: 500
- `min_genes`: 200

---

## [2180] source=multitask_sft_big

**USER:** In the r4rna_alignment_covariance_analysis workflow, is the 'fasta.txt' input required, and what format is expected?

**ASSISTANT:** The input `fasta.txt` is optional (`optional: true`). When provided, it expects a multiple sequence alignment in FASTA format.

---

## [2181] source=multitask_sft_big

**USER:** Please set up screclassify using my normalized data file 'pbmc_lognorm.rds' and cell labels vector stored as 'init_annotations'.

**ASSISTANT:** I have extracted the workflow parameters:
- `dat`: "pbmc_lognorm.rds" (SingleCellExperiment object containing log-normalized expression data)
- `cellTypes`: "init_annotations" (character vector of initial cell type annotations matching the columns of the SingleCellExperiment object)

---

## [2182] source=multitask_sft_big

**USER:** I want to generate a new Galaxy tool using toolfactory and plan to name the Toolshed repository 'My-RNAseq-Tool!'. Is that valid?

**ASSISTANT:** No, that name is invalid. The Toolshed repository name in toolfactory must contain only lowercase letters, digits, and underscores (to avoid namespace clashes with other tool developers). A valid version would be something like `my_rnaseq_tool`.

---

## [2183] source=multitask_sft_big

**USER:** What are the required input files for running the normr_predefined_regions workflow?

**ASSISTANT:** The workflow requires 'ChIP.bam', which must be a coordinate-sorted and indexed BAM file for the treatment/ChIP sample.

---

## [2184] source=multitask_sft_big

**USER:** I want to run FASTQ Read name affixer, but I need the header to retain characters across the first 2 spaces instead of cutting off at the very first space.

**ASSISTANT:** To keep characters across the spaces, set the space parameter to the positive integer `2`. The tool will incorporate those spaces into the sequence name and omit characters beyond them.

---

## [2185] source=multitask_sft_big

**USER:** I want to run LocARNA Multiple Aligner in local alignment mode. Are there any specific heuristic settings I need to adjust?

**ASSISTANT:** Yes. When running LocARNA Multiple Aligner in local alignment mode, you usually need to turn off the 'max-diff' heuristic (maximal difference for alignment traces).

---

## [2186] source=multitask_sft_big

**USER:** Please set up the orfhunter_orf_prediction_and_annotation workflow using my input file named 'my_transcripts.fasta'.

**ASSISTANT:** I have configured the `orfhunter_orf_prediction_and_annotation` workflow with your input:

```json
{
  "data_inputs": [
    {
      "name": "transcripts.fasta",
      "value": "my_transcripts.fasta"
    }
  ]
}
```

---

## [2187] source=multitask_sft_big

**USER:** I am configuring GATK4 Mutect2 in my pipeline, but my downstream parser only reads uncompressed text files. What should I do regarding the gzip setting?

**ASSISTANT:** You should leave the gzipped output box unchecked, as compressed output should not be used if your downstream tool lacks support for gzipped files.

---

## [2188] source=multitask_sft_big

**USER:** Set up the icnv_snp_array_only_cnv_detection pipeline with: lrr_values.rds, lrr_coords.txt, baf_values.rds, and baf_coords.txt.

**ASSISTANT:** The parameters for `icnv_snp_array_only_cnv_detection` have been extracted as follows:
- `snp_lrr`: lrr_values.rds (List of normalized LRR vectors)
- `snp_lrr.pos`: lrr_coords.txt (List of SNP positions)
- `snp_baf`: baf_values.rds (List of SNP BAF vectors)
- `snp_baf.pos`: baf_coords.txt (List of SNP BAF positions)

---

## [2189] source=multitask_sft_big

**USER:** What are the inputs and outputs of the genie3 workflow?

**ASSISTANT:** The input for the `genie3` workflow is `exprMatr` (a gene expression matrix with genes in rows and samples in columns). The outputs generated by the workflow are `expression_matrix` and `network_graph`.

---

## [2190] source=multitask_sft_big

**USER:** What community detection methods are available in netboxr, and which one is the default?

**ASSISTANT:** The community detection methods available in netboxr are: edge betweenness score (EBC), leading eigenvector method (LEC), Louvain method (LOUV), and Leiden method (LEID). The default method is EBC.

---

## [2191] source=multitask_sft_big

**USER:** Please set up Case Report Aggregation for sample 'PATIENT_101'. I want to set a CADD threshold of 20, max AF of 0.005, OUTRIDER padj of 0.05, and FRASER padj of 0.01.

**ASSISTANT:** Here are the extracted parameters for Case Report Aggregation:
- sample_id: "PATIENT_101"
- cadd_threshold: 20
- max_af: 0.005
- outrider_padj: 0.05
- fraser_padj: 0.01

---

## [2192] source=multitask_sft_big

**USER:** I am configuring the DefenseFinder data manager. I need versions 1.2.0, 1.3.0, and 2.1.0 to work with this model.

**ASSISTANT:** The extracted parameter for DefenseFinder is:
- Software versions: `1.2.0,1.3.0,2.1.0` (formatted as a comma-separated list).

---

## [2193] source=multitask_sft_big

**USER:** In the tool 'Annotates a text with bio-ontology terms', what parameter controls the depth of parent concepts considered during the semantic closure expansion step?

**ASSISTANT:** The parameter defines the maximum level a parent concept must have to be considered for the `is_a` semantic closure expansion step.

---

## [2194] source=multitask_sft_big

**USER:** I am analyzing TCR-seq data generated using a 5'RACE protocol with a template-switching oligo in MiXCR Analyze. Should I specify 'no-v-primers' or 'v-primers'?

**ASSISTANT:** You should use 'no-v-primers'. In MiXCR Analyze, 'no-v-primers' is designated for protocols without V gene primers, such as 5'RACE with a template switch oligo, whereas 'v-primers' is reserved for libraries using single or multiplex V gene-specific primers.

---

## [2195] source=multitask_sft_big

**USER:** Please convert my data file 'results.tsv' to standard CSV format. The file contains column headers in the first row.

**ASSISTANT:** Here are the extracted parameters for 'Tabular to CSV':
- Input file: results.tsv
- Target separator: CSV (comma)
- Has header line: Yes (true)

---

## [2196] source=multitask_sft_big

**USER:** I have my coding sequences in `seqs.fasta`, but I also have specific amino acid positions that I want to mutate. Does synmut support restricting mutations to certain regions?

**ASSISTANT:** Yes, `synmut` accepts an optional input file named `regions.csv`, which specifies the mutable amino acid positions. Along with your mandatory `seqs.fasta` file, this allows the workflow to preserve any regions outside the specified mutable positions.

---

## [2197] source=multitask_sft_big

**USER:** Here are my files for visualization: alignments are in sample_sorted.bam (with sample_sorted.bam.bai), variants are in snps.vcf.bgz, gene models are loaded via TxDb.Hsapiens.UCSC.hg38.knownGene, and the reference is BSgenome.Hsapiens.UCSC.hg38. Can you map them to the ggbio inputs?

**ASSISTANT:** The provided inputs map to the `ggbio` workflow as follows:
- `indexed_bam_file.bam`: sample_sorted.bam
- `variants_file.vcf.bgz`: snps.vcf.bgz
- `TxDb_or_OrganismDb_or_EnsDb_package`: TxDb.Hsapiens.UCSC.hg38.knownGene
- `BSgenome_package`: BSgenome.Hsapiens.UCSC.hg38

---

## [2198] source=multitask_sft_big

**USER:** What search parameters can be specified when using the GAP Get CFG cell web service?

**ASSISTANT:** Based on the CFG request specifications, the available parameters for 'GAP Get CFG cell' are:
- Species
- Participating Investigator
- Glycan type
- Cell type

---

## [2199] source=multitask_sft_big

**USER:** I want to run a longitudinal linear mixed-effects model in QIIME 2. I need to test how Shannon diversity changes over time across treatment groups ('Treatment' and 'Timepoint') while accounting for repeated measures on each 'SubjectID'. Which parameters should these map to in qiime2 longitudinal linear-mixed-effects?

**ASSISTANT:** In `qiime2 longitudinal linear-mixed-effects`, map your variables as follows:
- `metric`: The single dependent variable, which is Shannon diversity.
- `group_columns`: The exogenous covariates to evaluate and plot, here specified as 'Treatment' and 'Timepoint'.
- `random_effects`: The random effects variable accounting for repeated measures, which is 'SubjectID'.

---

## [2200] source=multitask_sft_big

**USER:** In Multi Compound Search, what flag must I supply to require a full match where the heavy atom count equals the SMARTS pattern atom count?

**ASSISTANT:** You should supply the `-f` flag, which enforces a full match by printing matching molecules only when the number of heavy atoms is also equal to the number of atoms in the SMARTS pattern.

---

## [2201] source=multitask_sft_big

**USER:** Please set up the metaseqr2_build_custom_annotation workflow using the nine-banded armadillo GTF file Dasypus_novemcinctus.Dasnov3.0.98.gtf.gz as the custom annotation source.

**ASSISTANT:** The parameter has been configured:
- `Dasypus_novemcinctus.Dasnov3.0.98.gtf.gz`: "Dasypus_novemcinctus.Dasnov3.0.98.gtf.gz" (GTF file of custom genome annotation).

---

## [2202] source=multitask_sft_big

**USER:** What mandatory input files are required to launch the qckitfastq workflow?

**ASSISTANT:** The qckitfastq workflow requires the mandatory input parameter `input_files` (type: data, optional: false).

---

## [2203] source=multitask_sft_big

**USER:** I am configuring flowviz_one_dimensional_density_plots. Here is my setup: data_inputs has GvHD pointing to 'GvHD_sample.rds'. Are there any other required parameters I need to provide?

**ASSISTANT:** The workflow parameters define 'GvHD' (an RDS file containing the flowSet object) as the required non-optional input. The parameter schema also lists 'input_files' as an available input parameter. Your input 'GvHD_sample.rds' satisfies the primary required flowSet input.

---

## [2204] source=multitask_sft_big

**USER:** What input peak data formats does chipenrich_diagnostic_qc_plots expect for the peaks_E2F4 input?

**ASSISTANT:** The parameter `peaks_E2F4` requires a table data type, specifically formatted as a data.frame or a path to a narrow peaks file.

---

## [2205] source=multitask_sft_big

**USER:** In the MALDIquant peak detection tool settings, what option should I select if the peaks have already been detected in my proteomics dataset?

**ASSISTANT:** You should choose 'Yes' to indicate that peak detection has already been done.

---

## [2206] source=multitask_sft_big

**USER:** What input data is required by pcamethods_robust_pca_outliers, and what formats are produced as output?

**ASSISTANT:** The workflow requires a mandatory input named 'metaboliteDataComplete' of type matrix (a complete matrix containing artificially introduced outliers). It produces outputs in three formats: 'table/csv', 'plot/pdf', and 'object/rds'.

---

## [2207] source=multitask_sft_big

**USER:** In my 16S amplicon workflow, I am configuring pick_rep_set to choose the representative sequence based on the longest read rather than the default first read. What parameter value should I set?

**ASSISTANT:** You should set the method parameter to `longest`. The valid choices for `pick_rep_set` are `random`, `longest`, `most_abundant`, and `first` (which is the default).

---

## [2208] source=multitask_sft_big

**USER:** I want to run `chipexoqual_subsampling_analysis` using my aligned reads stored at `experiment_rep1.bam`. Can you configure the input?

**ASSISTANT:** Certainly. For the `chipexoqual_subsampling_analysis` workflow, the file parameter is mapped as follows:
- `file.bam`: `experiment_rep1.bam` (aligned ChIP-exo/nexus reads).

---

## [2209] source=multitask_sft_big

**USER:** I want to run formulation screening on `CCC(=O)O...` for siRNA targeting hepatic tissue. What input parameters does the `lnp_formulation_optimization` workflow expect?

**ASSISTANT:** The workflow extracts the following key inputs:
- `ionizable_lipid_SMILES`: The chemical SMILES string of your ionizable lipid.
- `cargo_type`: The nucleic acid cargo (e.g., siRNA, mRNA, ASO, or DNA).
- `target_tissue`: The target tissue for delivery.

---

## [2210] source=multitask_sft_big

**USER:** Run Readseq on my alignment file `alignment.fasta` and save the results using the base prefix `species_phylip_out`.

**ASSISTANT:** Here are the extracted parameters for Readseq:
- Input file: `alignment.fasta`
- Output name: `species_phylip_out`

---

## [2211] source=multitask_sft_big

**USER:** I want to supply multiple query files listed in a text file to mash dist. Does it support this option?

**ASSISTANT:** Yes, 'mash dist' supports providing a file containing a list of query file names using the '-l' option.

---

## [2212] source=multitask_sft_big

**USER:** What input parameters are configured for providing the GTF annotation and BAM files in the `pram` workflow?

**ASSISTANT:** In the `pram` workflow parameters, the annotation file is passed via `in_gtf` (described as 'GTF file of existing gene annotations'), and the alignment BAM files are passed via `in_bamv`.

---

## [2213] source=multitask_sft_big

**USER:** What options are available for the `-m` workflow parameter in SeqSero2?

**ASSISTANT:** The `-m` parameter in `SeqSero2` specifies the workflow mode to apply:
- `'a'`: Raw reads allele micro-assembly (this is the default option).
- `'k'`: Raw reads and genome assembly k-mer based profiling.

---

## [2214] source=multitask_sft_big

**USER:** Prepare the workflow configuration for geva_quick_analysis using my RDS file located at `/data/inputs/study_gevainput.rds`.

**ASSISTANT:** Here is the parameter configuration for `geva_quick_analysis`:

```json
{
  "ginput": "/data/inputs/study_gevainput.rds"
}
```

This assigns your `GEVAInput` RDS object to the required, non-optional `ginput` parameter.

---

## [2215] source=multitask_sft_big

**USER:** Please set up the reference genome input for genomicdistributions_custom_reference_generation using my file: /refs/hg38/genome.fa.gz.

**ASSISTANT:** I have mapped your input parameter for genomicdistributions_custom_reference_generation:
- genome.fa.gz: "/refs/hg38/genome.fa.gz" (type: fasta)

---

## [2216] source=multitask_sft_big

**USER:** Please set up the imman workflow for human (taxid 9606) and mouse (taxid 10090). My human protein list is in `human_prots` and mouse list is in `mouse_prots`.

**ASSISTANT:** The inputs for the `imman` workflow are mapped as follows:
- `ProteinLists`: `[human_prots, mouse_prots]` (list of character vectors containing protein IDs for each species)
- `Species_IDs`: `[9606, 10090]` (numeric vector of NCBI taxonomy IDs)

This will generate the output `network_graph`.

---

## [2217] source=multitask_sft_big

**USER:** Here is my transcriptomics workflow configuration:
input_data: sample.ExpressionSet = GSE12345_eset.RData
I want to apply non-specific filtering on low-variance genes.
Extract the mandatory inputs and expected outputs for this run using the genefilter workflow.

**ASSISTANT:** Based on the genefilter workflow specification:
- Input: `sample.ExpressionSet` (ExpressionSet containing expression data and sample covariates, set to `GSE12345_eset.RData`).
- Outputs: `de_table` and `expression_matrix`.

---

## [2218] source=multitask_sft_big

**USER:** Run the gsalightning pipeline using my expression data located at './data/counts_matrix.csv', my sample labels at './data/clinical_groups.csv', and gene pathways from './ref/c2_curated.gmt'.

**ASSISTANT:** Extracted inputs for the `gsalightning` workflow:
- `expression_matrix.csv`: `./data/counts_matrix.csv`
- `sample_metadata.csv`: `./data/clinical_groups.csv`
- `gene_sets.gmt`: `./ref/c2_curated.gmt`

---

## [2219] source=multitask_sft_big

**USER:** I want to run the geneoverlap workflow. My target gene set is in 'tumor_genes.txt', my reference gene set is in 'pathway_signatures.txt', and our organism's background consists of 20500 total genes.

**ASSISTANT:** The extracted parameters for the `geneoverlap` workflow are:
- `list1.txt`: "tumor_genes.txt" (character vector of gene IDs for list A)
- `list2.txt`: "pathway_signatures.txt" (character vector of gene IDs for list B)
- `background_size`: 20500 (integer representing the total number of genes in the genomic background)

---

## [2220] source=multitask_sft_big

**USER:** I want FastME to determine nucleotide frequencies pairwise rather than globally across the whole alignment. How do I configure this?

**ASSISTANT:** In FastME, enable the checkbox for pairwise frequency estimation. This switches the frequency calculation from globally counting across the alignment to pairwise estimation by counting nucleotides or amino acids per sequence pair.

---

## [2221] source=multitask_sft_big

**USER:** I am querying a nucleotide sequence database using raptor search and want to bypass the probabilistic models by setting the score threshold to 0.65. Which parameter is being configured and is this valid?

**ASSISTANT:** In `raptor search`, you are configuring the search threshold parameter. Setting it to 0.65 is valid because the value must fall within the range [0,1]. When specified, this threshold is utilized instead of the default probabilistic models (default value is 0).

---

## [2222] source=multitask_sft_big

**USER:** I have prepared candidate gene Entrez ID 5214, a STRING interaction data frame `string_df`, a list of per-gene similarity matrices `sim_mats`, and a similarity score vector `gene_scores`. How should these be mapped to pcan_network_consensus, and what outputs will I get?

**ASSISTANT:** Your data maps to the `pcan_network_consensus` inputs as follows:
- `genId`: 5214
- `hqStrNw`: `string_df`
- `hpMatByGene`: `sim_mats`
- `resnSss`: `gene_scores`

The workflow will return two outputs:
1. `network_graph`
2. `consensus_score`

---

## [2223] source=multitask_sft_big

**USER:** Which parameter in CrossMap BAM scales the standard deviation threshold when determining if a mapped pair is proper?

**ASSISTANT:** The parameter is '-t', which multiplies the standard deviation from the mean to define the maximum distance threshold for proper pairs.

---

## [2224] source=multitask_sft_big

**USER:** What are the input slots defined for the Herper workflow, and what are their attributes?

**ASSISTANT:** The Herper workflow has a single declared data input slot named `count_data` (type: data). It is optional (`optional: true`) and is not read by the workflow (`read_by_workflow: false`).

---

## [2225] source=multitask_sft_big

**USER:** Does the seqArchRplus workflow define any data inputs in its pipeline specification?

**ASSISTANT:** Yes, seqArchRplus specifies an optional data input slot named 'count_data'.

---

## [2226] source=multitask_sft_big

**USER:** Please set up my nf-core/genomeskim run with input samplesheet at 'samples.csv', output directory './skim_results', custom reference fasta at 'data/ref.fasta', and set the MultiQC report title to 'Plant_Genome_Skim_QC'.

**ASSISTANT:** Here are the extracted parameters for nf-core/genomeskim:
- input: samples.csv
- outdir: ./skim_results
- fasta: data/ref.fasta
- multiqc_title: Plant_Genome_Skim_QC

---

## [2227] source=multitask_sft_big

**USER:** I want to run `lofreq filter` on my input VCF `tumor_raw.vcf` to exclude variants with coverage below 20x and a strand bias p-value threshold of 0.001. Can you extract the essential filtering criteria?

**ASSISTANT:** Based on your request, the parameters for `Lofreq Filter` are:
- Input file: `tumor_raw.vcf`
- Coverage cutoff: minimum depth of 20
- Strand bias threshold: p-value cutoff of 0.001 (variants with strand bias exceeding this significance are filtered out).

---

## [2228] source=multitask_sft_big

**USER:** I am running Phylodeep paramdeep on a viral phylogenetic tree containing 120 tips. Which model options are available for this tree size?

**ASSISTANT:** For trees between 50 and 199 tips, Phylodeep paramdeep allows you to select either BD (constant-rate birth-death with incomplete sampling) or BDEI (birth-death with exposed-infectious class).

---

## [2229] source=multitask_sft_big

**USER:** In Badread, how is the sequencing identity distribution specified, and what is its default setting?

**ASSISTANT:** In Badread, the sequencing identity distribution is defined by parameters for mean, max, and stdev (for a beta distribution) or mean and stdev (for a normal qscore distribution). Its default value is `95,99,2.5`.

---

## [2230] source=multitask_sft_big

**USER:** When configuring the 'Filter by quality' tool for Fastq manipulation, what does setting the parameter percent = 50 signify?

**ASSISTANT:** Setting percent = 50 specifies that the median quality score across the cycles in each read must be at least equal to your chosen quality cut-off value.

---

## [2231] source=multitask_sft_big

**USER:** I have individual-level mitochondrial coverage data. Can I supply this to the Diversity tool, and through what parameter or file format?

**ASSISTANT:** Yes, you can supply individual-level mitochondrial depth using the optional `gd_genotype` file, which records per-individual sequence coverage across each mitochondrial position for downstream diversity and variant analysis.

---

## [2232] source=multitask_sft_big

**USER:** I need to export two collections and a specific data file from iRODS: /zone/home/user/projectA, /zone/home/user/projectB, and /zone/home/user/summary.tsv. How should I format the 'iRODS path (source)' parameter?

**ASSISTANT:** In the export tool, you can specify multiple paths for 'iRODS path (source)' by separating each file or collection path with a pipe symbol (|). For your request, set the parameter to:

`/zone/home/user/projectA|/zone/home/user/projectB|/zone/home/user/summary.tsv`

---

## [2233] source=multitask_sft_big

**USER:** We need to set up OGS generateStructuredMesh for our simulation domain. What user-definable parameters does this tool accept?

**ASSISTANT:** OGS generateStructuredMesh allows users to define parameters including element type, dimensions, subdivisions, and other mesh creation settings to generate the structured mesh.

---

## [2234] source=multitask_sft_big

**USER:** Set up the inputs for the gars workflow using my normalized SummarizedExperiment file saved at 'data/norm_counts_se.rds'.

**ASSISTANT:** Here is the parameter configuration for the 'gars' workflow:

```json
{
  "datanorm": "data/norm_counts_se.rds"
}
```

This maps your normalized expression data directly to the required 'datanorm' input matrix parameter.

---

## [2235] source=multitask_sft_big

**USER:** In the 'Chado load Blast results' tool, what format or constraint must the query feature type parameter adhere to?

**ASSISTANT:** The query feature type parameter must be a valid Sequence Ontology term. Typical examples include 'gene', 'mRNA', 'polypeptide', or 'contig'.

---

## [2236] source=multitask_sft_big

**USER:** Configure kaiju2table to summarize Kaiju classification data for genus-level profiling in a comparative metagenomics experiment.

**ASSISTANT:** For `kaiju2table`, set the target taxonomic rank parameter to `genus`. Ensure your input consists of the raw Kaiju output file(s) containing taxon identifiers in the third column, alongside the reference taxonomy data for mapping.

---

## [2237] source=multitask_sft_big

**USER:** I have raw_array_data.txt ready with the Col and Row coordinates along with Log2 ratios. Please configure the inputs for the glad_array_spatial_visualization workflow.

**ASSISTANT:** The inputs for `glad_array_spatial_visualization` are configured as follows:
- `raw_array_data.txt`: Table format containing Col coordinates, Row coordinates, and Log2 ratios.

---

## [2238] source=multitask_sft_big

**USER:** What is the default scaling factor for estimating ensemble free energy in RNAfold, and what is the typical range of values?

**ASSISTANT:** The default value is 1.07, and useful values typically range from 1.0 to 1.2.

---

## [2239] source=multitask_sft_big

**USER:** Does FROGS Affiliation OTU enable the RDP classifier by default when performing taxonomy assignment?

**ASSISTANT:** No, taxonomy affiliation is performed by default using Blast. Running the RDP classifier alongside Blast is optional and defaults to 'No'.

---

## [2240] source=multitask_sft_big

**USER:** I want to run Annotate to mark branches. Can I provide a regex pattern to pick leaves, or do I have to provide an exact sequence list?

**ASSISTANT:** The `Annotate` tool supports both methods: you can either supply a regular expression to match leaf names or provide an explicit list of sequence names to select the branches you wish to label.

---

## [2241] source=multitask_sft_big

**USER:** I want to score my CCLE cohort. I have my expression matrix stored in 'CCLE.mito', the bicluster high-correlation gene set in 'CCLE.hicor.genes', and the bifurcation group classifications in 'CCLE.groups'. Can you extract the data inputs for `mcbiclust_scoring_independent_samples`?

**ASSISTANT:** Here are the extracted data input parameters for the `mcbiclust_scoring_independent_samples` workflow:

- `CCLE.mito`: 'CCLE.mito' (gene expression matrix to score)
- `CCLE.hicor.genes`: 'CCLE.hicor.genes' (highly correlated bicluster genes)
- `CCLE.groups`: 'CCLE.groups' (differently regulated gene groups)

---

## [2242] source=multitask_sft_big

**USER:** I want to run `msquality` on three mzML files: 'run1.mzML', 'run2.mzML', and 'run3.mzML', using 'meta.csv' for metadata. How should these inputs be mapped to the workflow parameters?

**ASSISTANT:** The workflow inputs should be mapped as follows:
- `fls`: `["run1.mzML", "run2.mzML", "run3.mzML"]` (character vector of paths to mzML files)
- `sample_metadata.csv`: `"meta.csv"` (sample annotation table)

---

## [2243] source=multitask_sft_big

**USER:** What software tool does the icare workflow invoke, and what are its expected outputs?

**ASSISTANT:** The icare workflow executes `bioconductor/icare` and outputs risk visualizations.

---

## [2244] source=multitask_sft_big

**USER:** Please set up the dino_custom_depth_normalization run. My raw count matrix is stored in 'pbmc_raw_counts.tsv'.

**ASSISTANT:** I have extracted the following parameter for `dino_custom_depth_normalization`:
- `pbmcSmall`: 'pbmc_raw_counts.tsv' (matrix of raw UMI counts)

---

## [2245] source=multitask_sft_big

**USER:** What are the output formats generated by the `dmrcaller_bisulfite_seq_replicates_analysis` pipeline?

**ASSISTANT:** The workflow produces outputs in table/csv, plot/pdf, and object/rds formats.

---

## [2246] source=multitask_sft_big

**USER:** Could you provide an example of a valid Method ID for describing a peak calling method in RBPBench?

**ASSISTANT:** An example of a Method ID used to describe a peak calling method in RBPBench is `clipper_idr`.

---

## [2247] source=multitask_sft_big

**USER:** I have prepared my inputs for planet_gestational_age_prediction: the methylation matrix is at 'placenta_betas.rds' and metadata is 'samples_meta.csv'. Could you set up the inputs for the run and confirm what outputs to expect?

**ASSISTANT:** The parameters and data inputs are extracted as follows:
- DNAm_betas.rds: 'placenta_betas.rds' (matrix of beta values, CpGs as rows and samples as columns)
- sample_metadata.csv: 'samples_meta.csv' (sample information data frame)

Upon execution, the workflow will generate outputs in table/csv, plot/pdf, and object/rds formats.

---

## [2248] source=multitask_sft_big

**USER:** Set up the inputs for xeva_create_xeva_object using my files: model table at 'pdx_models.csv' and drug table at 'tested_drugs.csv'.

**ASSISTANT:** Here are the mapped inputs for `xeva_create_xeva_object`:
- `model.csv`: "pdx_models.csv"
- `drug.csv`: "tested_drugs.csv"

---

## [2249] source=multitask_sft_big

**USER:** I need to download two items from iRODS using 'iBridges download from iRODS': the dataobject '/zone/home/data/sample1.fastq' and the collection '/zone/home/data/run2'. How should I set the 'iRODS path (source)' parameter?

**ASSISTANT:** Set 'iRODS path (source)' to:
`/zone/home/data/sample1.fastq|/zone/home/data/run2`
Multiple file (dataobject) and folder (collection) paths must be separated by pipes (|).

---

## [2250] source=multitask_sft_big

**USER:** Please set up the virtual patient cohort run for DrugX at 250 mg. Clearance is 5.5 L/h, volume of distribution is 45 L, bioavailability is 0.85, absorption rate ka is 1.2 per hour. We want to test 500 patients, with IIV on clearance at 0.25 CV and IIV on Vd at 0.30 CV. Mean body weight is 72 kg (SD 12 kg), and mean age is 55.

**ASSISTANT:** Here are the extracted parameters mapped to `virtual_cell/virtual_patient_cohort`:
- `drug_name`: "DrugX"
- `dose_mg`: 250
- `cl_L_h`: 5.5
- `vd_L`: 45
- `bioavailability`: 0.85
- `ka_per_h`: 1.2
- `n_patients`: 500
- `iiv_cl_cv`: 0.25
- `iiv_vd_cv`: 0.30
- `covariate_bwt_mean`: 72
- `covariate_bwt_sd`: 12
- `covariate_age_mean`: 55

---

## [2251] source=multitask_sft_big

**USER:** I want to run edger_fold_change_threshold_testing. I have stored my DGEList object in 'dgelist_data.rds' and the raw inputs in 'raw_counts.tsv'. Please set up the inputs.

**ASSISTANT:** I have extracted the following parameters for the `edger_fold_change_threshold_testing` workflow:
- `y`: "dgelist_data.rds" (RDS file containing the DGEList object)
- `input_files`: "raw_counts.tsv"

---

## [2252] source=multitask_sft_big

**USER:** Here is what I have prepared for the MassBank generation step:
- R workspace: /data/runs/processed_workspace.RData
- Incomplete infolists: /data/metadata/infolists_incomplete
- Compound annotation file: /data/metadata/Narcotics_infolist.csv

Please extract the necessary input parameters for the workflow.

**ASSISTANT:** Based on your provided paths, here are the extracted parameters for `rmassbank_massbank_record_generation`:

- `w`: `/data/runs/processed_workspace.RData` (Processed MS/MS workspace object)
- `infolists_incomplete`: `/data/metadata/infolists_incomplete` (Directory containing incomplete CSV infolists)
- `Narcotics_infolist.csv`: `/data/metadata/Narcotics_infolist.csv` (CSV file to write and edit compound annotations)

---

## [2253] source=multitask_sft_big

**USER:** What metadata and file parameters can be specified when using the ENA Webin CLI (Data Export) tool?

**ASSISTANT:** The parameters include:
- Free text description of the genome assembly (optional)
- Center name
- Consensus sequence assembly file
- Sequences in AGP format
- Chromosome List File (required when submitting assembled chromosomes)
- Submit to ENA test server

---

## [2254] source=multitask_sft_big

**USER:** I have my count data ready at '/data/hichip_counts.tsv'. How does that map to the HiCDCPlus inputs?

**ASSISTANT:** For the `HiCDCPlus` workflow, your file should be mapped to the required data input:
- `input_files`: '/data/hichip_counts.tsv' (count_data input slot for the pipeline).

---

## [2255] source=multitask_sft_big

**USER:** I am preparing my single-end FASTQ data for the rfastp_custom_trimming_and_filtering workflow. Which input parameter corresponds to the single-end file?

**ASSISTANT:** You should supply your file to the 'se_read1' parameter, which accepts a single-end FASTQ file (type: data, optional: true). General FASTQ files can also be passed via 'input_files'.

---

## [2256] source=multitask_sft_big

**USER:** I'm setting up 'Random Intervals' and selected a mask file, but now I've decided I do not want to mask any intervals. How do I disable masking without removing the file?

**ASSISTANT:** Change the 'Use Mask' option to 'No'. Setting 'Use Mask' to 'No' will override any mask files that have been selected.

---

## [2257] source=multitask_sft_big

**USER:** What tools are executed by the filterffpe workflow, and what output formats does it generate?

**ASSISTANT:** The filterffpe workflow utilizes the 'bioconductor/filterffpe' tool and outputs results in three formats: 'table/csv', 'plot/pdf', and 'object/rds'.

---

## [2258] source=multitask_sft_big

**USER:** I am formatting parameters for csvtk-gather and need to target the first two columns of my file. How should they be specified?

**ASSISTANT:** You can specify columns separated by a comma. To target the first two columns, provide the column numbers as '1,2'.

---

## [2259] source=multitask_sft_big

**USER:** How does `qiime2 quality-control filter-reads` execute sequence alignment internally, and what sequence inputs does it take?

**ASSISTANT:** Internally, `qiime2 quality-control filter-reads` uses `bowtie2` and `samtools` to align reads against a reference database. It accepts demultiplexed single-end or paired-end FASTQ sequences across metagenomics, amplicon sequencing, and shotgun metagenomics datasets.

---

## [2260] source=multitask_sft_big

**USER:** Please configure Propr Logratio to transform my abundance matrix using centered logratio transformation.

**ASSISTANT:** I will set the transformation method in Propr Logratio to centered logratio transformation (CLR) for your data matrix.

---

## [2261] source=multitask_sft_big

**USER:** What compute tier and BiocParallel worker settings are defined for the scrnaseq_trajectory_pseudotime workflow?

**ASSISTANT:** The workflow is locked to the T2 CPU tier with 16 vCPUs and 64 GB of RAM, running with BiocParallel `workers=4` (per tradeSeq #245).

---

## [2262] source=multitask_sft_big

**USER:** What outputs are produced by the glad_daglad_analysis workflow once it completes?

**ASSISTANT:** The glad_daglad_analysis workflow outputs 'copy_number_segments' and 'visualizations'.

---

## [2263] source=multitask_sft_big

**USER:** I want to submit compounds for CNS penetration prediction. Here are the values: SMILES string 'CC(=O)NC1=CC=C(O)C=C1', pKa of 9.5, logD at pH 7.4 is 0.46, plasma unbound fraction is 0.8, and we also want to predict efflux ratio. Please extract these parameters.

**ASSISTANT:** Here are the extracted parameters for the **Cns Penetration Prediction** workflow:
- `smiles_list`: ["CC(=O)NC1=CC=C(O)C=C1"]
- `pKa`: 9.5
- `logD74`: 0.46
- `fu_plasma`: 0.8
- `predict_efflux_ratio`: true

---

## [2264] source=multitask_sft_big

**USER:** I need to extract a subnetwork between my metabolites and export the graph specifically in JsonGraph format rather than an edge list.

**ASSISTANT:** For `ExtractSubNetwork`, the export format parameter should be set to `JsonGraph` (overriding the default tabulated edge list format).

---

## [2265] source=multitask_sft_big

**USER:** What input parameters are accepted by the `r453plus1toolbox_sff_manipulation_qc` workflow according to its configuration?

**ASSISTANT:** The workflow accepts `data_inputs` including `file` (a binary SFF file, marked as optional) and `input_files` (data type, optional).

---

## [2266] source=multitask_sft_big

**USER:** What are the declared data inputs and parameter requirements for running the CoreGx workflow?

**ASSISTANT:** The CoreGx workflow takes `count_data` as an input channel, requiring a non-optional data input named `input_files` (`optional: false`, `read_by_workflow: true`). It defines no additional parameters in its parameter list.

---

## [2267] source=multitask_sft_big

**USER:** Please set up a PBPK simulation for our lead small molecule: SMILES is CC(=O)Nc1ccc(O)cc1, drug_class is small_molecule, MW 151.16, logP 0.46, fu_plasma 0.8. We want to simulate oral administration of 10 mg/kg for 24 hours in rat (body weight 0.25 kg).

**ASSISTANT:** I have extracted the following parameters for the `Pbpk Peripheral Nerve` workflow:

- `SMILES`: "CC(=O)Nc1ccc(O)cc1"
- `drug_class`: "small_molecule"
- `MW`: 151.16
- `logP`: 0.46
- `fu_plasma`: 0.8
- `dose_mg_kg`: 10.0
- `dose_route`: "oral"
- `simulation_hours`: 24
- `body_weight_kg`: 0.25
- `simulation_species`: "rat"

Note that peripheral nerve-specific physiological parameters (such as `bnb_Papp_cm_s`, `bnb_efflux_ratio`, `v_peripheral_nerve_fBW`, `v_spinal_cord_fBW`, and `q_peripheral_nerve_fCO`) remain to be specified or set to baseline defaults.

---

## [2268] source=multitask_sft_big

**USER:** Please set up bionemo_structure_design to execute de novo molecule generation.

**ASSISTANT:** Parameter extracted for `bionemo_structure_design`:
- `mode`: "molecule_gen"

This configures the workflow to run de novo molecule generation using GenMol, MolMIM, and MoFlow.

---

## [2269] source=multitask_sft_big

**USER:** What output is generated by the signer_exposure_estimation_to_known_signatures workflow, and what tools are configured for it?

**ASSISTANT:** The workflow outputs `mutational_signatures` (representing the estimated exposures), and it has no external tools configured (`tools: None`).

---

## [2270] source=multitask_sft_big

**USER:** Run CalculateEnergy on structure.pdb using the CHARMM force field with a non-bonded cutoff of 12.0 angstroms and an electrostatic cut-on of 8.0 angstroms.

**ASSISTANT:** Extracted parameters for `CalculateEnergy`:
- Input file: `structure.pdb`
- `-force_field`: `CHARMM`
- `-non_bond_cutoff`: `12.0`
- `-elec_stat_cuton`: `8.0`

---

## [2271] source=multitask_sft_big

**USER:** We are preparing BLAST taxonomic filtering inputs for our metagenome run. We want to expand taxid 10239 (Viruses) and taxid 2 (Bacteria) into species-level IDs. What are the primary input criteria and output expectations for running COAST taxonomic filter generator?

**ASSISTANT:** For COAST taxonomic filter generator, the input criteria are the high-order taxonomy IDs (such as taxid 10239 for Viruses or taxid 2 for Bacteria, or lower-ranked taxid nodes). The tool processes these taxonomy nodes and generates a text file containing the corresponding list of species-level taxids, which can be directly passed to BLAST via its taxid list filtering option.

---

## [2272] source=multitask_sft_big

**USER:** What input data parameter is required by the flowmatch_template_construction_and_metaclustering workflow, and is it optional?

**ASSISTANT:** The workflow requires the input parameter `sample_list.rds`. It is non-optional (`optional: false`) and must be an RDS file containing a list of expression matrices for multiple flow cytometry samples.

---

