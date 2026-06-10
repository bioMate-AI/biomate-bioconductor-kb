#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: genomicdistributions — signal_in_regions
// Summarize and plot signal values (such as tissue specificity or open chromatin accessibility) across conditions of interest for a set of genomic ranges.
// Input: vistaEnhancers.bed.gz, example_cell_matrix.txt
// Container: quay.io/biocontainers/bioconductor-genomicdistributions:1.18.0--r45hdfd78af_0
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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library("GenomicDistributions")
    library("rtracklayer")
    library("GenomicRanges")
    library("data.table")
    library("ggplot2")
    
    # 1. Load query genomic ranges and the signal matrix from the working directory
    queryFile = "vistaEnhancers.bed.gz"
    query = rtracklayer::import(queryFile)
    
    query2 = GenomicRanges::shift(query, 1e6)
    queryList = GRangesList(vistaEnhancers=query, shifted=query2)
    
    exampleCellMatrixFile = "example_cell_matrix.txt"
    cellMatrix = data.table::fread(exampleCellMatrixFile)
    
    # 2. Calculate summary signal across regions using calcSummarySignal
    op = calcSummarySignal(query, cellMatrix)
    op2 = calcSummarySignal(queryList, cellMatrix)
    
    # Save calculated summary signals to disk
    write.csv(op, "summary_signal_single.csv", row.names = FALSE)
    write.csv(op2, "summary_signal_list.csv", row.names = FALSE)
    saveRDS(op, "summary_signal_single.rds")
    saveRDS(op2, "summary_signal_list.rds")
    
    # 3. Plot summary signal using plotSummarySignal and save to PDF
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

    cat <<-END_VERSIONS > versions.yml
    "BIOC_GENOMICDISTRIBUTIONS_SIGNAL_IN_REGIONS":
        genomicdistributions: \$(Rscript -e 'cat(as.character(packageVersion("genomicdistributions")))')
    END_VERSIONS
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
