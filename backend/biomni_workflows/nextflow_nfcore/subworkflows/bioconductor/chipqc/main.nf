#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chipqc — multi_sample_chipseq_qc
// Run a complete quality control analysis on a multi-sample ChIP-seq experiment using a sample sheet and generate diagnostic plots.
// Input: tamoxifenQC.csv, blacklist_hg19
// Container: quay.io/biocontainers/bioconductor-chipqc:1.42.0--r44hdfd78af_0
// R packages: ChIPQC
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: coverage plot, heatmap

nextflow.enable.dsl = 2

process BIOC_CHIPQC_MULTI_SAMPLE_CHIPSEQ_QC {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-chipqc:1.42.0--r44hdfd78af_0"

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
    .bm_deps <- c("ChIPQC")
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
    library(ChIPQC)
    
    # --- Load the sample sheet from the working directory ---
    samples <- read.csv("tamoxifenQC.csv", stringsAsFactors = FALSE)
    
    # --- Load the blacklist GRanges object from the working ---
    blacklist_file <- "blacklist_hg19"
    if (!file.exists(blacklist_file) && file.exists("blacklist_hg19.rds")) {
      blacklist_file <- "blacklist_hg19.rds"
    }
    blacklist.hg19 <- readRDS(blacklist_file)
    
    # --- Run ChIPQC to construct a ChIPQCexperiment object ---
    tamoxifen <- ChIPQC(samples, consensus=TRUE, bCount=TRUE, summits=250,
                        annotation="hg19", chromosomes="chr18",
                        blacklist = blacklist.hg19)
    
    # Save the constructed ChIPQCexperiment object
    saveRDS(tamoxifen, "tamoxifen_ChIPQC.rds")
    
    # Save the QC metrics table
    qc_metrics <- QCmetrics(tamoxifen)
    write.csv(qc_metrics, "tamoxifen_QCmetrics.csv", row.names = TRUE)
    
    # --- Generate and save diagnostic plots to PDF files ---
    
    pdf("plot_coverage_hist.pdf")
    plotCoverageHist(tamoxifen, facetBy=c("Tissue","Condition"))
    dev.off()
    
    pdf("plot_cc.pdf")
    plotCC(tamoxifen, facetBy=c("Tissue","Condition"))
    dev.off()
    
    pdf("plot_regi.pdf")
    plotRegi(tamoxifen, facetBy=c("Tissue","Condition"))
    dev.off()
    
    pdf("plot_peak_profile.pdf")
    plotPeakProfile(tamoxifen, facetBy=c("Tissue","Condition"))
    dev.off()
    
    pdf("plot_rap.pdf")
    plotRap(tamoxifen, facetBy=c("Tissue","Condition"))
    dev.off()
    
    pdf("plot_fribl.pdf")
    plotFribl(tamoxifen, facetBy=c("Tissue","Condition"))
    dev.off()
    
    pdf("plot_cor_heatmap.pdf")
    plotCorHeatmap(tamoxifen, attributes=c("Tissue","Factor","Condition","Replicate"))
    dev.off()
    
    pdf("plot_princomp.pdf")
    plotPrincomp(tamoxifen, attributes=c("Tissue","Condition"))
    dev.off()

    writeLines(c(
        '"BIOC_CHIPQC_MULTI_SAMPLE_CHIPSEQ_QC":',
        paste0('        chipqc: ', as.character(packageVersion("chipqc")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_sample_chipseq_qc.csv versions.yml
    """
}

workflow BIOC_CHIPQC_MULTI_SAMPLE_CHIPSEQ_QC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tamoxifenQC.csv, blacklist_hg19 ] ]

    main:
    BIOC_CHIPQC_MULTI_SAMPLE_CHIPSEQ_QC(ch_input)

    emit:
    tables   = BIOC_CHIPQC_MULTI_SAMPLE_CHIPSEQ_QC.out.tables
    plots    = BIOC_CHIPQC_MULTI_SAMPLE_CHIPSEQ_QC.out.plots
    objects  = BIOC_CHIPQC_MULTI_SAMPLE_CHIPSEQ_QC.out.objects
    versions = BIOC_CHIPQC_MULTI_SAMPLE_CHIPSEQ_QC.out.versions
}
