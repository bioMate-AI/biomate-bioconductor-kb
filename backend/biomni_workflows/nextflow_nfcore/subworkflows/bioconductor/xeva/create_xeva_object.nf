#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Xeva — create_xeva_object
// Create a new custom XevaSet object from raw experimental, metadata, and molecular profiling tables.
// Input: model.csv, drug.csv, experiments.csv, batch_list.rds, rnaseq.rds, modelToExpressionMap.csv
// Container: quay.io/biocontainers/bioconductor-xeva:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, Xeva
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read model metadata, drug metadata, and time-volume
//  * 2. [Input & Preparation] Read experimental design batch list
//  * 3. [Input & Preparation] Read molecular profiles (ExpressionSet)
//  * 4. [Input & Preparation] Read the mapping table between model IDs and molecular
//  * 5. [Input & Preparation] Construct the XevaSet using createXevaSet
//  * 6. [Input & Preparation] Write named output files for the meaningful results

nextflow.enable.dsl = 2

process BIOC_XEVA_CREATE_XEVA_OBJECT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    library(Xeva)
    library(Biobase)
    
    # --- Read model metadata, drug metadata, and time-volume ---
    if (!file.exists("model.csv")) {
      stop("Required input file 'model.csv' not found in the working directory.")
    }
    model <- read.csv("model.csv")
    head(model)
    
    if (!file.exists("drug.csv")) {
      stop("Required input file 'drug.csv' not found in the working directory.")
    }
    drug <- read.csv("drug.csv")
    head(drug)
    
    if (!file.exists("experiments.csv")) {
      stop("Required input file 'experiments.csv' not found in the working directory.")
    }
    experiment <- read.csv("experiments.csv")
    head(experiment)
    
    # --- Read experimental design batch list ---
    if (!file.exists("batch_list.rds")) {
      stop("Required input file 'batch_list.rds' not found in the working directory.")
    }
    expDesign <- readRDS("batch_list.rds")
    if (length(expDesign) > 0) {
      print(expDesign[[1]])
    }
    
    # --- Read molecular profiles (ExpressionSet) ---
    if (!file.exists("rnaseq.rds")) {
      stop("Required input file 'rnaseq.rds' not found in the working directory.")
    }
    RNASeq <- readRDS("rnaseq.rds")
    print(RNASeq)
    
    # --- Read the mapping table between model IDs and molecular ---
    if (!file.exists("modelToExpressionMap.csv")) {
      stop("Required input file 'modelToExpressionMap.csv' not found in the working directory.")
    }
    modToBiobaseMap <- read.csv("modelToExpressionMap.csv")
    head(modToBiobaseMap)
    
    # --- Construct the XevaSet using createXevaSet ---
    xeva.set <- createXevaSet(
      name = "example xevaSet",
      model = model,
      drug = drug,
      experiment = experiment,
      expDesign = expDesign,
      molecularProfiles = list(RNASeq = RNASeq),
      modToBiobaseMap = modToBiobaseMap
    )
    
    print(xeva.set)
    
    # --- Write named output files for the meaningful results ---
    saveRDS(xeva.set, file = "xeva_set.rds")
    
    # Save a text summary of the created XevaSet
    sink("xeva_set_summary.txt")
    cat("=== XevaSet Summary ===\n")
    print(xeva.set)
    cat("\n=== Model Info (First 6 rows) ===\n")
    print(head(modelInfo(xeva.set)))
    sink()
    
    cat("Pipeline completed successfully. Outputs saved to 'xeva_set.rds' and 'xeva_set_summary.txt'.\n")

    writeLines(c(
        '"BIOC_XEVA_CREATE_XEVA_OBJECT":',
        paste0('    Xeva: ', as.character(packageVersion('Xeva')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_create_xeva_object.csv versions.yml
    """
}

workflow BIOC_XEVA_CREATE_XEVA_OBJECT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ model.csv, drug.csv, experiments.csv, batch_list.rds, rnaseq.rds, modelToExpressionMap.csv ] ]

    main:
    BIOC_XEVA_CREATE_XEVA_OBJECT(ch_input)

    emit:
    tables   = BIOC_XEVA_CREATE_XEVA_OBJECT.out.tables
    plots    = BIOC_XEVA_CREATE_XEVA_OBJECT.out.plots
    objects  = BIOC_XEVA_CREATE_XEVA_OBJECT.out.objects
    versions = BIOC_XEVA_CREATE_XEVA_OBJECT.out.versions
}
