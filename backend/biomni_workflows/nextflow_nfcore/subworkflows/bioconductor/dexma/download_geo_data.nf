#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DExMA — download_geo_data
// Download public microarray datasets from NCBI GEO for meta-analysis.
// Input: GEOobjects
// Container: quay.io/biocontainers/bioconductor-dexma:1.18.0--r45hdfd78af_0
// R packages: DExMA
// Bioconductor: 3.20 | R: 4.4
// Requires: DExMA
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Download GEO datasets

nextflow.enable.dsl = 2

process BIOC_DEXMA_DOWNLOAD_GEO_DATA {
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
    .bm_deps <- c("DExMA")
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
    
    # Load required library
    library(DExMA)
    
    # Read user input file: GEOobjects (vector of GEO accession IDs)
    # We look for 'GEOobjects.txt' (one ID per line) or 'GEOobjects.csv'
    input_file_txt <- "GEOobjects.txt"
    input_file_csv <- "GEOobjects.csv"
    
    if (file.exists(input_file_txt)) {
      GEOobjects <- readLines(input_file_txt)
      GEOobjects <- trimws(GEOobjects)
      GEOobjects <- GEOobjects[GEOobjects != ""]
    } else if (file.exists(input_file_csv)) {
      GEOobjects_df <- read.csv(input_file_csv, header = FALSE, stringsAsFactors = FALSE)
      GEOobjects <- as.character(GEOobjects_df[[1]])
      GEOobjects <- trimws(GEOobjects)
      GEOobjects <- GEOobjects[GEOobjects != ""]
    } else {
      stop("Error: Input file 'GEOobjects.txt' or 'GEOobjects.csv' containing GEO accession IDs not found in the working directory.")
    }
    
    if (length(GEOobjects) == 0) {
      stop("Error: No GEO accession IDs found in the input file.")
    }
    
    # Execute the documented workflow step
    message("Downloading GEO datasets: ", paste(GEOobjects, collapse = ", "))
    dataGEO<-downloadGEOData(GEOobjects)
    
    # Save the downloaded datasets to an RDS file
    output_rds <- "dataGEO.rds"
    saveRDS(dataGEO, file = output_rds)
    message("Successfully downloaded and saved GEO data to ", output_rds)

    writeLines(c(
        '"BIOC_DEXMA_DOWNLOAD_GEO_DATA":',
        paste0('    DExMA: ', as.character(packageVersion('DExMA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_download_geo_data.csv versions.yml
    """
}

workflow BIOC_DEXMA_DOWNLOAD_GEO_DATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GEOobjects ] ]

    main:
    BIOC_DEXMA_DOWNLOAD_GEO_DATA(ch_input)

    emit:
    tables   = BIOC_DEXMA_DOWNLOAD_GEO_DATA.out.tables
    plots    = BIOC_DEXMA_DOWNLOAD_GEO_DATA.out.plots
    objects  = BIOC_DEXMA_DOWNLOAD_GEO_DATA.out.objects
    versions = BIOC_DEXMA_DOWNLOAD_GEO_DATA.out.versions
}
