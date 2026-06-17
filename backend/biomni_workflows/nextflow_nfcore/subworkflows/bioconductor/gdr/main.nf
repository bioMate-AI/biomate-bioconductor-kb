#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gdr — step_by_step_drug_response_processing
// Manually aggregate, normalize, average, and fit drug response data step-by-step to maintain granular control over intermediate SummarizedExperiment objects.
// Input: manifest.xlsx, Template_7daytreated.xlsx, Template_Untreated.xlsx, RawData_day0.xlsx, RawData_day7.xlsx
// Container: quay.io/biocontainers/bioconductor-gdr:1.8.0--r45hdfd78af_0
// R packages: SummarizedExperiment, gDRimport, gDRutils, gDR, kableExtra
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GDR_STEP_BY_STEP_DRUG_RESPONSE_PROCESSING {
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
    .bm_deps <- c("SummarizedExperiment", "gDRimport", "gDRutils", "gDR", "kableExtra")
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
    library(gDR)
    library(gDRimport)
    library(gDRutils)
    library(SummarizedExperiment)
    
    # Define helper functions to redirect the documented path functions to the user input files
    manifest_path <- function(td) "manifest.xlsx"
    template_path <- function(td) c("Template_7daytreated.xlsx", "Template_Untreated.xlsx")
    result_path <- function(td) c("RawData_day0.xlsx", "RawData_day7.xlsx")
    
    # Initialize dummy td object to avoid using package demo data
    td <- "user_input_data"
    
    # Import data
    imported_data <- 
      import_data(manifest_path(td), template_path(td), result_path(td))
    head(imported_data)
    
    # Save imported raw data
    write.csv(imported_data, "imported_raw_data.csv", row.names = FALSE)
    
    # Prepare input
    inl <- prepare_input(imported_data)
    detected_data_types <- names(inl\$exps)
    detected_data_types
    
    # Create and normalize SE
    se <- create_and_normalize_SE(
      inl\$df_list[["single-agent"]],
      data_type = "single-agent",
      nested_confounders = inl\$nested_confounders)
    se
    
    # Average SE
    se <- average_SE(se, data_type = "single-agent")
    
    # Fit SE
    se <- fit_SE(se, data_type = "single-agent")
    se
    
    # Save the final SummarizedExperiment object
    saveRDS(se, "single_agent_se.rds")
    
    # Convert Metrics assay to data.frame/data.table and save as CSV
    metrics_dt <- convert_se_assay_to_dt(se, "Metrics")
    write.csv(metrics_dt, "single_agent_metrics.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_GDR_STEP_BY_STEP_DRUG_RESPONSE_PROCESSING":',
        paste0('        gdr: ', as.character(packageVersion("gdr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_step_by_step_drug_response_processing.csv versions.yml
    """
}

workflow BIOC_GDR_STEP_BY_STEP_DRUG_RESPONSE_PROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ manifest.xlsx, Template_7daytreated.xlsx, Template_Untreated.xlsx, RawData_day0.xlsx, RawData_day7.xlsx ] ]

    main:
    BIOC_GDR_STEP_BY_STEP_DRUG_RESPONSE_PROCESSING(ch_input)

    emit:
    tables   = BIOC_GDR_STEP_BY_STEP_DRUG_RESPONSE_PROCESSING.out.tables
    plots    = BIOC_GDR_STEP_BY_STEP_DRUG_RESPONSE_PROCESSING.out.plots
    objects  = BIOC_GDR_STEP_BY_STEP_DRUG_RESPONSE_PROCESSING.out.objects
    versions = BIOC_GDR_STEP_BY_STEP_DRUG_RESPONSE_PROCESSING.out.versions
}
