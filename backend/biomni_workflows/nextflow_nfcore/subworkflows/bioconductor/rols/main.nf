#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rols — ols_ontology_annotation_pipeline
// Query the Ontology Lookup Service (OLS) to annotate a list of features or genes with standardized ontology terms, retrieve their hierarchical relationships, and
// Input: input.csv
// Container: 3.6.1--r45hdfd78af_0
// R packages: BiocStyle, DT, rols
// Bioconductor: 3.20 | R: 4.4
// Requires: rols
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ROLS_OLS_ONTOLOGY_ANNOTATION_PIPELINE {
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
    .bm_deps <- c("BiocStyle", "DT", "rols")
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
    library(rols)
    
    # ==========================================
    # Stage 1: Read and Parse Input Defensively
    # ==========================================
    input_file <- "input.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "does not exist."))
    }
    
    message("Reading input data...")
    input_data <- read.csv(input_file, stringsAsFactors = FALSE, check.names = FALSE)
    
    # Identify feature IDs and numeric columns
    if ("feature_id" %in% colnames(input_data)) {
      feature_ids <- as.character(input_data\$feature_id)
      numeric_cols <- setdiff(colnames(input_data), "feature_id")
    } else if (ncol(input_data) == 1) {
      feature_ids <- as.character(input_data[[1]])
      numeric_cols <- character(0)
    } else {
      # If first column is non-numeric, assume it contains identifiers
      if (!is.numeric(input_data[[1]])) {
        feature_ids <- as.character(input_data[[1]])
        numeric_cols <- colnames(input_data)[-1]
      } else {
        feature_ids <- as.character(rownames(input_data))
        numeric_cols <- colnames(input_data)
      }
    }
    
    # Clean feature IDs
    feature_ids <- unique(trimws(feature_ids))
    feature_ids <- feature_ids[feature_ids != "" & !is.na(feature_ids)]
    
    if (length(feature_ids) == 0) {
      stop("No valid feature identifiers found in the input file.")
    }
    
    # Limit queries to prevent API rate limits or long execution times
    max_queries <- 40
    if (length(feature_ids) > max_queries) {
      message(sprintf("Input contains %d unique features. Limiting OLS queries to the first %d to ensure fast execution.", length(feature_ids), max_queries))
      feature_ids <- feature_ids[1:max_queries]
    }
    
    # ==========================================
    # Stage 2: Query OLS for Term Metadata
    # ==========================================
    message("Resolving features against the Ontology Lookup Service...")
    
    resolve_term <- function(id) {
      # 1. Try direct instantiation if it looks like an accession (e.g., GO:0005802)
      if (grepl("^[A-Za-z0-9]+:[A-Za-z0-9_]+\$", id)) {
        parts <- strsplit(id, ":")[[1]]
        ont <- tolower(parts[1])
        trm <- tryCatch(olsTerm(ont, id), error = function(e) NULL)
        if (!is.null(trm)) return(trm)
      }
      
      # 2. Try exact search
      qry <- OlsSearch(q = id, exact = TRUE)
      qry <- tryCatch(olsSearch(qry), error = function(e) NULL)
      if (!is.null(qry)) {
        df <- tryCatch(as(qry, "data.frame"), error = function(e) NULL)
        if (!is.null(df) && nrow(df) > 0) {
          ont <- df\$ontology_name[1]
          term_id <- df\$obo_id[1]
          if (!is.na(ont) && !is.na(term_id)) {
            trm <- tryCatch(olsTerm(ont, term_id), error = function(e) NULL)
            if (!is.null(trm)) return(trm)
          }
        }
      }
      
      # 3. Try non-exact search as fallback
      qry_non_exact <- OlsSearch(q = id, exact = FALSE)
      qry_non_exact <- tryCatch(olsSearch(qry_non_exact), error = function(e) NULL)
      if (!is.null(qry_non_exact)) {
        df <- tryCatch(as(qry_non_exact, "data.frame"), error = function(e) NULL)
        if (!is.null(df) && nrow(df) > 0) {
          ont <- df\$ontology_name[1]
          term_id <- df\$obo_id[1]
          if (!is.na(ont) && !is.na(term_id)) {
            trm <- tryCatch(olsTerm(ont, term_id), error = function(e) NULL)
            if (!is.null(trm)) return(trm)
          }
        }
      }
      
      return(NULL)
    }
    
    # Query each feature
    resolved_terms <- list()
    for (fid in feature_ids) {
      message(paste("Querying:", fid))
      trm <- resolve_term(fid)
      if (!is.null(trm)) {
        resolved_terms[[fid]] <- trm
      }
    }
    
    # ==========================================
    # Stage 3: Extract Metadata and Relationships
    # ==========================================
    message("Extracting metadata and hierarchical relationships...")
    
    annotation_list <- list()
    relationship_list <- list()
    
    for (fid in names(resolved_terms)) {
      trm <- resolved_terms[[fid]]
      
      # Extract basic metadata safely
      t_id <- tryCatch(termId(trm), error = function(e) NA)
      t_label <- tryCatch(termLabel(trm), error = function(e) NA)
      t_ont <- tryCatch(termOntology(trm), error = function(e) NA)
      
      # Namespace can be a list or character vector; handle safely
      t_ns <- tryCatch({
        ns <- termNamespace(trm)
        if (is.list(ns)) paste(unlist(ns), collapse = "; ") else as.character(ns)
      }, error = function(e) NA)
      
      # Description can be a list or character vector; handle safely
      t_desc <- tryCatch({
        desc <- termDesc(trm)
        if (is.list(desc)) paste(unlist(desc), collapse = " ") else as.character(desc)
      }, error = function(e) NA)
      
      annotation_list[[fid]] <- data.frame(
        feature_id = fid,
        resolved_id = ifelse(is.null(t_id), NA, t_id),
        label = ifelse(is.null(t_label), NA, t_label),
        ontology = ifelse(is.null(t_ont), NA, t_ont),
        namespace = ifelse(is.null(t_ns) || length(t_ns) == 0, NA, t_ns),
        description = ifelse(is.null(t_desc) || length(t_desc) == 0, NA, t_desc),
        stringsAsFactors = FALSE
      )
      
      # Extract Parents
      t_parents <- tryCatch(parents(trm), error = function(e) NULL)
      if (!is.null(t_parents) && length(t_parents) > 0) {
        for (i in seq_along(t_parents)) {
          p_trm <- t_parents[[i]]
          relationship_list[[length(relationship_list) + 1]] <- data.frame(
            term_id = t_id,
            term_label = t_label,
            relation_type = "parent",
            related_term_id = termId(p_trm),
            related_term_label = termLabel(p_trm),
            stringsAsFactors = FALSE
          )
        }
      }
      
      # Extract Children
      t_children <- tryCatch(children(trm), error = function(e) NULL)
      if (!is.null(t_children) && length(t_children) > 0) {
        for (i in seq_along(t_children)) {
          c_trm <- t_children[[i]]
          relationship_list[[length(relationship_list) + 1]] <- data.frame(
            term_id = t_id,
            term_label = t_label,
            relation_type = "child",
            related_term_id = termId(c_trm),
            related_term_label = termLabel(c_trm),
            stringsAsFactors = FALSE
          )
        }
      }
    }
    
    # Combine annotations
    if (length(annotation_list) > 0) {
      annotated_df <- do.call(rbind, annotation_list)
    } else {
      annotated_df <- data.frame(
        feature_id = character(0), resolved_id = character(0), label = character(0),
        ontology = character(0), namespace = character(0), description = character(0)
      )
    }
    
    # Combine relationships
    if (length(relationship_list) > 0) {
      relationships_df <- do.call(rbind, relationship_list)
    } else {
      relationships_df <- data.frame(
        term_id = character(0), term_label = character(0), relation_type = character(0),
        related_term_id = character(0), related_term_label = character(0)
      )
    }
    
    # Write primary outputs
    write.csv(annotated_df, "annotated_features.csv", row.names = FALSE)
    write.csv(relationships_df, "term_relationships.csv", row.names = FALSE)
    message("Saved annotated_features.csv and term_relationships.csv")
    
    # ==========================================
    # Stage 4: Aggregate Expression Data (If Present)
    # ==========================================
    if (length(numeric_cols) > 0 && nrow(annotated_df) > 0) {
      message("Aggregating expression profiles by ontology namespace...")
      
      # Merge input numeric data with annotations
      # Reconstruct matrix with feature_id
      if ("feature_id" %in% colnames(input_data)) {
        expr_data <- input_data
      } else {
        expr_data <- input_data
        expr_data\$feature_id <- if (!is.numeric(input_data[[1]])) as.character(input_data[[1]]) else rownames(input_data)
      }
      
      merged_data <- merge(annotated_df[, c("feature_id", "namespace")], expr_data, by = "feature_id")
      
      # Filter out rows with missing namespace
      merged_data <- merged_data[!is.na(merged_data\$namespace) & merged_data\$namespace != "", ]
      
      if (nrow(merged_data) > 0) {
        # Aggregate numeric columns by namespace
        agg_list <- list()
        unique_namespaces <- unique(merged_data\$namespace)
        
        for (ns in unique_namespaces) {
          sub_data <- merged_data[merged_data\$namespace == ns, numeric_cols, drop = FALSE]
          # Convert columns to numeric safely
          sub_data[] <- lapply(sub_data, as.numeric)
          mean_profile <- colMeans(sub_data, na.rm = TRUE)
          agg_list[[ns]] <- c(namespace = ns, mean_profile)
        }
        
        aggregated_df <- as.data.frame(do.call(rbind, agg_list), stringsAsFactors = FALSE)
        write.csv(aggregated_df, "aggregated_ontology_expression.csv", row.names = FALSE)
        message("Saved aggregated_ontology_expression.csv")
      } else {
        # Fallback empty file
        write.csv(data.frame(namespace = character(0)), "aggregated_ontology_expression.csv", row.names = FALSE)
      }
    } else {
      # Fallback empty file
      write.csv(data.frame(namespace = character(0)), "aggregated_ontology_expression.csv", row.names = FALSE)
    }
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_ROLS_OLS_ONTOLOGY_ANNOTATION_PIPELINE":',
        paste0('    rols: ', as.character(packageVersion('rols')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ols_ontology_annotation_pipeline.csv versions.yml
    """
}

workflow BIOC_ROLS_OLS_ONTOLOGY_ANNOTATION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ROLS_OLS_ONTOLOGY_ANNOTATION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_ROLS_OLS_ONTOLOGY_ANNOTATION_PIPELINE.out.tables
    plots    = BIOC_ROLS_OLS_ONTOLOGY_ANNOTATION_PIPELINE.out.plots
    objects  = BIOC_ROLS_OLS_ONTOLOGY_ANNOTATION_PIPELINE.out.objects
    versions = BIOC_ROLS_OLS_ONTOLOGY_ANNOTATION_PIPELINE.out.versions
}
