#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MEAL — expression_analysis
// Perform differential expression analysis on an ExpressionSet.
// Input: brge_gexp
// Container: quay.io/biocontainers/bioconductor-meal:1.28.0--r42hdfd78af_0
// R packages: Biobase, GenomicRanges, MEAL, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GenomicRanges, MEAL, ggplot2
// Visualizations: volcano plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run differential mean analysis using runDiffMeanAnalysis
//  * 2. [Visualization & Output] Evaluate model fit and visualize results using QQ-plots, Volcano plots, and Manhattan plots

nextflow.enable.dsl = 2

process BIOC_MEAL_EXPRESSION_ANALYSIS {
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
    .bm_deps <- c("Biobase", "GenomicRanges", "MEAL", "ggplot2")
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
        library(MEAL)
        library(Biobase)
        library(GenomicRanges)
        library(ggplot2)
        
        # ----------------------------------------------------------------------
        # 1. Load User Input
        # ----------------------------------------------------------------------
        # The pipeline expects 'brge_gexp' in the working directory.
        # We handle multiple common formats (RDS, RData, or unextended files).
        if (file.exists("brge_gexp.rds")) {
          brge_gexp <- readRDS("brge_gexp.rds")
        } else if (file.exists("brge_gexp.RData")) {
          load("brge_gexp.RData")
        } else if (file.exists("brge_gexp")) {
          brge_gexp <- tryCatch({
            readRDS("brge_gexp")
          }, error = function(e) {
            env <- new.env()
            load("brge_gexp", envir = env)
            get(ls(env)[1], envir = env)
          })
        } else {
          stop("Required input file 'brge_gexp' (as RDS or RData) not found in the working directory.")
        }
        
        # Ensure the loaded object is an ExpressionSet
        if (!inherits(brge_gexp, "ExpressionSet")) {
          stop("Loaded object is not of class 'ExpressionSet'.")
        }
        
        # ----------------------------------------------------------------------
        # 2. Run Differential Mean Analysis
        # ----------------------------------------------------------------------
        gexpRes <- runDiffMeanAnalysis(set = brge_gexp, model = ~ sex)
        names(gexpRes)
        
        # Save the ResultSet object
        saveRDS(gexpRes, file = "gexpRes.rds")
        
        # Extract and save the association results table
        association_results <- getAssociation(gexpRes, rid = "DiffMean")
        write.csv(association_results, file = "gexp_diff_mean_results.csv", row.names = TRUE)
        
        # ----------------------------------------------------------------------
        # 3. Evaluate Model Fit and Visualize Results
        # ----------------------------------------------------------------------
        
        # A. QQ-plot
        pdf("qq_plot.pdf")
        p_qq <- plot(gexpRes, rid = "DiffMean", type = "qq")
        print(p_qq)
        dev.off()
        
        # B. Volcano plot
        pdf("volcano_plot.pdf")
        p_volcano <- plot(gexpRes, rid = "DiffMean", type = "volcano") + ggtitle("Differences in Means")
        print(p_volcano)
        dev.off()
        
        # C. Manhattan plot
        targetRangeNum <- GRanges("11:102600000-103300000")
        pdf("manhattan_plot.pdf")
        plot(gexpRes, rid = "DiffMean", type = "manhattan", main = "Differences in Means", highlight = targetRangeNum)
        dev.off()

    writeLines(c(
        '"BIOC_MEAL_EXPRESSION_ANALYSIS":',
        paste0('    MEAL: ', as.character(packageVersion('MEAL')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_expression_analysis.csv versions.yml
    """
}

workflow BIOC_MEAL_EXPRESSION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ brge_gexp ] ]

    main:
    BIOC_MEAL_EXPRESSION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MEAL_EXPRESSION_ANALYSIS.out.tables
    plots    = BIOC_MEAL_EXPRESSION_ANALYSIS.out.plots
    objects  = BIOC_MEAL_EXPRESSION_ANALYSIS.out.objects
    versions = BIOC_MEAL_EXPRESSION_ANALYSIS.out.versions
}
