#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: edaseq — gene_level_eda_and_normalization
// Diagnose gene-level biases (GC-content, length, over-dispersion) and perform within-lane and between-lane normalization on count data.
// Input: gene_counts.tsv, gene_metadata.tsv
// Container: quay.io/biocontainers/bioconductor-edaseq:2.44.0--r45hdfd78af_0
// R packages: DESeq2, EDASeq, edgeR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: box plot
// QC: dispersion/size-factor estimation, low-count filtering

nextflow.enable.dsl = 2

process BIOC_EDASEQ_GENE_LEVEL_EDA_AND_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-edaseq:2.44.0--r45hdfd78af_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("DESeq2", "EDASeq", "edgeR")
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
    library(EDASeq)
    library(edgeR)
    library(DESeq2)
    
    # -----------------------------------------------------------------
    # 1. Read User Input Files
    # -----------------------------------------------------------------
    # Read gene counts matrix (genes as rows, samples as columns)
    geneLevelData <- read.delim("gene_counts.tsv", row.names = 1, check.names = FALSE)
    
    # Read gene metadata (must contain 'gc' and 'length' columns, genes as rows)
    gene_metadata <- read.delim("gene_metadata.tsv", row.names = 1, check.names = FALSE)
    
    # Extract GC-content and length vectors
    yeastGC <- gene_metadata\$gc
    names(yeastGC) <- rownames(gene_metadata)
    
    yeastLength <- gene_metadata\$length
    names(yeastLength) <- rownames(gene_metadata)
    
    # -----------------------------------------------------------------
    # 2. Filter and Construct SeqExpressionSet
    # -----------------------------------------------------------------
    # Filter out non-expressed or low-count genes (mean count > 10)
    filter <- apply(geneLevelData, 1, function(x) mean(x) > 10)
    common <- intersect(names(yeastGC), rownames(geneLevelData[filter, ]))
    
    # Construct feature data frame
    feature <- data.frame(gc = yeastGC, length = yeastLength)
    
    # Define experimental conditions (defaulting to alternating mut/wt based on sample size)
    n_samples <- ncol(geneLevelData)
    conditions_vector <- factor(rep(c("mut", "wt"), length.out = n_samples))
    
    # Create the SeqExpressionSet object
    data <- newSeqExpressionSet(counts = as.matrix(geneLevelData[common, ]),
                                featureData = feature[common, ],
                                phenoData = data.frame(
                                  conditions = conditions_vector,
                                  row.names = colnames(geneLevelData)))
    
    # Print basic structure info to stdout
    cat("--- SeqExpressionSet Object Summary ---\n")
    print(head(counts(data)))
    print(pData(data))
    print(head(fData(data)))
    print(head(offst(data)))
    
    # -----------------------------------------------------------------
    # 3. Visualizations (EDA)
    # -----------------------------------------------------------------
    pdf("eda_diagnostic_plots.pdf", width = 10, height = 8)
    
    # Define colors for plotting
    colors <- rep(c(rgb(1, 0, 0, alpha = 0.7), rgb(0, 0, 1, alpha = 0.7)), length.out = n_samples)
    
    # Boxplot of gene counts
    boxplot(data, col = colors)
    
    # Mean-Difference (MD) Plot (comparing sample 1 and sample 3, or last sample if < 3)
    lane_compare <- ifelse(ncol(data) >= 3, 3, ncol(data))
    MDPlot(data, c(1, lane_compare))
    
    # Over-dispersion diagnostics (Mean-Variance Plots)
    if (ncol(data) >= 2) {
      meanVarPlot(data[, 1:2], log = TRUE, ylim = c(0, 16))
    }
    meanVarPlot(data, log = TRUE, ylim = c(0, 16))
    
    # GC-content bias plot
    biasPlot(data, "gc", log = TRUE, ylim = c(1, 5))
    
    # Stratified boxplot of log-fold-change by GC-content
    lfc <- log(counts(data)[, lane_compare] + 0.1) - log(counts(data)[, 1] + 0.1)
    biasBoxplot(lfc, fData(data)\$gc)
    
    dev.off()
    
    # -----------------------------------------------------------------
    # 4. Normalization (Within-Lane and Between-Lane)
    # -----------------------------------------------------------------
    # Perform within-lane normalization (GC-content correction) followed by between-lane normalization
    dataWithin <- withinLaneNormalization(data, "gc", which = "full")
    dataNorm <- betweenLaneNormalization(dataWithin, which = "full")
    
    # Save normalized diagnostic plots
    pdf("normalized_diagnostic_plots.pdf", width = 10, height = 8)
    biasPlot(dataNorm, "gc", log = TRUE, ylim = c(1, 5))
    boxplot(dataNorm, col = colors)
    dev.off()
    
    # Save normalized counts object
    saveRDS(dataNorm, "dataNorm.rds")
    write.csv(counts(dataNorm), "normalized_counts.csv")
    
    # -----------------------------------------------------------------
    # 5. Calculate and Export Normalization Offsets
    # -----------------------------------------------------------------
    dataOffset <- withinLaneNormalization(data, "gc", which = "full", offset = TRUE)
    dataOffset <- betweenLaneNormalization(dataOffset, which = "full", offset = TRUE)
    
    # Save offset object
    saveRDS(dataOffset, "dataOffset.rds")
    
    # -----------------------------------------------------------------
    # 6. Downstream Differential Expression Analysis
    # -----------------------------------------------------------------
    
    # --- edgeR Workflow ---
    design <- model.matrix(~conditions, data = pData(dataOffset))
    y <- DGEList(counts = counts(dataOffset), group = pData(dataOffset)\$conditions)
    y\$offset <- -offst(dataOffset) # Note the negative sign convention for edgeR offsets
    y <- estimateDisp(y, design)
    fit <- glmFit(y, design)
    lrt <- glmLRT(fit, coef = 2)
    
    edgeR_results <- topTags(lrt, n = Inf)
    write.csv(as.data.frame(edgeR_results), "edgeR_differential_expression.csv")
    
    # --- DESeq2 Workflow ---
    dds <- DESeqDataSetFromMatrix(countData = counts(dataOffset), 
                                  colData = pData(dataOffset), 
                                  design = ~ conditions)
    normFactors <- exp(-1 * offst(dataOffset))
    normFactors <- normFactors / exp(rowMeans(log(normFactors)))
    normalizationFactors(dds) <- normFactors
    dds <- DESeq(dds)
    res <- results(dds)
    
    write.csv(as.data.frame(res), "deseq2_differential_expression.csv")
    
    # -----------------------------------------------------------------
    # 7. Unrounded Normalization and Offset Verification
    # -----------------------------------------------------------------
    dataNorm_unrounded <- betweenLaneNormalization(data, round = FALSE, offset = TRUE)
    norm1 <- normCounts(dataNorm_unrounded)
    norm2 <- exp(log(counts(dataNorm_unrounded) + 0.1) + offst(dataNorm_unrounded)) - 0.1
    
    write.csv(head(norm1 - norm2), "unrounded_offset_verification.csv")
    
    rounded_diff <- head(round(normCounts(dataNorm_unrounded)) - round(counts(dataNorm_unrounded) * exp(offst(dataNorm_unrounded))))
    write.csv(rounded_diff, "rounded_offset_verification.csv")
    
    # -----------------------------------------------------------------
    # 8. Optional: Retrieve Gene Length and GC-Content (Robust tryCatch)
    # -----------------------------------------------------------------
    tryCatch({
      cat("Attempting to retrieve gene metadata via getGeneLengthAndGCContent...\n")
      # Example call using human genes as documented
      getGeneLengthAndGCContent(id = c("ENSG00000012048", "ENSG00000139618"), org = "hsa")
    }, error = function(e) {
      message("getGeneLengthAndGCContent call skipped or failed (likely offline or missing DB): ", e\$message)
    })
    
    cat("Pipeline completed successfully.\n")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # dispersion/size-factor estimation — object-type-aware. Try DESeq2
    # DESeqDataSet (mcols$dispOutlier), then edgeR DGEList (common.dispersion).
    .dsf_value <- NA_real_; .dsf_kind <- "none"
    for (.dsf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .dsf_obj <- tryCatch(readRDS(.dsf_rds), error = function(e) NULL)
      if (!is.null(.dsf_obj)) {
        if (inherits(.dsf_obj, "DESeqDataSet")) {
          .dsf_o <- tryCatch(mcols(.dsf_obj)\$dispOutlier, error = function(e) NULL)
          if (!is.null(.dsf_o)) { .dsf_value <- round(mean(.dsf_o, na.rm = TRUE), 4); .dsf_kind <- "deseq2"; break }
        } else if (inherits(.dsf_obj, "DGEList")) {
          .dsf_v <- tryCatch(.dsf_obj\$common.dispersion, error = function(e) NULL)
          if (!is.null(.dsf_v) && is.finite(.dsf_v)) { .dsf_value <- round(sqrt(.dsf_v), 4); .dsf_kind <- "edger_bcv"; break }
        }
      }
    }
    .gates_by_label[["dispersion/size-factor estimation"]] <- list(
      gate_row = "bioc_dispersion_size_factor",
      metric_name = if (.dsf_kind == "edger_bcv") "common_bcv" else "disp_outlier_fraction",
      metric_value = .dsf_value,
      passes = isTRUE(
        (.dsf_kind == "deseq2" && is.finite(.dsf_value) && .dsf_value <= 0.01) ||
        (.dsf_kind == "edger_bcv" && is.finite(.dsf_value) && .dsf_value > 0 && .dsf_value < 1.0)
      ),
      status = if (is.finite(.dsf_value)) paste0("computed (", .dsf_kind, ")")
               else "not_computed (no DESeqDataSet/DGEList .rds artifact present)"
    )

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .lcf_obj <- tryCatch(readRDS(.lcf_rds), error = function(e) NULL)
      .lcf_mat <- if (is.matrix(.lcf_obj) || is.data.frame(.lcf_obj)) .lcf_obj else NULL
      if (!is.null(.lcf_mat) && nrow(.lcf_mat) > 100) {
        .lcf_m <- tryCatch(as.matrix(.lcf_mat), error = function(e) NULL)
        if (!is.null(.lcf_m)) {
          .lcf_row_med <- suppressWarnings(apply(.lcf_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
          .lcf_kept <- sum(is.finite(.lcf_row_med) & .lcf_row_med >= 1) / nrow(.lcf_m)
          .lcf_kept_fractions <- c(.lcf_kept_fractions, .lcf_kept)
          .lcf_scanned <- c(.lcf_scanned, .lcf_rds)
        }
      }
    }
    .lcf_kept <- if (length(.lcf_kept_fractions) > 0) round(median(.lcf_kept_fractions), 4) else NA_real_
    .gates_by_label[["low-count filtering"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = .lcf_kept,
      passes = isTRUE(is.finite(.lcf_kept) && .lcf_kept >= 0.3 && .lcf_kept <= 0.6),
      status = if (is.finite(.lcf_kept)) paste0("computed (proxy: rows w/ median count >=1 across ", length(.lcf_scanned), " matrix .rds)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_EDASEQ_GENE_LEVEL_EDA_AND_NORMALIZATION",
      domain  = "bioconductor",
      declared_qc_steps = c("dispersion/size-factor estimation", "low-count filtering"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_EDASEQ_GENE_LEVEL_EDA_AND_NORMALIZATION":',
        paste0('        edaseq: ', as.character(packageVersion("edaseq")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_level_eda_and_normalization.csv versions.yml
    """
}

workflow BIOC_EDASEQ_GENE_LEVEL_EDA_AND_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_counts.tsv, gene_metadata.tsv ] ]

    main:
    BIOC_EDASEQ_GENE_LEVEL_EDA_AND_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_EDASEQ_GENE_LEVEL_EDA_AND_NORMALIZATION.out.tables
    plots    = BIOC_EDASEQ_GENE_LEVEL_EDA_AND_NORMALIZATION.out.plots
    objects  = BIOC_EDASEQ_GENE_LEVEL_EDA_AND_NORMALIZATION.out.objects
    versions = BIOC_EDASEQ_GENE_LEVEL_EDA_AND_NORMALIZATION.out.versions
}
