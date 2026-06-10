#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HPAanalyze — download_subset_export_hpa
// Download full HPA histology datasets, filter them for specific genes, tissues, and cancers of interest, and export the results to an Excel file.
// Input: geneList, tissueList, cancerList
// Container: quay.io/biocontainers/bioconductor-hpaanalyze:1.28.0--r45hdfd78af_0
// R packages: BiocStyle, dplyr, ggplot2, HPAanalyze, tibble
// Bioconductor: 3.20 | R: 4.4
// Requires: HPAanalyze
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Download HPA datasets using hpaDownload()
//  * 2. [Core Analysis] Subset the downloaded data using hpaSubset()
//  * 3. [Visualization & Output] Export the subsetted data to an Excel file using hpaExport()

nextflow.enable.dsl = 2

process BIOC_HPAANALYZE_DOWNLOAD_SUBSET_EXPORT_HPA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("BiocStyle", "dplyr", "ggplot2", "HPAanalyze", "tibble")
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
        library(HPAanalyze)
        
        # Helper function to robustly read user input files from the working directory
        read_input <- function(filename) {
          if (file.exists(filename)) {
            lines <- readLines(filename, warn = FALSE)
            lines <- trimws(lines)
            return(lines[lines != ""])
          } else if (file.exists(paste0(filename, ".txt"))) {
            lines <- readLines(paste0(filename, ".txt"), warn = FALSE)
            lines <- trimws(lines)
            return(lines[lines != ""])
          } else if (file.exists(paste0(filename, ".csv"))) {
            df <- read.csv(paste0(filename, ".csv"), header = FALSE, stringsAsFactors = FALSE)
            return(as.character(df[[1]]))
          } else {
            stop(paste("Error: Required input file", filename, "not found in the working directory."))
          }
        }
        
        # Read user inputs
        geneList <- read_input("geneList")
        tissueList <- read_input("tissueList")
        cancerList <- read_input("cancerList")
        
        # 1. Download HPA datasets using hpaDownload()
        downloadedData <- hpaDownload(downloadList = 'histology')
        
        # 2. Subset the downloaded data using hpaSubset()
        subsetData <- hpaSubset(data = downloadedData, targetGene = geneList, targetTissue = tissueList, targetCancer = cancerList)
        
        # 3. Export the subsetted data to an Excel file using hpaExport()
        hpaExport(subsetData, fileName = 'subset.xlsx', fileType = 'xlsx')
        
        # Additional outputs for robustness and downstream analysis
        saveRDS(subsetData, file = "subsetData.rds")
        
        if (is.list(subsetData)) {
          for (name in names(subsetData)) {
            if (is.data.frame(subsetData[[name]])) {
              write.csv(subsetData[[name]], file = paste0("subset_", name, ".csv"), row.names = FALSE)
            }
          }
        }

    writeLines(c(
        '"BIOC_HPAANALYZE_DOWNLOAD_SUBSET_EXPORT_HPA":',
        paste0('    HPAanalyze: ', as.character(packageVersion('HPAanalyze')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_download_subset_export_hpa.csv versions.yml
    """
}

workflow BIOC_HPAANALYZE_DOWNLOAD_SUBSET_EXPORT_HPA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ geneList, tissueList, cancerList ] ]

    main:
    BIOC_HPAANALYZE_DOWNLOAD_SUBSET_EXPORT_HPA(ch_input)

    emit:
    tables   = BIOC_HPAANALYZE_DOWNLOAD_SUBSET_EXPORT_HPA.out.tables
    plots    = BIOC_HPAANALYZE_DOWNLOAD_SUBSET_EXPORT_HPA.out.plots
    objects  = BIOC_HPAANALYZE_DOWNLOAD_SUBSET_EXPORT_HPA.out.objects
    versions = BIOC_HPAANALYZE_DOWNLOAD_SUBSET_EXPORT_HPA.out.versions
}
