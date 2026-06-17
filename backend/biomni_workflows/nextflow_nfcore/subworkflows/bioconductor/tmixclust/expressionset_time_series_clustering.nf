#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TMixClust — expressionset_time_series_clustering
// Extract time series gene expression data from a Biobase ExpressionSet object for downstream clustering.
// Input: sos
// Container: quay.io/biocontainers/bioconductor-tmixclust:1.32.0--r45hdfd78af_0
// R packages: Biobase, TMixClust
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, TMixClust
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the ExpressionSet object
//  * 2. [Core Analysis] Convert the ExpressionSet object to a compatible data frame using get_time_series_df_bio

nextflow.enable.dsl = 2

process BIOC_TMIXCLUST_EXPRESSIONSET_TIME_SERIES_CLUSTERING {
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
    .bm_deps <- c("Biobase", "TMixClust")
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
    library(TMixClust)
    library(Biobase)
    
    # 1. Load the ExpressionSet object from the user input file 'sos'
    # We assume the file 'sos' is an RDS file containing the Biobase ExpressionSet object.
    if (file.exists("sos")) {
      sos <- readRDS("sos")
    } else if (file.exists("sos.rds")) {
      sos <- readRDS("sos.rds")
    } else {
      stop("Error: Required input file 'sos' or 'sos.rds' not found in the working directory.")
    }
    
    # 2. Convert the ExpressionSet object to a compatible data frame using get_time_series_df_bio
    sos_data = get_time_series_df_bio(sos)
    
    # Print the first lines of the retrieved time series data frame
    print(head(sos_data))
    
    # 3. Save the meaningful results to output files
    write.csv(sos_data, "sos_data_time_series.csv", row.names = TRUE)
    saveRDS(sos_data, "sos_data_time_series.rds")

    writeLines(c(
        '"BIOC_TMIXCLUST_EXPRESSIONSET_TIME_SERIES_CLUSTERING":',
        paste0('    TMixClust: ', as.character(packageVersion('TMixClust')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_expressionset_time_series_clustering.csv versions.yml
    """
}

workflow BIOC_TMIXCLUST_EXPRESSIONSET_TIME_SERIES_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sos ] ]

    main:
    BIOC_TMIXCLUST_EXPRESSIONSET_TIME_SERIES_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_TMIXCLUST_EXPRESSIONSET_TIME_SERIES_CLUSTERING.out.tables
    plots    = BIOC_TMIXCLUST_EXPRESSIONSET_TIME_SERIES_CLUSTERING.out.plots
    objects  = BIOC_TMIXCLUST_EXPRESSIONSET_TIME_SERIES_CLUSTERING.out.objects
    versions = BIOC_TMIXCLUST_EXPRESSIONSET_TIME_SERIES_CLUSTERING.out.versions
}
