#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: biosigner — summarized_experiment_analysis
// Perform feature selection directly on a SummarizedExperiment object, updating the container with feature tiers and retrieving the trained models.
// Input: dia.se
// Container: quay.io/biocontainers/bioconductor-biosigner:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, biosigner
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read the user input SummarizedExperiment object
//  * 2. [Visualization & Output] Run feature selection using biosign, specifying the
//  * 3. [Visualization & Output] Extract the updated rowData containing the assigned
//  * 4. [Visualization & Output] Retrieve the trained biosign models from the metadata
//  * 5. [Visualization & Output] Plot the feature tiers for the selected classifiers and
//  * 6. [Visualization & Output] Write meaningful results to output files

nextflow.enable.dsl = 2

process BIOC_BIOSIGNER_SUMMARIZED_EXPERIMENT_ANALYSIS {
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
    library(biosigner)
    
    # --- Read the user input SummarizedExperiment object ---
    dia.se <- readRDS("dia.se")
    
    # Dynamically determine the response variable (assuming it is the first column in colData)
    response_var <- colnames(colData(dia.se))[1]
    
    # --- Run feature selection using biosign, specifying the ---
    # Removed 'bootI = 5' to use the default 50 bootstraps for stable signatures
    dia.se <- biosign(dia.se, response_var)
    
    # --- Extract the updated rowData containing the assigned ---
    feat.DF <- SummarizedExperiment::rowData(dia.se)
    
    # --- Retrieve the trained biosign models from the metadata ---
    dia_type.biosign <- getBiosign(dia.se)
    
    # --- Plot the feature tiers for the selected classifiers and ---
    pdf("feature_tiers_plot.pdf", width = 7, height = 7)
    # Dynamically extract the model name to avoid hardcoding
    model_name <- names(dia_type.biosign)[1]
    plot(dia_type.biosign[[model_name]], typeC = "tier")
    dev.off()
    
    # --- Write meaningful results to output files ---
    # Save the updated SummarizedExperiment object
    saveRDS(dia.se, "dia_se_updated.rds")
    
    # Save the extracted feature tiers as a CSV table
    write.csv(as.data.frame(feat.DF), "feature_tiers.csv", row.names = TRUE)
    
    # Save the retrieved biosign models
    saveRDS(dia_type.biosign, "dia_type_biosign.rds")

    writeLines(c(
        '"BIOC_BIOSIGNER_SUMMARIZED_EXPERIMENT_ANALYSIS":',
        paste0('    biosigner: ', as.character(packageVersion('biosigner')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_summarized_experiment_analysis.csv versions.yml
    """
}

workflow BIOC_BIOSIGNER_SUMMARIZED_EXPERIMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dia.se ] ]

    main:
    BIOC_BIOSIGNER_SUMMARIZED_EXPERIMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BIOSIGNER_SUMMARIZED_EXPERIMENT_ANALYSIS.out.tables
    plots    = BIOC_BIOSIGNER_SUMMARIZED_EXPERIMENT_ANALYSIS.out.plots
    objects  = BIOC_BIOSIGNER_SUMMARIZED_EXPERIMENT_ANALYSIS.out.objects
    versions = BIOC_BIOSIGNER_SUMMARIZED_EXPERIMENT_ANALYSIS.out.versions
}
