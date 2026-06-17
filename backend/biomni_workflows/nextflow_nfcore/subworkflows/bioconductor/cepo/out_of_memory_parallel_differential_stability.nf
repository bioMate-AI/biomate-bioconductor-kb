#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Cepo — out_of_memory_parallel_differential_stability
// Run Cepo on large-scale atlas datasets using out-of-memory HDF5 arrays and parallel processing.
// Input: cellbench
// Container: quay.io/biocontainers/bioconductor-cepo:1.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, Cepo, DelayedArray, HDF5Array, SingleCellExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert logcounts matrix to an HDF5-backed DelayedArray
//  * 2. [Core Analysis] Run Cepo on the HDF5 matrix
//  * 3. [Core Analysis] Configure parallel backend using BiocParallel and setAutoBPPARAM
//  * 4. [Core Analysis] Run Cepo in parallel
//  * 5. [Core Analysis] Revert parallel settings to serial

nextflow.enable.dsl = 2

process BIOC_CEPO_OUT_OF_MEMORY_PARALLEL_DIFFERENTIAL_STABILITY {
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
    .bm_deps <- c("Cepo", "DelayedArray", "HDF5Array", "BiocParallel")
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
    library(Cepo)
    library(DelayedArray)
    library(HDF5Array)
    library(BiocParallel)
    
    # Read user input file 'cellbench' from the working directory
    if (file.exists("cellbench")) {
      cellbench <- readRDS("cellbench")
    } else if (file.exists("cellbench.rds")) {
      cellbench <- readRDS("cellbench.rds")
    } else {
      stop("Required input file 'cellbench' or 'cellbench.rds' not found in the working directory.")
    }
    
    # Preprocess: remove duplicated genes
    cellbench = cellbench[!duplicated(rownames(cellbench)),]
    
    # Convert logcounts matrix to an HDF5-backed DelayedArray
    da_matrix = DelayedArray(realize(logcounts(cellbench), "HDF5Array"))
    
    # Run Cepo on the HDF5 matrix (serial)
    da_output = Cepo(exprsMat = da_matrix, cellType = cellbench\$celltype)
    
    # Configure parallel backend using BiocParallel
    BPPARAM = if (.Platform\$OS.type == "windows") {
      BiocParallel::SnowParam(workers = 2)
    } else {
      BiocParallel::MulticoreParam(workers = 2)
    }
    DelayedArray::setAutoBPPARAM(BPPARAM = BPPARAM) ## Setting two cores for computation
    
    # Run Cepo in parallel
    da_output_parallel = Cepo(exprsMat = da_matrix, cellTypes = cellbench\$celltype)
    
    # Revert parallel settings to serial
    DelayedArray::setAutoBPPARAM(BPPARAM = SerialParam()) ## Revert back to only one core
    
    # Save meaningful results to output files
    saveRDS(da_output, file = "da_output.rds")
    saveRDS(da_output_parallel, file = "da_output_parallel.rds")

    writeLines(c(
        '"BIOC_CEPO_OUT_OF_MEMORY_PARALLEL_DIFFERENTIAL_STABILITY":',
        paste0('    Cepo: ', as.character(packageVersion('Cepo')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_out_of_memory_parallel_differential_stability.csv versions.yml
    """
}

workflow BIOC_CEPO_OUT_OF_MEMORY_PARALLEL_DIFFERENTIAL_STABILITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cellbench ] ]

    main:
    BIOC_CEPO_OUT_OF_MEMORY_PARALLEL_DIFFERENTIAL_STABILITY(ch_input)

    emit:
    tables   = BIOC_CEPO_OUT_OF_MEMORY_PARALLEL_DIFFERENTIAL_STABILITY.out.tables
    plots    = BIOC_CEPO_OUT_OF_MEMORY_PARALLEL_DIFFERENTIAL_STABILITY.out.plots
    objects  = BIOC_CEPO_OUT_OF_MEMORY_PARALLEL_DIFFERENTIAL_STABILITY.out.objects
    versions = BIOC_CEPO_OUT_OF_MEMORY_PARALLEL_DIFFERENTIAL_STABILITY.out.versions
}
