#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MSPrep — dataframe_pipeline
// Pre-process mass spectrometry metabolomics data stored in a Data Frame format through summarization, filtering, imputation, and normalization.
// Input: metabolomics_df.csv
// Container: quay.io/biocontainers/bioconductor-msprep:1.20.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MSPrep
// QC: batch-effect correction, missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Summarize technical replicates using msSummarize()
//  * 2. [Core Analysis] Filter compounds based on presence threshold using msFilter()
//  * 3. [Core Analysis] Impute missing values using msImpute()
//  * 4. [Core Analysis] Transform and normalize data using msNormalize()
//  * 5. [Core Analysis] Alternatively, run the entire pipeline in one step using msPrepare()

nextflow.enable.dsl = 2

process BIOC_MSPREP_DATAFRAME_PIPELINE {
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
    .bm_deps <- c("MSPrep")
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
            
            # Load required library
            library(MSPrep)
            
            # Read user input file
            # The file must have the same structure as the 'msquant' dataset
            msquant <- read.csv("metabolomics_df.csv", check.names = FALSE, stringsAsFactors = FALSE)
            
            # 1. Summarize technical replicates
            summarizedDF <- msSummarize(msquant,
                                        cvMax = 0.50,
                                        minPropPresent = 1/3,
                                        compVars = c("mz", "rt"),
                                        sampleVars = c("batch", "replicate", "subject_id"),
                                        separator = "_",
                                        missingValue = 1)
            
            # 2. Filter compounds based on presence threshold
            filteredDF <- msFilter(summarizedDF,
                                   filterPercent = 0.8,
                                   compVars = c("mz", "rt"),
                                   sampleVars = c("batch", "subject_id"),
                                   separator = "_")
            
            # 3. Impute missing values
            imputedDF <- msImpute(filteredDF,
                                  imputeMethod = "knn",
                                  compVars = c("mz", "rt"),
                                  sampleVars = c("batch", "subject_id"),
                                  separator = "_",
                                  returnToSE = FALSE,
                                  missingValue = 0)
            
            # 4. Transform and normalize data
            normalizedDF <- msNormalize(imputedDF,
                                        normalizeMethod = "quantile + ComBat",
                                        transform = "log10",
                                        compVars = c("mz", "rt"),
                                        sampleVars = c("batch", "subject_id"),
                                        separator = "_")
            
            # 5. Alternatively, run the entire pipeline in one step
            preparedDF <- msPrepare(msquant,
                                    cvMax = 0.50,
                                    minPropPresent = 1/3,
                                    filterPercent = 0.8,
                                    imputeMethod = "knn",
                                    normalizeMethod = "quantile + ComBat",
                                    transform = "log10",
                                    compVars = c("mz", "rt"),
                                    sampleVars = c("batch", "replicate", "subject_id"),
                                    separator = "_",
                                    missingValue = 1,
                                    returnToSE = FALSE)
            
            # Save outputs to CSV files
            write.csv(summarizedDF, "summarized_metabolomics.csv", row.names = FALSE)
            write.csv(filteredDF, "filtered_metabolomics.csv", row.names = FALSE)
            write.csv(imputedDF, "imputed_metabolomics.csv", row.names = FALSE)
            write.csv(normalizedDF, "normalized_metabolomics.csv", row.names = FALSE)
            write.csv(preparedDF, "prepared_metabolomics.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_MSPREP_DATAFRAME_PIPELINE":',
        paste0('    MSPrep: ', as.character(packageVersion('MSPrep')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dataframe_pipeline.csv versions.yml
    """
}

workflow BIOC_MSPREP_DATAFRAME_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ metabolomics_df.csv ] ]

    main:
    BIOC_MSPREP_DATAFRAME_PIPELINE(ch_input)

    emit:
    tables   = BIOC_MSPREP_DATAFRAME_PIPELINE.out.tables
    plots    = BIOC_MSPREP_DATAFRAME_PIPELINE.out.plots
    objects  = BIOC_MSPREP_DATAFRAME_PIPELINE.out.objects
    versions = BIOC_MSPREP_DATAFRAME_PIPELINE.out.versions
}
