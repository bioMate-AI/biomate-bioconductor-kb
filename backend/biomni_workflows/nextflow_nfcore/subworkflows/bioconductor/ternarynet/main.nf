#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ternarynet — ternary_network_fitting
// Fit a ternary gene-regulatory network model from steady-state perturbation data using a parallel replica exchange Monte Carlo algorithm, with the option to resu
// Input: indata.csv
// Container: quay.io/biocontainers/bioconductor-ternarynet:1.54.0--r45ha27e39d_0
// R packages: ternarynet
// Bioconductor: 3.20 | R: 4.4
// Requires: ternarynet
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Format the experimental perturbation data into a data frame with 0-indexed node and experiment identifiers. 2. Run the parallel re

nextflow.enable.dsl = 2

process BIOC_TERNARYNET_TERNARY_NETWORK_FITTING {
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
    .bm_deps <- c("ternarynet")
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
    
    # Load the required library
    library(ternarynet)
    
    # Read the user input file from the working directory
    if (!file.exists("indata.csv")) {
      stop("Error: indata.csv not found in the working directory.")
    }
    
    indata <- read.csv("indata.csv", stringsAsFactors = FALSE)
    
    # Ensure correct data types for ternarynet
    indata\$i_exp <- as.integer(indata\$i_exp)
    indata\$i_node <- as.integer(indata\$i_node)
    indata\$outcome <- as.integer(indata\$outcome)
    indata\$value <- as.numeric(indata\$value)
    indata\$is_perturbation <- as.logical(indata\$is_perturbation)
    
    # Run the parallel replica exchange fitting algorithm (First Fit)
    results <- parallelFit(indata,
                            max_parents=1,
                            n_cycles=100000,
                            n_write=10,
                            T_lo=0.001,
                            T_hi=2.0,
                            target_score=0,
                            n_proc=1,
                            logfile='try.log')
    
    lowest_temp_results <- results[[1]]
    
    print('Unnormalized score:')
    print(lowest_temp_results\$unnormalized_score)
    
    print('Normalized score:')
    print(lowest_temp_results\$normalized_score)
    
    print('Parents:')
    print(lowest_temp_results\$parents)
    
    print('Outcomes:')
    print(lowest_temp_results\$outcomes)
    
    # Perform a subsequent fit using the previous fit's parents and outcomes as initial conditions (Refinement Fit)
    results <- parallelFit(indata,
                            max_parents=1,
                            n_cycles=10,
                            n_write=10,
                            T_lo=0.001,
                            T_hi=2.0,
                            target_score=0,
                            n_proc=1,
                            logfile='try.log',
                            init_parents=lowest_temp_results\$parents,
                            init_outcomes=lowest_temp_results\$outcomes)
    
    lowest_temp_results <- results[[1]]
    
    print('Refined Unnormalized score:')
    print(lowest_temp_results\$unnormalized_score)
    
    print('Refined Normalized score:')
    print(lowest_temp_results\$normalized_score)
    
    print('Refined Parents:')
    print(lowest_temp_results\$parents)
    
    print('Refined Outcomes:')
    print(lowest_temp_results\$outcomes)
    
    # Save meaningful results to output files
    write.csv(as.data.frame(lowest_temp_results\$parents), "parents.csv", row.names = FALSE)
    write.csv(as.data.frame(lowest_temp_results\$outcomes), "outcomes.csv", row.names = FALSE)
    
    scores_df <- data.frame(
      metric = c("unnormalized_score", "normalized_score"),
      value = c(lowest_temp_results\$unnormalized_score, lowest_temp_results\$normalized_score)
    )
    write.csv(scores_df, "scores.csv", row.names = FALSE)
    
    saveRDS(lowest_temp_results, "lowest_temp_results.rds")
    saveRDS(results, "all_results.rds")

    writeLines(c(
        '"BIOC_TERNARYNET_TERNARY_NETWORK_FITTING":',
        paste0('    ternarynet: ', as.character(packageVersion('ternarynet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ternary_network_fitting.csv versions.yml
    """
}

workflow BIOC_TERNARYNET_TERNARY_NETWORK_FITTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ indata.csv ] ]

    main:
    BIOC_TERNARYNET_TERNARY_NETWORK_FITTING(ch_input)

    emit:
    tables   = BIOC_TERNARYNET_TERNARY_NETWORK_FITTING.out.tables
    plots    = BIOC_TERNARYNET_TERNARY_NETWORK_FITTING.out.plots
    objects  = BIOC_TERNARYNET_TERNARY_NETWORK_FITTING.out.objects
    versions = BIOC_TERNARYNET_TERNARY_NETWORK_FITTING.out.versions
}
