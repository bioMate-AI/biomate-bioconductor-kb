#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CellBench — method_timing_benchmarking
// Measure and compare the execution times of different analysis methods across datasets.
// Input: datasets.rds
// Container: quay.io/biocontainers/bioconductor-cellbench:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CellBench, ggplot2, magrittr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load datasets into a list
//  * 2. [Input & Preparation] Define methods as a list of functions
//  * 3. [Core Analysis] Measure execution times sequentially using time_methods()
//  * 4. [Core Analysis] Unpack timing results into a flat tibble using unpack_timing() or strip timings using strip_timing()

nextflow.enable.dsl = 2

process BIOC_CELLBENCH_METHOD_TIMING_BENCHMARKING {
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
    .bm_deps <- c("CellBench", "magrittr", "ggplot2")
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
    library(magrittr)
    library(ggplot2)
    
    # 1. Load datasets into a list from the user input file
    if (!file.exists("datasets.rds")) {
      stop("Required input file 'datasets.rds' not found in the working directory.")
    }
    datasets <- readRDS("datasets.rds")
    
    # Ensure datasets is a list
    if (!is.list(datasets)) {
      datasets <- list(data = datasets)
    }
    
    # 2. Define methods as a list of functions (EXACTLY as documented)
    transform <- list(
      log = function(x) { Sys.sleep(0.1); log(x) },
      sqrt = function(x) { Sys.sleep(0.1); sqrt(x) }
    )
    
    transform2 <- list(
      plus = function(x) { Sys.sleep(0.1); x + 1 },
      minus = function(x) { Sys.sleep(0.1); x - 1 }
    )
    
    # 3. Measure execution times sequentially using time_methods()
    res2 <- datasets %>% time_methods(transform) %>% time_methods(transform2)
    
    # 4. Unpack timing results into a flat tibble and strip timings
    unpacked_res <- res2 %>% unpack_timing()
    stripped_res <- res2 %>% strip_timing()
    
    # Save outputs
    saveRDS(res2, "timing_benchmark_raw.rds")
    saveRDS(stripped_res, "timing_benchmark_stripped.rds")
    
    # Convert unpacked timing to a standard data frame and save as CSV
    # Duration objects from lubridate (used by CellBench) are converted to numeric seconds
    unpacked_df <- as.data.frame(unpacked_res)
    unpacked_df\$user <- as.numeric(unpacked_df\$user)
    unpacked_df\$system <- as.numeric(unpacked_df\$system)
    unpacked_df\$elapsed <- as.numeric(unpacked_df\$elapsed)
    
    write.csv(unpacked_df, "timing_benchmark_results.csv", row.names = FALSE)
    
    # Generate a timing comparison plot
    tryCatch({
      p <- ggplot(unpacked_df, aes(x = interaction(transform, transform2), y = elapsed, fill = data)) +
        geom_bar(stat = "identity", position = "dodge") +
        theme_minimal() +
        theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
        labs(
          title = "CellBench Method Timing Comparison",
          x = "Method Combination (transform . transform2)",
          y = "Elapsed Time (seconds)"
        )
      ggsave("timing_comparison_plot.pdf", plot = p, width = 8, height = 6)
    }, error = function(e) {
      warning("Could not generate timing plot: ", e\$message)
    })

    writeLines(c(
        '"BIOC_CELLBENCH_METHOD_TIMING_BENCHMARKING":',
        paste0('    CellBench: ', as.character(packageVersion('CellBench')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_method_timing_benchmarking.csv versions.yml
    """
}

workflow BIOC_CELLBENCH_METHOD_TIMING_BENCHMARKING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ datasets.rds ] ]

    main:
    BIOC_CELLBENCH_METHOD_TIMING_BENCHMARKING(ch_input)

    emit:
    tables   = BIOC_CELLBENCH_METHOD_TIMING_BENCHMARKING.out.tables
    plots    = BIOC_CELLBENCH_METHOD_TIMING_BENCHMARKING.out.plots
    objects  = BIOC_CELLBENCH_METHOD_TIMING_BENCHMARKING.out.objects
    versions = BIOC_CELLBENCH_METHOD_TIMING_BENCHMARKING.out.versions
}
