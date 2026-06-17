#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CellMapper — custom_data_search
// Prepare custom microarray expression data and predict cell type-specific gene expression.
// Input: ALL, query.genes
// Container: quay.io/biocontainers/bioconductor-cellmapper:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CellMapper
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load custom expression dataset
//  * 2. [Core Analysis] Pre-process the dataset using CMprep
//  * 3. [Input & Preparation] Define query gene(s)
//  * 4. [Core Analysis] Run co-expression search using CMsearch

nextflow.enable.dsl = 2

process BIOC_CELLMAPPER_CUSTOM_DATA_SEARCH {
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
    .bm_deps <- c("CellMapper")
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
    
    # 1. Load custom expression dataset
    # The pipeline expects 'ALL.rds' (ExpressionSet or matrix) or 'ALL.csv' (matrix)
    if (file.exists("ALL.rds")) {
      ALL <- readRDS("ALL.rds")
    } else if (file.exists("ALL.csv")) {
      ALL <- as.matrix(read.csv("ALL.csv", row.names = 1))
    } else {
      stop("Error: Missing required input file 'ALL.rds' or 'ALL.csv' in the working directory.")
    }
    
    # 2. Define query gene(s)
    # The pipeline expects a file 'query.genes' containing the query gene identifier(s)
    if (file.exists("query.genes")) {
      query_genes_val <- readLines("query.genes")
    } else if (file.exists("query.genes.txt")) {
      query_genes_val <- readLines("query.genes.txt")
    } else {
      stop("Error: Missing required input file 'query.genes' or 'query.genes.txt' in the working directory.")
    }
    
    # Clean query genes input
    query_genes_val <- trimws(query_genes_val)
    query_genes_val <- query_genes_val[query_genes_val != ""]
    
    if (length(query_genes_val) == 0) {
      stop("Error: The query.genes file is empty.")
    }
    
    # 3. Pre-process the dataset using CMprep
    message("Pre-processing the dataset using CMprep...")
    prepped.data <- CMprep(ALL)
    
    # Save the prepped data for future use
    saveRDS(prepped.data, file = "prepped_data.rds")
    message("Pre-processed data saved to 'prepped_data.rds'")
    
    # 4. Run co-expression search using CMsearch
    message("Running co-expression search using CMsearch...")
    out <- CMsearch(prepped.data, query.genes = query_genes_val)
    
    # Display top results
    message("Top search results:")
    print(head(out))
    
    # Write output results
    write.csv(out, file = "CellMapper_output.csv", row.names = FALSE)
    message("Results successfully saved to 'CellMapper_output.csv'")

    writeLines(c(
        '"BIOC_CELLMAPPER_CUSTOM_DATA_SEARCH":',
        paste0('    CellMapper: ', as.character(packageVersion('CellMapper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_data_search.csv versions.yml
    """
}

workflow BIOC_CELLMAPPER_CUSTOM_DATA_SEARCH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ALL, query.genes ] ]

    main:
    BIOC_CELLMAPPER_CUSTOM_DATA_SEARCH(ch_input)

    emit:
    tables   = BIOC_CELLMAPPER_CUSTOM_DATA_SEARCH.out.tables
    plots    = BIOC_CELLMAPPER_CUSTOM_DATA_SEARCH.out.plots
    objects  = BIOC_CELLMAPPER_CUSTOM_DATA_SEARCH.out.objects
    versions = BIOC_CELLMAPPER_CUSTOM_DATA_SEARCH.out.versions
}
