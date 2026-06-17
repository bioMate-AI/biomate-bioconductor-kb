#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ropls — multi_assay_experiment_workflow
// Build PLS-DA models in parallel for multiple datasets within a MultiAssayExperiment.
// Input: MultiAssayExperiment object
// Container: quay.io/biocontainers/bioconductor-ropls:1.42.0--r45hdfd78af_0
// R packages: MultiAssayExperiment, SummarizedExperiment, ropls
// Bioconductor: 3.20 | R: 4.4
// Requires: MultiAssayExperiment, SummarizedExperiment, ropls
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run PLS-DA using opls on the MultiAssayExperiment
//  * 2. [Core Analysis] Extract individual models
//  * 3. [Visualization & Output] Plot scores for a specific dataset

nextflow.enable.dsl = 2

process BIOC_ROPLS_MULTI_ASSAY_EXPERIMENT_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("MultiAssayExperiment", "SummarizedExperiment", "ropls")
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
    library(ropls)
    library(SummarizedExperiment)
    library(MultiAssayExperiment)
    
    # 1. Read the user input MultiAssayExperiment object
    # The pipeline expects 'nci_mae.rds' in the working directory.
    input_file <- "nci_mae.rds"
    if (!file.exists(input_file)) {
      stop(paste("Input file", input_file, "not found in the working directory."))
    }
    
    nci.mae <- readRDS(input_file)
    
    # Dynamically determine the response variable (using the first column of colData)
    response_var <- colnames(colData(nci.mae))[1]
    
    # 2. Run PLS-DA using opls on the MultiAssayExperiment
    nci.mae <- opls(nci.mae, response_var, predI = 2, fig.pdfC = "none")
    
    # Dynamically determine the first assay name
    assay_name <- names(nci.mae)[1]
    
    # Extract and save colData for the dynamically selected dataset
    assay_coldata <- SummarizedExperiment::colData(nci.mae[[assay_name]])
    write.csv(as.data.frame(assay_coldata), paste0(assay_name, "_colData_updated.csv"), row.names = TRUE)
    
    # 3. Extract individual models
    mae_opls.ls <- getOpls(nci.mae)
    
    # Save the updated MultiAssayExperiment and the extracted models list
    saveRDS(nci.mae, "nci_mae_updated.rds")
    saveRDS(mae_opls.ls, "mae_opls_models.rds")
    
    # Dynamically determine the model name for the selected assay
    model_name <- names(mae_opls.ls[[assay_name]])[1]
    
    # 4. Plot scores for a specific dataset and save as PDF
    pdf(paste0(assay_name, "_", model_name, "_xscore.pdf"), width = 7, height = 7)
    plot(mae_opls.ls[[assay_name]][[model_name]], typeVc = "x-score")
    dev.off()
    
    message(paste0("Pipeline completed successfully. Outputs saved: '", assay_name, "_colData_updated.csv', 'nci_mae_updated.rds', 'mae_opls_models.rds', and '", assay_name, "_", model_name, "_xscore.pdf'."))

    writeLines(c(
        '"BIOC_ROPLS_MULTI_ASSAY_EXPERIMENT_WORKFLOW":',
        paste0('    ropls: ', as.character(packageVersion('ropls')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_assay_experiment_workflow.csv versions.yml
    """
}

workflow BIOC_ROPLS_MULTI_ASSAY_EXPERIMENT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ MultiAssayExperiment object ] ]

    main:
    BIOC_ROPLS_MULTI_ASSAY_EXPERIMENT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_ROPLS_MULTI_ASSAY_EXPERIMENT_WORKFLOW.out.tables
    plots    = BIOC_ROPLS_MULTI_ASSAY_EXPERIMENT_WORKFLOW.out.plots
    objects  = BIOC_ROPLS_MULTI_ASSAY_EXPERIMENT_WORKFLOW.out.objects
    versions = BIOC_ROPLS_MULTI_ASSAY_EXPERIMENT_WORKFLOW.out.versions
}
