#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: miaViz — prevalence_plotting
// Visualize feature prevalence across different abundance thresholds and relative abundances.
// Input: GlobalPatterns
// Container: quay.io/biocontainers/bioconductor-miaviz:1.18.0--r45hdfd78af_0
// R packages: ggplot2, mia, miaViz
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, mia, miaViz
// Visualizations: prevalence plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Plot row prevalence across detection thresholds
//  * 2. [Visualization & Output] Plot prevalent abundance against mean relative abundance
//  * 3. [Visualization & Output] Plot sample prevalence across multiple detection and prevalence steps

nextflow.enable.dsl = 2

process BIOC_MIAVIZ_PREVALENCE_PLOTTING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20"

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
    .bm_deps <- c("ggplot2", "mia", "miaViz")
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
    library(mia)
    library(miaViz)
    library(ggplot2)
    
    # ------------------------------------------------------------------------------
    # 1. Load Input Data
    # ------------------------------------------------------------------------------
    # The pipeline expects 'GlobalPatterns' (a TreeSummarizedExperiment object)
    # to be present in the working directory as an RDS file.
    if (file.exists("GlobalPatterns.rds")) {
        GlobalPatterns <- readRDS("GlobalPatterns.rds")
    } else if (file.exists("GlobalPatterns")) {
        GlobalPatterns <- readRDS("GlobalPatterns")
    } else {
        stop("Required input file 'GlobalPatterns' or 'GlobalPatterns.rds' not found in the working directory.")
    }
    
    # Ensure the relative abundance assay is present, as it is commonly required
    # for downstream abundance and prevalence plotting.
    if (!"relabundance" %in% assayNames(GlobalPatterns)) {
        GlobalPatterns <- transformAssay(GlobalPatterns, method = "relabundance")
    }
    
    # ------------------------------------------------------------------------------
    # 2. Execute Prevalence Plotting Workflow
    # ------------------------------------------------------------------------------
    
    # Stage 1: Plot row prevalence across detection thresholds
    p1 <- plotRowPrevalence(
        GlobalPatterns, rank = "Phylum", detections = c(0, 0.001, 0.01, 0.1, 0.2))
    
    # Stage 2: Plot prevalent abundance against mean relative abundance
    p2 <- plotPrevalentAbundance(GlobalPatterns, rank = "Family", colour.by = "Phylum") +
        scale_x_log10()
    
    # Stage 3: Plot sample prevalence across multiple detection and prevalence steps
    p3 <- plotPrevalence(
        GlobalPatterns, rank = "Phylum",
        detections = c(0.01, 0.1, 1, 2, 5, 10, 20)/100,
        prevalences = seq(0.1, 1, 0.1))
    
    # ------------------------------------------------------------------------------
    # 3. Save Outputs
    # ------------------------------------------------------------------------------
    # Save the generated plots to PDF files
    ggsave("row_prevalence_plot.pdf", plot = p1, width = 8, height = 6)
    ggsave("prevalent_abundance_plot.pdf", plot = p2, width = 8, height = 6)
    ggsave("prevalence_plot.pdf", plot = p3, width = 8, height = 6)
    
    # Save the plots as RDS objects for downstream programmatic use if needed
    saveRDS(p1, "row_prevalence_plot.rds")
    saveRDS(p2, "prevalent_abundance_plot.rds")
    saveRDS(p3, "prevalence_plot.rds")

    writeLines(c(
        '"BIOC_MIAVIZ_PREVALENCE_PLOTTING":',
        paste0('    miaViz: ', as.character(packageVersion('miaViz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_prevalence_plotting.csv versions.yml
    """
}

workflow BIOC_MIAVIZ_PREVALENCE_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GlobalPatterns ] ]

    main:
    BIOC_MIAVIZ_PREVALENCE_PLOTTING(ch_input)

    emit:
    tables   = BIOC_MIAVIZ_PREVALENCE_PLOTTING.out.tables
    plots    = BIOC_MIAVIZ_PREVALENCE_PLOTTING.out.plots
    objects  = BIOC_MIAVIZ_PREVALENCE_PLOTTING.out.objects
    versions = BIOC_MIAVIZ_PREVALENCE_PLOTTING.out.versions
}
