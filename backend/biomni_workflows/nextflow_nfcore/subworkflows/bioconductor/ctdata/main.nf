#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CTdata — ct_gene_characterization
// Characterize custom RNA-seq expression data by integrating curated Cancer-Testis (CT) gene annotations, promoter methylation, and demethylation induction profil
// Input: counts.csv, coldata.csv
// Container: 1.10.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocGenerics, CTdata, GenomicRanges, IRanges, S4Vectors, SummarizedExperiment
// Visualizations: box plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CTDATA_CT_GENE_CHARACTERIZATION {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("CTdata", "S4Vectors", "GenomicRanges", "BiocGenerics", "SummarizedExperiment")
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
    library(CTdata)
    library(SummarizedExperiment)
    library(S4Vectors)
    library(GenomicRanges)
    library(BiocGenerics)
    
    # ==========================================
    # --- Load and Process User Expression Data ---
    # ==========================================
    
    message("Loading user expression data...")
    counts_df <- read.csv("counts.csv", stringsAsFactors = FALSE)
    coldata_df <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Set gene_id as row names
    rownames(counts_df) <- counts_df\$gene_id
    counts_matrix <- as.matrix(counts_df[, setdiff(names(counts_df), "gene_id"), drop = FALSE])
    
    # Align counts and coldata
    common_samples <- intersect(colnames(counts_matrix), coldata_df\$sample)
    if (length(common_samples) == 0) {
        stop("No matching samples found between counts.csv and coldata.csv")
    }
    counts_matrix <- counts_matrix[, common_samples, drop = FALSE]
    coldata_df <- coldata_df[match(common_samples, coldata_df\$sample), , drop = FALSE]
    
    # Calculate Counts Per Million (CPM) to normalize for library size
    libsizes <- colSums(counts_matrix)
    libsizes[libsizes == 0] <- 1  # Avoid division by zero
    cpm_matrix <- t(t(counts_matrix) / libsizes) * 1e6
    
    # Calculate mean expression per condition and log2 Fold Change
    conditions <- unique(coldata_df\$condition)
    if (length(conditions) >= 2) {
        cond1 <- conditions[1]
        cond2 <- conditions[2]
        message(sprintf("Calculating log2 Fold Change between %s and %s...", cond2, cond1))
        
        mean_cond1 <- rowMeans(cpm_matrix[, coldata_df\$sample[coldata_df\$condition == cond1], drop = FALSE], na.rm = TRUE)
        mean_cond2 <- rowMeans(cpm_matrix[, coldata_df\$sample[coldata_df\$condition == cond2], drop = FALSE], na.rm = TRUE)
        
        # Use a small offset to avoid log of zero
        log2FC <- log2((mean_cond2 + 0.1) / (mean_cond1 + 0.1))
        
        user_stats <- data.frame(
            gene_id = rownames(counts_matrix),
            mean_cpm_cond1 = mean_cond1,
            mean_cpm_cond2 = mean_cond2,
            log2FC = log2FC,
            mean_cpm_all = rowMeans(cpm_matrix, na.rm = TRUE),
            stringsAsFactors = FALSE
        )
        names(user_stats)[2:3] <- c(paste0("mean_cpm_", cond1), paste0("mean_cpm_", cond2))
    } else {
        message("Only one condition detected. Calculating mean expression...")
        mean_all <- rowMeans(cpm_matrix, na.rm = TRUE)
        user_stats <- data.frame(
            gene_id = rownames(counts_matrix),
            mean_cpm_all = mean_all,
            log2FC = 0,
            stringsAsFactors = FALSE
        )
    }
    
    # ==========================================
    # --- Integrate with CTdata Reference ---
    # ==========================================
    
    message("Loading CTdata reference datasets...")
    all_ref <- as.data.frame(all_genes())
    
    # Determine if user IDs are Ensembl IDs or Gene Symbols
    is_ensembl <- any(grepl("^ENSG", user_stats\$gene_id))
    if (is_ensembl) {
        message("Matching user genes by Ensembl Gene ID...")
        merged_data <- merge(user_stats, all_ref, by.x = "gene_id", by.y = "ensembl_gene_id", all.x = TRUE)
        merged_data\$ensembl_gene_id <- merged_data\$gene_id
    } else {
        message("Matching user genes by External Gene Name...")
        merged_data <- merge(user_stats, all_ref, by.x = "gene_id", by.y = "external_gene_name", all.x = TRUE)
    }
    
    # ==========================================
    # --- Annotate with Promoter Methylation ---
    # ==========================================
    
    message("Integrating promoter methylation data...")
    tryCatch({
        meth_tissues <- mean_methylation_in_tissues()
        meth_assay <- assays(meth_tissues)[[1]]
        meth_rowdata <- as.data.frame(rowData(meth_tissues))
        
        # Calculate mean somatic methylation (excluding sperm)
        somatic_cols <- setdiff(colnames(meth_tissues), "sperm")
        mean_somatic_meth <- rowMeans(meth_assay[, somatic_cols, drop = FALSE], na.rm = TRUE)
        sperm_meth <- meth_assay[, "sperm", drop = TRUE]
        
        meth_df <- data.frame(
            ensembl_gene_id = meth_rowdata\$ensembl_gene_id,
            mean_somatic_methylation = mean_somatic_meth,
            sperm_methylation = sperm_meth,
            stringsAsFactors = FALSE
        )
        merged_data <- merge(merged_data, meth_df, by = "ensembl_gene_id", all.x = TRUE)
    }, error = function(e) {
        warning("Could not merge methylation data: ", e\$message)
        merged_data\$mean_somatic_methylation <- NA
        merged_data\$sperm_methylation <- NA
    })
    
    # ==========================================
    # --- Annotate with Demethylation Induction ---
    # ==========================================
    
    message("Integrating DAC (demethylating agent) treatment data...")
    tryCatch({
        dac_data <- DAC_treated_cells()
        dac_rowdata <- as.data.frame(rowData(dac_data))
        dac_df <- data.frame(
            ensembl_gene_id = rownames(dac_data),
            dac_induced = dac_rowdata\$induced,
            stringsAsFactors = FALSE
        )
        merged_data <- merge(merged_data, dac_df, by = "ensembl_gene_id", all.x = TRUE)
    }, error = function(e) {
        warning("Could not merge DAC treated cells data: ", e\$message)
        merged_data\$dac_induced <- NA
    })
    
    # ==========================================
    # --- Annotate with CCLE CT Correlation ---
    # ==========================================
    
    message("Integrating CCLE CT-gene correlation matrix...")
    tryCatch({
        ccle_corr <- CCLE_correlation_matrix()
        common_cols <- intersect(colnames(ccle_corr), merged_data\$ensembl_gene_id)
        if (length(common_cols) > 0) {
            mean_ct_corr <- colMeans(ccle_corr[, common_cols, drop = FALSE], na.rm = TRUE)
            corr_df <- data.frame(
                ensembl_gene_id = names(mean_ct_corr),
                mean_ccle_ct_correlation = mean_ct_corr,
                stringsAsFactors = FALSE
            )
            merged_data <- merge(merged_data, corr_df, by = "ensembl_gene_id", all.x = TRUE)
        } else {
            merged_data\$mean_ccle_ct_correlation <- NA
        }
    }, error = function(e) {
        warning("Could not merge CCLE correlation data: ", e\$message)
        merged_data\$mean_ccle_ct_correlation <- NA
    })
    
    # Save the annotated dataset
    write.csv(merged_data, "ct_annotated_genes.csv", row.names = FALSE)
    message("Saved annotated gene table to 'ct_annotated_genes.csv'")
    
    # ==========================================
    # --- Visualization and Diagnostics ---
    # ==========================================
    
    message("Generating diagnostic plots...")
    pdf("ct_analysis_summary.pdf", width = 10, height = 8)
    
    # Define CT gene logical vector safely
    is_ct <- !is.na(merged_data\$CT_gene_type) & merged_data\$CT_gene_type == "CT_gene"
    
    # Plot 1: MA-like plot highlighting CT genes
    plot(merged_data\$mean_cpm_all + 0.1, merged_data\$log2FC, 
         col = ifelse(is_ct, "red", "grey80"),
         pch = ifelse(is_ct, 19, 1),
         cex = ifelse(is_ct, 1.2, 0.6),
         xlab = "Mean Expression (CPM + 0.1)", ylab = "Log2 Fold Change",
         main = "Expression Changes of CT Genes in User Dataset", log = "x")
    abline(h = 0, lty = 2, col = "black")
    legend("topright", legend = c("CT Genes", "Other Genes"), col = c("red", "grey80"), pch = c(19, 1))
    
    # Plot 2: Somatic vs Sperm Methylation for CT genes
    ct_subset <- merged_data[is_ct & !is.na(merged_data\$mean_somatic_methylation), ]
    if (nrow(ct_subset) > 0) {
        plot(ct_subset\$mean_somatic_methylation, ct_subset\$sperm_methylation,
             xlim = c(0, 1), ylim = c(0, 1),
             col = "blue", pch = 19,
             xlab = "Mean Somatic Methylation", ylab = "Sperm Methylation",
             main = "Promoter Methylation of CT Genes")
        abline(a = 0, b = 1, lty = 2, col = "red")
    } else {
        plot(1, type = "n", axes = FALSE, xlab = "", ylab = "", main = "No CT genes with methylation data")
    }
    
    # Plot 3: Boxplot of Log2FC by DAC induction status
    if ("dac_induced" %in% names(merged_data) && any(!is.na(merged_data\$dac_induced))) {
        boxplot(log2FC ~ dac_induced, data = merged_data,
                col = c("lightblue", "orange"),
                xlab = "DAC Induced Status (Reference)", ylab = "User Log2 Fold Change",
                main = "User Expression Changes by Demethylation Induction Status")
    } else {
        plot(1, type = "n", axes = FALSE, xlab = "", ylab = "", main = "No DAC induction data available")
    }
    
    dev.off()
    message("Saved diagnostic plots to 'ct_analysis_summary.pdf'")
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_CTDATA_CT_GENE_CHARACTERIZATION":',
        paste0('    CTdata: ', as.character(packageVersion('CTdata')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ct_gene_characterization.csv versions.yml
    """
}

workflow BIOC_CTDATA_CT_GENE_CHARACTERIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_CTDATA_CT_GENE_CHARACTERIZATION(ch_input)

    emit:
    tables   = BIOC_CTDATA_CT_GENE_CHARACTERIZATION.out.tables
    plots    = BIOC_CTDATA_CT_GENE_CHARACTERIZATION.out.plots
    objects  = BIOC_CTDATA_CT_GENE_CHARACTERIZATION.out.objects
    versions = BIOC_CTDATA_CT_GENE_CHARACTERIZATION.out.versions
}
