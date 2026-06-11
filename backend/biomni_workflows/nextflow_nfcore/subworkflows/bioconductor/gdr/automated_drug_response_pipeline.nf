#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gdr — automated_drug_response_pipeline
// Run the end-to-end drug response processing pipeline automatically to generate a MultiAssayExperiment and extract fitted metrics.
// Input: manifest.xlsx, Template_7daytreated.xlsx, Template_Untreated.xlsx, RawData_day0.xlsx, RawData_day7.xlsx
// Container: quay.io/biocontainers/bioconductor-gdr:1.8.0--r45hdfd78af_0
// R packages: SummarizedExperiment, gDR, kableExtra
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GDR_AUTOMATED_DRUG_RESPONSE_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-gdr:1.8.0--r45hdfd78af_0"

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
    .bm_deps <- c("SummarizedExperiment", "gDR", "kableExtra")
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
    library(gDR)
    library(SummarizedExperiment)
    library(kableExtra)
    
    # Define helper functions to redirect the documented code's path accessors
    # to the exact user-provided files in the working directory.
    manifest_path <- function(td) "manifest.xlsx"
    template_path <- function(td) c("Template_7daytreated.xlsx", "Template_Untreated.xlsx")
    result_path <- function(td) c("RawData_day0.xlsx", "RawData_day7.xlsx")
    
    # Define a dummy td object to match the documented code signature
    td <- "local_working_directory"
    
    # Import data
    imported_data <- 
      import_data(manifest_path(td), template_path(td), result_path(td))
    
    # Run gDR pipeline
    mae <- runDrugResponseProcessingPipeline(imported_data)
    mae
    
    names(mae)
    SummarizedExperiment::assayNames(mae[[1]])
    
    se <- mae[["single-agent"]]
    metrics_dt <- convert_se_assay_to_dt(se, "Metrics")
    head(metrics_dt)
    
    # Save meaningful results to output files
    saveRDS(mae, "mae_output.rds")
    write.csv(metrics_dt, "metrics_output.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_GDR_AUTOMATED_DRUG_RESPONSE_PIPELINE":',
        paste0('        gdr: ', as.character(packageVersion("gdr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_automated_drug_response_pipeline.csv versions.yml
    """
}

workflow BIOC_GDR_AUTOMATED_DRUG_RESPONSE_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ manifest.xlsx, Template_7daytreated.xlsx, Template_Untreated.xlsx, RawData_day0.xlsx, RawData_day7.xlsx ] ]

    main:
    BIOC_GDR_AUTOMATED_DRUG_RESPONSE_PIPELINE(ch_input)

    emit:
    tables   = BIOC_GDR_AUTOMATED_DRUG_RESPONSE_PIPELINE.out.tables
    plots    = BIOC_GDR_AUTOMATED_DRUG_RESPONSE_PIPELINE.out.plots
    objects  = BIOC_GDR_AUTOMATED_DRUG_RESPONSE_PIPELINE.out.objects
    versions = BIOC_GDR_AUTOMATED_DRUG_RESPONSE_PIPELINE.out.versions
}
