#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: imcRtools — imc_data_import
// Read segmented single-cell data and features from CellProfiler or Steinbock pipelines into SpatialExperiment or SingleCellExperiment objects.
// Input: cell.csv, Image.csv, Object_relationships.csv, intensities/, neighbors/, regionprops/
// Container: quay.io/biocontainers/bioconductor-imcrtools:1.16.0--r45hdfd78af_0
// R packages: SingleCellExperiment, SpatialExperiment, CATALYST, cytomapper, ggplot2, ggraph, imcRtools
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_IMCRTOOLS_IMC_DATA_IMPORT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-imcrtools:1.16.0--r45hdfd78af_0"

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
    .bm_deps <- c("SingleCellExperiment", "SpatialExperiment", "CATALYST", "cytomapper", "ggplot2", "ggraph", "imcRtools")
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
    library(imcRtools)
    library(SpatialExperiment)
    library(SingleCellExperiment)
    
    # Define the input path (working directory containing the user files)
    path <- "."
    
    # --- Browse and select CellProfiler features ---
    message("Browsing CellProfiler features...")
    cp_features <- show_cpout_features(path)
    write.csv(cp_features, "cp_features.csv", row.names = FALSE)
    
    # --- Read CellProfiler output into SpatialExperiment and ---
    cur_path <- "."
    message("Reading CellProfiler output as SpatialExperiment...")
    spe <- read_cpout(cur_path, graph_file = "Object_relationships.csv")
    saveRDS(spe, "spe_cellprofiler.rds")
    
    message("Reading CellProfiler output as SingleCellExperiment...")
    sce <- read_cpout(cur_path, graph_file = "Object_relationships.csv", return_as = "sce")
    saveRDS(sce, "sce_cellprofiler.rds")
    
    # --- Read Steinbock output into SpatialExperiment and ---
    cur_path <- "."
    message("Reading Steinbock output as SpatialExperiment...")
    spe_steinbock <- read_steinbock(cur_path)
    saveRDS(spe_steinbock, "spe_steinbock.rds")
    
    message("Reading Steinbock output as SingleCellExperiment...")
    sce_steinbock <- read_steinbock(cur_path, return_as = "sce")
    saveRDS(sce_steinbock, "sce_steinbock.rds")
    
    # --- Read raw TXT files into a CytoImageList object ---
    path <- "."
    message("Reading raw TXT files...")
    cur_CytoImageList <- tryCatch({
      readImagefromTXT(path)
    }, error = function(e) {
      message("Note: No raw TXT files found or error reading them: ", e\$message)
      NULL
    })
    
    if (!is.null(cur_CytoImageList)) {
      saveRDS(cur_CytoImageList, "raw_CytoImageList.rds")
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_IMCRTOOLS_IMC_DATA_IMPORT":',
        paste0('        imcRtools: ', as.character(packageVersion("imcRtools")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_imc_data_import.csv versions.yml
    """
}

workflow BIOC_IMCRTOOLS_IMC_DATA_IMPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cell.csv, Image.csv, Object_relationships.csv, intensities/, neighbors/, regionprops/ ] ]

    main:
    BIOC_IMCRTOOLS_IMC_DATA_IMPORT(ch_input)

    emit:
    tables   = BIOC_IMCRTOOLS_IMC_DATA_IMPORT.out.tables
    plots    = BIOC_IMCRTOOLS_IMC_DATA_IMPORT.out.plots
    objects  = BIOC_IMCRTOOLS_IMC_DATA_IMPORT.out.objects
    versions = BIOC_IMCRTOOLS_IMC_DATA_IMPORT.out.versions
}
