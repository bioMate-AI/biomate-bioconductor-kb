#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scone — scone_normalization_comparison
// Filter poor-quality single-cell libraries and systematically evaluate, rank, and select the best normalization workflow from multiple combinations of scaling, i
// Input: raw_counts.csv, cell_metadata.csv, housekeeping_genes.txt, positive_control_genes.txt
// Container: quay.io/biocontainers/bioconductor-scone:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, SingleCellExperiment, scone
// Visualizations: plot (ggplot/base)
// QC: low-count filtering, missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Input Files
//  * 2. [Visualization & Output] Filter Poor-Quality Samples & Genes
//  * 3. [Visualization & Output] Create SconeExperiment Object
//  * 4. [Visualization & Output] Define Scaling and Imputation Modules
//  * 5. [Visualization & Output] Define and Select SCONE Workflows
//  * 6. [Visualization & Output] Run and Score Workflows
//  * 7. [Visualization & Output] Extract Scores and Ranks
//  * 8. [Visualization & Output] Extract Optimal Normalized Expression Matrix
//  * 9. [Visualization & Output] Visualize Workflow Performance

nextflow.enable.dsl = 2

process BIOC_SCONE_SCONE_NORMALIZATION_COMPARISON {
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
    .bm_deps <- c("scone", "BiocParallel", "SummarizedExperiment")
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
        
        # Load required libraries        library(SummarizedExperiment)

        library(scone)
        library(BiocParallel)
        
        # ==========================================
        # --- Read User Input Files ---
        # ==========================================
        
        # Read raw counts matrix (genes as rows, cells as columns)
        counts <- as.matrix(read.csv("raw_counts.csv", row.names = 1, check.names = FALSE))
        
        # Read cell-level metadata
        meta <- read.csv("cell_metadata.csv", row.names = 1, check.names = FALSE)
        
        # Align counts and metadata
        common_cells <- intersect(colnames(counts), rownames(meta))
        if (length(common_cells) == 0) {
          stop("Error: No common cells found between raw_counts.csv and cell_metadata.csv")
        }
        counts <- counts[, common_cells, drop = FALSE]
        meta <- meta[common_cells, , drop = FALSE]
        
        # Read control gene lists
        hk <- readLines("housekeeping_genes.txt")
        poscon_genes <- readLines("positive_control_genes.txt")
        
        # Identify Biological Condition column
        bio_col <- "Biological_Condition"
        if (!(bio_col %in% colnames(meta))) {
          non_numeric_cols <- colnames(meta)[!sapply(meta, is.numeric)]
          if (length(non_numeric_cols) > 0) {
            bio_col <- non_numeric_cols[1]
          } else {
            bio_col <- NULL
          }
        }
        
        # Identify QC columns (numeric columns in metadata, excluding Biological_Condition)
        qc_cols <- colnames(meta)[sapply(meta, is.numeric)]
        if (!is.null(bio_col)) {
          qc_cols <- setdiff(qc_cols, bio_col)
        }
        
        # Construct the SingleCellExperiment object (representing 'fluidigm' in the vignette)
        fluidigm <- SingleCellExperiment(assays = list(counts = counts), colData = meta)
        metadata(fluidigm)\$which_qc <- qc_cols
        
        # ==========================================
        # --- Filter Poor-Quality Samples & Genes ---
        # ==========================================
        
        # Initial Gene Filtering: Select "common" transcripts based on proportional criteria
        num_reads = quantile(assay(fluidigm)[assay(fluidigm) > 0])[4]
        num_cells = 0.25 * ncol(fluidigm)
        is_common = rowSums(assay(fluidigm) >= num_reads) >= num_cells
        
        # Identify NREADS and RALIGN or fallback
        nreads_val <- if ("NREADS" %in% colnames(meta)) colData(fluidigm)\$NREADS else colSums(assay(fluidigm))
        ralign_val <- if ("RALIGN" %in% colnames(meta)) colData(fluidigm)\$RALIGN else NULL
        
        # Metric-based Filtering (saving diagnostic plots to PDF)
        pdf("metric_sample_filter_plots.pdf")
        mfilt = metric_sample_filter(assay(fluidigm),
                                     nreads = nreads_val,
                                     ralign = ralign_val,
                                     gene_filter = is_common,
                                     pos_controls = rownames(fluidigm) %in% hk,
                                     zcut = 3, mixture = FALSE,
                                     plot = TRUE)
        dev.off()
        
        # Simplify to a single logical vector
        mfilt = !apply(simplify2array(mfilt[!is.na(mfilt)]), 1, any)
        
        # Apply sample filter
        goodDat = fluidigm[, mfilt]
        
        # Final Gene Filtering: Highly expressed in at least 5 cells
        num_reads = quantile(assay(fluidigm)[assay(fluidigm) > 0])[4]
        num_cells = 5
        is_quality = rowSums(assay(fluidigm) >= num_reads) >= num_cells
        
        # Extract filtered expression matrix
        expr = assay(goodDat)[is_quality, ]
        
        # ==========================================
        # --- Create SconeExperiment Object ---
        # ==========================================
        
        if (!is.null(bio_col)) {
          bio = factor(colData(goodDat)[[bio_col]])
        } else {
          bio = factor(rep("all", ncol(goodDat)))
        }
        
        qc = colData(goodDat)[, metadata(goodDat)\$which_qc, drop = FALSE]
        ppq = scale(qc[, apply(qc, 2, sd) > 0, drop = FALSE], center = TRUE, scale = TRUE)
        
        negcon = intersect(rownames(expr), hk)
        poscon = intersect(rownames(expr), poscon_genes)
        
        my_scone <- SconeExperiment(expr,
                        qc=ppq, bio = bio,
                        negcon_ruv = rownames(expr) %in% negcon,
                        poscon = rownames(expr) %in% poscon
        )
        
        # ==========================================
        # --- Define Scaling and Imputation Modules ---
        # ==========================================
        
        # Simple FNR model estimation with SCONE::estimate_ziber
        fnr_out = estimate_ziber(x = expr, bulk_model = TRUE, pos_controls = rownames(expr) %in% hk, maxiter = 10000)
        
        imputation=list(none=impute_null, # No imputation
                        expect=impute_expectation) # Replace zeroes
        
        impute_args = list(p_nodrop = fnr_out\$p_nodrop, mu = exp(fnr_out\$Alpha[1,]))
        
        # User-defined function: Dividing by number of detected genes
        EFF_FN = function (ei) {
          sums = colSums(ei > 0)
          eo = t(t(ei)*sums/mean(sums))
          return(eo)
        }
        
        scaling=list(none=identity, # Identity - do nothing
                     eff = EFF_FN, # User-defined function
                     sum = SUM_FN, # SCONE library wrappers...
                     tmm = TMM_FN, 
                     uq = UQ_FN,
                     fq = FQT_FN,
                     psi = PSINORM_FN,
                     deseq = DESEQ_FN)
        
        # ==========================================
        # --- Define and Select SCONE Workflows ---
        # ==========================================
        
        my_scone <- scone(my_scone,
                        imputation = imputation,
                        impute_args = impute_args,
                        scaling=scaling,
                        k_qc=3, k_ruv = 3,
                        adjust_bio="no",
                        run=FALSE)
        
        # Screen out incompatible workflows (e.g. expectation imputation with EFF scaling)
        is_screened = ((get_params(my_scone)\$imputation_method == "expect") & 
                       (get_params(my_scone)\$scaling_method %in% c("none", "eff")))
        
        my_scone = select_methods(my_scone,
                                  rownames(get_params(my_scone))[!is_screened ])
        
        # ==========================================
        # --- Run and Score Workflows ---
        # ==========================================
        
        BiocParallel::register(
          BiocParallel::SerialParam()
        ) # Register BiocParallel Serial Execution
        
        my_scone <- scone(my_scone,
                          imputation = imputation,
                          impute_args = impute_args,
                          scaling=scaling,
                          run=TRUE,
                          eval_kclust = 2:6,
                          stratified_pam = TRUE,
                          return_norm = "in_memory",
                          zero = "postadjust")
        
        # ==========================================
        # --- Extract Scores and Ranks ---
        # ==========================================
        
        scores <- get_scores(my_scone)
        score_ranks <- get_score_ranks(my_scone)
        
        write.csv(scores, "scone_scores.csv", row.names = TRUE)
        write.csv(as.data.frame(score_ranks), "scone_score_ranks.csv", row.names = TRUE)
        
        # ==========================================
        # --- Extract Optimal Normalized Expression Matrix ---
        # ==========================================
        
        out_norm = get_normalized(my_scone,
                                  method = rownames(get_params(my_scone))[1])
        
        write.csv(out_norm, "normalized_counts.csv", row.names = TRUE)
        
        # Save the SconeExperiment object for downstream use
        saveRDS(my_scone, "my_scone.rds")
        
        # ==========================================
        # --- Visualize Workflow Performance ---
        # ==========================================
        
        pc_obj = prcomp(apply(t(get_scores(my_scone)), 1, rank),
                        center = TRUE, scale = FALSE)
        
        pdf("scone_biplot.pdf")
        bp_obj = biplot_color(pc_obj, y = -get_score_ranks(my_scone), expand = .6)
        
        # Highlight top method and no-op method
        points(t(bp_obj[1, ]), pch = 1, col = "red", cex = 1)
        points(t(bp_obj[1, ]), pch = 1, col = "red", cex = 1.5)
        
        if ("none,none,no_uv,no_bio,no_batch" %in% rownames(bp_obj)) {
          points(t(bp_obj[rownames(bp_obj) == "none,none,no_uv,no_bio,no_batch", ]),
                 pch = 1, col = "blue", cex = 1)
          points(t(bp_obj[rownames(bp_obj) == "none,none,no_uv,no_bio,no_batch", ]),
                 pch = 1, col = "blue", cex = 1.5)
        
          arrows(bp_obj[rownames(bp_obj) == "none,none,no_uv,no_bio,no_batch", ][1],
                 bp_obj[rownames(bp_obj) == "none,none,no_uv,no_bio,no_batch", ][2],
                 bp_obj[1, ][1],
                 bp_obj[1, ][2],
                 lty = 2, lwd = 2)
        }
        dev.off()
        
        # Launch interactive sconeReport Shiny app if in an interactive session
        if (interactive()) {
          scone_methods = c(rownames(get_params(my_scone))[1:12], "none,none,no_uv,no_bio,no_batch")
          sconeReport(my_scone, methods = scone_methods,
                      qc = ppq,
                      bio = bio,
                      negcon = negcon, poscon = poscon)
        }

    writeLines(c(
        '"BIOC_SCONE_SCONE_NORMALIZATION_COMPARISON":',
        paste0('    scone: ', as.character(packageVersion('scone')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scone_normalization_comparison.csv versions.yml
    """
}

workflow BIOC_SCONE_SCONE_NORMALIZATION_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_counts.csv, cell_metadata.csv, housekeeping_genes.txt, positive_control_genes.txt ] ]

    main:
    BIOC_SCONE_SCONE_NORMALIZATION_COMPARISON(ch_input)

    emit:
    tables   = BIOC_SCONE_SCONE_NORMALIZATION_COMPARISON.out.tables
    plots    = BIOC_SCONE_SCONE_NORMALIZATION_COMPARISON.out.plots
    objects  = BIOC_SCONE_SCONE_NORMALIZATION_COMPARISON.out.objects
    versions = BIOC_SCONE_SCONE_NORMALIZATION_COMPARISON.out.versions
}
