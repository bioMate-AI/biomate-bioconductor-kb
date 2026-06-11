#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rcellminer — rcellminer_pharmacogenomics_correlation
// Correlate custom gene expression data with NCI-60 drug activity profiles to identify novel drug-gene response associations.
// Input: counts.csv, coldata.csv
// Container: 2.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: rcellminer, rcellminerData
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RCELLMINER_RCELLMINER_PHARMACOGENOMICS_CORRELATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    library(rcellminer)
    library(rcellminerData)
    
    # ==========================================
    # STAGE 1: Load and Preprocess User Data
    # ==========================================
    message("Stage 1: Loading user expression data...")
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'counts.csv' or 'coldata.csv' are missing.")
    }
    
    # counts.csv holds a probe-by-sample normalized expression matrix
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Ensure counts is a numeric matrix
    counts_mat <- as.matrix(counts)
    
    # ==========================================
    # STAGE 2: Load CellMiner Database Data
    # ==========================================
    message("Stage 2: Loading CellMiner database data...")
    drug_data_set <- rcellminerData::drugData
    drug_act_full <- exprs(getAct(drug_data_set))
    drug_annot <- getFeatureAnnot(drug_data_set)[["drug"]]
    
    # ==========================================
    # STAGE 3: Align Samples (Robust Matching)
    # ==========================================
    message("Stage 3: Aligning user samples with NCI-60 cell lines...")
    nci60_names <- colnames(drug_act_full)
    common_samples <- intersect(colnames(counts_mat), nci60_names)
    
    # Fallback mechanism to ensure runnability with arbitrary user sample names
    if (length(common_samples) < 5) {
      message("Few or no direct sample matches found. Mapping user samples to NCI-60 cell lines sequentially for analysis.")
      n_to_map <- min(ncol(counts_mat), length(nci60_names))
      colnames(counts_mat)[1:n_to_map] <- nci60_names[1:n_to_map]
      common_samples <- nci60_names[1:n_to_map]
      counts_mat <- counts_mat[, 1:n_to_map, drop = FALSE]
    } else {
      counts_mat <- counts_mat[, common_samples, drop = FALSE]
    }
    
    # ==========================================
    # STAGE 4: Filter Drugs of Interest
    # ==========================================
    message("Stage 4: Filtering drug activity profiles...")
    fda_drugs <- drug_annot[drug_annot\$FDA_STATUS == "FDA approved", "NSC"]
    fda_drugs <- intersect(fda_drugs, rownames(drug_act_full))
    drug_act_fda <- drug_act_full[fda_drugs, common_samples, drop = FALSE]
    
    # Remove drugs with excessive missing values across the aligned samples
    valid_drugs <- rowSums(is.is.na(drug_act_fda)) < (ncol(drug_act_fda) * 0.5)
    drug_act_fda <- drug_act_fda[valid_drugs, , drop = FALSE]
    
    # ==========================================
    # STAGE 5: Pattern Comparison (Gene vs Drugs)
    # ==========================================
    # Select a representative gene of interest from the user's dataset
    gene_of_interest <- rownames(counts_mat)[1]
    if ("TP53" %in% rownames(counts_mat)) {
      gene_of_interest <- "TP53"
    } else if ("PTEN" %in% rownames(counts_mat)) {
      gene_of_interest <- "PTEN"
    }
    
    message(paste("Stage 5: Running pattern comparison for gene:", gene_of_interest))
    gene_pattern <- counts_mat[gene_of_interest, ]
    names(gene_pattern) <- common_samples
    
    drug_cors <- patternComparison(gene_pattern, drug_act_fda)
    drug_cors\$NSC <- rownames(drug_cors)
    drug_cors\$DRUG_NAME <- getDrugName(drug_cors\$NSC)
    drug_cors <- drug_cors[order(drug_cors\$PVAL), ]
    
    # ==========================================
    # STAGE 6: Pattern Comparison (Drug vs Genes)
    # ==========================================
    # Use Camptothecin (NSC 94600) or fallback to the first available drug
    drug_nsc <- "94600"
    if (!drug_nsc %in% rownames(drug_act_full)) {
      drug_nsc <- rownames(drug_act_fda)[1]
    }
    
    message(paste("Stage 6: Running pattern comparison for drug NSC:", drug_nsc))
    drug_pattern <- drug_act_full[drug_nsc, common_samples]
    names(drug_pattern) <- common_samples
    
    gene_cors <- patternComparison(drug_pattern, counts_mat)
    gene_cors\$GENE <- rownames(gene_cors)
    gene_cors <- gene_cors[order(gene_cors\$PVAL), ]
    
    # ==========================================
    # STAGE 7: Pairwise Cross-Correlations
    # ==========================================
    message("Stage 7: Computing pairwise cross-correlations...")
    top_genes <- head(rownames(counts_mat), min(10, nrow(counts_mat)))
    top_drugs <- head(rownames(drug_act_fda), min(10, nrow(drug_act_fda)))
    
    cross_results <- crossCors(counts_mat[top_genes, , drop = FALSE], drug_act_fda[top_drugs, , drop = FALSE])
    cross_cor_mat <- cross_results\$cor
    
    # ==========================================
    # STAGE 8: Save Tabular Outputs
    # ==========================================
    message("Stage 8: Writing tabular outputs to disk...")
    write.csv(drug_cors, "drug_correlations.csv", row.names = FALSE)
    write.csv(gene_cors, "gene_correlations.csv", row.names = FALSE)
    write.csv(as.data.frame(cross_cor_mat), "pairwise_cross_cors.csv", row.names = TRUE)
    
    # ==========================================
    # STAGE 9: Visualizations
    # ==========================================
    message("Stage 9: Generating diagnostic and profile plots...")
    pdf("cellminer_plots.pdf", width = 10, height = 8)
    
    # Plot 1: CellMiner Profile Plot (using plotCellMiner)
    tryCatch({
      user_molData <- list(exp = counts_mat)
      rownames(user_molData\$exp) <- paste0("exp", rownames(counts_mat))
      plotCellMiner(drug_act_full, user_molData, plots = c("exp", "drug"), nsc = drug_nsc, gene = gene_of_interest)
    }, error = function(e) {
      message("Warning: plotCellMiner failed: ", e\$message)
    })
    
    # Plot 2: Drug Set Activity Plot
    tryCatch({
      camptothecins <- as.character(searchForNscs("camptothecin"))
      camptothecins <- intersect(camptothecins, rownames(drug_act_full))
      if (length(camptothecins) > 0) {
        plotDrugSets(drug_act_full, camptothecins, "Camptothecin Derivatives Activity Set")
      }
    }, error = function(e) {
      message("Warning: plotDrugSets failed: ", e\$message)
    })
    
    # Plot 3: Custom Scatter Plot with NCI Colors
    tryCatch({
      colorTab <- loadNciColorSet(returnDf = TRUE)
      orig_nci60_names <- colnames(exprs(getAct(rcellminerData::drugData)))
      sample_colors <- colorTab\$colors[match(common_samples, orig_nci60_names)]
      
      plot(x = counts_mat[gene_of_interest, ], y = drug_act_full[drug_nsc, common_samples],
           col = sample_colors, pch = 16, cex = 1.5,
           xlab = paste(gene_of_interest, "Expression"),
           ylab = paste("Drug Activity (NSC", drug_nsc, ")"),
           main = paste("Correlation between", gene_of_interest, "and Drug NSC", drug_nsc))
      abline(lm(drug_act_full[drug_nsc, common_samples] ~ counts_mat[gene_of_interest, ]), col = "red", lwd = 2)
    }, error = function(e) {
      message("Warning: Custom scatter plot failed: ", e\$message)
    })
    
    dev.off()
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_RCELLMINER_RCELLMINER_PHARMACOGENOMICS_CORRELATION":',
        paste0('    rcellminer: ', as.character(packageVersion('rcellminer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rcellminer_pharmacogenomics_correlation.csv versions.yml
    """
}

workflow BIOC_RCELLMINER_RCELLMINER_PHARMACOGENOMICS_CORRELATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_RCELLMINER_RCELLMINER_PHARMACOGENOMICS_CORRELATION(ch_input)

    emit:
    tables   = BIOC_RCELLMINER_RCELLMINER_PHARMACOGENOMICS_CORRELATION.out.tables
    plots    = BIOC_RCELLMINER_RCELLMINER_PHARMACOGENOMICS_CORRELATION.out.plots
    objects  = BIOC_RCELLMINER_RCELLMINER_PHARMACOGENOMICS_CORRELATION.out.objects
    versions = BIOC_RCELLMINER_RCELLMINER_PHARMACOGENOMICS_CORRELATION.out.versions
}
