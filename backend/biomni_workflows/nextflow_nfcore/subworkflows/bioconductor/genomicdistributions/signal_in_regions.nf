#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: genomicdistributions — signal_in_regions
// Summarize and plot signal values (such as tissue specificity or open chromatin accessibility) across conditions of interest for a set of genomic ranges.
// Input: vistaEnhancers.bed.gz, example_cell_matrix.txt
// Container: quay.io/biocontainers/bioconductor-genomicdistributions:1.18.0--r45hdfd78af_0
// R packages: GenomicDistributions, GenomicRanges, data.table, ggplot2, rtracklayer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMICDISTRIBUTIONS_SIGNAL_IN_REGIONS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-genomicdistributions:1.18.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicDistributions", "GenomicRanges", "data.table", "ggplot2", "rtracklayer")
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
    library("GenomicDistributions")
    library("rtracklayer")
    library("GenomicRanges")
    library("data.table")
    library("ggplot2")
    
    # --- Load query genomic ranges and the signal matrix from the ---
    queryFile = "vistaEnhancers.bed.gz"
    query = rtracklayer::import(queryFile)
    
    query2 = GenomicRanges::shift(query, 1e6)
    queryList = GRangesList(vistaEnhancers=query, shifted=query2)
    
    exampleCellMatrixFile = "example_cell_matrix.txt"
    cellMatrix = data.table::fread(exampleCellMatrixFile)
    
    # --- Calculate summary signal across regions using ---
    op = calcSummarySignal(query, cellMatrix)
    op2 = calcSummarySignal(queryList, cellMatrix)
    
    # Save calculated summary signals to disk
    write.csv(op, "summary_signal_single.csv", row.names = FALSE)
    write.csv(op2, "summary_signal_list.csv", row.names = FALSE)
    saveRDS(op, "summary_signal_single.rds")
    saveRDS(op2, "summary_signal_list.rds")
    
    # --- Plot summary signal using plotSummarySignal and save to ---
    # Plot 1: Single query summary signal
    p1 = plotSummarySignal(op)
    ggplot2::ggsave("plot_summary_signal_single.pdf", plot = p1, width = 8, height = 6)
    
    # Plot 2: Query list summary signal
    p2 = plotSummarySignal(op2)
    ggplot2::ggsave("plot_summary_signal_list.pdf", plot = p2, width = 8, height = 6)
    
    # Plot 3: Query list with metadata coloring
    cellTypeMetadata = GenomicDistributions::cellTypeMetadata
    p3 = plotSummarySignal(op2, metadata = cellTypeMetadata, colorColumn = "tissueType")
    ggplot2::ggsave("plot_summary_signal_list_metadata.pdf", plot = p3, width = 10, height = 7)
    
    # Plot 4: Query list violin plot with metadata coloring
    p4 = plotSummarySignal(signalSummaryList = op2, plotType = "violinPlot", metadata = cellTypeMetadata, colorColumn = "tissueType")
    ggplot2::ggsave("plot_summary_signal_list_violin.pdf", plot = p4, width = 10, height = 7)

    writeLines(c(
        '"BIOC_GENOMICDISTRIBUTIONS_SIGNAL_IN_REGIONS":',
        paste0('        genomicdistributions: ', as.character(packageVersion("genomicdistributions")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_signal_in_regions.csv versions.yml
    """
}

workflow BIOC_GENOMICDISTRIBUTIONS_SIGNAL_IN_REGIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ vistaEnhancers.bed.gz, example_cell_matrix.txt ] ]

    main:
    BIOC_GENOMICDISTRIBUTIONS_SIGNAL_IN_REGIONS(ch_input)

    emit:
    tables   = BIOC_GENOMICDISTRIBUTIONS_SIGNAL_IN_REGIONS.out.tables
    plots    = BIOC_GENOMICDISTRIBUTIONS_SIGNAL_IN_REGIONS.out.plots
    objects  = BIOC_GENOMICDISTRIBUTIONS_SIGNAL_IN_REGIONS.out.objects
    versions = BIOC_GENOMICDISTRIBUTIONS_SIGNAL_IN_REGIONS.out.versions
}
