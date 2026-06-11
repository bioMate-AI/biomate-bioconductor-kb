#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ginmappeR — ginmapper_proteomics_translation
// Perform differential abundance analysis on proteomics intensity data, map the significant UniProt protein identifiers to CARD, KEGG, and NCBI databases, and ret
// Input: intensity.csv, coldata.csv
// Container: 1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ginmappeR
// Visualizations: box plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GINMAPPER_GINMAPPER_PROTEOMICS_TRANSLATION {
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
    
    # Load required libraries
    library(ginmappeR)
    library(stats)
    library(grDevices)
    library(graphics)
    library(utils)
    
    # ==========================================
    # --- Load and Pre-process Input Data ---
    # ==========================================
    
    message("Loading input datasets...")
    intensity_df <- read.csv("intensity.csv", check.names = FALSE, stringsAsFactors = FALSE)
    coldata_df <- read.csv("coldata.csv", check.names = FALSE, stringsAsFactors = FALSE)
    
    # Ensure feature_id is set as row names
    if ("feature_id" %in% colnames(intensity_df)) {
      rownames(intensity_df) <- intensity_df\$feature_id
      intensity_df\$feature_id <- NULL
    } else {
      stop("Input intensity.csv must contain a 'feature_id' column.")
    }
    
    # Align intensity columns with coldata samples
    common_samples <- intersect(colnames(intensity_df), coldata_df\$sample)
    if (length(common_samples) == 0) {
      stop("No matching samples found between intensity.csv and coldata.csv.")
    }
    
    intensity_matrix <- as.matrix(intensity_df[, common_samples, drop = FALSE])
    coldata_df <- coldata_df[match(common_samples, coldata_df\$sample), , drop = FALSE]
    
    # Log2 transformation and filtering of low-variance features
    message("Preprocessing and normalizing intensity data...")
    log_intensity <- log2(intensity_matrix + 1)
    row_vars <- apply(log_intensity, 1, var, na.rm = TRUE)
    valid_features <- which(!is.na(row_vars) & row_vars > 0)
    log_intensity <- log_intensity[valid_features, , drop = FALSE]
    
    # ==========================================
    # --- Differential Abundance Analysis ---
    # ==========================================
    
    message("Performing differential abundance analysis...")
    conditions <- as.factor(coldata_df\$condition)
    levels_cond <- levels(conditions)
    
    if (length(levels_cond) < 2) {
      stop("At least two conditions are required in coldata.csv for comparison.")
    }
    
    # Compare the first two conditions
    cond1 <- levels_cond[1]
    cond2 <- levels_cond[2]
    idx1 <- which(conditions == cond1)
    idx2 <- which(conditions == cond2)
    
    stats_res <- data.frame(
      Protein_ID = rownames(log_intensity),
      Mean_Cond1 = rowMeans(log_intensity[, idx1, drop = FALSE], na.rm = TRUE),
      Mean_Cond2 = rowMeans(log_intensity[, idx2, drop = FALSE], na.rm = TRUE),
      stringsAsFactors = FALSE
    )
    stats_res\$Log2FC <- stats_res\$Mean_Cond2 - stats_res\$Mean_Cond1
    
    # Compute t-test p-values
    p_values <- apply(log_intensity, 1, function(row) {
      tryCatch({
        t.test(row[idx1], row[idx2])\$p.value
      }, error = function(e) NA)
    })
    
    stats_res\$P_Value <- p_values
    stats_res\$Adj_P_Value <- p.adjust(p_values, method = "BH")
    stats_res <- stats_res[order(stats_res\$P_Value), ]
    
    # ==========================================
    # --- ID Mapping using ginmappeR ---
    # ==========================================
    
    message("Mapping identifiers using ginmappeR...")
    # Select top proteins for mapping (up to 50 to avoid API rate limits)
    top_proteins <- head(stats_res, 50)
    uniprot_ids <- top_proteins\$Protein_ID
    
    # Initialize mapping columns
    top_proteins\$CARD_ID <- NA
    top_proteins\$KEGG_ID <- NA
    top_proteins\$NCBI_Protein <- NA
    top_proteins\$NCBI_Gene <- NA
    
    # Helper function to safely run ginmappeR API calls
    safe_map <- function(mapping_func, ids) {
      tryCatch({
        mapping_func(ids)
      }, error = function(e) {
        warning("API mapping failed: ", e\$message)
        return(rep(NA, length(ids)))
      })
    }
    
    # Perform bidirectional/cross-database translations
    top_proteins\$CARD_ID <- safe_map(getCARD2UniProt, uniprot_ids) # Try mapping to CARD
    top_proteins\$KEGG_ID <- safe_map(getUniProt2KEGG, uniprot_ids)
    top_proteins\$NCBI_Protein <- safe_map(getUniProt2NCBIProtein, uniprot_ids)
    top_proteins\$NCBI_Gene <- safe_map(getUniProt2NCBIGene, uniprot_ids)
    
    # Write mapped differential abundance results
    write.csv(top_proteins, "differential_abundance_mapped.csv", row.names = FALSE)
    
    # ==========================================
    # --- Retrieve Similar Gene Clusters ---
    # ==========================================
    
    message("Retrieving UniProt similar gene clusters...")
    similar_genes_df <- data.frame(Query_Protein = character(), Similar_Protein = character(), stringsAsFactors = FALSE)
    
    if (length(uniprot_ids) > 0) {
      top_id <- uniprot_ids[1]
      similar_clusters <- tryCatch({
        getUniProtSimilarGenes(top_id, clusterIdentity = "0.9")
      }, error = function(e) {
        warning("Failed to retrieve similar genes: ", e\$message)
        NULL
      })
      
      if (!is.null(similar_clusters) && length(similar_clusters) > 0) {
        similar_genes_df <- data.frame(
          Query_Protein = top_id,
          Similar_Protein = unlist(similar_clusters),
          stringsAsFactors = FALSE
        )
      } else {
        similar_genes_df <- data.frame(
          Query_Protein = top_id,
          Similar_Protein = "No similar genes found or API timeout",
          stringsAsFactors = FALSE
        )
      }
    }
    
    write.csv(similar_genes_df, "similar_genes_top_protein.csv", row.names = FALSE)
    
    # ==========================================
    # --- Visualization and Diagnostics ---
    # ==========================================
    
    message("Generating diagnostic plots...")
    pdf("differential_abundance_plots.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    
    # Plot 1: Volcano Plot
    plot(
      stats_res\$Log2FC, 
      -log10(stats_res\$P_Value),
      pch = 19, 
      col = ifelse(stats_res\$P_Value < 0.05, "red", "black"),
      xlab = "Log2 Fold Change", 
      ylab = "-log10(P-Value)",
      main = "Differential Abundance Volcano Plot"
    )
    abline(h = -log10(0.05), col = "blue", lty = 2)
    abline(v = c(-1, 1), col = "blue", lty = 2)
    
    # Plot 2: Boxplot of the top differentially abundant protein
    if (nrow(stats_res) > 0) {
      top_protein_id <- stats_res\$Protein_ID[1]
      boxplot(
        log_intensity[top_protein_id, ] ~ conditions,
        col = c("lightblue", "lightgreen"),
        xlab = "Condition",
        ylab = "Log2 Intensity",
        main = paste("Top Protein:", top_protein_id)
      )
    } else {
      plot.new()
      text(0.5, 0.5, "No proteins available for boxplot")
    }
    
    dev.off()
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_GINMAPPER_GINMAPPER_PROTEOMICS_TRANSLATION":',
        paste0('    ginmappeR: ', as.character(packageVersion('ginmappeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ginmapper_proteomics_translation.csv versions.yml
    """
}

workflow BIOC_GINMAPPER_GINMAPPER_PROTEOMICS_TRANSLATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_GINMAPPER_GINMAPPER_PROTEOMICS_TRANSLATION(ch_input)

    emit:
    tables   = BIOC_GINMAPPER_GINMAPPER_PROTEOMICS_TRANSLATION.out.tables
    plots    = BIOC_GINMAPPER_GINMAPPER_PROTEOMICS_TRANSLATION.out.plots
    objects  = BIOC_GINMAPPER_GINMAPPER_PROTEOMICS_TRANSLATION.out.objects
    versions = BIOC_GINMAPPER_GINMAPPER_PROTEOMICS_TRANSLATION.out.versions
}
