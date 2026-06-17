#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methrix — methrix_methylation_analysis
// Import raw bedgraph files, perform quality control, filter out low-quality sites and SNPs, subset genomic regions, and visualize methylation and coverage profil
// Input: bdg_files, sample_anno, BSgenome.Hsapiens.UCSC.hg19
// Container: quay.io/biocontainers/bioconductor-methrix:1.24.0--r45hdfd78af_0
// R packages: BSgenome.Hsapiens.UCSC.hg19, GenomicRanges, MafDb.1Kgenomes.phase3.hs37d5, bsseq, GenomicScores, methrix
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg19, GenomicRanges, GenomicScores, MafDb.1Kgenomes.phase3.hs37d5, bsseq, methrix
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract reference CpG sites using extract_CPGs
//  * 2. [Input & Preparation] Read bedgraph files and create a methrix object using read_bedgraphs
//  * 3. [Visualization & Output] Generate an interactive HTML QC report using methrix_report
//  * 4. [Core Analysis] Filter out uncovered loci using remove_uncovered
//  * 5. [Core Analysis] Filter out SNPs using remove_snps
//  * 6. [Core Analysis] Extract coverage and methylation matrices using get_matrix
//  * 7. [Core Analysis] Filter sites based on coverage thresholds using coverage_filter
//  * 8. [Core Analysis] Subset the dataset by contigs, regions, or samples using subset_methrix
//  * 9. [Visualization & Output] Calculate summary statistics using get_stats and plot them using plot_stats
//  * 10. [Visualization & Output] Perform PCA and plot results using methrix_pca and plot_pca
//  * 11. [Visualization & Output] Visualize data using plot_violin and plot_coverage
//  * 12. [Core Analysis] Convert the methrix object to a BSseq object using methrix2bsseq

nextflow.enable.dsl = 2

process BIOC_METHRIX_METHRIX_METHYLATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "GenomicRanges", "MafDb.1Kgenomes.phase3.hs37d5", "bsseq", "GenomicScores", "methrix")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load required libraries
        library(methrix)
        library(BSgenome.Hsapiens.UCSC.hg19)
        library(MafDb.1Kgenomes.phase3.hs37d5)
        library(GenomicScores)
        library(bsseq)
        library(GenomicRanges)
        
        # ==========================================
        # 1. USER INPUT & DATA SETUP
        # ==========================================
        
        # Read bedGraph.gz files from the working directory
        if (!exists("bdg_files")) {
          bdg_files <- list.files(path = ".", pattern = "\\\\.bedGraph\\\\.gz\$", full.names = TRUE)
          if (length(bdg_files) == 0) {
            bdg_files <- list.files(path = ".", pattern = "\\\\.bedGraph\$", full.names = TRUE)
          }
        }
        
        if (length(bdg_files) == 0) {
          stop("Error: No bedGraph or bedGraph.gz files found in the working directory.")
        }
        
        # Read or construct sample annotation data.frame
        if (!exists("sample_anno")) {
          if (file.exists("sample_anno.csv")) {
            sample_anno <- read.csv("sample_anno.csv", row.names = 1, stringsAsFactors = FALSE)
          } else if (file.exists("sample_anno.tsv")) {
            sample_anno <- read.delim("sample_anno.tsv", row.names = 1, stringsAsFactors = FALSE)
          } else {
            warning("sample_anno.csv/tsv not found. Constructing sample_anno from bedgraph filenames.")
            sample_names <- gsub("\\\\.bedGraph(\\\\.gz)?\$", "", basename(bdg_files))
            sample_anno <- data.frame(
              row.names = sample_names,
              Condition = rep(c("cancer", "normal"), length.out = length(sample_names)),
              Pair = paste0("pair", rep(1:ceiling(length(sample_names)/2), each = 2)[1:length(sample_names)]),
              stringsAsFactors = FALSE
            )
          }
        }
        
        # ==========================================
        # 2. METHYLATION ANALYSIS PIPELINE
        # ==========================================
        
        # Step 1: Extract reference CpG sites
        hg19_cpgs <- suppressWarnings(methrix::extract_CPGs(ref_genome = "BSgenome.Hsapiens.UCSC.hg19"))
        
        # Step 2: Read bedgraph files and create a methrix object
        meth <- methrix::read_bedgraphs(
          files = bdg_files,
          ref_cpgs = hg19_cpgs,
          chr_idx = 1,
          start_idx = 2,
          M_idx = 3,
          U_idx = 4,
          stranded = FALSE,
          zero_based = FALSE, 
          collapse_strands = FALSE, 
          coldata = sample_anno
        )
        
        # Step 3: Generate interactive HTML QC report
        methrix::methrix_report(meth = meth, output_dir = ".")
        
        # Step 4: Filter out uncovered loci
        meth = methrix::remove_uncovered(m = meth)
        
        # Step 5: Filter out SNPs
        meth_snps_filtered <- methrix::remove_snps(m = meth)
        
        # Assign the filtered object to methrix_data to replace the vignette's bundled dataset
        methrix_data <- meth_snps_filtered
        
        # Step 6: Extract coverage and methylation matrices
        coverage_mat <- methrix::get_matrix(m = methrix_data, type = "C")
        meth_mat <- methrix::get_matrix(m = methrix_data, type = "M")
        meth_mat_with_loci <- methrix::get_matrix(m = methrix_data, type = "M", add_loci = TRUE, in_granges = TRUE)
        
        # Step 7: Filter sites based on coverage thresholds
        meth_cov_filtered <- methrix::coverage_filter(m = methrix_data, cov_thr = 3, min_samples = 2)
        
        # Step 8: Subset operations
        # Subset by chromosome
        meth_chr21 <- methrix::subset_methrix(m = methrix_data, contigs = "chr21")
        
        # Subset by genomic regions
        target_loci <- GenomicRanges::GRanges("chr21:27867971-27868103")
        meth_region <- methrix::subset_methrix(m = methrix_data, regions = target_loci)
        
        # Subset by samples (with fallback in case "C1" is not in the user's dataset)
        meth_sample <- tryCatch({
          methrix::subset_methrix(m = methrix_data, samples = "C1")
        }, error = function(e) {
          message("Warning: Sample 'C1' not found. Subsetting by the first available sample instead.")
          methrix::subset_methrix(m = methrix_data, samples = colnames(methrix_data)[1])
        })
        
        # Index subsetting
        meth_idx <- methrix_data[, 1]
        
        # Step 9: Calculate summary statistics
        meth_stats <- get_stats(m = methrix_data)
        
        # Step 10 & 11: Perform PCA and Visualizations (Saved to PDF)
        pdf("methrix_visualization_plots.pdf", width = 10, height = 8)
        
        # Draw mean coverage per sample
        tryCatch({
          print(plot_stats(plot_dat = meth_stats, what = "C", stat = "mean"))
        }, error = function(e) {
          message("Error plotting coverage stats: ", e\$message)
        })
        
        # Draw mean methylation per sample
        tryCatch({
          print(plot_stats(plot_dat = meth_stats, what = "M", stat = "mean"))
        }, error = function(e) {
          message("Error plotting methylation stats: ", e\$message)
        })
        
        # PCA
        mpca <- methrix_pca(m = methrix_data, do_plot = FALSE)
        tryCatch({
          print(plot_pca(pca_res = mpca, show_labels = TRUE))
        }, error = function(e) {
          message("Error plotting PCA: ", e\$message)
        })
        
        # Color code PCA by annotation
        tryCatch({
          print(plot_pca(pca_res = mpca, m = methrix_data, col_anno = "Condition"))
        }, error = function(e) {
          message("Warning: Could not plot PCA with col_anno = 'Condition'. trying first available column.")
          if (ncol(sample_anno) > 0) {
            print(plot_pca(pca_res = mpca, m = methrix_data, col_anno = colnames(sample_anno)[1]))
          }
        })
        
        # Violin plots
        tryCatch({
          print(methrix::plot_violin(m = methrix_data))
        }, error = function(e) {
          message("Error plotting violin: ", e\$message)
        })
        
        # Coverage density plots
        tryCatch({
          print(methrix::plot_coverage(m = methrix_data, type = "dens"))
        }, error = function(e) {
          message("Error plotting coverage density: ", e\$message)
        })
        
        dev.off()
        
        # Step 12: Convert the methrix object to a BSseq object
        bs_seq <- methrix::methrix2bsseq(m = methrix_data)
        
        # ==========================================
        # 3. EXPORT OUTPUTS
        # ==========================================
        write.csv(as.matrix(coverage_mat), "coverage_matrix.csv", row.names = TRUE)
        write.csv(as.matrix(meth_mat), "methylation_matrix.csv", row.names = TRUE)
        write.csv(as.data.frame(meth_stats), "meth_stats.csv", row.names = FALSE)
        
        saveRDS(meth_mat_with_loci, "meth_mat_with_loci.rds")
        saveRDS(methrix_data, "methrix_data_filtered.rds")
        saveRDS(meth_cov_filtered, "meth_cov_filtered.rds")
        saveRDS(bs_seq, "bsseq_object.rds")
        
        message("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_METHRIX_METHRIX_METHYLATION_ANALYSIS":',
        paste0('    methrix: ', as.character(packageVersion('methrix')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methrix_methylation_analysis.csv versions.yml
    """
}

workflow BIOC_METHRIX_METHRIX_METHYLATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bdg_files, sample_anno, BSgenome.Hsapiens.UCSC.hg19 ] ]

    main:
    BIOC_METHRIX_METHRIX_METHYLATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METHRIX_METHRIX_METHYLATION_ANALYSIS.out.tables
    plots    = BIOC_METHRIX_METHRIX_METHYLATION_ANALYSIS.out.plots
    objects  = BIOC_METHRIX_METHRIX_METHYLATION_ANALYSIS.out.objects
    versions = BIOC_METHRIX_METHRIX_METHYLATION_ANALYSIS.out.versions
}
