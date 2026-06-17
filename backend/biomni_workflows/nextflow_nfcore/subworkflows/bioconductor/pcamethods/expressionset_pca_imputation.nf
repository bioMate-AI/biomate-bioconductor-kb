#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pcaMethods — expressionset_pca_imputation
// Perform PCA and impute missing values directly on a Bioconductor ExpressionSet object.
// Input: sample.ExpressionSet
// Container: quay.io/biocontainers/bioconductor-pcamethods:2.2.0--r45ha27e39d_0
// R packages: Biobase, pcaMethods
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, pcaMethods
// Visualizations: PCA plot
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Introduce missing values to the ExpressionSet
//  * 2. [Core Analysis] Run PCA on the ExpressionSet
//  * 3. [Core Analysis] Convert the PCA result back to an imputed ExpressionSet using asExprSet

nextflow.enable.dsl = 2

process BIOC_PCAMETHODS_EXPRESSIONSET_PCA_IMPUTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("Biobase", "pcaMethods")
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
    library(pcaMethods)
    library(Biobase)
    
    # 1. Read the user input file (ExpressionSet object)
    # The pipeline expects "sample.ExpressionSet" in the working directory.
    exSet <- readRDS("sample.ExpressionSet")
    
    # 2. Introduce missing values to the ExpressionSet
    exSetNa <- exSet
    total_elements <- length(exprs(exSetNa))
    # We dynamically determine the number of NAs to introduce based on the dataset size,
    # mimicking the vignette's introduction of missing values.
    num_to_na <- min(200, as.integer(total_elements * 0.05))
    set.seed(123) # Ensure reproducibility of the NA mask
    exprs(exSetNa)[sample(total_elements, num_to_na)] <- NA
    lost <- is.na(exprs(exSetNa))
    
    # 3. Run PCA on the ExpressionSet
    pc <- pca(exSetNa, nPcs=2, method="ppca")
    
    # 4. Convert the PCA result back to an imputed ExpressionSet using asExprSet
    impExSet <- asExprSet(pc, exSetNa)
    
    # 5. Write named output files
    # Save the imputed ExpressionSet object
    saveRDS(impExSet, "imputed_ExpressionSet.rds")
    
    # Save the PCA result object
    saveRDS(pc, "pca_result.rds")
    
    # Save the imputed expression matrix as a CSV
    write.csv(exprs(impExSet), "imputed_expression_matrix.csv", row.names = TRUE)
    
    # Save a PDF plot of the PCA scores
    pdf("pca_scores_plot.pdf")
    plotPcs(pc, pc=1:2, type="score")
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_PCAMETHODS_EXPRESSIONSET_PCA_IMPUTATION",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_PCAMETHODS_EXPRESSIONSET_PCA_IMPUTATION":',
        paste0('    pcaMethods: ', as.character(packageVersion('pcaMethods')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_expressionset_pca_imputation.csv versions.yml
    """
}

workflow BIOC_PCAMETHODS_EXPRESSIONSET_PCA_IMPUTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.ExpressionSet ] ]

    main:
    BIOC_PCAMETHODS_EXPRESSIONSET_PCA_IMPUTATION(ch_input)

    emit:
    tables   = BIOC_PCAMETHODS_EXPRESSIONSET_PCA_IMPUTATION.out.tables
    plots    = BIOC_PCAMETHODS_EXPRESSIONSET_PCA_IMPUTATION.out.plots
    objects  = BIOC_PCAMETHODS_EXPRESSIONSET_PCA_IMPUTATION.out.objects
    versions = BIOC_PCAMETHODS_EXPRESSIONSET_PCA_IMPUTATION.out.versions
}
