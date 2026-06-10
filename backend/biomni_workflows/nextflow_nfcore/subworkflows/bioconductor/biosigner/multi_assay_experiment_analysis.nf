#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: biosigner — multi_assay_experiment_analysis
// Perform parallel feature selection across multiple omics datasets stored within a MultiAssayExperiment object.
// Input: nci.mae
// Container: quay.io/biocontainers/bioconductor-biosigner:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MultiAssayExperiment, SummarizedExperiment, biosigner
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Run feature selection using biosign on the MultiAssayExperiment, specifying the response variable. 2. Extract the updated rowData 

nextflow.enable.dsl = 2

process BIOC_BIOSIGNER_MULTI_ASSAY_EXPERIMENT_ANALYSIS {
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
    library(MultiAssayExperiment)
    
    # Read the input MultiAssayExperiment object from the working directory
    nci.mae <- readRDS("nci.mae")
    
    # Dynamically determine the response variable (assuming it's the first column in colData)
    response_var <- colnames(colData(nci.mae))[1]
    
    # Perform feature selection using biosign on the MultiAssayExperiment
    nci.mae <- biosign(nci.mae, response_var, bootI = 5)
    
    # Extract the updated rowData containing feature tiers from individual experiments
    # and save the extracted rowData to a CSV file for each experiment
    for (exp_name in names(nci.mae)) {
      exp_rowdata <- SummarizedExperiment::rowData(nci.mae[[exp_name]])
      write.csv(as.data.frame(exp_rowdata), paste0(exp_name, "_biosign_results.csv"), row.names = TRUE)
    }
    
    # Retrieve the list of trained biosign models from the metadata of individual experiments
    mae_biosign.ls <- getBiosign(nci.mae)
    
    # Plot the feature tiers for each experiment and save to a PDF
    pdf("biosigner_tier_plots.pdf", width = 8, height = 8)
    for (set.c in names(mae_biosign.ls)) {
      # Dynamically get the model name rather than hardcoding it
      model_name <- names(mae_biosign.ls[[set.c]])[1]
      plot(mae_biosign.ls[[set.c]][[model_name]],
           typeC = "tier",
           plotSubC = set.c)
    }
    dev.off()
    
    # Save the updated MultiAssayExperiment object
    saveRDS(nci.mae, "nci_mae_biosign_results.rds")

    writeLines(c(
        '"BIOC_BIOSIGNER_MULTI_ASSAY_EXPERIMENT_ANALYSIS":',
        paste0('    biosigner: ', as.character(packageVersion('biosigner')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_assay_experiment_analysis.csv versions.yml
    """
}

workflow BIOC_BIOSIGNER_MULTI_ASSAY_EXPERIMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ nci.mae ] ]

    main:
    BIOC_BIOSIGNER_MULTI_ASSAY_EXPERIMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BIOSIGNER_MULTI_ASSAY_EXPERIMENT_ANALYSIS.out.tables
    plots    = BIOC_BIOSIGNER_MULTI_ASSAY_EXPERIMENT_ANALYSIS.out.plots
    objects  = BIOC_BIOSIGNER_MULTI_ASSAY_EXPERIMENT_ANALYSIS.out.objects
    versions = BIOC_BIOSIGNER_MULTI_ASSAY_EXPERIMENT_ANALYSIS.out.versions
}
