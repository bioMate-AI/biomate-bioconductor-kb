#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GenomicDistributions — signal_specificity_analysis
// Summarize and visualize signal values (such as tissue-specific open chromatin) across query genomic ranges using a signal matrix.
// Input: queryFile.bed, example_cell_matrix.txt
// Container: quay.io/biocontainers/bioconductor-genomicdistributions:1.18.0--r45hdfd78af_0
// R packages: GenomicDistributions, GenomicRanges, data.table, ggplot2, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicDistributions, GenomicRanges, data.table, ggplot2, rtracklayer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import query genomic ranges
//  * 2. [Input & Preparation] Load signal matrix using data.table::fread
//  * 3. [Visualization & Output] Calculate summary signal across regions using calcSummarySignal
//  * 4. [Visualization & Output] Plot summary signal using plotSummarySignal

nextflow.enable.dsl = 2

process BIOC_GENOMICDISTRIBUTIONS_SIGNAL_SPECIFICITY_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    library("GenomicDistributions")
    library("rtracklayer")
    library("GenomicRanges")
    library("data.table")
    library("ggplot2")
    
    # 1. Import query genomic ranges from the user input file
    queryFile = "queryFile.bed"
    query = rtracklayer::import(queryFile)
    
    # Create a second region set by shifting the first one
    query2 = GenomicRanges::shift(query, 1e6)
    queryList = GRangesList(vistaEnhancers=query, shifted=query2)
    
    # 2. Load signal matrix using data.table::fread from the user input file
    exampleCellMatrixFile = "example_cell_matrix.txt"
    cellMatrix = data.table::fread(exampleCellMatrixFile)
    
    # 3. Calculate summary signal across regions using calcSummarySignal
    op = calcSummarySignal(query, cellMatrix)
    op2 = calcSummarySignal(queryList, cellMatrix)
    
    # Save calculated summary signals to CSV and RDS
    write.csv(op, "summary_signal_single.csv", row.names = FALSE)
    write.csv(op2, "summary_signal_multi.csv", row.names = FALSE)
    saveRDS(op, "summary_signal_single.rds")
    saveRDS(op2, "summary_signal_multi.rds")
    
    # Retrieve or construct cell type metadata safely
    cellTypeMetadata = tryCatch({
      GenomicDistributions::cellTypeMetadata
    }, error = function(e) {
      # Fallback: construct metadata dynamically from the cell matrix columns
      cols = colnames(cellMatrix)
      non_cell_cols = c("chr", "start", "end", "width", "strand", "id", "V1", "V2", "V3", "seqnames", "ranges")
      cell_types = setdiff(cols, non_cell_cols)
      data.frame(cellType = cell_types, tissueType = "Unknown", stringsAsFactors = FALSE)
    })
    
    # 4. Plot summary signal using plotSummarySignal and save to PDF
    pdf("summary_signal_plots.pdf", width = 10, height = 8)
    
    p1 = plotSummarySignal(op)
    print(p1)
    
    p2 = plotSummarySignal(op2)
    print(p2)
    
    p3 = plotSummarySignal(op2, metadata = cellTypeMetadata, colorColumn = "tissueType")
    print(p3)
    
    p4 = plotSummarySignal(signalSummaryList = op2, plotType = "violinPlot", metadata = cellTypeMetadata, colorColumn = "tissueType")
    print(p4)
    
    dev.off()

    writeLines(c(
        '"BIOC_GENOMICDISTRIBUTIONS_SIGNAL_SPECIFICITY_ANALYSIS":',
        paste0('    GenomicDistributions: ', as.character(packageVersion('GenomicDistributions')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_signal_specificity_analysis.csv versions.yml
    """
}

workflow BIOC_GENOMICDISTRIBUTIONS_SIGNAL_SPECIFICITY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ queryFile.bed, example_cell_matrix.txt ] ]

    main:
    BIOC_GENOMICDISTRIBUTIONS_SIGNAL_SPECIFICITY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GENOMICDISTRIBUTIONS_SIGNAL_SPECIFICITY_ANALYSIS.out.tables
    plots    = BIOC_GENOMICDISTRIBUTIONS_SIGNAL_SPECIFICITY_ANALYSIS.out.plots
    objects  = BIOC_GENOMICDISTRIBUTIONS_SIGNAL_SPECIFICITY_ANALYSIS.out.objects
    versions = BIOC_GENOMICDISTRIBUTIONS_SIGNAL_SPECIFICITY_ANALYSIS.out.versions
}
