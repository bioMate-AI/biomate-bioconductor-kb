#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: hpar — hpa_proteomics_annotation
// Annotate and contextualize experimental proteomics abundance data with Human Protein Atlas (HPA) tissue expression, subcellular localization, and secretome stat
// Input: intensity.csv, coldata.csv
// Container: 1.52.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocGenerics, hpar
// Visualizations: bar plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HPAR_HPA_PROTEOMICS_ANNOTATION {
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
    library(hpar)
    library(BiocGenerics)
    
    # --- Load Experimental Proteomics Data ---
    message("Loading experimental proteomics data...")
    if (!file.exists("intensity.csv") || !file.exists("coldata.csv")) {
        stop("Required input files 'intensity.csv' and/or 'coldata.csv' are missing.")
    }
    
    intensity_df <- read.csv("intensity.csv", stringsAsFactors = FALSE)
    coldata_df <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Validate input structure
    if (!"feature_id" %in% colnames(intensity_df)) {
        # If feature_id is not a column, assume the first column is the feature ID
        colnames(intensity_df)[1] <- "feature_id"
    }
    
    # --- Perform Differential Abundance Analysis (Simple Two-Group ---
    message("Performing differential abundance analysis...")
    samples <- coldata_df\$sample
    conditions <- coldata_df\$condition
    unique_conds <- unique(conditions)
    
    if (length(unique_conds) < 2) {
        message("Warning: Less than 2 conditions found. Calculating overall mean intensity instead.")
        intensity_df\$mean_intensity <- rowMeans(intensity_df[, samples, drop = FALSE], na.rm = TRUE)
        intensity_df\$log2FC <- 0
        intensity_df\$p_value <- 1
    } else {
        cond1_samples <- coldata_df\$sample[coldata_df\$condition == unique_conds[1]]
        cond2_samples <- coldata_df\$sample[coldata_df\$condition == unique_conds[2]]
        
        # Ensure samples exist in intensity columns
        cond1_samples <- intersect(cond1_samples, colnames(intensity_df))
        cond2_samples <- intersect(cond2_samples, colnames(intensity_df))
        
        if (length(cond1_samples) > 0 && length(cond2_samples) > 0) {
            mean_cond1 <- rowMeans(intensity_df[, cond1_samples, drop = FALSE], na.rm = TRUE)
            mean_cond2 <- rowMeans(intensity_df[, cond2_samples, drop = FALSE], na.rm = TRUE)
            
            intensity_df\$mean_cond1 <- mean_cond1
            intensity_df\$mean_cond2 <- mean_cond2
            intensity_df\$log2FC <- mean_cond2 - mean_cond1
            
            # Calculate simple t-test p-values if replicates allow
            p_vals <- apply(intensity_df[, c(cond1_samples, cond2_samples), drop = FALSE], 1, function(row) {
                val1 <- as.numeric(row[cond1_samples])
                val2 <- as.numeric(row[cond2_samples])
                if (sum(!is.na(val1)) >= 2 && sum(!is.na(val2)) >= 2 && var(val1, na.rm=TRUE) > 0 && var(val2, na.rm=TRUE) > 0) {
                    return(t.test(val1, val2, var.equal = FALSE)\$p.value)
                } else {
                    return(NA)
                }
            })
            intensity_df\$p_value <- p_vals
        } else {
            intensity_df\$log2FC <- 0
            intensity_df\$p_value <- NA
        }
    }
    
    # --- Fetch Human Protein Atlas (HPA) Datasets ---
    message("Fetching Human Protein Atlas datasets...")
    subcell_loc <- hpaSubcellularLoc()
    norm_tissue <- hpaNormalTissue()
    secretome <- hpaSecretome()
    
    # --- Map Experimental Features to HPA Annotations ---
    message("Mapping experimental features to HPA annotations...")
    # Determine if feature_ids are Ensembl IDs or Gene Symbols
    sample_ids <- head(intensity_df\$feature_id, 50)
    is_ensembl <- any(grepl("^ENSG", sample_ids))
    
    if (is_ensembl) {
        message("Detected Ensembl Gene IDs as feature identifiers.")
        # Map Subcellular Location
        subcell_mapped <- subcell_loc[match(intensity_df\$feature_id, subcell_loc\$Gene), ]
        # Map Secretome Status
        secretome_mapped <- secretome[match(intensity_df\$feature_id, secretome\$Gene), ]
    } else {
        message("Detected Gene Symbols (or other formats) as feature identifiers.")
        # Map Subcellular Location using Gene name
        subcell_mapped <- subcell_loc[match(intensity_df\$feature_id, subcell_loc\$Gene.name), ]
        # Map Secretome Status (secretome dataset only has 'Gene' Ensembl IDs, so we map via subcell_loc first)
        ensembl_ids <- subcell_loc\$Gene[match(intensity_df\$feature_id, subcell_loc\$Gene.name)]
        secretome_mapped <- secretome[match(ensembl_ids, secretome\$Gene), ]
    }
    
    # Combine annotations into a single data frame
    annotated_df <- intensity_df
    annotated_df\$HPA_Ensembl <- if(is_ensembl) intensity_df\$feature_id else subcell_loc\$Gene[match(intensity_df\$feature_id, subcell_loc\$Gene.name)]
    annotated_df\$HPA_Gene_Name <- subcell_mapped\$Gene.name
    annotated_df\$Subcellular_Reliability <- subcell_mapped\$Reliability
    annotated_df\$Main_Location <- subcell_mapped\$Main.location
    annotated_df\$GO_ID <- subcell_mapped\$GO.id
    
    # Add Secretome status (e.g., whether it is predicted to be secreted)
    # The secretome dataset contains genes with at least one predicted secreted transcript.
    annotated_df\$Is_Secreted <- !is.na(secretome_mapped\$Gene)
    
    # Map Normal Tissue Expression (summarize to find tissues with High/Medium expression)
    message("Summarizing normal tissue expression profiles...")
    if (is_ensembl) {
        tissue_sub <- norm_tissue[norm_tissue\$Gene %in% annotated_df\$HPA_Ensembl, ]
    } else {
        tissue_sub <- norm_tissue[norm_tissue\$Gene.name %in% annotated_df\$feature_id, ]
    }
    
    if (nrow(tissue_sub) > 0) {
        # Find the tissue with the highest expression level for each gene
        # Levels: High > Medium > Low > Not detected
        tissue_sub\$Level_Score <- factor(tissue_sub\$Level, levels = c("Not detected", "Low", "Medium", "High"), ordered = TRUE)
        
        # Aggregate to find the top tissue and level per gene
        tissue_agg <- do.call(rbind, lapply(split(tissue_sub, tissue_sub\$Gene), function(sub_df) {
            best_row <- sub_df[which.max(sub_df\$Level_Score), ]
            data.frame(
                Gene = best_row\$Gene,
                Top_Tissue = best_row\$Tissue,
                Top_Cell_Type = best_row\$Cell.type,
                Max_Expression_Level = best_row\$Level,
                stringsAsFactors = FALSE
            )
        }))
        
        annotated_df\$Top_Tissue <- tissue_agg\$Top_Tissue[match(annotated_df\$HPA_Ensembl, tissue_agg\$Gene)]
        annotated_df\$Top_Cell_Type <- tissue_agg\$Top_Cell_Type[match(annotated_df\$HPA_Ensembl, tissue_agg\$Gene)]
        annotated_df\$Max_Expression_Level <- tissue_agg\$Max_Expression_Level[match(annotated_df\$HPA_Ensembl, tissue_agg\$Gene)]
    } else {
        annotated_df\$Top_Tissue <- NA
        annotated_df\$Top_Cell_Type <- NA
        annotated_df\$Max_Expression_Level <- NA
    }
    
    # Write annotated results
    write.csv(annotated_df, "hpa_annotated_proteomics.csv", row.names = FALSE)
    message("Annotated proteomics data written to 'hpa_annotated_proteomics.csv'.")
    
    # --- Generate Visualizations and Diagnostic Plots ---
    message("Generating summary visualizations...")
    pdf("hpa_proteomics_summary.pdf", width = 10, height = 8)
    
    # Set up plotting layout
    par(mfrow = c(2, 2), mar = c(5, 4, 4, 2) + 0.1)
    
    # Plot 1: Subcellular Localization Distribution
    loc_counts <- table(unlist(strsplit(as.character(annotated_df\$Main_Location[!is.na(annotated_df\$Main_Location)]), ";")))
    if (length(loc_counts) > 0) {
        loc_counts <- sort(loc_counts, decreasing = TRUE)
        # Limit to top 10 locations for readability
        top_locs <- head(loc_counts, 10)
        barplot(top_locs, las = 2, col = "skyblue", main = "Top Subcellular Locations", 
                ylab = "Number of Proteins", cex.names = 0.7)
    } else {
        plot.new()
        text(0.5, 0.5, "No Subcellular Location Data Available", cex = 1.2)
    }
    
    # Plot 2: Secretome Classification
    secreted_counts <- table(Factor_Secreted = factor(annotated_df\$Is_Secreted, levels = c(TRUE, FALSE), labels = c("Secreted", "Non-Secreted")))
    barplot(secreted_counts, col = c("coral", "lightgrey"), main = "Secretome Classification",
            ylab = "Number of Proteins")
    
    # Plot 3: Maximum Expression Level in Normal Tissues
    expr_levels <- table(factor(annotated_df\$Max_Expression_Level, levels = c("High", "Medium", "Low", "Not detected")))
    barplot(expr_levels, col = c("darkred", "orange", "yellow", "lightgrey"), 
            main = "Max Expression Level in Normal Tissues", ylab = "Number of Proteins")
    
    # Plot 4: Volcano Plot of Differential Abundance with HPA Highlights
    if ("log2FC" %in% colnames(annotated_df) && "p_value" %in% colnames(annotated_df) && any(!is.na(annotated_df\$p_value))) {
        log_p <- -log10(annotated_df\$p_value)
        plot(annotated_df\$log2FC, log_p, pch = 16, col = "grey",
             xlab = "Log2 Fold Change", ylab = "-log10(p-value)",
             main = "Volcano Plot (Secreted Proteins Highlighted)")
        
        # Highlight secreted proteins
        secreted_idx <- which(annotated_df\$Is_Secreted == TRUE)
        if (length(secreted_idx) > 0) {
            points(annotated_df\$log2FC[secreted_idx], log_p[secreted_idx], col = "red", pch = 16)
            legend("topright", legend = c("Other", "Secreted"), col = c("grey", "red"), pch = 16)
        }
    } else {
        plot.new()
        text(0.5, 0.5, "Volcano Plot Unavailable\n(Insufficient replicates or conditions)", cex = 1.2)
    }
    
    dev.off()
    message("Summary plots saved to 'hpa_proteomics_summary.pdf'.")
    
    # --- Export HPA Metadata ---
    message("Exporting HPA metadata...")
    metadata_conn <- file("hpa_metadata.txt")
    writeLines(c(
        "Human Protein Atlas (HPA) Database Metadata",
        "==========================================",
        paste("HPA Version: ", getHpaVersion()),
        paste("Release Date:", getHpaDate()),
        paste("Ensembl Build:", getHpaEnsembl())
    ), metadata_conn)
    close(metadata_conn)
    message("Metadata written to 'hpa_metadata.txt'.")
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_HPAR_HPA_PROTEOMICS_ANNOTATION":',
        paste0('    hpar: ', as.character(packageVersion('hpar')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hpa_proteomics_annotation.csv versions.yml
    """
}

workflow BIOC_HPAR_HPA_PROTEOMICS_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_HPAR_HPA_PROTEOMICS_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_HPAR_HPA_PROTEOMICS_ANNOTATION.out.tables
    plots    = BIOC_HPAR_HPA_PROTEOMICS_ANNOTATION.out.plots
    objects  = BIOC_HPAR_HPA_PROTEOMICS_ANNOTATION.out.objects
    versions = BIOC_HPAR_HPA_PROTEOMICS_ANNOTATION.out.versions
}
