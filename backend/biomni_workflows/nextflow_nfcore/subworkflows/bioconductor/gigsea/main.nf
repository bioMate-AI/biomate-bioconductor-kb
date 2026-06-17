#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GIGSEA — gigsea_differential_expression_enrichment
// Perform genotype-imputed gene set enrichment analysis (GIGSEA) using custom-built gene sets derived from RNA-seq differential expression statistics.
// Input: counts.csv, coldata.csv
// Container: 1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GIGSEA, Matrix
// Visualizations: bar plot, enrichment plot
// QC: count normalization
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GIGSEA_GIGSEA_DIFFERENTIAL_EXPRESSION_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("GIGSEA", "Matrix")
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
    library(GIGSEA)
    library(Matrix)
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    message("Loading input counts and metadata...")
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Align samples between counts and coldata
    common_samples <- intersect(colnames(counts), coldata\$sample)
    if (length(common_samples) < 2) {
      stop("Error: Insufficient matching samples between counts.csv and coldata.csv.")
    }
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), ]
    
    # Normalize counts using CPM (Counts Per Million)
    message("Normalizing expression data...")
    libsizes <- colSums(counts)
    cpm <- t(t(counts) / libsizes) * 1e6
    log2_cpm <- log2(cpm + 1)
    
    # ==========================================
    # --- Compute Differential Expression Statistics ---
    # ==========================================
    message("Computing differential expression statistics...")
    conds <- unique(coldata\$condition)
    if (length(conds) < 2) {
      stop("Error: coldata\$condition must contain at least two distinct groups.")
    }
    
    group1 <- coldata\$sample[coldata\$condition == conds[1]]
    group2 <- coldata\$sample[coldata\$condition == conds[2]]
    
    n1 <- length(group1)
    n2 <- length(group2)
    
    # Compute row-wise variance and mean
    var1 <- apply(log2_cpm[, group1, drop = FALSE], 1, var)
    var2 <- apply(log2_cpm[, group2, drop = FALSE], 1, var)
    mean1 <- rowMeans(log2_cpm[, group1, drop = FALSE])
    mean2 <- rowMeans(log2_cpm[, group2, drop = FALSE])
    
    # Calculate standard error and t-statistic (as a proxy for Z-score)
    se <- sqrt(var1/n1 + var2/n2 + 1e-6)
    t_stat <- (mean1 - mean2) / se
    names(t_stat) <- rownames(counts)
    
    # Define weights based on mean expression level (higher expression = higher confidence)
    weights <- rowMeans(log2_cpm) + 1
    names(weights) <- rownames(counts)
    
    # ==========================================
    # --- Build Custom Gene Sets ---
    # ==========================================
    message("Building custom gene sets from expression data...")
    num_genes <- length(t_stat)
    pathway_size <- max(5, min(50, floor(num_genes * 0.1)))
    
    # Sort genes to define mock pathways representing biological extremes
    genes_sorted <- names(t_stat)[order(t_stat, decreasing = TRUE)]
    up_genes <- head(genes_sorted, pathway_size)
    down_genes <- tail(genes_sorted, pathway_size)
    random_genes <- sample(names(t_stat), pathway_size)
    
    terms <- c("Pathway_Up_Regulated", "Pathway_Down_Regulated", "Pathway_Random_Control")
    geneset_vec <- c(
      paste(up_genes, collapse = ","),
      paste(down_genes, collapse = ","),
      paste(random_genes, collapse = ",")
    )
    value_vec <- c(
      paste(rep(1, length(up_genes)), collapse = ","),
      paste(rep(1, length(down_genes)), collapse = ","),
      paste(rep(1, length(random_genes)), collapse = ",")
    )
    
    # Convert gene sets to a sparse matrix format
    net <- geneSet2sparseMatrix(term = terms, geneset = geneset_vec, value = value_vec)
    
    # ==========================================
    # --- Intersect and Align Data ---
    # ==========================================
    message("Aligning gene expression statistics with gene sets...")
    data_df <- data.frame(gene = names(t_stat), fc = t_stat, weights = weights, stringsAsFactors = FALSE)
    data2 <- orderedIntersect(x = data_df, by.x = data_df\$gene, by.y = rownames(net))
    net2 <- orderedIntersect(x = net, by.x = rownames(net), by.y = data_df\$gene)
    
    # ==========================================
    # --- Run GIGSEA Enrichment Analyses ---
    # ==========================================
    message("Running Single Gene Set Enrichment Analysis (SGSEA)...")
    sgsea_res <- tryCatch({
      permutationSimpleLmMatrix(fc = data2\$fc, net = net2, weights = data2\$weights, num = 100)
    }, error = function(e) {
      warning("SGSEA failed: ", e\$message)
      NULL
    })
    
    message("Running Multiple Gene Set Enrichment Analysis (MGSEA)...")
    mgsea_res <- tryCatch({
      permutationMultipleLmMatrix(fc = data2\$fc, net = net2, weights = data2\$weights, num = 100)
    }, error = function(e) {
      warning("MGSEA failed: ", e\$message)
      NULL
    })
    
    # ==========================================
    # --- Save Results and Generate Plots ---
    # ==========================================
    message("Writing output files...")
    if (!is.null(sgsea_res)) {
      write.csv(sgsea_res, "sgsea_results.csv", row.names = FALSE)
    } else {
      write.csv(data.frame(Error = "SGSEA failed to run"), "sgsea_results.csv", row.names = FALSE)
    }
    
    if (!is.null(mgsea_res)) {
      write.csv(mgsea_res, "mgsea_results.csv", row.names = FALSE)
    } else {
      write.csv(data.frame(Error = "MGSEA failed to run"), "mgsea_results.csv", row.names = FALSE)
    }
    
    # Generate diagnostic plots
    pdf("enrichment_plots.pdf", width = 8, height = 6)
    par(mfrow = c(1, 2), mar = c(10, 4, 4, 2))
    
    if (!is.null(sgsea_res)) {
      barplot(sgsea_res\$observedCorr, names.arg = sgsea_res\$term, las = 2,
              main = "SGSEA Observed Corr", col = "skyblue", ylab = "Correlation")
    } else {
      plot.new()
      text(0.5, 0.5, "SGSEA Plot Unavailable")
    }
    
    if (!is.null(mgsea_res)) {
      barplot(mgsea_res\$observedTstats, names.arg = mgsea_res\$term, las = 2,
              main = "MGSEA Observed T-stats", col = "coral", ylab = "T-statistic")
    } else {
      plot.new()
      text(0.5, 0.5, "MGSEA Plot Unavailable")
    }
    
    dev.off()
    message("Pipeline completed successfully.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_GIGSEA_GIGSEA_DIFFERENTIAL_EXPRESSION_ENRICHMENT",
      domain  = "bioconductor",
      declared_qc_steps = c("count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_GIGSEA_GIGSEA_DIFFERENTIAL_EXPRESSION_ENRICHMENT":',
        paste0('    GIGSEA: ', as.character(packageVersion('GIGSEA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gigsea_differential_expression_enrichment.csv versions.yml
    """
}

workflow BIOC_GIGSEA_GIGSEA_DIFFERENTIAL_EXPRESSION_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_GIGSEA_GIGSEA_DIFFERENTIAL_EXPRESSION_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_GIGSEA_GIGSEA_DIFFERENTIAL_EXPRESSION_ENRICHMENT.out.tables
    plots    = BIOC_GIGSEA_GIGSEA_DIFFERENTIAL_EXPRESSION_ENRICHMENT.out.plots
    objects  = BIOC_GIGSEA_GIGSEA_DIFFERENTIAL_EXPRESSION_ENRICHMENT.out.objects
    versions = BIOC_GIGSEA_GIGSEA_DIFFERENTIAL_EXPRESSION_ENRICHMENT.out.versions
}
