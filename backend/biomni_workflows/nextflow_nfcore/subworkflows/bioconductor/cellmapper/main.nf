#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CellMapper — preprocessed_data_search
// Predict cell type-specific gene expression using pre-processed datasets from CellMapperData.
// Input: query, CellMapperData object
// Container: quay.io/biocontainers/bioconductor-cellmapper:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CellMapper, ExperimentHub
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load pre-processed data from ExperimentHub
//  * 2. [Input & Preparation] Define query gene(s)
//  * 3. [Core Analysis] Run co-expression search using CMsearch
//  * 4. [Core Analysis] Inspect top results

nextflow.enable.dsl = 2

process BIOC_CELLMAPPER_PREPROCESSED_DATA_SEARCH {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("CellMapper", "ExperimentHub")
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
    library(CellMapper)
    library(ExperimentHub)
    
    # -----------------------------------------------------------------------------
    # USER INPUT SETUP & FALLBACK
    # The pipeline reads EXACTLY these files from the working directory:
    #   - query.txt (containing the Entrez ID of the marker gene)
    #   - dataset.rds (the pre-processed CellMapperData object)
    # -----------------------------------------------------------------------------
    
    query_file <- "query.txt"
    dataset_file <- "dataset.rds"
    
    # Fallback: If the user-specified input files do not exist in the working directory,
    # retrieve the authentic pre-processed dataset and query from ExperimentHub to 
    # make the pipeline fully runnable and self-contained without fabricating data.
    if (!file.exists(query_file)) {
      message("Input file '", query_file, "' not found. Creating default query with Entrez ID '2571' (GAD1)...")
      writeLines("2571", query_file)
    }
    
    if (!file.exists(dataset_file)) {
      message("Input file '", dataset_file, "' not found. Downloading EH170 from ExperimentHub...")
      tryCatch({
        hub <- ExperimentHub()
        BrainAtlas_downloaded <- hub[["EH170"]]
        saveRDS(BrainAtlas_downloaded, dataset_file)
      }, error = function(e) {
        stop("Failed to download fallback dataset from ExperimentHub: ", e\$message)
      })
    }
    
    # -----------------------------------------------------------------------------
    # STAGE 1 & 2: Read User Inputs from Working Directory
    # -----------------------------------------------------------------------------
    message("Reading query gene from ", query_file, "...")
    query_lines <- readLines(query_file, warn = FALSE)
    query <- trimws(query_lines[query_lines != ""])[1]
    
    message("Reading pre-processed dataset from ", dataset_file, "...")
    BrainAtlas <- readRDS(dataset_file)
    
    # -----------------------------------------------------------------------------
    # STAGE 3: Run Co-expression Search using CMsearch
    # -----------------------------------------------------------------------------
    message("Running CellMapper search...")
    GABAergic <- CMsearch(BrainAtlas, query.genes = query)
    
    # -----------------------------------------------------------------------------
    # STAGE 4: Inspect and Save Results
    # -----------------------------------------------------------------------------
    message("Top search results:")
    print(head(GABAergic))
    
    output_csv <- "CellMapper_analysis_results.csv"
    write.csv(GABAergic, file = output_csv, row.names = FALSE)
    message("Results successfully saved to '", output_csv, "'.")

    writeLines(c(
        '"BIOC_CELLMAPPER_PREPROCESSED_DATA_SEARCH":',
        paste0('    CellMapper: ', as.character(packageVersion('CellMapper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_preprocessed_data_search.csv versions.yml
    """
}

workflow BIOC_CELLMAPPER_PREPROCESSED_DATA_SEARCH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ query, CellMapperData object ] ]

    main:
    BIOC_CELLMAPPER_PREPROCESSED_DATA_SEARCH(ch_input)

    emit:
    tables   = BIOC_CELLMAPPER_PREPROCESSED_DATA_SEARCH.out.tables
    plots    = BIOC_CELLMAPPER_PREPROCESSED_DATA_SEARCH.out.plots
    objects  = BIOC_CELLMAPPER_PREPROCESSED_DATA_SEARCH.out.objects
    versions = BIOC_CELLMAPPER_PREPROCESSED_DATA_SEARCH.out.versions
}
