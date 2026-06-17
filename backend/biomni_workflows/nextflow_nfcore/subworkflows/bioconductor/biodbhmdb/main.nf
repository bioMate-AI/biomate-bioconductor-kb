#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: biodbHmdb — hmdb_metabolite_annotation_and_differential_analysis
// Annotate metabolomics features using the HMDB database via biodbHmdb and perform differential abundance analysis.
// Input: intensity.csv, coldata.csv
// Container: 1.12.0--r44he5774e6_0
// R packages: biodb, biodbHmdb
// Bioconductor: 3.20 | R: 4.4
// Requires: biodb, biodbHmdb
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIODBHMDB_HMDB_METABOLITE_ANNOTATION_AND_DIFFERENTIAL_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps"

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
    .bm_deps <- c("biodb", "biodbHmdb")
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
    library(biodb)
    library(biodbHmdb)
    
    # --- Load Input Data ---
    if (!file.exists("intensity.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'intensity.csv' and/or 'coldata.csv' are missing.")
    }
    
    intensity <- read.csv("intensity.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Align samples between intensity matrix and coldata
    common_samples <- intersect(colnames(intensity), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("No matching samples found between intensity matrix columns and coldata 'sample' column.")
    }
    intensity <- intensity[, common_samples, drop = FALSE]
    coldata <- coldata[coldata\$sample %in% common_samples, ]
    
    # --- Initialize biodb and HMDB Connector ---
    message("Initializing biodb and HMDB connector...")
    bd <- biodb::newBiodb()
    conn <- NULL
    
    tryCatch({
      if (bd\$getFactory()\$isRegistered('hmdb.metabolites')) {
        conn <- bd\$getFactory()\$createConn('hmdb.metabolites')
      } else {
        warning("HMDB Metabolites connector is not registered in the biodb factory.")
      }
    }, error = function(e) {
      warning("Failed to initialize HMDB connector: ", e\$message)
    })
    
    # --- Retrieve HMDB Annotations ---
    feature_ids <- rownames(intensity)
    hmdb_ids <- feature_ids[grep("^HMDB\\\\d+", feature_ids)]
    
    # Initialize default annotation data frame
    annot_df <- data.frame(
      feature_id = feature_ids,
      metabolite_name = feature_ids,
      formula = NA,
      molecular_weight = NA,
      stringsAsFactors = FALSE
    )
    
    if (!is.null(conn) && length(hmdb_ids) > 0) {
      message("Querying HMDB database for ", length(hmdb_ids), " features...")
      tryCatch({
        # Retrieve properties for the HMDB IDs
        db_annot <- conn\$getEntryPropertiesAsDf(hmdb_ids)
        
        if (!is.null(db_annot) && nrow(db_annot) > 0) {
          # Standardize identifier column for merging
          if ("accession" %in% colnames(db_annot)) {
            db_annot\$feature_id <- db_annot\$accession
          } else if ("id" %in% colnames(db_annot)) {
            db_annot\$feature_id <- db_annot\$id
          }
          
          # Extract useful columns if they exist
          name_col <- intersect(c("name", "title"), colnames(db_annot))[1]
          formula_col <- intersect(c("chemical.formula", "formula"), colnames(db_annot))[1]
          mw_col <- intersect(c("average.molecular.weight", "molecular.weight", "mono.mass"), colnames(db_annot))[1]
          
          # Build clean annotation mapping
          clean_db <- data.frame(feature_id = db_annot\$feature_id, stringsAsFactors = FALSE)
          if (!is.na(name_col)) clean_db\$metabolite_name <- db_annot[[name_col]]
          if (!is.na(formula_col)) clean_db\$formula <- db_annot[[formula_col]]
          if (!is.na(mw_col)) clean_db\$molecular_weight <- as.numeric(db_annot[[mw_col]])
          
          # Merge back with the full feature list
          annot_df <- merge(annot_df[, !colnames(annot_df) %in% colnames(clean_db)[-1]], clean_db, by = "feature_id", all.x = TRUE)
        }
      }, error = function(e) {
        warning("Failed to retrieve annotations from HMDB: ", e\$message)
      })
    } else {
      message("No HMDB-format IDs detected or connector unavailable; skipping database query.")
    }
    
    # --- Differential Abundance Analysis ---
    message("Performing differential abundance analysis...")
    conditions <- unique(coldata\$condition)
    p_values <- rep(NA, nrow(intensity))
    log2_fc <- rep(0, nrow(intensity))
    
    if (length(conditions) >= 2) {
      cond1_samples <- coldata\$sample[coldata\$condition == conditions[1]]
      cond2_samples <- coldata\$sample[coldata\$condition == conditions[2]]
      
      # Check if data needs log transformation
      is_large <- max(intensity, na.rm = TRUE) > 50
      
      for (i in seq_len(nrow(intensity))) {
        val1 <- as.numeric(intensity[i, cond1_samples])
        val2 <- as.numeric(intensity[i, cond2_samples])
        
        # Calculate Log2 Fold Change
        if (is_large) {
          log2_fc[i] <- mean(log(val2 + 1, 2), na.rm = TRUE) - mean(log(val1 + 1, 2), na.rm = TRUE)
        } else {
          log2_fc[i] <- mean(val2, na.rm = TRUE) - mean(val1, na.rm = TRUE)
        }
        
        # Two-sample t-test
        tt <- tryCatch(t.test(val2, val1), error = function(e) NULL)
        if (!is.null(tt)) {
          p_values[i] <- tt\$p.value
        }
      }
    } else {
      warning("Fewer than 2 conditions found in coldata.csv; skipping statistical testing.")
    }
    
    # Adjust p-values for multiple testing
    adj_p_values <- p.adjust(p_values, method = "BH")
    
    # Combine statistics
    stats_df <- data.frame(
      feature_id = rownames(intensity),
      log2FC = log2_fc,
      p_value = p_values,
      adj_p_value = adj_p_values,
      stringsAsFactors = FALSE
    )
    
    # Merge statistics with HMDB annotations
    final_results <- merge(stats_df, annot_df, by = "feature_id", all.x = TRUE)
    
    # Write results to CSV
    write.csv(final_results, "annotated_differential_metabolites.csv", row.names = FALSE)
    message("Saved annotated results to 'annotated_differential_metabolites.csv'")
    
    # --- Visualization ---
    message("Generating diagnostic plots...")
    pdf("metabolite_analysis_plots.pdf", width = 8, height = 6)
    
    # Volcano Plot
    plot(final_results\$log2FC, -log10(final_results\$p_value),
         pch = 21, bg = ifelse(final_results\$adj_p_value < 0.05, "red", "grey"),
         xlab = "log2 Fold Change", ylab = "-log10(p-value)",
         main = "Volcano Plot of Metabolites",
         xlim = c(-max(abs(final_results\$log2FC), na.rm = TRUE) - 0.5, max(abs(final_results\$log2FC), na.rm = TRUE) + 0.5))
    abline(h = -log10(0.05), col = "blue", lty = 2)
    abline(v = c(-1, 1), col = "blue", lty = 2)
    
    # Label top significant metabolites
    sig_idx <- which(final_results\$adj_p_value < 0.05)
    if (length(sig_idx) > 0) {
      top_sig <- sig_idx[order(final_results\$p_value[sig_idx])][1:min(5, length(sig_idx))]
      text(final_results\$log2FC[top_sig], -log10(final_results\$p_value[top_sig]),
           labels = final_results\$metabolite_name[top_sig], pos = 3, cex = 0.7, col = "darkred")
    }
    
    dev.off()
    message("Saved plots to 'metabolite_analysis_plots.pdf'")
    
    # Clean up biodb instance
    if (!is.null(bd)) {
      bd\$terminate()
    }
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_BIODBHMDB_HMDB_METABOLITE_ANNOTATION_AND_DIFFERENTIAL_ANALYSIS":',
        paste0('    biodbHmdb: ', as.character(packageVersion('biodbHmdb')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hmdb_metabolite_annotation_and_differential_analysis.csv versions.yml
    """
}

workflow BIOC_BIODBHMDB_HMDB_METABOLITE_ANNOTATION_AND_DIFFERENTIAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BIODBHMDB_HMDB_METABOLITE_ANNOTATION_AND_DIFFERENTIAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BIODBHMDB_HMDB_METABOLITE_ANNOTATION_AND_DIFFERENTIAL_ANALYSIS.out.tables
    plots    = BIOC_BIODBHMDB_HMDB_METABOLITE_ANNOTATION_AND_DIFFERENTIAL_ANALYSIS.out.plots
    objects  = BIOC_BIODBHMDB_HMDB_METABOLITE_ANNOTATION_AND_DIFFERENTIAL_ANALYSIS.out.objects
    versions = BIOC_BIODBHMDB_HMDB_METABOLITE_ANNOTATION_AND_DIFFERENTIAL_ANALYSIS.out.versions
}
