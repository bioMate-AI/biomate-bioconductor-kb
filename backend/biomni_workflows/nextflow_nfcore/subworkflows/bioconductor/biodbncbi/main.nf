#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: biodbNcbi — ncbi_gene_annotation
// Retrieve functional annotations and metadata from the NCBI Gene database for a list of gene identifiers using biodbNcbi.
// Input: input.csv
// Container: 1.10.0--r44hdfd78af_0
// R packages: biodb, biodbNcbi
// Bioconductor: 3.20 | R: 4.4
// Requires: biodb, biodbNcbi
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIODBNCBI_NCBI_GENE_ANNOTATION {
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
    .bm_deps <- c("biodb", "biodbNcbi")
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
    
    # --- Load required libraries safely ---
    library(biodb)
    library(biodbNcbi)
    
    # --- Read and clean input identifiers defensively ---
    input_file <- "input.csv"
    if (!file.exists(input_file)) {
      stop("Input file 'input.csv' not found in the working directory.")
    }
    
    # Read input CSV
    data <- read.csv(input_file, stringsAsFactors = FALSE, check.names = FALSE)
    
    # Extract candidate gene/feature IDs
    if (ncol(data) == 1) {
      ids <- data[[1]]
    } else if ("feature_id" %in% colnames(data)) {
      ids <- data\$feature_id
    } else {
      # Fallback to row names or the first column
      ids <- rownames(data)
      if (is.null(ids) || all(ids == as.character(seq_len(nrow(data))))) {
        ids <- data[[1]]
      }
    }
    
    # Clean and deduplicate IDs
    ids <- as.character(ids)
    ids <- unique(ids[!is.na(ids) & ids != ""])
    
    if (length(ids) == 0) {
      stop("No valid identifiers found in the input file.")
    }
    
    # Limit queries to prevent API timeouts and rate-limiting issues
    max_queries <- 50
    if (length(ids) > max_queries) {
      message(sprintf("Limiting query to the first %d IDs to prevent API rate-limiting.", max_queries))
      ids <- ids[1:max_queries]
    }
    
    # --- Initialize biodb and NCBI Gene connector ---
    message("Initializing biodb framework and NCBI Gene connector...")
    bd <- biodb::newBiodb()
    
    # Create the NCBI Gene connector (registered by loading biodbNcbi)
    conn <- bd\$getFactory()\$createConn('ncbi.gene')
    
    # --- Query NCBI Gene database ---
    message("Querying NCBI Gene database for annotations...")
    entries <- list()
    for (id in ids) {
      tryCatch({
        # Retrieve entry for the given ID
        entry <- conn\$getEntry(id)
        if (!is.null(entry)) {
          entries <- c(entries, entry)
        }
      }, error = function(e) {
        warning(sprintf("Failed to retrieve NCBI Gene entry for ID '%s': %s", id, e\$message))
      })
    }
    
    # --- Extract annotations and compile results ---
    message("Compiling annotation results...")
    if (length(entries) > 0) {
      # Attempt to convert entries to a data frame using biodb's built-in converter
      df <- tryCatch({
        bd\$entriesToDf(entries)
      }, error = function(e) {
        message("Falling back to manual field extraction...")
        # Manual fallback extraction of common fields
        do.call(rbind, lapply(entries, function(entry) {
          id <- entry\$getFieldValue('id')
          name <- entry\$getFieldValue('name')
          desc <- entry\$getFieldValue('description')
          org <- entry\$getFieldValue('organism')
          
          data.frame(
            id = ifelse(is.null(id), "", paste(id, collapse = "; ")),
            name = ifelse(is.null(name), "", paste(name, collapse = "; ")),
            description = ifelse(is.null(desc), "", paste(desc, collapse = "; ")),
            organism = ifelse(is.null(org), "", paste(org, collapse = "; ")),
            stringsAsFactors = FALSE
          )
        }))
      })
    } else {
      # Fallback empty dataframe if no entries were successfully retrieved
      message("No entries were successfully retrieved. Creating empty output template.")
      df <- data.frame(
        id = ids,
        status = "No NCBI Gene entry found or query failed",
        stringsAsFactors = FALSE
      )
    }
    
    # --- Write output to CSV ---
    write.csv(df, "ncbi_annotations.csv", row.names = FALSE)
    message("Analysis complete. Annotations written to 'ncbi_annotations.csv'.")

    writeLines(c(
        '"BIOC_BIODBNCBI_NCBI_GENE_ANNOTATION":',
        paste0('    biodbNcbi: ', as.character(packageVersion('biodbNcbi')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ncbi_gene_annotation.csv versions.yml
    """
}

workflow BIOC_BIODBNCBI_NCBI_GENE_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BIODBNCBI_NCBI_GENE_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_BIODBNCBI_NCBI_GENE_ANNOTATION.out.tables
    plots    = BIOC_BIODBNCBI_NCBI_GENE_ANNOTATION.out.plots
    objects  = BIOC_BIODBNCBI_NCBI_GENE_ANNOTATION.out.objects
    versions = BIOC_BIODBNCBI_NCBI_GENE_ANNOTATION.out.versions
}
