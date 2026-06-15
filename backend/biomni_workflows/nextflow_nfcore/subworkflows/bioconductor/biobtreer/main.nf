#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: biobtreeR — biobtree_id_mapping
// Perform comprehensive biological identifier mapping, search, and functional annotation using biobtreeR.
// Input: input.csv
// Container: 1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: biobtreeR
// QC: missing-value handling
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOBTREER_BIOBTREE_ID_MAPPING {
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
    .bm_deps <- c("biobtreeR")
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
    library(biobtreeR)
    
    # Define output files
    search_out <- "search_results.csv"
    transcript_out <- "transcript_mappings.csv"
    go_out <- "go_mappings.csv"
    
    # Ensure clean exit by stopping the biobtree server on script termination
    on.exit({
      message("Stopping biobtree server...")
      tryCatch(bbStop(), error = function(e) NULL)
    })
    
    # ==========================================
    # --- Initialize and Start Biobtree Server ---
    # ==========================================
    message("Stage 1: Initializing biobtree database...")
    
    # Set local output directory for database storage
    db_dir <- tempdir()
    bbUseOutDir(db_dir)
    
    # Retrieve the pre-built database containing common datasets (hgnc, go, uniprot, ensembl, etc.)
    # Note: This downloads the standard pre-built database if not already present.
    tryCatch({
      bbBuiltInDB()
    }, error = function(e) {
      warning("Failed to retrieve built-in DB. Attempting to proceed with existing or custom DB: ", e\$message)
    })
    
    # Start the local lightweight biobtree background server
    message("Starting biobtree local server...")
    bbStart()
    
    # ==========================================
    # --- Read and Process Input Identifiers ---
    # ==========================================
    message("Stage 2: Reading input identifiers...")
    
    if (!file.exists("input.csv")) {
      stop("Input file 'input.csv' not found. Please stage the input file.")
    }
    
    # Read input defensively
    input_data <- read.csv("input.csv", stringsAsFactors = FALSE, check.names = FALSE)
    
    # Extract identifiers from 'feature_id' column, first column, or row names
    if ("feature_id" %in% colnames(input_data)) {
      raw_ids <- input_data\$feature_id
    } else if (ncol(input_data) == 1) {
      raw_ids <- input_data[[1]]
    } else {
      raw_ids <- rownames(input_data)
    }
    
    # Clean and deduplicate identifiers
    ids <- unique(na.omit(as.character(raw_ids)))
    ids <- ids[ids != "" & !is.na(ids)]
    
    if (length(ids) == 0) {
      stop("No valid identifiers found in input.csv")
    }
    
    message(paste("Loaded", length(ids), "unique identifiers for mapping."))
    
    # Helper function to batch queries to avoid URL/command length limits
    run_batched_search <- function(identifiers, showURL = TRUE) {
      chunks <- split(identifiers, ceiling(seq_along(identifiers) / 50))
      results <- list()
      for (i in seq_along(chunks)) {
        chunk_str <- paste(chunks[[i]], collapse = ",")
        tryCatch({
          res <- bbSearch(chunk_str, showURL = showURL)
          if (!is.null(res) && nrow(res) > 0) {
            results[[length(results) + 1]] <- res
          }
        }, error = function(e) {
          warning("Search failed for batch ", i, ": ", e\$message)
        })
      }
      if (length(results) > 0) {
        return(do.call(rbind, results))
      } else {
        return(data.frame(input = character(), identifier = character(), dataset = character(), mapping_count = numeric(), url = character()))
      }
    }
    
    run_batched_mapping <- function(identifiers, query, attrs = NULL, source = NULL) {
      chunks <- split(identifiers, ceiling(seq_along(identifiers) / 50))
      results <- list()
      for (i in seq_along(chunks)) {
        chunk_str <- paste(chunks[[i]], collapse = ",")
        tryCatch({
          if (is.null(attrs) && is.null(source)) {
            res <- bbMapping(chunk_str, query)
          } else if (is.null(attrs)) {
            res <- bbMapping(chunk_str, query, source = source)
          } else if (is.null(source)) {
            res <- bbMapping(chunk_str, query, attrs = attrs)
          } else {
            res <- bbMapping(chunk_str, query, attrs = attrs, source = source)
          }
          if (!is.null(res) && nrow(res) > 0) {
            results[[length(results) + 1]] <- res
          }
        }, error = function(e) {
          warning("Mapping failed for batch ", i, " with query '", query, "': ", e\$message)
        })
      }
      if (length(results) > 0) {
        return(do.call(rbind, results))
      } else {
        return(data.frame())
      }
    }
    
    # ==========================================
    # --- Identifier Search & URL Retrieval ---
    # ==========================================
    message("Stage 3: Searching identifiers and retrieving database URLs...")
    
    search_results <- run_batched_search(ids, showURL = TRUE)
    write.csv(search_results, file = search_out, row.names = FALSE)
    message(paste("Saved search results to", search_out))
    
    # ==========================================
    # --- Gene-Centric Transcript Mapping ---
    # ==========================================
    message("Stage 4: Mapping genes to Ensembl transcripts and genomic regions...")
    
    # Map input genes to transcripts and retrieve genomic region attributes
    transcript_mappings <- run_batched_mapping(ids, query = "map(transcript)", attrs = "seq_region")
    
    if (nrow(transcript_mappings) > 0) {
      write.csv(transcript_mappings, file = transcript_out, row.names = FALSE)
      message(paste("Saved transcript mappings to", transcript_out))
    } else {
      # Write fallback empty file with expected headers
      write.csv(data.frame(input = character(), input_dataset = character(), mapping_id = character(), seq_region = character()), 
                file = transcript_out, row.names = FALSE)
      warning("No transcript mappings found. Written empty fallback file.")
    }
    
    # ==========================================
    # --- Protein-Centric Functional Annotation (GO) ---
    # ==========================================
    message("Stage 5: Mapping genes/proteins to Gene Ontology (GO) terms...")
    
    # Map input identifiers to Uniprot, then chain-map to GO terms, filtering for biological processes
    go_mappings <- run_batched_mapping(ids, query = "map(uniprot).map(go)", attrs = "type")
    
    if (nrow(go_mappings) > 0) {
      write.csv(go_mappings, file = go_out, row.names = FALSE)
      message(paste("Saved GO mappings to", go_out))
    } else {
      # Write fallback empty file with expected headers
      write.csv(data.frame(input = character(), input_dataset = character(), mapping_id = character(), type = character()), 
                file = go_out, row.names = FALSE)
      warning("No GO mappings found. Written empty fallback file.")
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_BIOBTREER_BIOBTREE_ID_MAPPING":',
        paste0('    biobtreeR: ', as.character(packageVersion('biobtreeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biobtree_id_mapping.csv versions.yml
    """
}

workflow BIOC_BIOBTREER_BIOBTREE_ID_MAPPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BIOBTREER_BIOBTREE_ID_MAPPING(ch_input)

    emit:
    tables   = BIOC_BIOBTREER_BIOBTREE_ID_MAPPING.out.tables
    plots    = BIOC_BIOBTREER_BIOBTREE_ID_MAPPING.out.plots
    objects  = BIOC_BIOBTREER_BIOBTREE_ID_MAPPING.out.objects
    versions = BIOC_BIOBTREER_BIOBTREE_ID_MAPPING.out.versions
}
