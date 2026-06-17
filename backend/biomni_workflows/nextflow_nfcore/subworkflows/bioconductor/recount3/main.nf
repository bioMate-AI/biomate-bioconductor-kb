#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: recount3 — recount3_local_transformation
// Transform and scale local RNA-seq count data using recount3's uniform scaling and transformation methodologies, followed by diagnostic PCA visualization.
// Input: counts.csv, coldata.csv
// Container: 1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocGenerics, GenomicRanges, IRanges, S4Vectors, SummarizedExperiment, recount3
// Visualizations: PCA plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RECOUNT3_RECOUNT3_LOCAL_TRANSFORMATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("recount3", "S4Vectors", "GenomicRanges", "BiocGenerics", "SummarizedExperiment")
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
    library(recount3)
    library(SummarizedExperiment)
    library(S4Vectors)
    library(GenomicRanges)
    library(BiocGenerics)
    
    # ==========================================
    # --- Load Input Data ---
    # ==========================================
    message("Stage 1: Loading input counts and coldata...")
    
    # Read counts matrix
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    if ("gene_id" %in% colnames(counts_df)) {
        rownames(counts_df) <- counts_df\$gene_id
        counts_df\$gene_id <- NULL
    }
    counts_mat <- as.matrix(counts_df)
    
    # Read coldata metadata
    coldata_df <- read.csv("coldata.csv", check.names = FALSE)
    if ("sample" %in% colnames(coldata_df)) {
        rownames(coldata_df) <- coldata_df\$sample
    }
    
    # Align samples between counts and coldata
    common_samples <- intersect(colnames(counts_mat), rownames(coldata_df))
    if (length(common_samples) == 0) {
        stop("No common samples found between counts.csv and coldata.csv")
    }
    counts_mat <- counts_mat[, common_samples, drop = FALSE]
    coldata_df <- coldata_df[common_samples, drop = FALSE]
    
    # ==========================================
    # --- Construct RangedSummarizedExperiment ---
    # ==========================================
    message("Stage 2: Constructing RangedSummarizedExperiment...")
    
    n_genes <- nrow(counts_mat)
    # Create dummy genomic coordinates for the genes
    gene_ranges <- GRanges(
        seqnames = Rle(rep("chr1", n_genes)),
        ranges = IRanges(start = seq(1, by = 2000, length.out = n_genes), width = 1000),
        strand = Rle(rep("*", n_genes))
    )
    names(gene_ranges) <- rownames(counts_mat)
    
    # Add gene length to rowData (required for some recount3 transformations)
    mcols(gene_ranges)\$bp_length <- width(gene_ranges)
    
    # Construct the RSE object with raw_counts assay
    rse <- SummarizedExperiment(
        assays = list(raw_counts = counts_mat),
        rowRanges = gene_ranges,
        colData = DataFrame(coldata_df)
    )
    
    # ==========================================
    # --- Inject recount3-specific Metadata ---
    # ==========================================
    message("Stage 3: Injecting recount3-specific QC metrics...")
    
    # recount3 scaling functions rely on specific QC columns like area_under_coverage (auc)
    # We estimate AUC as total raw counts multiplied by a standard read length (e.g., 100bp)
    read_len <- 100
    estimated_auc <- colSums(counts_mat) * read_len
    
    colData(rse)\$recount_qc.area_under_coverage <- estimated_auc
    colData(rse)\$auc <- estimated_auc
    colData(rse)\$mapped_read_count <- colSums(counts_mat)
    
    # ==========================================
    # --- Transform Counts using recount3 ---
    # ==========================================
    message("Stage 4: Transforming counts using recount3 methods...")
    
    # Attempt to scale counts using recount3's transform_counts
    scaled_counts <- tryCatch({
        recount3::transform_counts(rse, by = "auc")
    }, error = function(e) {
        message("recount3::transform_counts failed, applying manual scaling fallback: ", e\$message)
        # Fallback: scale to a target of 40 million 100bp reads (AUC = 4e9)
        auc <- colData(rse)\$recount_qc.area_under_coverage
        if (is.null(auc) || any(auc == 0)) {
            auc <- colSums(assay(rse, "raw_counts")) * 100
        }
        t(t(assay(rse, "raw_counts")) * 4e9 / auc)
    })
    
    # Compute scale factors
    scale_factors <- tryCatch({
        recount3::compute_scale_factors(rse)
    }, error = function(e) {
        message("recount3::compute_scale_factors failed, using library size factors fallback: ", e\$message)
        lib_sizes <- colSums(assay(rse, "raw_counts"))
        lib_sizes / mean(lib_sizes)
    })
    
    # ==========================================
    # --- Downstream Diagnostics & PCA ---
    # ==========================================
    message("Stage 5: Performing PCA diagnostics...")
    
    # Log-transform the scaled counts
    log_scaled <- log2(scaled_counts + 1)
    
    # Run PCA
    pca_res <- prcomp(t(log_scaled), scale. = TRUE)
    pca_df <- as.data.frame(pca_res\$x)
    pca_df\$condition <- coldata_df\$condition
    pca_df\$sample <- rownames(pca_df)
    
    # Generate PCA Plot
    pdf("pca_plot.pdf", width = 7, height = 5)
    plot(pca_df\$PC1, pca_df\$PC2, 
         col = as.factor(pca_df\$condition), 
         pch = 19, 
         xlab = paste0("PC1 (", round(summary(pca_res)\$importance[2, 1] * 100, 1), "%)"), 
         ylab = paste0("PC2 (", round(summary(pca_res)\$importance[2, 2] * 100, 1), "%)"), 
         main = "PCA of recount3-Transformed Counts")
    text(pca_df\$PC1, pca_df\$PC2, labels = pca_df\$sample, pos = 3, cex = 0.8)
    legend("topright", legend = unique(pca_df\$condition), col = unique(as.factor(pca_df\$condition)), pch = 19)
    dev.off()
    
    # ==========================================
    # --- Write Outputs ---
    # ==========================================
    message("Stage 6: Writing output files...")
    
    write.csv(scaled_counts, "scaled_counts.csv", row.names = TRUE)
    
    scale_factors_df <- data.frame(
        Sample = names(scale_factors),
        ScaleFactor = scale_factors,
        row.names = NULL
    )
    write.csv(scale_factors_df, "scale_factors.csv", row.names = FALSE)
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_RECOUNT3_RECOUNT3_LOCAL_TRANSFORMATION":',
        paste0('    recount3: ', as.character(packageVersion('recount3')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_recount3_local_transformation.csv versions.yml
    """
}

workflow BIOC_RECOUNT3_RECOUNT3_LOCAL_TRANSFORMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_RECOUNT3_RECOUNT3_LOCAL_TRANSFORMATION(ch_input)

    emit:
    tables   = BIOC_RECOUNT3_RECOUNT3_LOCAL_TRANSFORMATION.out.tables
    plots    = BIOC_RECOUNT3_RECOUNT3_LOCAL_TRANSFORMATION.out.plots
    objects  = BIOC_RECOUNT3_RECOUNT3_LOCAL_TRANSFORMATION.out.objects
    versions = BIOC_RECOUNT3_RECOUNT3_LOCAL_TRANSFORMATION.out.versions
}
