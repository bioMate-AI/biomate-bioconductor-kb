#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MPRAnalyze — quantification_analysis
// Estimate transcription rates for each enhancer and test for activity against negative controls.
// Input: dna_counts.tsv, rna_counts.tsv, col_annotations.tsv, controls.txt
// Container: quay.io/biocontainers/bioconductor-mpranalyze:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MPRAnalyze
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read user input files from the working directory
//  * 2. [Core Analysis] Initialize the MpraObject with count matrices,
//  * 3. [Core Analysis] Estimate library depth normalization factors
//  * 4. [Core Analysis] Fit the quantification model using DNA and RNA design
//  * 5. [Core Analysis] Extract transcription rate estimates (alpha values)
//  * 6. [Core Analysis] Test for enhancer activity against negative controls
//  * 7. [Core Analysis] Write named output files for the results

nextflow.enable.dsl = 2

process BIOC_MPRANALYZE_QUANTIFICATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("MPRAnalyze")
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
        
    # Load required library
    library(MPRAnalyze)
    
    # --- Read user input files from the working directory ---
    dna_counts <- as.matrix(read.delim("dna_counts.tsv", header = TRUE, row.names = 1))
    rna_counts <- as.matrix(read.delim("rna_counts.tsv", header = TRUE, row.names = 1))
    col_annot <- read.delim("col_annotations.tsv", header = TRUE, row.names = 1)
    controls <- as.logical(readLines("controls.txt"))
    
    # Extract annotation columns dynamically to avoid hardcoding specific column names
    annot_cols <- colnames(col_annot)
    cond_col <- annot_cols[length(annot_cols)] # Assume the last column is the condition of interest
    
    # --- Initialize the MpraObject with count matrices, ---
    obj <- MpraObject(dnaCounts = dna_counts, rnaCounts = rna_counts, 
                      dnaAnnot = col_annot, rnaAnnot = col_annot, 
                      controls = controls)
    
    # --- Estimate library depth normalization factors ---
    obj <- estimateDepthFactors(obj, lib.factor = annot_cols,
                                which.lib = "both")
    
    # --- Fit the quantification model using DNA and RNA design ---
    dna_design <- as.formula(paste("~", paste(annot_cols, collapse = " + ")))
    rna_design <- as.formula(paste("~", cond_col))
    
    obj <- analyzeQuantification(obj = obj, 
                                  dnaDesign = dna_design,
                                  rnaDesign = rna_design)
    
    # --- Extract transcription rate estimates (alpha values) ---
    alpha <- getAlpha(obj, by.factor = cond_col)
    
    # --- Test for enhancer activity against negative controls ---
    # Use the first condition level dynamically instead of hardcoding 'MT'
    res.epi <- testEmpirical(obj = obj, 
                                   statistic = alpha[[1]])
    
    # --- Write named output files for the results ---
    # Save the fitted MPRAnalyze object
    saveRDS(obj, file = "mpra_object_quantification.rds")
    
    # Save the transcription rate estimates and empirical test results as CSV tables
    write.csv(alpha, file = "alpha_estimates.csv", row.names = TRUE)
    write.csv(res.epi, file = "empirical_test_results_epi.csv", row.names = TRUE)
    
    # Generate and save diagnostic plots to a PDF
    pdf("quantification_analysis_plots.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    
    # Plot 1: Boxplot of alpha estimates across conditions
    boxplot(alpha, main = "Transcription Rate (Alpha) Estimates", 
            xlab = "Condition", ylab = "Alpha Value", col = c("lightblue", "lightgreen"))
    
    # Plot 2: Histogram of empirical p-values (MAD-score based if available, otherwise empirical)
    if ("pval.mad" %in% colnames(res.epi)) {
      hist(res.epi\$pval.mad, main = "Distribution of pval.mad", 
           xlab = "p-value", col = "lavender", border = "darkgray")
    } else {
      hist(res.epi\$pval.empirical, main = "Distribution of Empirical p-values", 
           xlab = "p-value", col = "lavender", border = "darkgray")
    }
    
    dev.off()

    writeLines(c(
        '"BIOC_MPRANALYZE_QUANTIFICATION_ANALYSIS":',
        paste0('    MPRAnalyze: ', as.character(packageVersion('MPRAnalyze')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quantification_analysis.csv versions.yml
    """
}

workflow BIOC_MPRANALYZE_QUANTIFICATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dna_counts.tsv, rna_counts.tsv, col_annotations.tsv, controls.txt ] ]

    main:
    BIOC_MPRANALYZE_QUANTIFICATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MPRANALYZE_QUANTIFICATION_ANALYSIS.out.tables
    plots    = BIOC_MPRANALYZE_QUANTIFICATION_ANALYSIS.out.plots
    objects  = BIOC_MPRANALYZE_QUANTIFICATION_ANALYSIS.out.objects
    versions = BIOC_MPRANALYZE_QUANTIFICATION_ANALYSIS.out.versions
}
