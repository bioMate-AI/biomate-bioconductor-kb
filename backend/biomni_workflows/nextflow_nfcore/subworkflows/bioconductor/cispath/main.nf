#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cisPath — ppi_path_visualization
// Identify shortest interaction paths among a set of proteins and generate an interactive HTML visualization.
// Input: protein_list.txt, ppi_data.tsv
// Container: quay.io/biocontainers/bioconductor-cispath:1.46.0--r44he5774e6_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: cisPath
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Format the raw PPI data into the required format using format_ppi
//  * 2. [Visualization & Output] Run the path-finding algorithm and generate the HTML visualization using cisPath

nextflow.enable.dsl = 2

process BIOC_CISPATH_PPI_PATH_VISUALIZATION {
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
    .bm_deps <- c("cisPath")
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
    library(cisPath)
    
    # Define input file paths
    interaction_file <- "ppi_data.tsv"
    protein_list_file <- "protein_list.txt"
    
    # Validate input files existence
    if (!file.exists(interaction_file)) {
      stop("Input file 'ppi_data.tsv' not found in the working directory.")
    }
    if (!file.exists(protein_list_file)) {
      stop("Input file 'protein_list.txt' not found in the working directory.")
    }
    
    # Read the protein list from the user input file
    proteinList <- readLines(protein_list_file)
    proteinList <- trimws(proteinList)
    proteinList <- proteinList[proteinList != ""]
    
    # Define the output directory for the HTML visualization
    output_dir <- "cisPath_output"
    if (!dir.exists(output_dir)) {
      dir.create(output_dir, recursive = TRUE)
    }
    
    # Stage 1: Format the raw PPI data into the required format
    # Documented call: infoFile <- format_ppi(interaction_file, source="STRING", species="9606")
    infoFile <- file.path(output_dir, "formatted_ppi.txt")
    formatSTRINGppi(interaction_file, infoFile)
    
    # Stage 2: Run the path-finding algorithm and generate the HTML visualization
    # Documented call: cisPath(infoFile, proteinList, outFolder=tempdir())
    cisPath(infoFile, output_dir, proteinList)
    
    # Write a summary file of the execution results
    summary_file <- file.path(output_dir, "run_summary.txt")
    writeLines(c(
      paste("Execution Date:", Sys.time()),
      paste("Input PPI File:", interaction_file),
      paste("Formatted PPI File:", infoFile),
      paste("Number of Query Proteins:", length(proteinList)),
      "Query Proteins:",
      paste(proteinList, collapse = ", ")
    ), con = summary_file)

    writeLines(c(
        '"BIOC_CISPATH_PPI_PATH_VISUALIZATION":',
        paste0('    cisPath: ', as.character(packageVersion('cisPath')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ppi_path_visualization.csv versions.yml
    """
}

workflow BIOC_CISPATH_PPI_PATH_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ protein_list.txt, ppi_data.tsv ] ]

    main:
    BIOC_CISPATH_PPI_PATH_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_CISPATH_PPI_PATH_VISUALIZATION.out.tables
    plots    = BIOC_CISPATH_PPI_PATH_VISUALIZATION.out.plots
    objects  = BIOC_CISPATH_PPI_PATH_VISUALIZATION.out.objects
    versions = BIOC_CISPATH_PPI_PATH_VISUALIZATION.out.versions
}
