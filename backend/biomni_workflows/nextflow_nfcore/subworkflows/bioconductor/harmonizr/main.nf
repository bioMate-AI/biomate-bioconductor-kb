#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HarmonizR — batch_correction_dataframe
// Perform batch effect correction on a data frame containing missing values using ComBat or limma.
// Input: df, des
// Container: quay.io/biocontainers/bioconductor-harmonizr:1.8.0--r45hdfd78af_0
// R packages: HarmonizR
// Bioconductor: 3.20 | R: 4.4
// Requires: HarmonizR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare the input data frame and sample description data frame
//  * 2. [Core Analysis] Run the harmonizR function to perform matrix dissection and batch effect correction

nextflow.enable.dsl = 2

process BIOC_HARMONIZR_BATCH_CORRECTION_DATAFRAME {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("HarmonizR")
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
    
    # Load the required library
    library(HarmonizR)
    
    # 1. Prepare the input data frame and sample description data frame
    # Read the molecular features data frame (samples as columns, features as rows)
    if (file.exists("df.csv")) {
      df <- read.csv("df.csv", row.names = 1, check.names = FALSE)
    } else if (file.exists("df.tsv")) {
      df <- read.delim("df.tsv", row.names = 1, check.names = FALSE)
    } else {
      stop("Required input file 'df.csv' or 'df.tsv' not found in the working directory.")
    }
    
    # Read the description data frame mapping sample IDs to their respective batches
    if (file.exists("des.csv")) {
      des <- read.csv("des.csv", check.names = FALSE)
    } else if (file.exists("des.tsv")) {
      des <- read.delim("des.tsv", check.names = FALSE)
    } else {
      stop("Required input file 'des.csv' or 'des.tsv' not found in the working directory.")
    }
    
    # Ensure df is a data.frame
    df <- as.data.frame(df)
    des <- as.data.frame(des)
    
    # 2. Run the harmonizR function to perform matrix dissection and batch effect correction
    result <- harmonizR(df, des, output_file = FALSE, cores = 1)
    
    # 3. Write the meaningful results to output files
    write.csv(result, "harmonized_result.csv", row.names = TRUE)
    saveRDS(result, "harmonized_result.rds")

    writeLines(c(
        '"BIOC_HARMONIZR_BATCH_CORRECTION_DATAFRAME":',
        paste0('    HarmonizR: ', as.character(packageVersion('HarmonizR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_batch_correction_dataframe.csv versions.yml
    """
}

workflow BIOC_HARMONIZR_BATCH_CORRECTION_DATAFRAME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ df, des ] ]

    main:
    BIOC_HARMONIZR_BATCH_CORRECTION_DATAFRAME(ch_input)

    emit:
    tables   = BIOC_HARMONIZR_BATCH_CORRECTION_DATAFRAME.out.tables
    plots    = BIOC_HARMONIZR_BATCH_CORRECTION_DATAFRAME.out.plots
    objects  = BIOC_HARMONIZR_BATCH_CORRECTION_DATAFRAME.out.objects
    versions = BIOC_HARMONIZR_BATCH_CORRECTION_DATAFRAME.out.versions
}
