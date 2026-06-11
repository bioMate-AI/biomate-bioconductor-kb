#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DEGreport — qc_and_covariate_analysis
// Perform quality control on normalized counts, check size factors, evaluate mean-variance relationships, and analyze covariate effects and correlations.
// Input: counts_matrix.tsv, metadata.csv
// Container: quay.io/biocontainers/bioconductor-degreport:1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DEGreport, DESeq2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Check size factors using degCheckFactors
//  * 2. [Core Analysis] Run comprehensive QC (p-value distribution,
//  * 3. [Core Analysis] Analyze covariate effects on principal components using
//  * 4. [Core Analysis] Test correlation among covariates and metrics using

nextflow.enable.dsl = 2

process BIOC_DEGREPORT_QC_AND_COVARIATE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("DESeq2", "DEGreport")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
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
    library(DESeq2)
    library(DEGreport)
    
    # Read user input files from the working directory
    counts_data <- read.table("counts_matrix.tsv", header = TRUE, sep = "\t", row.names = 1, check.names = FALSE)
    metadata <- read.csv("metadata.csv", row.names = 1, check.names = FALSE)
    
    # Align counts and metadata
    common_samples <- intersect(colnames(counts_data), rownames(metadata))
    if (length(common_samples) == 0) {
      stop("Error: No common samples found between counts_matrix.tsv and metadata.csv")
    }
    counts_data <- counts_data[, common_samples, drop = FALSE]
    metadata <- metadata[common_samples, , drop = FALSE]
    
    # Ensure 'group' column exists in metadata (fallback to first column if missing)
    if (!"group" %in% colnames(metadata)) {
      metadata\$group <- as.factor(metadata[[1]])
    } else {
      metadata\$group <- as.factor(metadata\$group)
    }
    
    # Convert counts to integer for DESeq2 processing
    count_matrix_int <- round(as.matrix(counts_data))
    
    # Create DESeqDataSet and run DESeq2 pipeline
    dds <- DESeqDataSetFromMatrix(countData = count_matrix_int,
                                  colData = metadata,
                                  design = ~ group)
    dds <- DESeq(dds)
    res <- results(dds)
    
    # Extract normalized counts and design data frame
    counts <- counts(dds, normalized = TRUE)
    design <- as.data.frame(colData(dds))
    
    # --- Check size factors using degCheckFactors ---
    pdf("deg_check_factors.pdf", width = 8, height = 6)
    print(degCheckFactors(counts[, 1:min(6, ncol(counts)), drop = FALSE]))
    dev.off()
    
    # --- Run comprehensive QC (p-value distribution, ---
    pdf("deg_qc.pdf", width = 10, height = 8)
    print(degQC(counts, design[["group"]], pvalue = res[["pvalue"]]))
    dev.off()
    
    # --- Analyze covariate effects on principal components using ---
    pdf("deg_covariates.pdf", width = 10, height = 8)
    resCov <- degCovariates(log2(counts(dds)+0.5),
                            colData(dds))
    print(resCov\$plot)
    dev.off()
    saveRDS(resCov, "resCov.rds")
    
    # --- Test correlation among covariates and metrics using ---
    pdf("deg_cor_cov.pdf", width = 8, height = 8)
    cor <- degCorCov(colData(dds))
    print(cor\$plot)
    dev.off()
    saveRDS(cor, "cor_results.rds")
    
    # Print the names of the correlation list object
    print(names(cor))

    writeLines(c(
        '"BIOC_DEGREPORT_QC_AND_COVARIATE_ANALYSIS":',
        paste0('    DEGreport: ', as.character(packageVersion('DEGreport')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qc_and_covariate_analysis.csv versions.yml
    """
}

workflow BIOC_DEGREPORT_QC_AND_COVARIATE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_matrix.tsv, metadata.csv ] ]

    main:
    BIOC_DEGREPORT_QC_AND_COVARIATE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DEGREPORT_QC_AND_COVARIATE_ANALYSIS.out.tables
    plots    = BIOC_DEGREPORT_QC_AND_COVARIATE_ANALYSIS.out.plots
    objects  = BIOC_DEGREPORT_QC_AND_COVARIATE_ANALYSIS.out.objects
    versions = BIOC_DEGREPORT_QC_AND_COVARIATE_ANALYSIS.out.versions
}
