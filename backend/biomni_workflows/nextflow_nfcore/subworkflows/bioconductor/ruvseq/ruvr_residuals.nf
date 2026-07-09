#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RUVSeq — ruvr_residuals
// Estimate factors of unwanted variation using residuals from a first-pass GLM regression.
// Input: counts_matrix.csv, sample_groups.csv
// Container: quay.io/biocontainers/bioconductor-ruvseq:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EDASeq, RUVSeq, edgeR
// Visualizations: PCA plot, RLE plot
// QC: TMM normalization, diagnostic MA/PCA QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform a first-pass GLM regression without RUV
//  * 2. [Core Analysis] Extract deviance residuals from the GLM fit
//  * 3. [Core Analysis] Estimate unwanted variation factors using RUVr with the residuals

nextflow.enable.dsl = 2

process BIOC_RUVSEQ_RUVR_RESIDUALS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("RUVSeq", "EDASeq", "edgeR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(RUVSeq)
    library(EDASeq)
    library(edgeR)
    
    # ------------------------------------------------------------------------------
    # 1. Read User Input Files
    # ------------------------------------------------------------------------------
    # Read raw RNA-Seq read counts
    counts_data <- read.csv("counts_matrix.csv", row.names = 1, check.names = FALSE)
    
    # Read experimental design covariates
    sample_groups <- read.csv("sample_groups.csv", row.names = 1, check.names = FALSE)
    
    # Align samples between counts and sample groups
    common_samples <- intersect(colnames(counts_data), rownames(sample_groups))
    if (length(common_samples) == 0) {
      stop("Error: No matching sample names found between counts_matrix.csv and sample_groups.csv")
    }
    
    counts_data <- counts_data[, common_samples, drop = FALSE]
    sample_groups <- sample_groups[common_samples, , drop = FALSE]
    
    # Extract the covariate of interest 'x'
    if ("x" %in% colnames(sample_groups)) {
      x <- as.factor(sample_groups\$x)
    } else {
      # Fallback to the first column if 'x' is not explicitly named
      x <- as.factor(sample_groups[[1]])
    }
    
    # Construct the SeqExpressionSet object
    set <- newSeqExpressionSet(as.matrix(counts_data),
                               phenoData = data.frame(x, row.names = colnames(counts_data)))
    
    # Define genes to be used for estimating factors of unwanted variation (all genes)
    genes <- rownames(set)
    
    # ------------------------------------------------------------------------------
    # 2. Perform First-Pass GLM Regression & Extract Deviance Residuals
    # ------------------------------------------------------------------------------
    design <- model.matrix(~x, data=pData(set))
    y <- DGEList(counts=counts(set), group=x)
    y <- calcNormFactors(y, method="upperquartile")
    y <- estimateGLMCommonDisp(y, design)
    y <- estimateGLMTagwiseDisp(y, design)
    fit <- glmFit(y, design)
    res <- residuals(fit, type="deviance")
    
    # ------------------------------------------------------------------------------
    # 3. Estimate Unwanted Variation Factors using RUVr
    # ------------------------------------------------------------------------------
    set4 <- RUVr(set, genes, k=1, res)
    
    # ------------------------------------------------------------------------------
    # 4. Write Outputs
    # ------------------------------------------------------------------------------
    # Save the estimated factors of unwanted variation (W_1, etc.)
    write.csv(pData(set4), "unwanted_factors.csv", row.names = TRUE)
    
    # Save the normalized counts (for exploration/visualization purposes)
    write.csv(normCounts(set4), "normalized_counts.csv", row.names = TRUE)
    
    # Save the final SeqExpressionSet object as an RDS file
    saveRDS(set4, "ruvr_output.rds")
    
    # Generate diagnostic plots (RLE and PCA) before and after RUVr
    pdf("ruvr_diagnostics.pdf", width = 10, height = 10)
    par(mfrow = c(2, 2))
    
    # Before RUVr
    plotRLE(set, outline = FALSE, main = "RLE Before RUVr")
    plotPCA(set, main = "PCA Before RUVr")
    
    # After RUVr
    plotRLE(set4, outline = FALSE, main = "RLE After RUVr")
    plotPCA(set4, main = "PCA After RUVr")
    
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # TMM normalization — DGEList\$samples\$norm.factors set (Robinson & Oshlack 2010).
    .tmm_factors <- NULL; .tmm_n_nontrivial <- NA_real_
    for (.tmm_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .tmm_obj <- tryCatch(readRDS(.tmm_rds), error = function(e) NULL)
      if (!is.null(.tmm_obj) && inherits(.tmm_obj, "DGEList")) {
        .tmm_f <- tryCatch(.tmm_obj\$samples\$norm.factors, error = function(e) NULL)
        if (!is.null(.tmm_f) && length(.tmm_f) > 0) {
          .tmm_factors <- .tmm_f; .tmm_n_nontrivial <- sum(abs(.tmm_f - 1.0) > 1e-6); break
        }
      }
    }
    .gates_by_label[["TMM normalization"]] <- list(
      gate_row = "bioc_tmm_normalization",
      metric_name = "n_nontrivial_norm_factors",
      metric_value = .tmm_n_nontrivial,
      passes = isTRUE(is.finite(.tmm_n_nontrivial) && .tmm_n_nontrivial > 0),
      status = if (is.finite(.tmm_n_nontrivial)) paste0("computed (n=", length(.tmm_factors), ", nontrivial=", .tmm_n_nontrivial, ")")
               else "not_computed (no DGEList .rds artifact present)"
    )

    # diagnostic MA/PCA QC — PC1 variance explained on any large matrix.
    # Pass when PC1 > 10% (Risso 2014 RUV-seq diagnostic).
    .pca_pc1 <- NA_real_; .pca_files <- character(0)
    for (.pca_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .pca_obj <- tryCatch(readRDS(.pca_rds), error = function(e) NULL)
      .pca_mat <- if (is.matrix(.pca_obj) || is.data.frame(.pca_obj)) .pca_obj else NULL
      if (!is.null(.pca_mat) && ncol(.pca_mat) >= 3 && nrow(.pca_mat) >= 100) {
        .pca_m <- suppressWarnings(as.matrix(.pca_mat))
        .pca_kept <- apply(.pca_m, 1, function(r) all(is.finite(r)) && var(r) > 0)
        if (sum(.pca_kept) >= 50) {
          .pca_fit <- tryCatch(prcomp(t(.pca_m[.pca_kept, , drop = FALSE])), error = function(e) NULL)
          if (!is.null(.pca_fit)) {
            .pca_vars <- (.pca_fit\$sdev^2) / sum(.pca_fit\$sdev^2)
            .pca_pc1 <- round(.pca_vars[1] * 100, 2); .pca_files <- c(.pca_files, .pca_rds); break
          }
        }
      }
    }
    .gates_by_label[["diagnostic MA/PCA QC"]] <- list(
      gate_row = "bioc_diagnostic_ma_pca_qc",
      metric_name = "pc1_var_explained",
      metric_value = .pca_pc1,
      passes = isTRUE(is.finite(.pca_pc1) && .pca_pc1 > 10),
      status = if (is.finite(.pca_pc1)) paste0("computed (PC1=", .pca_pc1, "%)")
               else "not_computed (no large numeric matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_RUVSEQ_RUVR_RESIDUALS",
      domain  = "bioconductor",
      declared_qc_steps = c("TMM normalization", "diagnostic MA/PCA QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_RUVSEQ_RUVR_RESIDUALS":',
        paste0('    RUVSeq: ', as.character(packageVersion('RUVSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ruvr_residuals.csv versions.yml
    """
}

workflow BIOC_RUVSEQ_RUVR_RESIDUALS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_matrix.csv, sample_groups.csv ] ]

    main:
    BIOC_RUVSEQ_RUVR_RESIDUALS(ch_input)

    emit:
    tables   = BIOC_RUVSEQ_RUVR_RESIDUALS.out.tables
    plots    = BIOC_RUVSEQ_RUVR_RESIDUALS.out.plots
    objects  = BIOC_RUVSEQ_RUVR_RESIDUALS.out.objects
    versions = BIOC_RUVSEQ_RUVR_RESIDUALS.out.versions
}
