#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RadioGx — biomarker_discovery_signatures
// Correlate molecular features with radiation sensitivity profiles to identify biomarkers of radio-sensitivity or radio-resistance.
// Input: radio_set.RData
// Container: quay.io/biocontainers/bioconductor-radiogx:2.14.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RadioGx, SummarizedExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Summarize sensitivity profiles across cell lines using summarizeSensitivityProfiles
//  * 2. [Visualization & Output] Summarize molecular profiles using summarizeMolecularProfiles
//  * 3. [Core Analysis] Compute radiation sensitivity signatures for specific features using radSensitivitySig

nextflow.enable.dsl = 2

process BIOC_RADIOGX_BIOMARKER_DISCOVERY_SIGNATURES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("RadioGx")
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
        library(RadioGx)
        
        # -----------------------------------------------------------------------------
        # Stage 0: Load the User-Provided RadioSet Object
        # -----------------------------------------------------------------------------
        if (!file.exists("radio_set.RData")) {
          stop("Error: Required input file 'radio_set.RData' not found in the working directory.")
        }
        
        # Load the RData file into a temporary environment to locate the RadioSet object
        temp_env <- new.env()
        load("radio_set.RData", envir = temp_env)
        
        # Identify the RadioSet (or CoreSet) object
        rset_name <- NULL
        for (name in ls(temp_env)) {
          if (inherits(temp_env[[name]], "RadioSet") || inherits(temp_env[[name]], "CoreSet")) {
            rset_name <- name
            break
          }
        }
        
        if (is.null(rset_name)) {
          stop("Error: No RadioSet or CoreSet object found in 'radio_set.RData'.")
        }
        
        # Assign to clevelandSmall to match the documented code exactly
        clevelandSmall <- temp_env[[rset_name]]
        
        # -----------------------------------------------------------------------------
        # Stage 1: Summarize sensitivity profiles across cell lines
        # -----------------------------------------------------------------------------
        sensSummary <- summarizeSensitivityProfiles(clevelandSmall)
        
        # Save sensitivity summary to a CSV file
        write.csv(as.data.frame(sensSummary), file = "sensitivity_summary.csv", row.names = TRUE)
        
        # -----------------------------------------------------------------------------
        # Stage 2: Summarize molecular profiles
        # -----------------------------------------------------------------------------
        mdata_names <- mDataNames(clevelandSmall)
        if (length(mdata_names) == 0) {
          stop("Error: No molecular data types available in the provided RadioSet.")
        }
        mDataType_val <- mdata_names[1]
        
        mprofSummary <- summarizeMolecularProfiles(
          clevelandSmall, 
          mDataType = mDataType_val, 
          summary.stat = 'median', 
          fill.missing = FALSE
        )
        
        # Save the summarized molecular profiles (SummarizedExperiment) as an RDS file
        saveRDS(mprofSummary, file = "molecular_profile_summary.rds")
        
        # -----------------------------------------------------------------------------
        # Stage 3: Compute radiation sensitivity signatures for specific features
        # -----------------------------------------------------------------------------
        # Ensure the requested features exist in the dataset before running
        available_features <- fNames(clevelandSmall, mDataType_val)
        if (length(available_features) == 0) {
          stop("Error: The loaded RadioSet does not contain any features to run the signature analysis.")
        }
        
        radSensSig <- radSensitivitySig(
          clevelandSmall, 
          mDataType = mDataType_val, 
          features = available_features, 
          nthread = 1
        )
        
        # Extract the underlying data array
        sig_data <- radSensSig@.Data
        
        # Save the signature object and its underlying data
        saveRDS(radSensSig, file = "radiation_sensitivity_signature.rds")
        saveRDS(sig_data, file = "radiation_sensitivity_signature_data.rds")
        
        # Print a message indicating successful completion
        cat("Workflow completed successfully. Outputs saved:\n")
        cat("- sensitivity_summary.csv\n")
        cat("- molecular_profile_summary.rds\n")
        cat("- radiation_sensitivity_signature.rds\n")
        cat("- radiation_sensitivity_signature_data.rds\n")

    writeLines(c(
        '"BIOC_RADIOGX_BIOMARKER_DISCOVERY_SIGNATURES":',
        paste0('    RadioGx: ', as.character(packageVersion('RadioGx')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biomarker_discovery_signatures.csv versions.yml
    """
}

workflow BIOC_RADIOGX_BIOMARKER_DISCOVERY_SIGNATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ radio_set.RData ] ]

    main:
    BIOC_RADIOGX_BIOMARKER_DISCOVERY_SIGNATURES(ch_input)

    emit:
    tables   = BIOC_RADIOGX_BIOMARKER_DISCOVERY_SIGNATURES.out.tables
    plots    = BIOC_RADIOGX_BIOMARKER_DISCOVERY_SIGNATURES.out.plots
    objects  = BIOC_RADIOGX_BIOMARKER_DISCOVERY_SIGNATURES.out.objects
    versions = BIOC_RADIOGX_BIOMARKER_DISCOVERY_SIGNATURES.out.versions
}
