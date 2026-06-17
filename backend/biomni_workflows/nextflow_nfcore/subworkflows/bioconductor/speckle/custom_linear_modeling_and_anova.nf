#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: speckle — custom_linear_modeling_and_anova
// Extract transformed proportions to perform custom linear modeling, ANOVA, pairwise t-tests, continuous trend fitting, or random effects modeling.
// Input: sce_all
// Container: quay.io/biocontainers/bioconductor-speckle:1.10.0--r45hdfd78af_0
// R packages: SingleCellExperiment, edgeR, ggplot2, limma, patchwork, scater, speckle, statmod
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, edgeR, ggplot2, limma, patchwork, scater, speckle, statmod
// Visualizations: plot (ggplot/base)
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read the input SingleCellExperiment object
//  * 2. [Input & Preparation] Extract counts, proportions, and transformed proportions
//  * 3. [Input & Preparation] Set up a design matrix for group and pairing covariates
//  * 4. [Input & Preparation] Perform an ANOVA test across multiple groups using
//  * 5. [Input & Preparation] Perform a pairwise t-test using propeller.ttest with
//  * 6. [Input & Preparation] Fit a continuous variable (dose/trend) directly using
//  * 7. [Input & Preparation] Fit a linear model accounting for random effects using
//  * 8. [Input & Preparation] Generate and save diagnostic plots

nextflow.enable.dsl = 2

process BIOC_SPECKLE_CUSTOM_LINEAR_MODELING_AND_ANOVA {
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
    .bm_deps <- c("SingleCellExperiment", "edgeR", "ggplot2", "limma", "patchwork", "scater", "speckle", "statmod")
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
    library(speckle)
    library(limma)
    library(ggplot2)
    library(scater)
    library(patchwork)
    library(edgeR)
    library(statmod)
    
    # --- Read the input SingleCellExperiment object ---
    if (file.exists("sce_all.rds")) {
      sce_all <- readRDS("sce_all.rds")
    } else if (file.exists("sce_all")) {
      sce_all <- readRDS("sce_all")
    } else {
      stop("Error: Could not find 'sce_all' or 'sce_all.rds' in the working directory.")
    }
    
    # --- Extract counts, proportions, and transformed proportions ---
    props <- getTransformedProps(sce_all\$cluster, sce_all\$sample, transform="logit")
    
    samples_in_props <- colnames(props\$TransformedProps)
    
    # Extract unique sample-to-group mapping from sce_all
    sample_group_map <- unique(data.frame(
      sample = sce_all\$sample,
      group = sce_all\$group
    ))
    
    # Extract pair and dose covariates only if they actually exist in the experimental design
    if (!is.null(sce_all\$pair)) {
      sample_group_map\$pair <- sce_all\$pair[match(sample_group_map\$sample, sce_all\$sample)]
    }
    if (!is.null(sce_all\$dose)) {
      sample_group_map\$dose <- sce_all\$dose[match(sample_group_map\$sample, sce_all\$sample)]
    }
    
    sample_group_map <- sample_group_map[match(samples_in_props, sample_group_map\$sample), ]
    
    # Use the actual groups from the user's data
    group <- factor(sample_group_map\$group)
    
    # --- Set up a design matrix for group and pairing covariates ---
    if ("pair" %in% colnames(sample_group_map)) {
      pair <- factor(sample_group_map\$pair)
      design <- model.matrix(~ 0 + group + pair)
    } else {
      design <- model.matrix(~ 0 + group)
    }
    
    # --- Perform an ANOVA test across multiple groups using ---
    group_coefs <- 1:length(levels(group))
    anova_res <- propeller.anova(prop.list=props, design=design, coef = group_coefs, robust=TRUE, trend=FALSE, sort=TRUE)
    write.csv(anova_res, "propeller_anova_results.csv", row.names=TRUE)
    
    # --- Perform a pairwise t-test using propeller.ttest with ---
    if (length(levels(group)) >= 2) {
      # Dynamically create a contrast between the first two groups, using backticks to safely handle any special characters
      contr_str <- paste0("`", colnames(design)[1], "` - `", colnames(design)[2], "`")
      mycontr <- makeContrasts(contrasts = contr_str, levels=design)
      ttest_res <- propeller.ttest(props, design, contrasts = mycontr, robust=TRUE, trend=FALSE, sort=TRUE)
      write.csv(ttest_res, "propeller_ttest_results.csv", row.names=TRUE)
    }
    
    # --- Fit a continuous variable (dose/trend) directly using ---
    if ("dose" %in% colnames(sample_group_map)) {
      dose <- sample_group_map\$dose
      des.dose <- model.matrix(~dose)
      fit <- lmFit(props\$TransformedProps, des.dose)
      fit <- eBayes(fit, robust=TRUE)
      top_dose <- topTable(fit)
      write.csv(top_dose, "limma_continuous_dose_results.csv", row.names=TRUE)
    }
    
    # --- Fit a linear model accounting for random effects using ---
    if ("pair" %in% colnames(sample_group_map)) {
      des.tech <- model.matrix(~group)
      dupcor <- duplicateCorrelation(props\$TransformedProps, design=des.tech, block=pair)
      fit1 <- lmFit(props\$TransformedProps, design=des.tech, block=pair, correlation=dupcor\$consensus)
      fit1 <- eBayes(fit1)
      top_tech <- topTable(fit1, coef=2)
      write.csv(top_tech, "limma_random_effects_results.csv", row.names=TRUE)
    }
    
    # --- Generate and save diagnostic plots ---
    pdf("speckle_diagnostic_plots.pdf", width=10, height=8)
    try({
      print(plotCellTypeProps(sce_all))
    })
    try({
      par(mfrow=c(1,2))
      plotCellTypeMeanVar(props\$Counts)
      plotCellTypePropsMeanVar(props\$Counts)
    })
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cqc_obj <- tryCatch(readRDS(.cqc_rds), error = function(e) NULL)
      .cqc_mat <- if (is.matrix(.cqc_obj) || is.data.frame(.cqc_obj)) .cqc_obj else NULL
      if (!is.null(.cqc_mat) && nrow(.cqc_mat) > 100) {
        .cqc_ncells <- ncol(.cqc_mat); .cqc_nfeats <- nrow(.cqc_mat)
        .cqc_files <- c(.cqc_files, .cqc_rds); break
      }
    }
    .gates_by_label[["cell QC metrics"]] <- list(
      gate_row = "bioc_cell_qc_metrics",
      metric_name = "n_cells",
      metric_value = .cqc_ncells,
      passes = isTRUE(is.finite(.cqc_ncells) && .cqc_ncells >= 50 && .cqc_nfeats >= 200),
      status = if (is.finite(.cqc_ncells)) paste0("computed (cells=", .cqc_ncells, ", features=", .cqc_nfeats, "; proxy gate)")
               else "not_computed (no scRNA matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SPECKLE_CUSTOM_LINEAR_MODELING_AND_ANOVA",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SPECKLE_CUSTOM_LINEAR_MODELING_AND_ANOVA":',
        paste0('    speckle: ', as.character(packageVersion('speckle')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_linear_modeling_and_anova.csv versions.yml
    """
}

workflow BIOC_SPECKLE_CUSTOM_LINEAR_MODELING_AND_ANOVA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce_all ] ]

    main:
    BIOC_SPECKLE_CUSTOM_LINEAR_MODELING_AND_ANOVA(ch_input)

    emit:
    tables   = BIOC_SPECKLE_CUSTOM_LINEAR_MODELING_AND_ANOVA.out.tables
    plots    = BIOC_SPECKLE_CUSTOM_LINEAR_MODELING_AND_ANOVA.out.plots
    objects  = BIOC_SPECKLE_CUSTOM_LINEAR_MODELING_AND_ANOVA.out.objects
    versions = BIOC_SPECKLE_CUSTOM_LINEAR_MODELING_AND_ANOVA.out.versions
}
