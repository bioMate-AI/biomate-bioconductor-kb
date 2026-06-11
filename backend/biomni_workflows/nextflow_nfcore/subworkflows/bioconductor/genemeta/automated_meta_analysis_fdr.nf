#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeneMeta — automated_meta_analysis_fdr
// Perform an all-in-one meta-analysis across multiple studies to compute combined z-scores, estimate false discovery rates (FDR) via permutations, and visualize r
// Input: Split1, Split2, Nevins, Split1.ER, Split2.ER, data.ER
// Container: quay.io/biocontainers/bioconductor-genemeta:1.82.0--r45hdfd78af_0
// R packages: Biobase, GeneMeta, RColorBrewer
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GeneMeta, RColorBrewer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Compute combined z-scores and meta-analysis statistics
//  * 2. [Visualization & Output] Plot combined vs original scores and IDR plot
//  * 3. [Visualization & Output] Estimate FDR using zScoreFDR
//  * 4. [Visualization & Output] Visualize FDR thresholds and gene counts using CountPlot

nextflow.enable.dsl = 2

process BIOC_GENEMETA_AUTOMATED_META_ANALYSIS_FDR {
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
    .bm_deps <- c("Biobase", "GeneMeta", "RColorBrewer")
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
    library(GeneMeta)
    library(RColorBrewer)
    library(Biobase)
    
    # Read user input files from the working directory
    Split1 <- readRDS("Split1.rds")
    Split2 <- readRDS("Split2.rds")
    Nevins <- readRDS("Nevins.rds")
    Split1.ER <- readRDS("Split1.ER.rds")
    Split2.ER <- readRDS("Split2.ER.rds")
    data.ER <- readRDS("data.ER.rds")
    
    # Execute the documented workflow steps
    esets     <- list(Split1,Split2,Nevins)
    classes   <- list(Split1.ER,Split2.ER,data.ER)
    
    # --- Compute combined z-scores and meta-analysis statistics ---
    theScores <- zScores(esets,classes,useREM=FALSE,CombineExp=1:2)
    
    # Save z-scores results
    write.csv(theScores, "theScores.csv", row.names=TRUE)
    saveRDS(theScores, "theScores.rds")
    
    # --- Plot combined vs original scores and IDR plot ---
    pdf("CombinedVsOriginal.pdf")
    plot(theScores[,"zSco_Ex_3"],theScores[,"zSco"],pch="*",xlab="original score",ylab="combined score")
    abline(0,1,col="red")
    dev.off()
    
    pdf("IDRplot.pdf")
    IDRplot(theScores,Combine=1:2,colPos="blue", colNeg="red")
    dev.off()
    
    # --- Estimate FDR using zScoreFDR ---
    ScoresFDR <- zScoreFDR(esets, classes, useREM=FALSE, nperm=50,CombineExp=1:2)
    
    # Save FDR results
    saveRDS(ScoresFDR, "ScoresFDR.rds")
    
    # Define color palette for plotting
    theNewC <- brewer.pal(3,"Set2")
    
    # --- Visualize FDR thresholds and gene counts using CountPlot ---
    pdf("CountPlot.pdf")
    CountPlot(ScoresFDR,Score="FDR",kindof="two.sided",cols=c("red",theNewC),main="two sided FDR", xlab="FDR threshold",ylab="Number of genes",CombineExp=3)
    dev.off()

    writeLines(c(
        '"BIOC_GENEMETA_AUTOMATED_META_ANALYSIS_FDR":',
        paste0('    GeneMeta: ', as.character(packageVersion('GeneMeta')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_automated_meta_analysis_fdr.csv versions.yml
    """
}

workflow BIOC_GENEMETA_AUTOMATED_META_ANALYSIS_FDR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Split1, Split2, Nevins, Split1.ER, Split2.ER, data.ER ] ]

    main:
    BIOC_GENEMETA_AUTOMATED_META_ANALYSIS_FDR(ch_input)

    emit:
    tables   = BIOC_GENEMETA_AUTOMATED_META_ANALYSIS_FDR.out.tables
    plots    = BIOC_GENEMETA_AUTOMATED_META_ANALYSIS_FDR.out.plots
    objects  = BIOC_GENEMETA_AUTOMATED_META_ANALYSIS_FDR.out.objects
    versions = BIOC_GENEMETA_AUTOMATED_META_ANALYSIS_FDR.out.versions
}
