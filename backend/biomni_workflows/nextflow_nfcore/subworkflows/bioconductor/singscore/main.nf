#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: singscore — standard_singscore_scoring
// Score transcriptome-wide gene expression data against up- and down-regulated gene sets, visualize rank distributions, and evaluate statistical significance.
// Input: tgfb_expr_10_se, tgfb_gs_up, tgfb_gs_dn
// Container: quay.io/biocontainers/bioconductor-singscore:1.30.0--r45hdfd78af_0
// R packages: SummarizedExperiment, GSEABase, singscore
// Bioconductor: 3.20 | R: 4.4
// Requires: GSEABase, SummarizedExperiment, singscore
// Visualizations: density plot, dispersion plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Rank genes using rankGenes
//  * 2. [Core Analysis] Score samples using simpleScore
//  * 3. [Visualization & Output] Plot rank densities using plotRankDensity
//  * 4. [Visualization & Output] Plot score dispersions using plotDispersion
//  * 5. [Core Analysis] Generate null distribution using generateNull
//  * 6. [Core Analysis] Calculate empirical p-values using getPvals
//  * 7. [Visualization & Output] Plot null distributions using plotNull

nextflow.enable.dsl = 2

process BIOC_SINGSCORE_STANDARD_SINGSCORE_SCORING {
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
    .bm_deps <- c("SummarizedExperiment", "GSEABase", "singscore")
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
    library(singscore)
    library(GSEABase)
    
    # -----------------------------------------------------------------------------
    # Stage 0: Read User Input Files
    # -----------------------------------------------------------------------------
    # Read the declared user input files from the working directory
    tgfb_expr_10_se <- readRDS("tgfb_expr_10_se.rds")
    tgfb_gs_up <- readRDS("tgfb_gs_up.rds")
    tgfb_gs_dn <- readRDS("tgfb_gs_dn.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 1: Rank genes using rankGenes
    # -----------------------------------------------------------------------------
    rankData <- rankGenes(tgfb_expr_10_se)
    
    # -----------------------------------------------------------------------------
    # Stage 2: Score samples using simpleScore
    # -----------------------------------------------------------------------------
    scoredf <- simpleScore(rankData, upSet = tgfb_gs_up, downSet = tgfb_gs_dn)
    
    # Save the scoring results
    write.csv(scoredf, "singscore_results.csv", row.names = TRUE)
    
    # -----------------------------------------------------------------------------
    # Stage 3: Plot rank densities using plotRankDensity
    # -----------------------------------------------------------------------------
    pdf("rank_density_plot.pdf", width = 8, height = 6)
    plotRankDensity(rankData[,2,drop = FALSE], upSet = tgfb_gs_up, 
                    downSet = tgfb_gs_dn, isInteractive = FALSE)
    dev.off()
    
    # -----------------------------------------------------------------------------
    # Stage 4: Plot score dispersions using plotDispersion
    # -----------------------------------------------------------------------------
    # Construct annotation data frame from sample names
    tgfbAnnot <- data.frame(SampleID = colnames(tgfb_expr_10_se), Type = NA)
    tgfbAnnot\$Type[grepl("Ctrl", tgfbAnnot\$SampleID)] = "Control"
    tgfbAnnot\$Type[grepl("TGFb", tgfbAnnot\$SampleID)] = "TGFb"
    
    pdf("dispersion_plot.pdf", width = 8, height = 6)
    plotDispersion(scoredf, annot = tgfbAnnot\$Type, isInteractive = FALSE)
    dev.off()
    
    # -----------------------------------------------------------------------------
    # Stage 5: Generate null distribution using generateNull
    # -----------------------------------------------------------------------------
    ncores <- 1
    
    permuteResult <-
      generateNull(
        upSet = tgfb_gs_up,
        downSet = tgfb_gs_dn,
        rankData = rankData,
        subSamples = 1:5,
        centerScore = TRUE,
        knownDirection = TRUE,
        B = 1000,
        ncores = ncores,
        seed = 1,
        useBPPARAM = NULL
      )
    
    # Save permutation results
    saveRDS(permuteResult, "permutation_results.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 6: Calculate empirical p-values using getPvals
    # -----------------------------------------------------------------------------
    pvals <- getPvals(permuteResult, scoredf, subSamples = 1:5)
    
    # Save p-values
    write.csv(as.data.frame(pvals), "pvalues_results.csv", row.names = TRUE)
    
    # -----------------------------------------------------------------------------
    # Stage 7: Plot null distributions using plotNull
    # -----------------------------------------------------------------------------
    pdf("null_distribution_plot.pdf", width = 8, height = 6)
    plotNull(permuteResult, scoredf, pvals, sampleNames = names(pvals)[1])
    dev.off()

    writeLines(c(
        '"BIOC_SINGSCORE_STANDARD_SINGSCORE_SCORING":',
        paste0('    singscore: ', as.character(packageVersion('singscore')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_singscore_scoring.csv versions.yml
    """
}

workflow BIOC_SINGSCORE_STANDARD_SINGSCORE_SCORING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tgfb_expr_10_se, tgfb_gs_up, tgfb_gs_dn ] ]

    main:
    BIOC_SINGSCORE_STANDARD_SINGSCORE_SCORING(ch_input)

    emit:
    tables   = BIOC_SINGSCORE_STANDARD_SINGSCORE_SCORING.out.tables
    plots    = BIOC_SINGSCORE_STANDARD_SINGSCORE_SCORING.out.plots
    objects  = BIOC_SINGSCORE_STANDARD_SINGSCORE_SCORING.out.objects
    versions = BIOC_SINGSCORE_STANDARD_SINGSCORE_SCORING.out.versions
}
