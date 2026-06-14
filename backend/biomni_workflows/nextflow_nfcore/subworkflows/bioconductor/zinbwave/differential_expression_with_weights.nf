#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: zinbwave — differential_expression_with_weights
// Compute observational weights using ZINB-WaVE and perform differential expression analysis on single-cell data using edgeR or DESeq2.
// Input: SummarizedExperiment_object.rds
// Container: quay.io/biocontainers/bioconductor-zinbwave:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, DESeq2, SummarizedExperiment, edgeR, zinbwave
// QC: TMM normalization, dispersion/size-factor estimation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Load User Input
//  * 2. [Core Analysis] Fit the ZINB model and compute weights
//  * 3. [Core Analysis] Differential expression with edgeR
//  * 4. [Core Analysis] Differential expression with DESeq2

nextflow.enable.dsl = 2

process BIOC_ZINBWAVE_DIFFERENTIAL_EXPRESSION_WITH_WEIGHTS {
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
    .bm_deps <- c("zinbwave", "BiocParallel", "edgeR", "DESeq2", "SummarizedExperiment")
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
          library(SummarizedExperiment)
      library(zinbwave)
        library(BiocParallel)
        library(edgeR)
        library(DESeq2)
        
        # Register BiocParallel Serial Execution for stability
        BiocParallel::register(BiocParallel::SerialParam())
        
        # --- Load User Input ---
        # The pipeline reads EXACTLY the declared input file from the working directory
        if (!file.exists("SummarizedExperiment_object.rds")) {
          stop("Error: 'SummarizedExperiment_object.rds' not found in the working directory.")
        }
        
        fluidigm <- readRDS("SummarizedExperiment_object.rds")
        
        # Ensure the first assay is named "counts" as expected by the workflow
        if (!"counts" %in% assayNames(fluidigm)) {
          assayNames(fluidigm)[1] <- "counts"
        }
        
        # --- Fit the ZINB model and compute weights ---
        # Keep every documented function call and its argument names EXACTLY as shown
        zinb <- zinbFit(fluidigm, K=2, epsilon=1000)
        fluidigm_zinb <- zinbwave(fluidigm, fitted_model = zinb, K = 2, epsilon=1000, observationalWeights = TRUE)
        weights <- assay(fluidigm_zinb, "weights")
        
        # Save computed weights and the zinbwave object
        saveRDS(weights, "zinbwave_observational_weights.rds")
        saveRDS(fluidigm_zinb, "fluidigm_zinb_output.rds")
        
        # --- Differential expression with edgeR ---
        dge <- DGEList(assay(fluidigm_zinb))
        dge <- calcNormFactors(dge)
        
        # Determine the condition column to use for the design matrix dynamically
        condition_col <- NULL
        if ("Biological_Condition" %in% colnames(colData(fluidigm))) {
          condition_col <- "Biological_Condition"
        } else {
          for (col in colnames(colData(fluidigm))) {
            if (length(unique(colData(fluidigm)[[col]])) >= 2) {
              condition_col <- col
              break
            }
          }
          if (is.null(condition_col) && ncol(colData(fluidigm)) > 0) {
            condition_col <- colnames(colData(fluidigm))[1]
          }
        }
        
        if (is.null(condition_col)) {
          stop("No metadata columns available in colData for differential expression.")
        }
        
        design_formula <- as.formula(paste("~", condition_col))
        design <- model.matrix(design_formula, data = colData(fluidigm))
        
        dge\$weights <- weights
        dge <- estimateDisp(dge, design)
        fit <- glmFit(dge, design)
        
        # Use the moderated F-test (glmWeightedF)
        # Note: coef = 3 is used as in the documented vignette code. Adjust if design matrix differs.
        coef_to_test <- min(3, ncol(design))
        lrt <- glmWeightedF(fit, coef = coef_to_test)
        edgeR_results <- topTags(lrt, n = Inf)
        
        # Save edgeR results
        write.csv(as.data.frame(edgeR_results), "edgeR_weighted_DE_results.csv", row.names = TRUE)
        
        # --- Differential expression with DESeq2 ---
        counts(fluidigm_zinb) <- as.matrix(counts(fluidigm_zinb))
        dds <- DESeqDataSet(fluidigm_zinb, design = design_formula)
        dds <- DESeq(dds, sfType="poscounts", useT=TRUE, minmu=1e-6)
        
        # Determine contrast levels dynamically based on the selected condition column to avoid out-of-bounds errors,
        # but fallback to the documented contrast if those levels exist.
        levels_present <- levels(as.factor(colData(fluidigm)[[condition_col]]))
        if ("NPC" %in% levels_present && "GW16" %in% levels_present) {
          contrast_spec <- c(condition_col, "NPC", "GW16")
        } else if (length(levels_present) >= 2) {
          contrast_spec <- c(condition_col, levels_present[1], levels_present[2])
        } else {
          contrast_spec <- NULL
        }
        
        if (!is.null(contrast_spec)) {
          res <- lfcShrink(dds, contrast=contrast_spec, type = "normal")
          # Save DESeq2 results
          write.csv(as.data.frame(res), "DESeq2_weighted_DE_results.csv", row.names = TRUE)
        } else {
          warning(paste("Not enough levels in", condition_col, "to perform DESeq2 contrast shrinkage."))
        }

    writeLines(c(
        '"BIOC_ZINBWAVE_DIFFERENTIAL_EXPRESSION_WITH_WEIGHTS":',
        paste0('    zinbwave: ', as.character(packageVersion('zinbwave')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_expression_with_weights.csv versions.yml
    """
}

workflow BIOC_ZINBWAVE_DIFFERENTIAL_EXPRESSION_WITH_WEIGHTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SummarizedExperiment_object.rds ] ]

    main:
    BIOC_ZINBWAVE_DIFFERENTIAL_EXPRESSION_WITH_WEIGHTS(ch_input)

    emit:
    tables   = BIOC_ZINBWAVE_DIFFERENTIAL_EXPRESSION_WITH_WEIGHTS.out.tables
    plots    = BIOC_ZINBWAVE_DIFFERENTIAL_EXPRESSION_WITH_WEIGHTS.out.plots
    objects  = BIOC_ZINBWAVE_DIFFERENTIAL_EXPRESSION_WITH_WEIGHTS.out.objects
    versions = BIOC_ZINBWAVE_DIFFERENTIAL_EXPRESSION_WITH_WEIGHTS.out.versions
}
