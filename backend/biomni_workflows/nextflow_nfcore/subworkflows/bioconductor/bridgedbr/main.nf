#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BridgeDbR — bridgedb_identifier_mapping
// Automatically detect input identifier types, download the appropriate BridgeDb mapping database (gene or metabolite), map identifiers to multiple standard targe
// Input: input.csv
// Container: 2.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BridgeDbR
// Visualizations: bar plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BRIDGEDBR_BRIDGEDB_IDENTIFIER_MAPPING {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(BridgeDbR)
    
    # ==========================================
    # STAGE 1: Read and Parse Input Data
    # ==========================================
    message("Stage 1: Reading input data...")
    
    if (!file.exists("input.csv")) {
      stop("Input file 'input.csv' not found in the working directory.")
    }
    
    # Read input defensively
    input_data <- read.csv("input.csv", stringsAsFactors = FALSE, check.names = FALSE)
    
    if (nrow(input_data) == 0) {
      stop("Input dataset is empty.")
    }
    
    # Identify the column containing identifiers
    # Look for 'feature_id' first, then fallback to row names or the first column
    if ("feature_id" %in% colnames(input_data)) {
      raw_ids <- as.character(input_data\$feature_id)
    } else if (ncol(input_data) >= 1 && !is.numeric(input_data[[1]])) {
      raw_ids <- as.character(input_data[[1]])
    } else {
      raw_ids <- rownames(input_data)
    }
    
    # Clean and extract unique identifiers for mapping
    clean_ids <- unique(raw_ids[!is.na(raw_ids) & raw_ids != ""])
    
    if (length(clean_ids) == 0) {
      stop("No valid identifiers found for mapping.")
    }
    
    message(sprintf("Found %d unique identifiers to map.", length(clean_ids)))
    
    # ==========================================
    # STAGE 2: Source Database Detection
    # ==========================================
    message("Stage 2: Detecting source database...")
    
    # Query matching sources for a sample of identifiers to guess the source database
    sample_size <- min(length(clean_ids), 20)
    sample_ids <- clean_ids[1:sample_size]
    
    matching_sources <- lapply(sample_ids, function(id) {
      tryCatch(getMatchingSources(id), error = function(e) NULL)
    })
    
    all_sources <- unlist(matching_sources)
    
    if (length(all_sources) == 0) {
      message("Could not automatically detect source database. Defaulting to Ensembl Gene.")
      source_system <- "En"
      best_source <- "Ensembl"
    } else {
      source_table <- table(all_sources)
      best_source <- names(source_table)[which.max(source_table)]
      source_system <- tryCatch(getSystemCode(best_source), error = function(e) NA)
      
      if (is.na(source_system) || source_system == "") {
        source_system <- "En" # Fallback
        best_source <- "Ensembl"
      }
    }
    
    message(sprintf("Detected Source Database: %s (System Code: %s)", best_source, source_system))
    
    # ==========================================
    # STAGE 3: Load Mapping Database
    # ==========================================
    message("Stage 3: Loading BridgeDb mapping database...")
    
    # Determine if the source is metabolite-related or gene-related
    metabolite_keywords <- c("HMDB", "ChEBI", "PubChem", "ChemSpider", "KEGG Compound", "Metabolite")
    is_metabolite <- any(sapply(metabolite_keywords, function(kw) grepl(kw, best_source, ignore.case = TRUE)))
    
    db_file <- NULL
    mapper <- NULL
    
    if (is_metabolite) {
      message("Metabolite source detected. Downloading metabolite mapping database from Figshare...")
      db_file <- file.path(tempdir(), "metabolites.bridge")
      if (!file.exists(db_file)) {
        tryCatch({
          download.file("https://figshare.com/ndownloader/files/26001794", db_file, mode = "wb")
        }, error = function(e) {
          stop("Failed to download metabolite database from Figshare: ", e\$message)
        })
      }
      # Define target databases for metabolites
      targets <- list(
        HMDB = "Ch",
        ChEBI = "Ce",
        PubChem = "Cpc"
      )
    } else {
      message("Gene/Protein source detected. Downloading Homo sapiens gene database...")
      tryCatch({
        db_file <- getDatabase("Homo sapiens", location = tempdir())
      }, error = function(e) {
        stop("Failed to download Homo sapiens gene database: ", e\$message)
      })
      # Define target databases for genes
      targets <- list(
        Ensembl = "En",
        EntrezGene = "L",
        HGNC = "H"
      )
    }
    
    # Load the database
    mapper <- loadDatabase(db_file)
    message("Database loaded successfully.")
    
    # ==========================================
    # STAGE 4: Perform Identifier Mapping
    # ==========================================
    message("Stage 4: Mapping identifiers...")
    
    # Helper function to safely map identifiers
    safe_map <- function(mapper, ids, source_sys, target_sys) {
      tryCatch({
        input_df <- data.frame(
          source = rep(source_sys, length(ids)),
          identifier = ids,
          stringsAsFactors = FALSE
        )
        maps(mapper, input_df, target_sys)
      }, error = function(e) {
        # Fallback to individual map calls if maps() fails
        message("maps() failed, falling back to individual map() calls...")
        do.call(rbind, lapply(ids, function(id) {
          tryCatch({
            map(mapper, source_sys, id, target_sys)
          }, error = function(err) NULL)
        }))
      })
    }
    
    # Helper function to aggregate multi-mappings to maintain 1-to-1 relationship
    aggregate_mappings <- function(map_df, original_ids) {
      mapped_vector <- setNames(rep(NA_character_, length(original_ids)), original_ids)
      if (!is.null(map_df) && nrow(map_df) > 0) {
        # Find the column containing the mapped target identifier
        col_candidates <- colnames(map_df)
        val_col <- intersect(col_candidates, c("mapping", "target_identifier"))
        if (length(val_col) == 0) {
          val_col <- setdiff(col_candidates, c("source", "identifier", "target", "isPrimary"))[1]
        }
        
        if (length(val_col) > 0 && !is.na(val_col)) {
          split_mapped <- split(map_df[[val_col]], map_df\$identifier)
          collapsed <- sapply(split_mapped, function(x) {
            x <- unique(x[!is.na(x) & x != ""])
            if (length(x) == 0) return(NA_character_)
            paste(x, collapse = "; ")
          })
          mapped_vector[names(collapsed)] <- collapsed
        }
      }
      return(mapped_vector)
    }
    
    # Map to each target database
    mapping_results <- list()
    for (target_name in names(targets)) {
      target_sys <- targets[[target_name]]
      message(sprintf("Mapping to %s (%s)...", target_name, target_sys))
      
      raw_map <- safe_map(mapper, clean_ids, source_system, target_sys)
      mapping_results[[target_name]] <- aggregate_mappings(raw_map, clean_ids)
    }
    
    # ==========================================
    # STAGE 5: Post-processing and Merging
    # ==========================================
    message("Stage 5: Merging mapping results back to original dataset...")
    
    # Create a mapping data frame
    mapping_df <- data.frame(
      feature_id = clean_ids,
      stringsAsFactors = FALSE
    )
    
    for (target_name in names(mapping_results)) {
      mapping_df[[paste0("mapped_", target_name)]] <- mapping_results[[target_name]][clean_ids]
    }
    
    # Merge back with the original input data
    if ("feature_id" %in% colnames(input_data)) {
      final_df <- merge(input_data, mapping_df, by = "feature_id", all.x = TRUE)
    } else {
      # If matched by row names or first column
      input_data\$feature_id <- raw_ids
      final_df <- merge(input_data, mapping_df, by = "feature_id", all.x = TRUE)
    }
    
    # Write the final mapped dataset
    write.csv(final_df, "mapped_features.csv", row.names = FALSE)
    message("Saved mapped dataset to 'mapped_features.csv'.")
    
    # ==========================================
    # STAGE 6: Diagnostics and Visualization
    # ==========================================
    message("Stage 6: Generating diagnostics and summary...")
    
    # Calculate mapping efficiency
    total_ids <- length(clean_ids)
    efficiency <- sapply(mapping_results, function(x) {
      sum(!is.na(x)) / total_ids * 100
    })
    
    # Write summary report
    summary_conn <- file("mapping_summary.txt", "w")
    writeLines(c(
      "==========================================",
      "      BridgeDbR Mapping Summary Report     ",
      "==========================================",
      sprintf("Date: %s", Sys.time()),
      sprintf("Total Input Identifiers: %d", total_ids),
      sprintf("Detected Source Database: %s (System Code: %s)", best_source, source_system),
      sprintf("Database Type: %s", ifelse(is_metabolite, "Metabolite", "Gene/Protein")),
      "------------------------------------------",
      "Mapping Efficiency per Target Database:"
    ), summary_conn)
    
    for (target_name in names(efficiency)) {
      writeLines(sprintf("  - %s: %.2f%% (%d/%d mapped)", 
                         target_name, 
                         efficiency[target_name], 
                         sum(!is.na(mapping_results[[target_name]])), 
                         total_ids), 
                 summary_conn)
    }
    writeLines("==========================================", summary_conn)
    close(summary_conn)
    message("Saved summary report to 'mapping_summary.txt'.")
    
    # Generate bar plot of mapping efficiency
    pdf("mapping_efficiency.pdf", width = 7, height = 5)
    par(mar = c(5, 8, 4, 2) + 0.1)
    barplot(
      efficiency,
      horiz = TRUE,
      las = 1,
      col = "skyblue",
      xlim = c(0, 100),
      xlab = "Mapping Efficiency (%)",
      main = "BridgeDbR Identifier Mapping Efficiency"
    )
    abline(v = seq(0, 100, by = 20), lty = "dashed", col = "gray")
    dev.off()
    message("Saved efficiency plot to 'mapping_efficiency.pdf'.")
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_BRIDGEDBR_BRIDGEDB_IDENTIFIER_MAPPING":',
        paste0('    BridgeDbR: ', as.character(packageVersion('BridgeDbR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bridgedb_identifier_mapping.csv versions.yml
    """
}

workflow BIOC_BRIDGEDBR_BRIDGEDB_IDENTIFIER_MAPPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BRIDGEDBR_BRIDGEDB_IDENTIFIER_MAPPING(ch_input)

    emit:
    tables   = BIOC_BRIDGEDBR_BRIDGEDB_IDENTIFIER_MAPPING.out.tables
    plots    = BIOC_BRIDGEDBR_BRIDGEDB_IDENTIFIER_MAPPING.out.plots
    objects  = BIOC_BRIDGEDBR_BRIDGEDB_IDENTIFIER_MAPPING.out.objects
    versions = BIOC_BRIDGEDBR_BRIDGEDB_IDENTIFIER_MAPPING.out.versions
}
