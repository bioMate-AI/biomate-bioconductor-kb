#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cummeRbund — cummerbund_transcriptomics
// Perform persistent storage, exploration, differential expression analysis, and visualization of transcriptomics data using cummeRbund by mocking Cuffdiff inputs
// Input: counts.csv, coldata.csv
// Container: 2.48.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: cummeRbund, ggplot2
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CUMMERBUND_CUMMERBUND_TRANSCRIPTOMICS {
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
    library(cummeRbund)
    library(ggplot2)
    
    # ==========================================
    # Stage 1: Read Input Data & Align Samples
    # ==========================================
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Align counts columns with coldata samples
    samples <- coldata\$sample
    counts <- counts[, samples, drop = FALSE]
    conditions <- unique(coldata\$condition)
    
    # ==========================================
    # Stage 2: Generate Mock Cuffdiff Files
    # ==========================================
    # Calculate condition-level mean FPKMs (using counts as proxy for FPKM)
    cond_fpkms <- do.call(cbind, lapply(conditions, function(cond) {
      samps <- coldata\$sample[coldata\$condition == cond]
      if (length(samps) > 1) {
        rowMeans(counts[, samps, drop = FALSE])
      } else {
        counts[, samps]
      }
    }))
    colnames(cond_fpkms) <- conditions
    
    # 1. Create genes.fpkm_tracking
    genes_fpkm <- data.frame(
      tracking_id = rownames(counts),
      class_code = rep(".", nrow(counts)),
      nearest_ref_id = rep(".", nrow(counts)),
      gene_id = rownames(counts),
      gene_short_name = rownames(counts),
      tss_id = rep(".", nrow(counts)),
      locus = rep("chr1:1-1000", nrow(counts)),
      length = rep(1000, nrow(counts)),
      coverage = rep(10, nrow(counts)),
      stringsAsFactors = FALSE
    )
    for (cond in conditions) {
      fpkm <- cond_fpkms[, cond]
      genes_fpkm[[paste0(cond, "_FPKM")]] <- fpkm
      genes_fpkm[[paste0(cond, "_conf_lo")]] <- fpkm * 0.8
      genes_fpkm[[paste0(cond, "_conf_hi")]] <- fpkm * 1.2
      genes_fpkm[[paste0(cond, "_status")]] <- rep("OK", nrow(counts))
    }
    write.table(genes_fpkm, "genes.fpkm_tracking", sep = "\t", row.names = FALSE, quote = FALSE)
    
    # 2. Create gene_exp.diff (pairwise comparisons)
    pairs <- combn(conditions, 2, simplify = FALSE)
    if (length(pairs) == 0) {
      pairs <- list(c(conditions[1], conditions[1]))
    }
    
    diff_list <- list()
    for (p in pairs) {
      cond1 <- p[1]
      cond2 <- p[2]
      val1 <- cond_fpkms[, cond1]
      val2 <- cond_fpkms[, cond2]
      log2fc <- log2((val2 + 0.01) / (val1 + 0.01))
      
      # Mock p-value based on fold change
      p_val <- exp(-abs(log2fc))
      p_val[is.na(p_val)] <- 1
      q_val <- p.adjust(p_val, method = "BH")
      sig <- ifelse(q_val < 0.05, "yes", "no")
      
      df <- data.frame(
        test_id = rownames(counts),
        gene_id = rownames(counts),
        gene = rownames(counts),
        locus = rep("chr1:1-1000", nrow(counts)),
        sample_1 = rep(cond1, nrow(counts)),
        sample_2 = rep(cond2, nrow(counts)),
        status = rep("OK", nrow(counts)),
        value_1 = val1,
        value_2 = val2,
        `log2(fold_change)` = log2fc,
        t_stat = rep(0, nrow(counts)),
        p_value = p_val,
        q_value = q_val,
        significant = sig,
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
      diff_list[[length(diff_list) + 1]] <- df
    }
    gene_diff <- do.call(rbind, diff_list)
    write.table(gene_diff, "gene_exp.diff", sep = "\t", row.names = FALSE, quote = FALSE)
    
    # 3. Create genes.read_group_tracking (replicate-level tracking)
    replicate_list <- list()
    for (cond in conditions) {
      samps <- coldata\$sample[coldata\$condition == cond]
      for (i in seq_along(samps)) {
        samp <- samps[i]
        df <- data.frame(
          tracking_id = rownames(counts),
          condition = rep(cond, nrow(counts)),
          replicate = rep(i - 1, nrow(counts)),
          raw_frags = counts[, samp],
          internal_scale_factor = rep(1, nrow(counts)),
          external_scale_factor = rep(1, nrow(counts)),
          fpkm = counts[, samp],
          effective_length = rep(1000, nrow(counts)),
          status = rep("OK", nrow(counts)),
          stringsAsFactors = FALSE
        )
        replicate_list[[length(replicate_list) + 1]] <- df
      }
    }
    genes_replicate <- do.call(rbind, replicate_list)
    write.table(genes_replicate, "genes.read_group_tracking", sep = "\t", row.names = FALSE, quote = FALSE)
    
    # Clean up any pre-existing SQLite database to avoid conflicts
    if (file.exists("cuffData.db")) {
      file.remove("cuffData.db")
    }
    
    # ==========================================
    # Stage 3: Initialize cummeRbund & Load Data
    # ==========================================
    cuff <- readCufflinks(
      dir = ".",
      geneFPKM = "genes.fpkm_tracking",
      geneDiff = "gene_exp.diff",
      rebuild = TRUE
    )
    
    # Extract gene-level data
    gene_data <- genes(cuff)
    gene_fpkm_matrix <- fpkmMatrix(gene_data)
    gene_diff_data <- diffData(gene_data)
    
    # Merge FPKM and differential expression statistics
    summary_df <- merge(gene_fpkm_matrix, gene_diff_data, by.x = "row.names", by.y = "gene_id")
    colnames(summary_df)[1] <- "gene_id"
    write.csv(summary_df, "gene_expression_summary.csv", row.names = FALSE)
    
    # Identify and write significant genes
    sig_genes <- getSig(cuff, alpha = 0.05, level = "genes")
    write.csv(data.frame(significant_gene_id = sig_genes), "significant_genes.csv", row.names = FALSE)
    
    # ==========================================
    # Stage 4: Visualization & Diagnostics
    # ==========================================
    pdf("cummerbund_plots.pdf", width = 8, height = 8)
    
    # 1. Density Plot of FPKM values
    tryCatch({
      print(csDensity(gene_data) + ggtitle("Gene Expression Density"))
    }, error = function(e) warning("Density plot failed: ", e\$message))
    
    # 2. Scatter Plot (if at least 2 conditions exist)
    if (length(conditions) >= 2) {
      tryCatch({
        print(csScatter(gene_data, conditions[1], conditions[2]) + ggtitle("Scatter Plot"))
      }, error = function(e) warning("Scatter plot failed: ", e\$message))
    }
    
    # 3. Volcano Plot (if at least 2 conditions exist)
    if (length(conditions) >= 2) {
      tryCatch({
        print(csVolcano(gene_data, conditions[1], conditions[2]) + ggtitle("Volcano Plot"))
      }, error = function(e) warning("Volcano plot failed: ", e\$message))
    }
    
    # 4. Dendrogram of Conditions
    tryCatch({
      print(csDendro(gene_data))
    }, error = function(e) warning("Dendrogram failed: ", e\$message))
    
    # 5. PCA Plot of Replicates
    tryCatch({
      print(PCAplot(gene_data) + ggtitle("PCA Plot"))
    }, error = function(e) warning("PCA plot failed: ", e\$message))
    
    # 6. MDS Plot of Replicates
    tryCatch({
      print(MDSplot(gene_data) + ggtitle("MDS Plot"))
    }, error = function(e) warning("MDS plot failed: ", e\$message))
    
    # 7. Heatmap of Significant (or top variable) Genes
    tryCatch({
      heatmap_genes <- sig_genes
      if (length(heatmap_genes) < 5) {
        # Fallback to top 20 variable genes if too few significant genes
        vars <- apply(gene_fpkm_matrix, 1, var)
        heatmap_genes <- names(sort(vars, decreasing = TRUE)[1:min(20, length(vars))])
      }
      gene_set <- getGenes(cuff, heatmap_genes)
      print(csHeatmap(gene_set) + ggtitle("Gene Expression Heatmap"))
    }, error = function(e) warning("Heatmap failed: ", e\$message))
    
    dev.off()
    
    # Clean up temporary mock files
    temp_files <- c("genes.fpkm_tracking", "gene_exp.diff", "genes.read_group_tracking")
    for (f in temp_files) {
      if (file.exists(f)) file.remove(f)
    }

    writeLines(c(
        '"BIOC_CUMMERBUND_CUMMERBUND_TRANSCRIPTOMICS":',
        paste0('    cummeRbund: ', as.character(packageVersion('cummeRbund')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cummerbund_transcriptomics.csv versions.yml
    """
}

workflow BIOC_CUMMERBUND_CUMMERBUND_TRANSCRIPTOMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_CUMMERBUND_CUMMERBUND_TRANSCRIPTOMICS(ch_input)

    emit:
    tables   = BIOC_CUMMERBUND_CUMMERBUND_TRANSCRIPTOMICS.out.tables
    plots    = BIOC_CUMMERBUND_CUMMERBUND_TRANSCRIPTOMICS.out.plots
    objects  = BIOC_CUMMERBUND_CUMMERBUND_TRANSCRIPTOMICS.out.objects
    versions = BIOC_CUMMERBUND_CUMMERBUND_TRANSCRIPTOMICS.out.versions
}
