#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epiNEM — systematic_modulator_screening
// Perform a systematic analysis to identify and rank the most likely modulators for signaling gene pairs across a larger perturbation screen.
// Input: large_binary_effects_matrix.csv
// Container: quay.io/biocontainers/bioconductor-epinem:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: epiNEM
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare binary effect matrix
//  * 2. [Core Analysis] Run epiScreen to identify modulators
//  * 3. [Visualization & Output] Plot global distribution of inferred logics
//  * 4. [Visualization & Output] Plot detailed ranked modulators for specific pairs
//  * 5. [Visualization & Output] Visualize perfect binary effects matrix for each logic

nextflow.enable.dsl = 2

process BIOC_EPINEM_SYSTEMATIC_MODULATOR_SCREENING {
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
    
    # Load required library
    library(epiNEM)
    
    # 1. Prepare binary effect matrix
    input_file <- "large_binary_effects_matrix.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    # Read the user-provided CSV file
    data_df <- read.csv(input_file, row.names = 1, check.names = FALSE)
    data <- as.matrix(data_df)
    
    # 2. Run epiScreen to identify modulators
    res <- epiScreen(data)
    
    # 3. Plot global distribution of inferred logics
    pdf("global_distribution_logics.pdf", width = 8, height = 6)
    plot(res)
    dev.off()
    
    # 4. Plot detailed ranked modulators for specific pairs
    pdf("ranked_modulators_pair1.pdf", width = 8, height = 6)
    plot(res, global = FALSE, ind = 1)
    dev.off()
    
    # 5. Visualize perfect binary effects matrix for each logic
    pdf("perfect_binary_effects_matrix.pdf", width = 10, height = 6)
    epiAnno()
    dev.off()
    
    # 6. Save results to files
    saveRDS(res, file = "epiScreen_results.rds")
    
    # Export likelihoods and logics as CSV tables
    if (!is.null(res\$ll)) {
      write.csv(as.data.frame(res\$ll), "log_likelihoods.csv", row.names = TRUE)
    }
    if (!is.null(res\$logic)) {
      write.csv(as.data.frame(res\$logic), "inferred_logics.csv", row.names = TRUE)
    }

    writeLines(c(
        '"BIOC_EPINEM_SYSTEMATIC_MODULATOR_SCREENING":',
        paste0('    epiNEM: ', as.character(packageVersion('epiNEM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_systematic_modulator_screening.csv versions.yml
    """
}

workflow BIOC_EPINEM_SYSTEMATIC_MODULATOR_SCREENING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ large_binary_effects_matrix.csv ] ]

    main:
    BIOC_EPINEM_SYSTEMATIC_MODULATOR_SCREENING(ch_input)

    emit:
    tables   = BIOC_EPINEM_SYSTEMATIC_MODULATOR_SCREENING.out.tables
    plots    = BIOC_EPINEM_SYSTEMATIC_MODULATOR_SCREENING.out.plots
    objects  = BIOC_EPINEM_SYSTEMATIC_MODULATOR_SCREENING.out.objects
    versions = BIOC_EPINEM_SYSTEMATIC_MODULATOR_SCREENING.out.versions
}
