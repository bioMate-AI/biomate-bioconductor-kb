#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gCrisprTools — advanced_contrast_comparison
// Compare, regularize, and integrate multiple screening contrasts to identify replicated signals, interaction effects, and common pathway enrichments.
// Input: resultsDF, res2, allResults, genesetdb
// Container: quay.io/biocontainers/bioconductor-gcrisprtools:2.16.0--r45hdfd78af_0
// R packages: Biobase, ComplexHeatmap, gCrisprTools, limma, sparrow
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, ComplexHeatmap, gCrisprTools, limma, sparrow
// Visualizations: scatter plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert results data.frames to target-level simpleResult objects using ct.simpleResult
//  * 2. [Core Analysis] Regularize multiple contrasts to be "in register" using ct.regularizeContrasts
//  * 3. [Core Analysis] Compare contrasts and identify replicated signals using ct.compareContrasts
//  * 4. [Visualization & Output] Visualize contrast dynamics using ct.contrastBarchart and ct.scatter
//  * 5. [Core Analysis] Analyze complex interaction effects by comparing multiple simple results
//  * 6. [Visualization & Output] Generate UpSet plots to visualize multi-contrast overlaps using ct.upSet
//  * 7. [Core Analysis] Perform multi-contrast pathway enrichment analysis using ct.seas

nextflow.enable.dsl = 2

process BIOC_GCRISPRTOOLS_ADVANCED_CONTRAST_COMPARISON {
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
    .bm_deps <- c("Biobase", "ComplexHeatmap", "gCrisprTools", "limma", "sparrow")
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
        library(Biobase)
        library(limma)
        library(gCrisprTools)
        library(sparrow)
        library(ComplexHeatmap)
        
        # ==========================================
        # 1. LOAD USER INPUT FILES
        # ==========================================
        
        # Load resultsDF
        if (file.exists("resultsDF.rds")) {
          resultsDF <- readRDS("resultsDF.rds")
        } else if (file.exists("resultsDF.csv")) {
          resultsDF <- read.csv("resultsDF.csv", row.names = 1, check.names = FALSE)
        } else {
          stop("Required input file 'resultsDF' (RDS or CSV) not found in the working directory.")
        }
        
        # Load res2
        if (file.exists("res2.rds")) {
          res2 <- readRDS("res2.rds")
        } else if (file.exists("res2.csv")) {
          res2 <- read.csv("res2.csv", row.names = 1, check.names = FALSE)
        } else {
          stop("Required input file 'res2' (RDS or CSV) not found in the working directory.")
        }
        
        # Load allResults
        if (file.exists("allResults.rds")) {
          allResults <- readRDS("allResults.rds")
        } else {
          stop("Required input file 'allResults.rds' not found in the working directory.")
        }
        
        # Load genesetdb
        if (file.exists("genesetdb.rds")) {
          genesetdb <- readRDS("genesetdb.rds")
        } else {
          stop("Required input file 'genesetdb.rds' not found in the working directory.")
        }
        
        # ==========================================
        # 2. PREPARE DATA & RUN WORKFLOW
        # ==========================================
        
        # Convert resultsDF to target-level simpleResult object
        res <- ct.simpleResult(resultsDF, collapse = 'geneSymbol')
        
        # Regularize multiple contrasts to be "in register"
        regularized <- ct.regularizeContrasts(dflist = list('Experiment1' = res, 'Experiment2' = res2), collapse = 'geneSymbol')
        
        # Compare contrasts and identify replicated signals
        comparison <- ct.compareContrasts(dflist = regularized, statistics = c('best.q', 'best.p'), cutoffs = c(0.5,0.05), same.dir = rep(TRUE, length(regularized)))
        write.csv(comparison, "comparison_results.csv", row.names = TRUE)
        
        # Compare contrasts returning summary statistics
        comparison_stats <- ct.compareContrasts(dflist = regularized, statistics = c('best.q', 'best.p'), cutoffs = c(0.5,0.05), same.dir = rep(TRUE, length(regularized)), return.stats = TRUE)
        write.csv(comparison_stats, "comparison_stats.csv", row.names = TRUE)
        
        # Visualize contrast dynamics using ct.contrastBarchart
        pdf("contrast_barchart.pdf", width = 8, height = 8)
        ct.contrastBarchart(regularized, background = FALSE, statistic = 'best.p')
        dev.off()
        
        # Visualize contrast dynamics using ct.scatter
        pdf("scatter_plot.pdf", width = 8, height = 8)
        scat <- ct.scatter(regularized, targets = 'geneSymbol', statistic = 'best.p', cutoff = 0.05)
        dev.off()
        write.csv(scat, "scatter_data.csv", row.names = TRUE)
        
        # Analyze complex interaction effects by comparing multiple simple results
        allSimple <- ct.regularizeContrasts(allResults)
        
        time.effect <- ct.compareContrasts(list("con" = allSimple[[1]], "tx" = allSimple[[2]]))
        write.csv(time.effect, "time_effect_comparison.csv", row.names = TRUE)
        
        mod.control <- ct.compareContrasts(list("con" = allSimple[[1]], "Interaction" = allSimple[[min(3, length(allSimple))]]), same.dir = c(TRUE, FALSE))
        write.csv(mod.control, "mod_control_comparison.csv", row.names = TRUE)
        
        # Generate UpSet plots to visualize multi-contrast overlaps
        pdf("upset_plot.pdf", width = 8, height = 8)
        upset <- ct.upSet(allSimple)
        dev.off()
        saveRDS(upset, "upset_matrix.rds")
        
        # Perform multi-contrast pathway enrichment analysis using ct.seas
        sparrowList <- ct.seas(allSimple, gdb = genesetdb)
        saveRDS(sparrowList, "sparrow_enrichment_results.rds")
        
        message("gCrisprTools advanced contrast comparison pipeline completed successfully.")

    writeLines(c(
        '"BIOC_GCRISPRTOOLS_ADVANCED_CONTRAST_COMPARISON":',
        paste0('    gCrisprTools: ', as.character(packageVersion('gCrisprTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_advanced_contrast_comparison.csv versions.yml
    """
}

workflow BIOC_GCRISPRTOOLS_ADVANCED_CONTRAST_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ resultsDF, res2, allResults, genesetdb ] ]

    main:
    BIOC_GCRISPRTOOLS_ADVANCED_CONTRAST_COMPARISON(ch_input)

    emit:
    tables   = BIOC_GCRISPRTOOLS_ADVANCED_CONTRAST_COMPARISON.out.tables
    plots    = BIOC_GCRISPRTOOLS_ADVANCED_CONTRAST_COMPARISON.out.plots
    objects  = BIOC_GCRISPRTOOLS_ADVANCED_CONTRAST_COMPARISON.out.objects
    versions = BIOC_GCRISPRTOOLS_ADVANCED_CONTRAST_COMPARISON.out.versions
}
