#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cliProfiler — custom_window_profiling
// Profile CLIP-seq peaks against customized genomic annotations or non-model organism annotations stored in a GRanges object.
// Input: peaks.rds, custom_annotation.gff3
// Container: quay.io/biocontainers/bioconductor-cliprofiler:1.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: cliProfiler, ggplot2, rtracklayer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load peak data and custom annotation
//  * 2. [Core Analysis] Extract target features (e.g., exons) into a GRanges object
//  * 3. [Visualization & Output] Run windowProfile to calculate relative positions and generate the profile plot

nextflow.enable.dsl = 2

process BIOC_CLIPROFILER_CUSTOM_WINDOW_PROFILING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("cliProfiler", "rtracklayer", "ggplot2")
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
    library(cliProfiler)
    library(rtracklayer)
    library(ggplot2)
    
    # 1. Load peak data and custom annotation from the working directory
    peaks_file <- "peaks.rds"
    annotation_file <- "custom_annotation.gff3"
    
    if (!file.exists(peaks_file)) {
      stop(paste("Required input file missing:", peaks_file))
    }
    if (!file.exists(annotation_file)) {
      stop(paste("Required input file missing:", annotation_file))
    }
    
    # Read the GRanges object of peak coordinates
    test <- readRDS(peaks_file)
    
    # Set the path to the custom annotation file
    test_gff3 <- annotation_file
    
    # 2. Extract target features (exons) into a GRanges object
    test_anno <- rtracklayer::import.gff3(test_gff3)
    test_anno <- test_anno[test_anno\$type == "exon"]
    
    # 3. Run windowProfile to calculate relative positions and generate the profile plot
    window_profile <- windowProfile(test, test_anno)
    
    # Extract results
    profile_granges <- window_profile[[1]]
    profile_plot <- window_profile[[2]]
    
    # 4. Write named output files for the meaningful results
    # Save the GRanges result as RDS
    saveRDS(profile_granges, "window_profile_results.rds")
    
    # Save the GRanges result as a CSV table for easy viewing
    write.csv(as.data.frame(profile_granges), "window_profile_results.csv", row.names = FALSE)
    
    # Save the profile plot as a PDF
    ggsave("window_profile_plot.pdf", plot = profile_plot, width = 8, height = 6)

    writeLines(c(
        '"BIOC_CLIPROFILER_CUSTOM_WINDOW_PROFILING":',
        paste0('    cliProfiler: ', as.character(packageVersion('cliProfiler')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_window_profiling.csv versions.yml
    """
}

workflow BIOC_CLIPROFILER_CUSTOM_WINDOW_PROFILING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peaks.rds, custom_annotation.gff3 ] ]

    main:
    BIOC_CLIPROFILER_CUSTOM_WINDOW_PROFILING(ch_input)

    emit:
    tables   = BIOC_CLIPROFILER_CUSTOM_WINDOW_PROFILING.out.tables
    plots    = BIOC_CLIPROFILER_CUSTOM_WINDOW_PROFILING.out.plots
    objects  = BIOC_CLIPROFILER_CUSTOM_WINDOW_PROFILING.out.objects
    versions = BIOC_CLIPROFILER_CUSTOM_WINDOW_PROFILING.out.versions
}
