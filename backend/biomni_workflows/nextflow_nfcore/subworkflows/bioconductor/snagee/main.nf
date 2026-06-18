#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SNAGEE — study_quality_assessment
// Estimate the overall signal-to-noise ratio (SNR) of a gene expression study to assess its quality.
// Input: ALL
// Container: quay.io/biocontainers/bioconductor-snagee:1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, SNAGEE
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the SNAGEE package and the dataset. 2. Calculate the study-level quality score using qualStudy. 3. Print the resulting SNR sc

nextflow.enable.dsl = 2

process BIOC_SNAGEE_STUDY_QUALITY_ASSESSMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("SNAGEE", "Biobase")
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
    library(SNAGEE)
    library(Biobase)
    
    # Read the user input file 'ALL' from the working directory
    # Supports RDS format (containing ExpressionSet or matrix) or CSV format
    if (file.exists("ALL.rds")) {
      ALL <- readRDS("ALL.rds")
    } else if (file.exists("ALL")) {
      ALL <- tryCatch({
        readRDS("ALL")
      }, error = function(e) {
        as.matrix(read.csv("ALL", row.names = 1, check.names = FALSE))
      })
    } else if (file.exists("ALL.csv")) {
      ALL <- as.matrix(read.csv("ALL.csv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: User input file 'ALL' (as RDS or CSV) not found in the working directory.")
    }
    
    # Calculate the study-level quality score using qualStudy
    q = qualStudy(ALL)
    
    # Print the resulting SNR score
    print(q)
    
    # Write the meaningful results to an output file
    write.csv(data.frame(SNR = q), "study_snr.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_SNAGEE_STUDY_QUALITY_ASSESSMENT":',
        paste0('    SNAGEE: ', as.character(packageVersion('SNAGEE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_study_quality_assessment.csv versions.yml
    """
}

workflow BIOC_SNAGEE_STUDY_QUALITY_ASSESSMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ALL ] ]

    main:
    BIOC_SNAGEE_STUDY_QUALITY_ASSESSMENT(ch_input)

    emit:
    tables   = BIOC_SNAGEE_STUDY_QUALITY_ASSESSMENT.out.tables
    plots    = BIOC_SNAGEE_STUDY_QUALITY_ASSESSMENT.out.plots
    objects  = BIOC_SNAGEE_STUDY_QUALITY_ASSESSMENT.out.objects
    versions = BIOC_SNAGEE_STUDY_QUALITY_ASSESSMENT.out.versions
}
