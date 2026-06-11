#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: recount — recount_normalization_pipeline
// Build a RangedSummarizedExperiment from local count data and metadata, then perform recount-specific scaling, RPKM, and TPM calculations, and export the normali
// Input: counts.csv, coldata.csv
// Container: 1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, SummarizedExperiment, recount
// Visualizations: box plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RECOUNT_RECOUNT_NORMALIZATION_PIPELINE {
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
    library(recount)
    library(GenomicRanges)
    
    # Stage 1: Read and align input files
    message("Loading input datasets...")
    counts_df <- read.csv("counts.csv", check.names = FALSE, stringsAsFactors = FALSE)
    if (!"gene_id" %in% colnames(counts_df)) {
        stop("Input counts.csv must contain a 'gene_id' column.")
    }
    rownames(counts_df) <- counts_df\$gene_id
    counts_matrix <- as.matrix(counts_df[, -which(colnames(counts_df) == "gene_id"), drop = FALSE])
    
    coldata_df <- read.csv("coldata.csv", check.names = FALSE, stringsAsFactors = FALSE)
    if (!all(c("sample", "condition") %in% colnames(coldata_df))) {
        stop("Input coldata.csv must contain 'sample' and 'condition' columns.")
    }
    rownames(coldata_df) <- coldata_df\$sample
    
    # Align samples between counts and coldata
    common_samples <- intersect(colnames(counts_matrix), rownames(coldata_df))
    if (length(common_samples) == 0) {
        stop("No common samples found between counts.csv and coldata.csv.")
    }
    counts_matrix <- counts_matrix[, common_samples, drop = FALSE]
    coldata_df <- coldata_df[common_samples, , drop = FALSE]
    
    # Stage 2: Construct RangedSummarizedExperiment with recount-specific metadata
    message("Constructing RangedSummarizedExperiment object...")
    # Create dummy genomic ranges for the genes
    row_ranges <- GRanges(
        seqnames = rep("chr1", nrow(counts_matrix)),
        ranges = IRanges(start = seq_len(nrow(counts_matrix)) * 1000, width = 100),
        strand = "*"
    )
    names(row_ranges) <- rownames(counts_matrix)
    
    # Add bp_length to rowData (required for RPKM and TPM calculations)
    mcols(row_ranges)\$bp_length <- as.integer(rep(2000, nrow(counts_matrix)))
    mcols(row_ranges)\$gene_id <- rownames(counts_matrix)
    
    # Add recount-specific columns to colData
    # scale_counts requires 'auc' (Area Under Coverage) or 'mapped_read_count'
    coldata_df\$mapped_read_count <- as.numeric(colSums(counts_matrix))
    # Estimate AUC assuming an average read length of 100bp
    coldata_df\$auc <- coldata_df\$mapped_read_count * 100
    
    rse <- RangedSummarizedExperiment(
        assays = list(counts = counts_matrix),
        rowRanges = row_ranges,
        colData = as(coldata_df, "DataFrame")
    )
    
    # Stage 3: Perform recount scaling and normalization
    message("Scaling counts using recount::scale_counts...")
    # Scale counts to mapped reads (standardizes library size)
    rse_scaled <- scale_counts(rse, by = "mapped_reads")
    scaled_counts <- assay(rse_scaled)
    
    message("Calculating RPKM using recount::getRPKM...")
    rpkm_matrix <- getRPKM(rse, length_var = "bp_length", mapped_var = "mapped_read_count")
    
    message("Calculating TPM using recount::getTPM...")
    tpm_matrix <- getTPM(rse, length_var = "bp_length", mapped_var = "mapped_read_count")
    
    # Stage 4: Write outputs to files
    message("Writing normalized matrices to CSV...")
    write.csv(scaled_counts, "scaled_counts.csv", row.names = TRUE)
    write.csv(rpkm_matrix, "rpkm_matrix.csv", row.names = TRUE)
    write.csv(tpm_matrix, "tpm_matrix.csv", row.names = TRUE)
    
    # Stage 5: Generate diagnostic plots
    message("Generating diagnostic plots...")
    pdf("normalization_summary.pdf", width = 10, height = 8)
    par(mfrow = c(2, 2), mar = c(6, 4, 4, 2))
    boxplot(log2(counts_matrix + 1), main = "Raw Counts (log2 + 1)", las = 2, col = "skyblue")
    boxplot(log2(scaled_counts + 1), main = "Scaled Counts (log2 + 1)", las = 2, col = "tomato")
    boxplot(log2(rpkm_matrix + 1), main = "RPKM (log2 + 1)", las = 2, col = "lightgreen")
    boxplot(log2(tpm_matrix + 1), main = "TPM (log2 + 1)", las = 2, col = "gold")
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_RECOUNT_RECOUNT_NORMALIZATION_PIPELINE":',
        paste0('    recount: ', as.character(packageVersion('recount')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_recount_normalization_pipeline.csv versions.yml
    """
}

workflow BIOC_RECOUNT_RECOUNT_NORMALIZATION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_RECOUNT_RECOUNT_NORMALIZATION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_RECOUNT_RECOUNT_NORMALIZATION_PIPELINE.out.tables
    plots    = BIOC_RECOUNT_RECOUNT_NORMALIZATION_PIPELINE.out.plots
    objects  = BIOC_RECOUNT_RECOUNT_NORMALIZATION_PIPELINE.out.objects
    versions = BIOC_RECOUNT_RECOUNT_NORMALIZATION_PIPELINE.out.versions
}
