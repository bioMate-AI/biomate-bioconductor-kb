#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MassArray — amplicon_prediction_and_design
// Predict fragmentation patterns, assayability of CG sites, and identify potential conversion controls for a candidate amplicon sequence.
// Input: sequence
// Container: quay.io/biocontainers/bioconductor-massarray:1.62.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MassArray
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run in silico prediction using ampliconPrediction() to evaluate fragmentation patterns and CG assayability

nextflow.enable.dsl = 2

process BIOC_MASSARRAY_AMPLICON_PREDICTION_AND_DESIGN {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("MassArray")
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
    
    library(MassArray)
    
    # Read the candidate amplicon sequence from the user input file 'sequence'
    if (!file.exists("sequence")) {
      stop("Error: The required input file 'sequence' does not exist in the working directory.")
    }
    
    sequence_str <- trimws(paste(readLines("sequence", warn=FALSE), collapse=""))
    
    # Run in silico prediction using ampliconPrediction() to evaluate fragmentation patterns and CG assayability.
    # Since ampliconPrediction() generates a plot, we wrap it in a PDF device to save the visualization.
    pdf("amplicon_prediction_plot.pdf", width=11, height=8.5)
    results <- ampliconPrediction(sequence_str)
    dev.off()
    
    # Print results to console as in the documented code
    results
    
    # Write meaningful outputs to the working directory
    if (!is.null(results\$summary)) {
      write.csv(results\$summary, "amplicon_summary.csv", row.names=FALSE)
    }
    if (!is.null(results\$counts)) {
      write.csv(results\$counts, "amplicon_counts.csv", row.names=TRUE)
    }
    saveRDS(results, "amplicon_results.rds")

    writeLines(c(
        '"BIOC_MASSARRAY_AMPLICON_PREDICTION_AND_DESIGN":',
        paste0('    MassArray: ', as.character(packageVersion('MassArray')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_amplicon_prediction_and_design.csv versions.yml
    """
}

workflow BIOC_MASSARRAY_AMPLICON_PREDICTION_AND_DESIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sequence ] ]

    main:
    BIOC_MASSARRAY_AMPLICON_PREDICTION_AND_DESIGN(ch_input)

    emit:
    tables   = BIOC_MASSARRAY_AMPLICON_PREDICTION_AND_DESIGN.out.tables
    plots    = BIOC_MASSARRAY_AMPLICON_PREDICTION_AND_DESIGN.out.plots
    objects  = BIOC_MASSARRAY_AMPLICON_PREDICTION_AND_DESIGN.out.objects
    versions = BIOC_MASSARRAY_AMPLICON_PREDICTION_AND_DESIGN.out.versions
}
