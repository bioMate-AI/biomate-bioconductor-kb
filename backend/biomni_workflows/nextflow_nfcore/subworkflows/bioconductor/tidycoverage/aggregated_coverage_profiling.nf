#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tidyCoverage — aggregated_coverage_profiling
// Aggregate and plot genomic track coverage over multiple sets of genomic features.
// Input: tracks, features
// Container: quay.io/biocontainers/bioconductor-tidycoverage:1.6.0--r45hdfd78af_0
// R packages: ggplot2, plyranges, purrr, rtracklayer, tidyCoverage
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, plyranges, purrr, rtracklayer, tidyCoverage
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import genomic features and tracks
//  * 2. [Core Analysis] Instantiate CoverageExperiment
//  * 3. [Core Analysis] Aggregate coverage to AggregatedCoverage
//  * 4. [Visualization & Output] Plot using geom_aggrcoverage

nextflow.enable.dsl = 2

process BIOC_TIDYCOVERAGE_AGGREGATED_COVERAGE_PROFILING {
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
    .bm_deps <- c("ggplot2", "plyranges", "purrr", "rtracklayer", "tidyCoverage")
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
    library(tidyCoverage)
    library(purrr)
    library(plyranges)
    library(rtracklayer)
    library(ggplot2)
    
    # 1. Import genomic features and tracks from the working directory
    # Find BED files in the working directory
    bed_files <- list.files(pattern = "\\\\.bed\$", full.names = TRUE)
    if (length(bed_files) == 0) {
        stop("Error: No .bed files found in the working directory.")
    }
    features_list <- setNames(as.list(bed_files), tools::file_path_sans_ext(basename(bed_files)))
    
    # Find BigWig files in the working directory
    bw_files <- list.files(pattern = "\\\\.(bw|bigwig)\$", full.names = TRUE)
    if (length(bw_files) == 0) {
        stop("Error: No .bw or .bigwig files found in the working directory.")
    }
    tracks_list <- setNames(as.list(bw_files), tools::file_path_sans_ext(basename(bw_files)))
    
    # Import features
    features <- features_list |> map(import)
    
    # Import tracks as Rle objects
    tracks <- tracks_list |> map(import, as = 'Rle')
    
    # 2. Instantiate CoverageExperiment
    CE <- CoverageExperiment(tracks, features, width = 5000, scale = TRUE, center = TRUE)
    
    # 3. Aggregate coverage to AggregatedCoverage
    AC <- aggregate(CE)
    
    # 4. Save intermediate and final R objects
    saveRDS(CE, "coverage_experiment.rds")
    saveRDS(AC, "aggregated_coverage.rds")
    
    # Save the aggregated coverage table as CSV
    ac_tbl <- as_tibble(AC)
    write.csv(ac_tbl, "aggregated_coverage.csv", row.names = FALSE)
    
    # 5. Plot using geom_aggrcoverage and save as PDF
    p <- ac_tbl |> 
        ggplot(aes(col = track)) + 
        geom_aggrcoverage() + 
        facet_grid(features ~ .) + 
        labs(x = 'Distance from genomic feature', y = 'Mean coverage (\u00b1 95% conf. intervale)') + 
        theme_bw() + 
        theme(legend.position = 'top')
    
    ggsave("aggregated_coverage_profile.pdf", plot = p, width = 10, height = 8)

    writeLines(c(
        '"BIOC_TIDYCOVERAGE_AGGREGATED_COVERAGE_PROFILING":',
        paste0('    tidyCoverage: ', as.character(packageVersion('tidyCoverage')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_aggregated_coverage_profiling.csv versions.yml
    """
}

workflow BIOC_TIDYCOVERAGE_AGGREGATED_COVERAGE_PROFILING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tracks, features ] ]

    main:
    BIOC_TIDYCOVERAGE_AGGREGATED_COVERAGE_PROFILING(ch_input)

    emit:
    tables   = BIOC_TIDYCOVERAGE_AGGREGATED_COVERAGE_PROFILING.out.tables
    plots    = BIOC_TIDYCOVERAGE_AGGREGATED_COVERAGE_PROFILING.out.plots
    objects  = BIOC_TIDYCOVERAGE_AGGREGATED_COVERAGE_PROFILING.out.objects
    versions = BIOC_TIDYCOVERAGE_AGGREGATED_COVERAGE_PROFILING.out.versions
}
