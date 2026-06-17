#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GAprediction — gestational_age_prediction
// Predict gestational age from blood DNA methylation data.
// Input: mlmatr
// Container: quay.io/biocontainers/bioconductor-gaprediction:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GAprediction
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract required CpG sites using extractSites
//  * 2. [Input & Preparation] Prepare the input matrix ensuring no NAs in required CpGs
//  * 3. [Core Analysis] Predict gestational age using predictGA

nextflow.enable.dsl = 2

process BIOC_GAPREDICTION_GESTATIONAL_AGE_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("GAprediction")
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
    
    # Load required package
    library(GAprediction)
    
    # 1. Read the user input file 'mlmatr' from the working directory.
    # We support CSV and RDS formats.
    if (file.exists("mlmatr.csv")) {
      mlmatr <- read.csv("mlmatr.csv", row.names = 1, check.names = FALSE)
    } else if (file.exists("mlmatr.rds")) {
      mlmatr <- readRDS("mlmatr.rds")
    } else {
      stop("Error: Input file 'mlmatr.csv' or 'mlmatr.rds' not found in the working directory.")
    }
    
    # Ensure mlmatr is a data frame
    mlmatr <- as.data.frame(mlmatr)
    
    # 2. Extract required CpG sites
    cpgs <- extractSites( type="se" )
    allcpgs <- extractSites( type="all" )
    
    # 3. Prepare the input matrix ensuring no NAs in required CpGs
    # Check if required CpGs are present in the input data
    missing_cpgs <- setdiff(cpgs, colnames(mlmatr))
    if (length(missing_cpgs) > 0) {
      message("Warning: Some required CpGs are missing. Adding them with default beta value of 0.5.")
      for (cg in missing_cpgs) {
        mlmatr[[cg]] <- 0.5
      }
    }
    
    # Ensure no NA values exist in the required CpG columns
    for (cg in cpgs) {
      if (any(is.na(mlmatr[[cg]]))) {
        # Impute NA values with 0.5 (neutral beta value)
        mlmatr[[cg]][is.na(mlmatr[[cg]])] <- 0.5
      }
    }
    
    # 4. Predict gestational age
    mypred <- predictGA( mlmatr )
    
    # Display the first few predictions
    print("First few predictions:")
    print(head( mypred ))
    
    # 5. Save the results to a CSV file
    write.csv(mypred, "predicted_gestational_age.csv", row.names = TRUE)
    message("Predictions successfully saved to 'predicted_gestational_age.csv'.")

    writeLines(c(
        '"BIOC_GAPREDICTION_GESTATIONAL_AGE_PREDICTION":',
        paste0('    GAprediction: ', as.character(packageVersion('GAprediction')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gestational_age_prediction.csv versions.yml
    """
}

workflow BIOC_GAPREDICTION_GESTATIONAL_AGE_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mlmatr ] ]

    main:
    BIOC_GAPREDICTION_GESTATIONAL_AGE_PREDICTION(ch_input)

    emit:
    tables   = BIOC_GAPREDICTION_GESTATIONAL_AGE_PREDICTION.out.tables
    plots    = BIOC_GAPREDICTION_GESTATIONAL_AGE_PREDICTION.out.plots
    objects  = BIOC_GAPREDICTION_GESTATIONAL_AGE_PREDICTION.out.objects
    versions = BIOC_GAPREDICTION_GESTATIONAL_AGE_PREDICTION.out.versions
}
