#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: infinityFlow — basic_pipeline
// Run the standard Infinity Flow pipeline using the default XGBoost regression model to predict exploratory marker expression.
// Input: input_dir, backbone_selection_file.csv, steady_state_lung_annotation
// Container: quay.io/biocontainers/bioconductor-infinityflow:1.20.2--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: flowCore, infinityFlow
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load package and example data
//  * 2. [Visualization & Output] Define paths for input, output, and intermediary results
//  * 3. [Input & Preparation] Set up target and isotype annotation vectors
//  * 4. [Core Analysis] Run the pipeline using infinity_flow()

nextflow.enable.dsl = 2

process BIOC_INFINITYFLOW_BASIC_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("infinityFlow", "flowCore")
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
    
    library(infinityFlow)
    library(flowCore)
    
    # Define paths for input, output, and intermediary results
    path_to_fcs <- "input_dir"
    path_to_output <- "output"
    path_to_intermediary_results <- "tmp"
    backbone_selection_file <- "backbone_selection_file.csv"
    
    # Read the annotation file from the working directory
    annotation_file <- "steady_state_lung_annotation"
    if (!file.exists(annotation_file) && file.exists("steady_state_lung_annotation.csv")) {
      annotation_file <- "steady_state_lung_annotation.csv"
    }
    
    steady_state_lung_annotation <- read.csv(annotation_file, row.names = 1, stringsAsFactors = FALSE)
    
    # Set up target and isotype annotation vectors
    targets <- steady_state_lung_annotation\$Infinity_target
    names(targets) <- rownames(steady_state_lung_annotation)
    isotypes <- steady_state_lung_annotation\$Infinity_isotype
    names(isotypes) <- rownames(steady_state_lung_annotation)
    
    # Set downsampling and core parameters
    input_events_downsampling <- 1000
    prediction_events_downsampling <- 500
    cores <- 1L
    
    # Run the pipeline using infinity_flow()
    imputed_data <- infinity_flow(
    	path_to_fcs = path_to_fcs,
    	path_to_output = path_to_output,
    	path_to_intermediary_results = path_to_intermediary_results,
    	backbone_selection_file = backbone_selection_file,
    	annotation = targets,
    	isotype = isotypes,
    	input_events_downsampling = input_events_downsampling,
    	prediction_events_downsampling = prediction_events_downsampling,
    	verbose = TRUE,
    	cores = cores
    )
    
    # Save the final imputed data object
    saveRDS(imputed_data, file = "imputed_data.rds")
    
    # Save background-corrected predictions as a CSV if available
    if (!is.null(imputed_data\$bgc)) {
      write.csv(as.data.frame(imputed_data\$bgc), file = "imputed_data_bgc.csv", row.names = TRUE)
    }
    
    # Save raw predictions as a CSV if available
    if (!is.null(imputed_data\$raw)) {
      write.csv(as.data.frame(imputed_data\$raw), file = "imputed_data_raw.csv", row.names = TRUE)
    }

    writeLines(c(
        '"BIOC_INFINITYFLOW_BASIC_PIPELINE":',
        paste0('    infinityFlow: ', as.character(packageVersion('infinityFlow')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_basic_pipeline.csv versions.yml
    """
}

workflow BIOC_INFINITYFLOW_BASIC_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input_dir, backbone_selection_file.csv, steady_state_lung_annotation ] ]

    main:
    BIOC_INFINITYFLOW_BASIC_PIPELINE(ch_input)

    emit:
    tables   = BIOC_INFINITYFLOW_BASIC_PIPELINE.out.tables
    plots    = BIOC_INFINITYFLOW_BASIC_PIPELINE.out.plots
    objects  = BIOC_INFINITYFLOW_BASIC_PIPELINE.out.objects
    versions = BIOC_INFINITYFLOW_BASIC_PIPELINE.out.versions
}
