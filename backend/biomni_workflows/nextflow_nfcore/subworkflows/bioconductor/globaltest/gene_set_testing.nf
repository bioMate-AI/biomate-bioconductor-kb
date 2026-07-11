#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: globaltest — gene_set_testing
// Test the association of biological pathways (KEGG/GO) with a phenotype using transcriptomic expression data.
// Input: Golub_Train
// Container: quay.io/biocontainers/bioconductor-globaltest:5.64.0--r45hdfd78af_0
// R packages: globaltest, hu6800.db, vsn
// Bioconductor: 3.20 | R: 4.4
// Requires: globaltest, hu6800.db, vsn
// Visualizations: plot (ggplot/base)
// QC: variance-stabilizing normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Normalize expression data
//  * 2. [Core Analysis] Run pathway-specific global tests using gtKEGG() or gtGO()
//  * 3. [Visualization & Output] Extract and plot gene-level features using features()

nextflow.enable.dsl = 2

process BIOC_GLOBALTEST_GENE_SET_TESTING {
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
    .bm_deps <- c("globaltest", "hu6800.db", "vsn")
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
    library(globaltest)
    library(vsn)
    library(hu6800.db)
    
    # 1. Read the user input ExpressionSet object from the working directory
    Golub_Train <- readRDS("Golub_Train")
    
    # 2. Normalize expression data using vsn
    exprs(Golub_Train) <- exprs(vsn2(Golub_Train))
    
    # 3. Run overall global test
    gt_overall <- gt(ALL.AML, Golub_Train)
    
    # Save overall test results
    write.csv(result(gt_overall), "gt_overall_results.csv", row.names = FALSE)
    saveRDS(gt_overall, "gt_overall.rds")
    
    # 4. Run pathway-specific global tests using gtKEGG
    gtKEGG(ALL.AML, Golub_Train, id = "04110")
    res <- gtKEGG(ALL.AML, Golub_Train, id = "04110")
    
    # Save KEGG test results
    write.csv(result(res), "gt_kegg_04110_results.csv", row.names = FALSE)
    saveRDS(res, "gt_kegg_04110.rds")
    
    # 5. Extract and plot gene-level features using features()
    pdf("features_plot.pdf", width = 10, height = 8)
    features(res, alias = hu6800SYMBOL)
    dev.off()
    
    # Extract features without plotting to save as a CSV table
    ft_data <- features(res, alias = hu6800SYMBOL, plot = FALSE)
    extracted_features <- extract(ft_data)
    write.csv(as.data.frame(extracted_features), "extracted_features.csv", row.names = TRUE)
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # VSN — DESeqTransform / vsd matrix; mean-SD slope ≤ 0.5 (vsn::meanSdPlot).
    .vsn_slope <- NA_real_
    for (.vsn_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .vsn_obj <- tryCatch(readRDS(.vsn_rds), error = function(e) NULL)
      .vsn_mat <- NULL
      if (!is.null(.vsn_obj)) {
        if (inherits(.vsn_obj, "DESeqTransform") || inherits(.vsn_obj, "SummarizedExperiment")) {
          .vsn_mat <- tryCatch(assay(.vsn_obj), error = function(e) NULL)
        } else if (is.matrix(.vsn_obj)) { .vsn_mat <- .vsn_obj }
      }
      if (!is.null(.vsn_mat) && nrow(.vsn_mat) > 100) {
        .vsn_rmean <- suppressWarnings(rowMeans(.vsn_mat, na.rm = TRUE))
        .vsn_rsd <- suppressWarnings(apply(.vsn_mat, 1, sd, na.rm = TRUE))
        .vsn_ok <- is.finite(.vsn_rmean) & is.finite(.vsn_rsd)
        if (sum(.vsn_ok) > 50) {
          .vsn_fit <- tryCatch(lm(.vsn_rsd[.vsn_ok] ~ .vsn_rmean[.vsn_ok]), error = function(e) NULL)
          if (!is.null(.vsn_fit)) { .vsn_slope <- round(abs(coef(.vsn_fit)[2]), 4); break }
        }
      }
    }
    .gates_by_label[["variance-stabilizing normalization"]] <- list(
      gate_row = "bioc_vsn_normalization",
      metric_name = "mean_sd_slope_after_vsn",
      metric_value = .vsn_slope,
      passes = isTRUE(is.finite(.vsn_slope) && .vsn_slope <= 0.5),
      status = if (is.finite(.vsn_slope)) "computed (lm slope row-SD ~ row-mean)"
               else "not_computed (no DESeqTransform/vsd .rds present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_GLOBALTEST_GENE_SET_TESTING",
      domain  = "bioconductor",
      declared_qc_steps = c("variance-stabilizing normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_GLOBALTEST_GENE_SET_TESTING":',
        paste0('    globaltest: ', as.character(packageVersion('globaltest')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_set_testing.csv versions.yml
    """
}

workflow BIOC_GLOBALTEST_GENE_SET_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Golub_Train ] ]

    main:
    BIOC_GLOBALTEST_GENE_SET_TESTING(ch_input)

    emit:
    tables   = BIOC_GLOBALTEST_GENE_SET_TESTING.out.tables
    plots    = BIOC_GLOBALTEST_GENE_SET_TESTING.out.plots
    objects  = BIOC_GLOBALTEST_GENE_SET_TESTING.out.objects
    versions = BIOC_GLOBALTEST_GENE_SET_TESTING.out.versions
}
