#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scMerge — sc_seg_index_computation
// Compute data-adaptive stably expressed genes (SEGs) to use as negative controls.
// Input: example_sce
// Container: quay.io/biocontainers/bioconductor-scmerge:1.26.0--r45hdfd78af_0
// R packages: SingleCellExperiment, SummarizedExperiment, scMerge
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, SummarizedExperiment, scMerge
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract raw count matrix
//  * 2. [Core Analysis] Run scSEGIndex to calculate the SEG index for each gene

nextflow.enable.dsl = 2

process BIOC_SCMERGE_SC_SEG_INDEX_COMPUTATION {
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
    .bm_deps <- c("SingleCellExperiment", "SummarizedExperiment", "scMerge")
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
    library(scMerge)
    
    library(SummarizedExperiment)
    # Read user input file from the working directory
    # The pipeline expects 'example_sce.rds' containing the SingleCellExperiment object
    example_sce <- readRDS("example_sce.rds")
    
    # 1. Extract raw count matrix
    exprs_mat = SummarizedExperiment::assay(example_sce, 'counts')
    
    # 2. Run scSEGIndex to calculate the SEG index for each gene
    result = scSEGIndex(exprs_mat = exprs_mat)
    
    # Write meaningful results to output files
    write.csv(result, "scseg_index_results.csv", row.names = TRUE)
    saveRDS(result, "scseg_index_results.rds")

    writeLines(c(
        '"BIOC_SCMERGE_SC_SEG_INDEX_COMPUTATION":',
        paste0('    scMerge: ', as.character(packageVersion('scMerge')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sc_seg_index_computation.csv versions.yml
    """
}

workflow BIOC_SCMERGE_SC_SEG_INDEX_COMPUTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example_sce ] ]

    main:
    BIOC_SCMERGE_SC_SEG_INDEX_COMPUTATION(ch_input)

    emit:
    tables   = BIOC_SCMERGE_SC_SEG_INDEX_COMPUTATION.out.tables
    plots    = BIOC_SCMERGE_SC_SEG_INDEX_COMPUTATION.out.plots
    objects  = BIOC_SCMERGE_SC_SEG_INDEX_COMPUTATION.out.objects
    versions = BIOC_SCMERGE_SC_SEG_INDEX_COMPUTATION.out.versions
}
