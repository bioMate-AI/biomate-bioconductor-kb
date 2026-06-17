#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CellBench — combinatorial_method_benchmarking
// Apply a sequence of analysis methods combinatorially to a list of datasets and collapse the pipeline names for downstream analysis or plotting.
// Input: datasets.rds
// Container: quay.io/biocontainers/bioconductor-cellbench:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CellBench, SingleCellExperiment, dplyr, purrr
// QC: count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load datasets into a list
//  * 2. [Input & Preparation] Define pipeline steps as lists of functions
//  * 3. [Core Analysis] Apply the first set of methods using apply_methods()
//  * 4. [Core Analysis] Apply subsequent methods using apply_methods()
//  * 5. [Core Analysis] Collapse pipeline steps using pipeline_collapse()

nextflow.enable.dsl = 2

process BIOC_CELLBENCH_COMBINATORIAL_METHOD_BENCHMARKING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20-slim"

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
    .bm_deps <- c("CellBench", "dplyr", "purrr")
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
    library(CellBench)
    library(dplyr)
    library(purrr)
    
    # 1. Load datasets into a list
    # The pipeline reads EXACTLY datasets.rds from the working directory
    datasets <- readRDS("datasets.rds")
    
    # Ensure datasets is indeed a list
    if (!is.list(datasets)) {
      datasets <- list(sample_data = datasets)
    }
    
    # 2. Define pipeline steps as lists of functions
    norm_method <- list(
      none = counts,
      cpm = function(x) t(t(1e6 * counts(x)) / colSums(counts(x)))
    )
    
    transform <- list(
      none = identity,
      log2 = function(x) log2(x+1)
    )
    
    # 3. Apply the first set of methods using apply_methods()
    res1 <- datasets %>% apply_methods(norm_method)
    
    # 4. Apply subsequent methods using apply_methods()
    res2 <- res1 %>% apply_methods(transform)
    
    # 5. Collapse pipeline steps using pipeline_collapse()
    collapsed_res <- res2 %>% pipeline_collapse()
    
    # Write named output files for the meaningful results
    # Save the complete collapsed results object
    saveRDS(collapsed_res, "collapsed_results.rds")
    
    # Generate and save a summary table of the pipeline runs
    pipeline_summary <- collapsed_res %>%
      mutate(
        features = map_int(result, nrow),
        samples = map_int(result, ncol)
      ) %>%
      select(pipeline, features, samples)
    
    write.csv(pipeline_summary, "pipeline_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_CELLBENCH_COMBINATORIAL_METHOD_BENCHMARKING":',
        paste0('    CellBench: ', as.character(packageVersion('CellBench')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_combinatorial_method_benchmarking.csv versions.yml
    """
}

workflow BIOC_CELLBENCH_COMBINATORIAL_METHOD_BENCHMARKING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ datasets.rds ] ]

    main:
    BIOC_CELLBENCH_COMBINATORIAL_METHOD_BENCHMARKING(ch_input)

    emit:
    tables   = BIOC_CELLBENCH_COMBINATORIAL_METHOD_BENCHMARKING.out.tables
    plots    = BIOC_CELLBENCH_COMBINATORIAL_METHOD_BENCHMARKING.out.plots
    objects  = BIOC_CELLBENCH_COMBINATORIAL_METHOD_BENCHMARKING.out.objects
    versions = BIOC_CELLBENCH_COMBINATORIAL_METHOD_BENCHMARKING.out.versions
}
