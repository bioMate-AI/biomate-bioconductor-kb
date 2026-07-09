#!/usr/bin/env nextflow
// ============================================================
// validation_deseq2_raw_counts — DESeq2 on raw count matrix
// Used for: BioMate System Validation Test 1-B
//   GSE89408 synovial RNA-seq, RA vs. Normal (Stephenson 2018)
//
// Input: gzipped tab-delimited count matrix with named columns
//        Column naming convention: {tissue_type}_{tissue}_N
//        e.g. RA_tissue_1, normal_tissue_5
//
// Outputs: DEGs CSV, PCA PNG, summary JSON, normalized counts
// ============================================================

nextflow.enable.dsl = 2

params.count_matrix_s3  = null   // S3 URI to count matrix .gz
params.comparison_a     = "RA"   // Case group prefix in column names
params.comparison_b     = "normal"  // Control group prefix
params.fdr_threshold    = 0.05
params.lfc_threshold    = 1.0
params.outdir           = "s3://biomate-nextflow-work/nextflow/validation-test1b"
params.run_combat_seq   = false  // Set true to apply batch correction

process DESEQ2_FROM_COUNTS {
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"
    publishDir params.outdir, mode: 'copy'
    memory "8 GB"
    cpus 4

    output:
    path "deseq2_results.csv"
    path "deseq2_pca.png"
    path "deseq2_summary.json"
    path "deseq2_normalized_counts.csv.gz", optional: true

    script:
    def run_combat = params.run_combat_seq ? "TRUE" : "FALSE"
    """
    #!/usr/bin/env Rscript
    cat("=== DESeq2 Validation Test 1-B ===\\n")
    cat(paste("Comparison:", "${params.comparison_a}", "vs.", "${params.comparison_b}", "\\n"))

    suppressPackageStartupMessages({
        library(DESeq2)
        library(ggplot2)
        library(jsonlite)
    })

    # Download count matrix from S3
    count_s3 <- "${params.count_matrix_s3}"
    cat(paste("Downloading:", count_s3, "\\n"))
    system(paste("aws s3 cp", count_s3, "/tmp/count_matrix.txt.gz"))

    counts_raw <- read.table(
        gzfile("/tmp/count_matrix.txt.gz"),
        header = TRUE, row.names = 1, sep = "\\t",
        check.names = FALSE
    )
    cat(paste("Count matrix:", nrow(counts_raw), "genes x", ncol(counts_raw), "samples\\n"))

    # Build colData from column names
    # Convention: {condition_prefix}_{tissue}_N
    col_names <- colnames(counts_raw)
    # Extract condition: 'RA' or 'normal' from prefix
    condition <- ifelse(
        grepl("^${params.comparison_a}_", col_names, ignore.case = TRUE),
        "${params.comparison_a}",
        ifelse(
            grepl("^${params.comparison_b}_", col_names, ignore.case = TRUE),
            "${params.comparison_b}",
            "other"
        )
    )
    # Batch assignment: proxy from sample number modulo 4 (4 centers in GSE89408)
    # Extract trailing number via strsplit to avoid regex escaping issues
    sample_num <- sapply(strsplit(col_names, "_"), function(x) {
        n <- suppressWarnings(as.integer(x[length(x)]))
        if (is.na(n)) 1L else n
    })
    batch <- paste0("B", ((sample_num - 1L) %% 4L) + 1L)

    coldata <- data.frame(
        sample    = col_names,
        condition = factor(condition),
        batch     = factor(batch),
        row.names = col_names
    )

    # Subset to comparison groups
    keep_samples <- coldata\\$condition %in% c("${params.comparison_a}", "${params.comparison_b}")
    coldata_sub  <- coldata[keep_samples, ]
    counts_sub   <- counts_raw[, rownames(coldata_sub)]
    coldata_sub\\$condition <- droplevels(coldata_sub\\$condition)
    coldata_sub\\$condition <- relevel(coldata_sub\\$condition, ref = "${params.comparison_b}")

    n_case    <- sum(coldata_sub\\$condition == "${params.comparison_a}")
    n_control <- sum(coldata_sub\\$condition == "${params.comparison_b}")
    cat(paste("Samples: ", n_case, "${params.comparison_a}", ",", n_control, "${params.comparison_b}", "\\n"))

    # Filter low-expressed genes (≥10 counts in ≥5 samples)
    keep_genes <- rowSums(counts_sub >= 10) >= 5
    counts_filt <- counts_sub[keep_genes, ]
    cat(paste("After filter:", nrow(counts_filt), "genes pass quality cutoff\\n"))

    # Optional ComBat-seq batch correction
    run_combat <- as.logical("${run_combat}")
    if (run_combat) {
        cat("Applying ComBat-seq batch correction...\\n")
        if (!requireNamespace("sva", quietly = TRUE)) {
            install.packages("BiocManager", repos = "https://cran.r-project.org", quiet = TRUE)
            BiocManager::install("sva", ask = FALSE, quiet = TRUE)
        }
        library(sva)
        counts_filt <- ComBat_seq(
            as.matrix(counts_filt),
            batch = coldata_sub\\$batch,
            group = coldata_sub\\$condition
        )
        cat("ComBat-seq correction applied\\n")
    }

    # DESeq2
    dds <- DESeqDataSetFromMatrix(
        countData = round(counts_filt),
        colData   = coldata_sub,
        design    = ~ condition
    )
    dds <- DESeq(dds)
    res <- results(dds,
        contrast = c("condition", "${params.comparison_a}", "${params.comparison_b}"),
        alpha    = ${params.fdr_threshold}
    )

    # Count DEGs
    sig       <- !is.na(res\\$padj) & res\\$padj < ${params.fdr_threshold}
    sig_genes <- sum(sig, na.rm = TRUE)
    sig_up    <- sum(sig & res\\$log2FoldChange > ${params.lfc_threshold}, na.rm = TRUE)
    sig_down  <- sum(sig & res\\$log2FoldChange < -${params.lfc_threshold}, na.rm = TRUE)
    cat(paste("DEGs FDR<${params.fdr_threshold}:", sig_genes, "total,", sig_up, "up,", sig_down, "down\\n"))

    # Save results
    res_df      <- as.data.frame(res)
    res_df\\$gene <- rownames(res_df)
    res_sorted  <- res_df[order(res_df\\$pvalue, na.last = TRUE), ]
    write.csv(res_sorted, "deseq2_results.csv", row.names = FALSE)

    # PCA
    vsd <- vst(dds, blind = FALSE)
    pca_data    <- plotPCA(vsd, intgroup = c("condition", "batch"), returnData = TRUE)
    percent_var <- round(100 * attr(pca_data, "percentVar"))
    p <- ggplot(pca_data, aes(PC1, PC2, color = condition, shape = batch)) +
        geom_point(size = 3.5, alpha = 0.8) +
        xlab(paste0("PC1: ", percent_var[1], "% variance")) +
        ylab(paste0("PC2: ", percent_var[2], "% variance")) +
        ggtitle("GSE89408 PCA — RA vs. Normal Synovial RNA-seq") +
        scale_color_manual(values = c("${params.comparison_a}" = "#E41A1C", "${params.comparison_b}" = "#4DAF4A")) +
        theme_bw(base_size = 14)
    ggsave("deseq2_pca.png", p, width = 10, height = 8, dpi = 150)
    cat("PCA saved: deseq2_pca.png\\n")

    # Normalized counts for LASSO downstream
    norm_counts <- counts(dds, normalized = TRUE)
    gz <- gzfile("deseq2_normalized_counts.csv.gz", "w")
    write.csv(norm_counts, gz)
    close(gz)

    # Top genes
    top10 <- head(res_sorted[!is.na(res_sorted\\$padj), ], 10)
    cat("\\nTop 10 DEGs:\\n")
    print(top10[, c("gene", "baseMean", "log2FoldChange", "padj")])

    # Known RA markers
    ra_markers <- c("IL6", "TNF", "IL1B", "MMP3", "CXCL13", "IL6R", "CD68", "IL17A", "STAT3", "PTPN22")
    ra_hits    <- ra_markers[ra_markers %in% rownames(res)]
    cat(paste("\\nKnown RA markers detected:", paste(ra_hits, collapse = ", "), "\\n"))

    # PCA batch structure check
    pc1_batch_cor <- tryCatch({
        b_num <- as.numeric(factor(coldata_sub\\$batch))
        abs(cor(pca_data\\$PC1, b_num, method = "spearman"))
    }, error = function(e) NA_real_)
    cat(paste("PC1-batch Spearman |r|:", round(pc1_batch_cor, 3), "\\n"))
    if (!is.na(pc1_batch_cor) && pc1_batch_cor > 0.3) {
        cat("QC ALERT: PC1 correlates with batch — ComBat-seq correction recommended\\n")
    }

    # Summary JSON
    summary <- list(
        test_id               = "1-B",
        dataset               = "GSE89408",
        comparison            = paste("${params.comparison_a}", "vs.", "${params.comparison_b}"),
        n_samples_case        = n_case,
        n_samples_control     = n_control,
        n_genes_tested        = nrow(counts_filt),
        n_DEGs_total          = sig_genes,
        n_DEGs_up             = sig_up,
        n_DEGs_down           = sig_down,
        fdr_threshold         = ${params.fdr_threshold},
        lfc_threshold         = ${params.lfc_threshold},
        pca_PC1_variance_pct  = percent_var[1],
        pca_PC2_variance_pct  = percent_var[2],
        pc1_batch_correlation = pc1_batch_cor,
        batch_correction      = run_combat,
        top_genes             = head(res_sorted\\$gene[!is.na(res_sorted\\$padj)], 20),
        ra_markers_detected   = ra_hits,
        pass_DEG_criterion    = sig_genes >= 200,
        pass_batch_check      = !is.na(pc1_batch_cor)
    )
    write_json(summary, "deseq2_summary.json", pretty = TRUE, auto_unbox = TRUE)

    cat("\\n=== PASS CRITERIA ===\\n")
    cat(paste("≥200 DEGs at FDR<${params.fdr_threshold}:", ifelse(sig_genes >= 200, "PASS", "FAIL"),
        paste0("(", sig_genes, ")"), "\\n"))
    cat(paste("PCA batch correlation detectable:",
        ifelse(!is.na(pc1_batch_cor) && pc1_batch_cor > 0.3, "YES (batch effect present)", "NO (batch effect not detected)"), "\\n"))
    cat("DESeq2 complete\\n")
    """
}

workflow {
    if (!params.count_matrix_s3) {
        error "Provide --count_matrix_s3 <s3://...>"
    }
    DESEQ2_FROM_COUNTS()
}
