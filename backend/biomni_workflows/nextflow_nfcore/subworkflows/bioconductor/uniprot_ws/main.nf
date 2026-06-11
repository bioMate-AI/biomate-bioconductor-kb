#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: uniprot_ws — uniprot_annotation_pipeline
// Retrieve comprehensive protein annotations, sequence properties, and functional metadata from UniProt for a set of input identifiers, and integrate them with ex
// Input: input.csv
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: UniProt.ws, uniprot_ws
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_UNIPROT_WS_UNIPROT_ANNOTATION_PIPELINE {
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
    .bm_deps <- c("UniProt.ws")
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
    
    # --- Parameter Setup & Input Reading ---
    library(UniProt.ws)
    
    # Define parameters
    tax_id <- as.numeric(Sys.getenv("TAX_ID", unset = "9606"))
    
    message("Reading input data...")
    if (!file.exists("input.csv")) {
      stop("Required input file 'input.csv' not found.")
    }
    
    # Read input defensively
    df <- read.csv("input.csv", stringsAsFactors = FALSE, check.names = FALSE)
    
    # Identify the identifier column
    if ("feature_id" %in% colnames(df)) {
      ids <- as.character(df\$feature_id)
    } else if (ncol(df) >= 1) {
      if (is.character(df[[1]]) || is.factor(df[[1]])) {
        ids <- as.character(df[[1]])
      } else {
        ids <- as.character(rownames(df))
      }
    } else {
      ids <- as.character(rownames(df))
    }
    
    # Clean and deduplicate identifiers
    ids <- unique(ids[!is.na(ids) & ids != ""])
    if (length(ids) == 0) {
      stop("No valid identifiers found in the input file.")
    }
    message(sprintf("Found %d unique identifiers to query.", length(ids)))
    
    # --- Initialize UniProt.ws Client ---
    message(sprintf("Initializing UniProt.ws client for Taxonomy ID: %d...", tax_id))
    up <- tryCatch({
      UniProt.ws(taxId = tax_id)
    }, error = function(e) {
      stop("Failed to initialize UniProt.ws client. Please check your internet connection and Taxonomy ID: ", e\$message)
    })
    
    # --- Keytype & Column Selection ---
    available_keytypes <- keytypes(up)
    available_cols <- columns(up)
    
    # Guess the input keytype based on identifier patterns
    sample_ids <- head(ids, 10)
    is_uniprot <- any(grepl("^[OPQ][0-9][A-Z0-9]{3}[0-9]|[A-NR-Z][0-9]([A-Z][A-Z0-9]{2}[0-9]){1,2}\$", sample_ids))
    is_ensembl <- any(grepl("^ENS[A-Z]*[0-9]+", sample_ids))
    
    if (is_uniprot) {
      kt <- grep("uniprot|acc|entry", available_keytypes, ignore.case = TRUE, value = TRUE)[1]
      if (is.na(kt)) kt <- "UniProtKB"
    } else if (is_ensembl) {
      kt <- grep("ensembl", available_keytypes, ignore.case = TRUE, value = TRUE)[1]
      if (is.na(kt)) kt <- "ENSEMBL"
    } else {
      kt <- grep("gene_name|symbol|gene", available_keytypes, ignore.case = TRUE, value = TRUE)[1]
      if (is.na(kt)) kt <- "Gene_Name"
    }
    
    # Select standard useful columns to retrieve
    target_cols <- c("ENTRY", "PROTEIN-NAMES", "GENES", "SEQUENCE")
    selected_cols <- c()
    for (tc in target_cols) {
      match_col <- grep(paste0("^", tc, "\$"), available_cols, ignore.case = TRUE, value = TRUE)
      if (length(match_col) > 0) {
        selected_cols <- c(selected_cols, match_col[1])
      }
    }
    if (length(selected_cols) == 0) {
      selected_cols <- head(available_cols, 3)
    }
    
    # Ensure the query keytype is included in the columns to map back
    if (!(kt %in% selected_cols)) {
      selected_cols <- c(kt, selected_cols)
    }
    selected_cols <- unique(selected_cols)
    
    message("Querying UniProt with keytype: ", kt)
    message("Selected columns: ", paste(selected_cols, collapse = ", "))
    
    # --- Query UniProt Database ---
    results <- tryCatch({
      select(up, keys = ids, columns = selected_cols, keytype = kt)
    }, error = function(e) {
      message("Batch query failed: ", e\$message)
      NULL
    })
    
    # Fallback: Try individual queries if batch query fails (robustness against bad keys)
    if (is.null(results)) {
      message("Attempting individual queries for robustness...")
      results_list <- list()
      for (id in ids) {
        res_single <- tryCatch({
          select(up, keys = id, columns = selected_cols, keytype = kt)
        }, error = function(e) NULL)
        if (!is.null(res_single)) {
          results_list[[id]] <- res_single
        }
      }
      if (length(results_list) > 0) {
        results <- do.call(rbind, results_list)
      }
    }
    
    # --- Merge Annotations with Input Data ---
    if (!is.null(results) && nrow(results) > 0) {
      # Find the column in results that matches the input keys
      overlap_counts <- sapply(results, function(col) sum(as.character(col) %in% ids, na.rm = TRUE))
      key_col_in_results <- names(overlap_counts)[which.max(overlap_counts)]
    
      # Create a merge key in the original data frame
      if ("feature_id" %in% colnames(df)) {
        df\$merge_key <- as.character(df\$feature_id)
      } else if (is.character(df[[1]]) || is.factor(df[[1]])) {
        df\$merge_key <- as.character(df[[1]])
      } else {
        df\$merge_key <- rownames(df)
      }
    
      merged_df <- merge(df, results, by.x = "merge_key", by.y = key_col_in_results, all.x = TRUE)
      merged_df\$merge_key <- NULL
      message(sprintf("Successfully annotated %d out of %d features.", sum(!is.na(merged_df[[selected_cols[2]]])), nrow(df)))
    } else {
      message("Warning: No annotations could be retrieved. Returning original data.")
      merged_df <- df
      merged_df\$uniprot_error <- "No annotations found or service unavailable"
    }
    
    # Write output table
    write.csv(merged_df, "annotated_features.csv", row.names = FALSE)
    message("Saved annotated features to 'annotated_features.csv'")
    
    # --- Diagnostic Visualizations & Output Generation ---
    message("Generating diagnostic PDF report...")
    pdf("uniprot_annotation_report.pdf", width = 8, height = 8)
    
    # Page 1: Summary Metadata
    plot.new()
    text(0.5, 0.9, "UniProt Annotation Report", cex = 1.6, font = 2)
    text(0.5, 0.75, paste("Taxonomy ID:", tax_id), cex = 1.2)
    text(0.5, 0.65, paste("Total Input Features:", length(ids)), cex = 1.2)
    if (!is.null(results) && nrow(results) > 0) {
      text(0.5, 0.55, paste("Successfully Annotated:", length(unique(results[[1]]))), cex = 1.2, col = "darkgreen")
    } else {
      text(0.5, 0.55, "Successfully Annotated: 0 (Query Failed)", cex = 1.2, col = "red")
    }
    
    # Page 2: Sequence Length Distribution
    if (!is.null(results) && nrow(results) > 0) {
      seq_col <- grep("sequence", colnames(results), ignore.case = TRUE, value = TRUE)
      if (length(seq_col) > 0) {
        seq_lengths <- nchar(as.character(results[[seq_col[1]]]))
        seq_lengths <- seq_lengths[!is.na(seq_lengths)]
        if (length(seq_lengths) > 0) {
          hist(seq_lengths, breaks = 30, col = "skyblue", border = "white",
               main = "Distribution of Annotated Sequence Lengths",
               xlab = "Sequence Length (amino acids)", ylab = "Frequency")
        }
      }
    }
    
    # Page 3: Heatmap of Top Variable Features (if numeric expression data is present)
    numeric_cols <- sapply(df, is.numeric)
    if (any(numeric_cols) && sum(numeric_cols) >= 2) {
      mat <- as.matrix(df[, numeric_cols, drop = FALSE])
      if (nrow(mat) > 1) {
        # Calculate variance to find top variable features
        vars <- apply(mat, 1, var, na.rm = TRUE)
        top_idx <- order(vars, decreasing = TRUE)[1:min(30, nrow(mat))]
        mat_top <- mat[top_idx, , drop = FALSE]
    
        # Map row names to Entry names for better labels
        row_ids <- rownames(df)[top_idx]
        if ("feature_id" %in% colnames(df)) {
          row_ids <- df\$feature_id[top_idx]
        }
        
        labels <- row_ids
        if (!is.null(results) && nrow(results) > 0) {
          entry_col <- grep("entry|name", colnames(results), ignore.case = TRUE, value = TRUE)[1]
          if (!is.na(entry_col)) {
            map_idx <- match(row_ids, results[[key_col_in_results]])
            mapped_labels <- results[[entry_col]][map_idx]
            labels[!is.na(mapped_labels)] <- mapped_labels[!is.na(mapped_labels)]
          }
        }
    
        # Plot heatmap
        heatmap(mat_top, labRow = labels, col = heat.colors(256),
                main = "Heatmap of Top Variable Features", margins = c(10, 10))
      }
    }
    
    dev.off()
    message("Saved diagnostic report to 'uniprot_annotation_report.pdf'")
    message("Pipeline complete!")

    writeLines(c(
        '"BIOC_UNIPROT_WS_UNIPROT_ANNOTATION_PIPELINE":',
        paste0('    uniprot_ws: ', as.character(packageVersion('uniprot_ws')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_uniprot_annotation_pipeline.csv versions.yml
    """
}

workflow BIOC_UNIPROT_WS_UNIPROT_ANNOTATION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_UNIPROT_WS_UNIPROT_ANNOTATION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_UNIPROT_WS_UNIPROT_ANNOTATION_PIPELINE.out.tables
    plots    = BIOC_UNIPROT_WS_UNIPROT_ANNOTATION_PIPELINE.out.plots
    objects  = BIOC_UNIPROT_WS_UNIPROT_ANNOTATION_PIPELINE.out.objects
    versions = BIOC_UNIPROT_WS_UNIPROT_ANNOTATION_PIPELINE.out.versions
}
