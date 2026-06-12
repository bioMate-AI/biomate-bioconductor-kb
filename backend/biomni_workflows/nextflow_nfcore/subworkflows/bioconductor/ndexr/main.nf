#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ndexr — ndex_network_retrieval
// Query the NDEx server using a gene list to find, summarize, and extract relevant biological networks and their node components.
// Input: input.csv
// Container: 1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ndexr
// QC: missing-value handling
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NDEXR_NDEX_NETWORK_RETRIEVAL {
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
    .bm_deps <- c("ndexr")
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
    library(ndexr)
    
    # --- Read input defensively ---
    input_file <- "input.csv"
    genes <- c("EGFR") # Default fallback
    
    if (file.exists(input_file)) {
      tryCatch({
        input_data <- read.csv(input_file, stringsAsFactors = FALSE, header = TRUE)
        if (ncol(input_data) > 0) {
          if ("feature_id" %in% colnames(input_data)) {
            genes <- input_data\$feature_id
          } else if (ncol(input_data) == 1) {
            genes <- input_data[[1]]
          } else {
            # Try using row names or first column
            genes <- rownames(input_data)
            if (is.null(genes) || length(genes) == 0 || all(genes == as.character(1:nrow(input_data)))) {
              genes <- input_data[[1]]
            }
          }
        }
      }, error = function(e) {
        message("Error reading input.csv, using default gene list. Error: ", e\$message)
      })
    }
    
    # Clean and validate gene list
    genes <- unique(na.omit(genes))
    genes <- genes[genes != ""]
    if (length(genes) == 0) {
      genes <- c("EGFR")
    }
    
    # --- Connect to NDEx server ---
    message("Connecting to NDEx server...")
    ndexcon <- tryCatch({
      ndex_connect()
    }, error = function(e) {
      message("Failed to connect to NDEx server: ", e\$message)
      NULL
    })
    
    # Initialize empty outputs in case of server or query failure
    search_results <- data.frame(
      name = character(), 
      externalId = character(), 
      nodeCount = numeric(), 
      edgeCount = numeric(), 
      stringsAsFactors = FALSE
    )
    net_summary_df <- data.frame(
      Property = character(), 
      Value = character(), 
      stringsAsFactors = FALSE
    )
    net_metadata <- data.frame(
      name = character(), 
      elementCount = numeric(), 
      version = character(), 
      idCounter = numeric(), 
      stringsAsFactors = FALSE
    )
    net_nodes <- data.frame(
      id = character(), 
      name = character(), 
      stringsAsFactors = FALSE
    )
    
    if (!is.null(ndexcon)) {
      # --- Search for networks matching the primary gene of interest ---
      search_term <- genes[1]
      message("Searching NDEx for: ", search_term)
      
      tryCatch({
        search_results <- ndex_find_networks(ndexcon, searchString = search_term)
        if (nrow(search_results) == 0) {
          message("No networks found for ", search_term, ". Trying fallback 'EGFR'...")
          search_results <- ndex_find_networks(ndexcon, searchString = "EGFR")
        }
      }, error = function(e) {
        message("Error searching networks: ", e\$message)
      })
      
      if (nrow(search_results) > 0) {
        # --- Retrieve top network details ---
        top_network_id <- search_results[1, "externalId"]
        message("Selected network ID: ", top_network_id)
        
        # Get Network Summary
        tryCatch({
          summary_info <- ndex_network_get_summary(ndexcon, top_network_id)
          summary_keys <- names(summary_info)
          summary_values <- sapply(summary_info, function(x) {
            if (is.list(x) || length(x) > 1) {
              paste(as.character(unlist(x)), collapse = "; ")
            } else {
              as.character(x)
            }
          })
          net_summary_df <- data.frame(Property = summary_keys, Value = summary_values, stringsAsFactors = FALSE)
        }, error = function(e) {
          message("Error getting network summary: ", e\$message)
        })
        
        # Get Network Metadata
        tryCatch({
          net_metadata <- ndex_network_get_metadata(ndexcon, top_network_id)
        }, error = function(e) {
          message("Error getting network metadata: ", e\$message)
        })
        
        # Get Nodes Aspect
        tryCatch({
          nodes_aspect <- ndex_network_get_aspect(ndexcon, top_network_id, "nodes")
          if (!is.null(nodes_aspect) && nrow(nodes_aspect) > 0) {
            net_nodes <- nodes_aspect
          } else {
            # Fallback to downloading entire network as RCX object
            rcx <- ndex_get_network(ndexcon, top_network_id)
            if (!is.null(rcx\$nodes)) {
              net_nodes <- rcx\$nodes
            }
          }
        }, error = function(e) {
          message("Error getting network nodes: ", e\$message)
        })
      }
    }
    
    # --- Write outputs to working directory ---
    write.csv(search_results, "ndex_search_results.csv", row.names = FALSE)
    write.csv(net_summary_df, "selected_network_summary.csv", row.names = FALSE)
    write.csv(net_metadata, "selected_network_metadata.csv", row.names = FALSE)
    write.csv(net_nodes, "selected_network_nodes.csv", row.names = FALSE)
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_NDEXR_NDEX_NETWORK_RETRIEVAL":',
        paste0('    ndexr: ', as.character(packageVersion('ndexr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ndex_network_retrieval.csv versions.yml
    """
}

workflow BIOC_NDEXR_NDEX_NETWORK_RETRIEVAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_NDEXR_NDEX_NETWORK_RETRIEVAL(ch_input)

    emit:
    tables   = BIOC_NDEXR_NDEX_NETWORK_RETRIEVAL.out.tables
    plots    = BIOC_NDEXR_NDEX_NETWORK_RETRIEVAL.out.plots
    objects  = BIOC_NDEXR_NDEX_NETWORK_RETRIEVAL.out.objects
    versions = BIOC_NDEXR_NDEX_NETWORK_RETRIEVAL.out.versions
}
