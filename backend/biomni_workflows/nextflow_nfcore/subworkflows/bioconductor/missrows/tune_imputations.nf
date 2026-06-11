#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: missRows — tune_imputations
// Determine the appropriate number of imputations (M) needed to stabilize the estimated compromise configurations.
// Input: midt.RData
// Container: quay.io/biocontainers/bioconductor-missrows:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, missRows
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Run tuneM to evaluate the stability of configurations across different numbers of imputations. 2. Inspect the stability statistics

nextflow.enable.dsl = 2

process BIOC_MISSROWS_TUNE_IMPUTATIONS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
    # Load required libraries
    library(missRows)
    library(ggplot2)
    
    # Read user input file
    if (!file.exists("midt.RData")) {
      stop("Error: Input file 'midt.RData' not found in the working directory.")
    }
    
    load("midt.RData")
    
    # Ensure 'midt' object is loaded
    if (!exists("midt")) {
      stop("Error: 'midt' object not found in 'midt.RData'.")
    }
    
    # 1. Run tuneM to evaluate the stability of configurations across different numbers of imputations.
    set.seed(1)
    tune <- tuneM(midt, ncomp=2, Mmax=100, inc=10, N=20, showPlot=FALSE)
    
    print(tune)
    
    # 2. Inspect the stability statistics and plot the RV coefficients.
    print(tune\$stats)
    
    # Save the stability statistics to a CSV file
    write.csv(tune\$stats, file = "tune_stats.csv", row.names = FALSE)
    
    # Save the RV coefficient plot to a PDF file
    if (!is.null(tune\$ggp)) {
      ggplot2::ggsave("tune_plot.pdf", plot = tune\$ggp, width = 7, height = 5)
    }
    
    # Save the complete tune object as an RDS file
    saveRDS(tune, file = "tune_results.rds")

    writeLines(c(
        '"BIOC_MISSROWS_TUNE_IMPUTATIONS":',
        paste0('    missRows: ', as.character(packageVersion('missRows')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tune_imputations.csv versions.yml
    """
}

workflow BIOC_MISSROWS_TUNE_IMPUTATIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ midt.RData ] ]

    main:
    BIOC_MISSROWS_TUNE_IMPUTATIONS(ch_input)

    emit:
    tables   = BIOC_MISSROWS_TUNE_IMPUTATIONS.out.tables
    plots    = BIOC_MISSROWS_TUNE_IMPUTATIONS.out.plots
    objects  = BIOC_MISSROWS_TUNE_IMPUTATIONS.out.objects
    versions = BIOC_MISSROWS_TUNE_IMPUTATIONS.out.versions
}
