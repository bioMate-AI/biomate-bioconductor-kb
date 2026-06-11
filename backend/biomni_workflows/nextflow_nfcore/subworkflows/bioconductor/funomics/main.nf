#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: funOmics — funomics_pathway_aggregation
// Aggregate proteomics intensity data into KEGG pathway-level functional activity scores using multiple pooling operators, identify short pathways, and perform di
// Input: intensity.csv, coldata.csv
// Container: 1.4.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, funOmics
// Visualizations: heatmap
// QC: low-count filtering
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FUNOMICS_FUNOMICS_PATHWAY_AGGREGATION {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # --- Load libraries and input data ---
    library(funOmics)
    
    message("Loading input datasets...")
    intensity_df <- read.csv("intensity.csv", check.names = FALSE, stringsAsFactors = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Set feature_id as row names and convert to matrix
    if (!"feature_id" %in% colnames(intensity_df)) {
      stop("Input intensity.csv must contain a 'feature_id' column.")
    }
    rownames(intensity_df) <- intensity_df\$feature_id
    intensity_matrix <- as.matrix(intensity_df[, setdiff(colnames(intensity_df), "feature_id"), drop = FALSE])
    
    # Align samples between intensity matrix and coldata
    common_samples <- intersect(colnames(intensity_matrix), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("No matching samples found between intensity.csv and coldata.csv.")
    }
    intensity_matrix <- intensity_matrix[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), , drop = FALSE]
    
    # --- Determine identifier type and retrieve KEGG pathway sets ---
    # Check if IDs look like Ensembl (e.g., ENSG...) or Gene Symbols
    first_ids <- head(rownames(intensity_matrix), 50)
    is_ensembl <- any(grepl("^ENSG", first_ids))
    detected_id_type <- if (is_ensembl) "ensembl" else "symbol"
    
    message(paste("Detected identifier type:", detected_id_type))
    kegg_sets <- get_kegg_sets(organism = "hsa", geneid_type = detected_id_type)
    
    # --- Filter and clean the intensity matrix ---
    # NMF and PCA require non-negative values and no completely null rows
    intensity_matrix[is.na(intensity_matrix)] <- 0
    intensity_matrix[intensity_matrix < 0] <- 0
    intensity_matrix <- intensity_matrix[rowSums(intensity_matrix) > 0, , drop = FALSE]
    
    # --- Perform pathway-level aggregation ---
    message("Aggregating pathway-level activity scores...")
    minsize_threshold <- 10
    
    # 4.1 PCA Aggregation
    pathway_pca <- tryCatch({
      summarize_pathway_level(intensity_matrix, kegg_sets, type = "pca", minsize = minsize_threshold)
    }, error = function(e) {
      message("PCA aggregation failed: ", e\$message)
      NULL
    })
    
    # 4.2 Mean Aggregation
    pathway_mean <- tryCatch({
      summarize_pathway_level(intensity_matrix, kegg_sets, type = "mean", minsize = minsize_threshold)
    }, error = function(e) {
      message("Mean aggregation failed: ", e\$message)
      NULL
    })
    
    # 4.3 NMF Aggregation
    pathway_nmf <- tryCatch({
      summarize_pathway_level(intensity_matrix, kegg_sets, type = "nmf", minsize = minsize_threshold)
    }, error = function(e) {
      message("NMF aggregation failed: ", e\$message)
      NULL
    })
    
    # Save aggregated matrices
    if (!is.null(pathway_pca)) {
      write.csv(as.data.frame(pathway_pca), "pathway_activity_pca.csv", row.names = TRUE)
    }
    if (!is.null(pathway_mean)) {
      write.csv(as.data.frame(pathway_mean), "pathway_activity_mean.csv", row.names = TRUE)
    }
    if (!is.null(pathway_nmf)) {
      write.csv(as.data.frame(pathway_nmf), "pathway_activity_nmf.csv", row.names = TRUE)
    }
    
    # --- Identify and document short pathways ---
    message("Identifying short pathways excluded from aggregation...")
    short_sets <- short_sets_detail(kegg_sets, minsize = minsize_threshold)
    short_sets_df <- data.frame(
      pathway = short_sets\$short_sets,
      length = short_sets\$short_sets_lengths,
      stringsAsFactors = FALSE
    )
    write.csv(short_sets_df, "short_pathways_detail.csv", row.names = FALSE)
    
    # --- Differential pathway activity analysis ---
    message("Performing differential pathway activity analysis...")
    if (!is.null(pathway_mean) && "condition" %in% colnames(coldata)) {
      conditions <- unique(coldata\$condition)
      if (length(conditions) >= 2) {
        g1 <- coldata\$sample[coldata\$condition == conditions[1]]
        g2 <- coldata\$sample[coldata\$condition == conditions[2]]
        
        diff_results <- apply(pathway_mean, 1, function(row) {
          t_res <- tryCatch(t.test(row[g1], row[g2]), error = function(e) NULL)
          if (!is.null(t_res)) {
            c(p_value = t_res\$p.value, 
              t_stat = t_res\$statistic[[1]], 
              mean_cond1 = t_res\$estimate[1], 
              mean_cond2 = t_res\$estimate[2])
          } else {
            c(p_value = NA, t_stat = NA, mean_cond1 = NA, mean_cond2 = NA)
          }
        })
        
        diff_df <- as.data.frame(t(diff_results))
        diff_df\$pathway <- rownames(diff_df)
        diff_df\$adj_p_value <- p.adjust(diff_df\$p_value, method = "BH")
        diff_df <- diff_df[, c("pathway", "t_stat", "p_value", "adj_p_value", "mean_cond1.mean of x", "mean_cond2.mean of y")]
        colnames(diff_df)[5:6] <- paste0("mean_", conditions[1:2])
        
        write.csv(diff_df, "differential_pathway_activity.csv", row.names = FALSE)
      } else {
        write.csv(data.frame(message = "Fewer than 2 conditions found; skipping differential analysis."), 
                  "differential_pathway_activity.csv", row.names = FALSE)
      }
    } else {
      write.csv(data.frame(message = "Mean pathway activity matrix or condition column missing."), 
                "differential_pathway_activity.csv", row.names = FALSE)
    }
    
    # --- Visualization ---
    message("Generating pathway activity heatmap...")
    pdf("pathway_activity_heatmap.pdf", width = 10, height = 8)
    if (!is.null(pathway_mean) && nrow(pathway_mean) > 1) {
      # Select top 20 most variable pathways for visualization
      row_vars <- apply(pathway_mean, 1, var, na.rm = TRUE)
      top_20_indices <- head(order(row_vars, decreasing = TRUE), 20)
      heatmap_data <- pathway_mean[top_20_indices, , drop = FALSE]
      
      heatmap(heatmap_data, 
              main = "Top 20 Most Variable Pathways (Mean Aggregation)",
              col = heat.colors(256), 
              margins = c(10, 15))
    } else {
      plot.new()
      text(0.5, 0.5, "Insufficient data to generate heatmap")
    }
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_FUNOMICS_FUNOMICS_PATHWAY_AGGREGATION":',
        paste0('    funOmics: ', as.character(packageVersion('funOmics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_funomics_pathway_aggregation.csv versions.yml
    """
}

workflow BIOC_FUNOMICS_FUNOMICS_PATHWAY_AGGREGATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_FUNOMICS_FUNOMICS_PATHWAY_AGGREGATION(ch_input)

    emit:
    tables   = BIOC_FUNOMICS_FUNOMICS_PATHWAY_AGGREGATION.out.tables
    plots    = BIOC_FUNOMICS_FUNOMICS_PATHWAY_AGGREGATION.out.plots
    objects  = BIOC_FUNOMICS_FUNOMICS_PATHWAY_AGGREGATION.out.objects
    versions = BIOC_FUNOMICS_FUNOMICS_PATHWAY_AGGREGATION.out.versions
}
