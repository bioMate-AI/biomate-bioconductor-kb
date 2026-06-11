#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: affyPLM — flexible_threestep_preprocessing
// Preprocess AffyBatch microarray data using a flexible three-step framework (custom background correction, normalization, and summarization).
// Input: Dilution
// Container: quay.io/biocontainers/bioconductor-affyplm:1.86.0--r45h01b2380_0
// R packages: affyPLM
// Bioconductor: 3.20 | R: 4.4
// Requires: affyPLM
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load package and update the AffyBatch object
//  * 2. [Visualization & Output] Run the threestep function with default or customized background, normalization, and summarization methods

nextflow.enable.dsl = 2

process BIOC_AFFYPLM_FLEXIBLE_THREESTEP_PREPROCESSING {
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
    .bm_deps <- c("affyPLM")
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
        library(affyPLM)
        
        # ==========================================
        # 1. Load and Update the AffyBatch Object
        # ==========================================
        # Read the user-provided Dilution AffyBatch object from the working directory
        if (!file.exists("Dilution.rds")) {
          stop("Error: 'Dilution.rds' file not found in the working directory.")
        }
        
        Dilution <- readRDS("Dilution.rds")
        
        # Update the AffyBatch object to ensure compatibility
        Dilution = updateObject(Dilution)
        
        # ==========================================
        # 2. Run Threestep Preprocessing Workflows
        # ==========================================
        
        # Workflow A: Default threestep preprocessing
        eset <- threestep(Dilution)
        saveRDS(eset, "eset_default.rds")
        write.csv(exprs(eset), "exprs_default.csv", row.names = TRUE)
        
        # Workflow B: Custom background (MASIM), quantile normalization, and Tukey Biweight summarization
        eset <- threestep(Dilution, background.method = "MASIM", normalize.method="quantile",summary.method="tukey.biweight")
        saveRDS(eset, "eset_masim_quantile_tukey.rds")
        write.csv(exprs(eset), "exprs_masim_quantile_tukey.csv", row.names = TRUE)
        
        # Workflow C: Custom background (IdealMM), quantile normalization, and log 2nd largest summarization
        eset <- threestep(Dilution, background.method = "IdealMM", normalize="quantile",summary.method="log.2nd.largest")
        saveRDS(eset, "eset_idealmm_quantile_log2nd.rds")
        write.csv(exprs(eset), "exprs_idealmm_quantile_log2nd.csv", row.names = TRUE)
        
        # ==========================================
        # 3. Generate Diagnostic Plots
        # ==========================================
        # Load the processed datasets to plot comparison
        eset_def <- readRDS("eset_default.rds")
        eset_cust1 <- readRDS("eset_masim_quantile_tukey.rds")
        eset_cust2 <- readRDS("eset_idealmm_quantile_log2nd.rds")
        
        pdf("threestep_preprocessing_comparison.pdf", width = 12, height = 5)
        par(mfrow = c(1, 3))
        boxplot(exprs(eset_def), main = "Default Threestep", las = 2, col = "lightblue")
        boxplot(exprs(eset_cust1), main = "MASIM + Quantile + Tukey", las = 2, col = "lightgreen")
        boxplot(exprs(eset_cust2), main = "IdealMM + Quantile + Log2nd", las = 2, col = "lightpink")
        dev.off()

    writeLines(c(
        '"BIOC_AFFYPLM_FLEXIBLE_THREESTEP_PREPROCESSING":',
        paste0('    affyPLM: ', as.character(packageVersion('affyPLM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flexible_threestep_preprocessing.csv versions.yml
    """
}

workflow BIOC_AFFYPLM_FLEXIBLE_THREESTEP_PREPROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Dilution ] ]

    main:
    BIOC_AFFYPLM_FLEXIBLE_THREESTEP_PREPROCESSING(ch_input)

    emit:
    tables   = BIOC_AFFYPLM_FLEXIBLE_THREESTEP_PREPROCESSING.out.tables
    plots    = BIOC_AFFYPLM_FLEXIBLE_THREESTEP_PREPROCESSING.out.plots
    objects  = BIOC_AFFYPLM_FLEXIBLE_THREESTEP_PREPROCESSING.out.objects
    versions = BIOC_AFFYPLM_FLEXIBLE_THREESTEP_PREPROCESSING.out.versions
}
