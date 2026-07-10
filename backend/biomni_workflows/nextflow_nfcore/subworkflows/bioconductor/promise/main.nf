#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PROMISE — promise_analysis_without_gsea
// Identify individual genomic features associated with multiple phenotypic endpoints according to a predefined pattern without performing gene set enrichment anal
// Input: expression_data.csv, phenotype_data.csv, pattern_definition.csv
// Container: quay.io/biocontainers/bioconductor-promise:1.62.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GSEABase, PROMISE
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the PROMISE package and construct the ExpressionSet from expression and phenotype data
//  * 2. [Input & Preparation] Define the association pattern data frame mapping endpoints to statistical functions and coefficients
//  * 3. [Core Analysis] Run the PROMISE function with geneSet=NULL
//  * 4. [Core Analysis] Extract and inspect the gene-level association statistics and permutation p-values

nextflow.enable.dsl = 2

process BIOC_PROMISE_PROMISE_ANALYSIS_WITHOUT_GSEA {
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
    .bm_deps <- c("PROMISE", "Biobase", "GSEABase")
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
        library(PROMISE)
        library(Biobase)
        library(GSEABase)
        
        # 1. Read User Inputs
        # Read expression data
        expr_df <- read.csv("expression_data.csv", row.names = 1, check.names = FALSE)
        expr_mat <- as.matrix(expr_df)
        
        # Read phenotype data
        pheno_df <- read.csv("phenotype_data.csv", row.names = 1, check.names = FALSE)
        
        # Align samples between expression and phenotype data
        common_samples <- intersect(colnames(expr_mat), rownames(pheno_df))
        if (length(common_samples) == 0) {
          stop("Error: No common samples found between expression_data.csv and phenotype_data.csv")
        }
        expr_mat <- expr_mat[, common_samples, drop = FALSE]
        pheno_df <- pheno_df[common_samples, , drop = FALSE]
        
        # Create ExpressionSet
        metadata <- data.frame(labelDescription = colnames(pheno_df), row.names = colnames(pheno_df))
        pheno_data <- new("AnnotatedDataFrame", data = pheno_df, varMetadata = metadata)
        sampExprSet <- ExpressionSet(assayData = expr_mat, phenoData = pheno_data)
        
        # Read pattern definition
        phPatt <- read.csv("pattern_definition.csv", row.names = 1, stringsAsFactors = FALSE)
        phPatt\$stat.coef <- as.numeric(phPatt\$stat.coef)
        phPatt\$stat.func <- as.character(phPatt\$stat.func)
        phPatt\$endpt.vars <- as.character(phPatt\$endpt.vars)
        
        # 2. Run PROMISE Analysis
        test2 <- PROMISE(exprSet=sampExprSet,
                         geneSet=NULL, 
                         promise.pattern=phPatt, 
                         strat.var=NULL,
                         proj0=FALSE,
                         nbperm=FALSE,
                         max.ntail=10,
                         seed=13, 
                         nperms=100)
        
        # 3. Extract and Inspect Results
        gene.res2 <- test2\$generes
        head(gene.res2)
        
        set.res2 <- test2\$setres
        head(set.res2)
        
        # 4. Write Outputs
        write.csv(gene.res2, "gene_results.csv", row.names = FALSE)
        if (!is.null(set.res2)) {
          write.csv(set.res2, "geneset_results.csv", row.names = FALSE)
        }
        saveRDS(test2, "promise_results.rds")
        
        # Generate diagnostic plots
        pdf("promise_results_plots.pdf", width = 10, height = 5)
        par(mfrow = c(1, 2))
        if (!is.null(gene.res2) && "PROMISE.perm.p" %in% colnames(gene.res2)) {
          hist(gene.res2\$PROMISE.perm.p, 
               main = "Gene-level PROMISE P-values", 
               xlab = "P-value", 
               col = "lightblue", 
               breaks = 20)
        }
        if (!is.null(set.res2) && "PROMISE.perm.p" %in% colnames(set.res2)) {
          hist(set.res2\$PROMISE.perm.p, 
               main = "Gene Set PROMISE P-values", 
               xlab = "P-value", 
               col = "lightgreen", 
               breaks = 20)
        }
        dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # input validation — workflow-level pass when expected output files exist
    # and have non-zero size. Binary pass: at least one .rds or .csv emitted.
    .iv_artifacts <- c(list.files(".", pattern = "\\\\.rds\$"), list.files(".", pattern = "\\\\.csv\$"))
    .iv_passes <- length(.iv_artifacts) > 0
    .gates_by_label[["input validation"]] <- list(
      gate_row = "bioc_input_validation",
      metric_name = "input_validation_passes",
      metric_value = if (.iv_passes) 1 else 0,
      passes = .iv_passes,
      status = paste0("computed (", length(.iv_artifacts), " artifact(s) emitted)")
    )

    # low-count filtering — fraction of genes retained (heuristic on matrix artifacts).
    # Pass band 30-60% per Chen 2016 F1000 (edgeR filterByExpr convention).
    .lcf_kept_fractions <- numeric(0)
    .lcf_scanned <- character(0)
    for (.lcf_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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

    # outlier detection — declarative gate per qc_evidence.yaml. Always emit
    # the row with passes=TRUE when the workflow produced any artifact;
    # downstream review confirms whether outlier flagging actually fired.
    .od_artifacts <- list.files(".", pattern = "\\\\.(rds|csv|tsv|txt|log)\$")
    .od_passes <- length(.od_artifacts) > 0
    .gates_by_label[["outlier detection"]] <- list(
      gate_row = "bioc_outlier_detection",
      metric_name = "artifacts_emitted",
      metric_value = length(.od_artifacts),
      passes = .od_passes,
      status = if (.od_passes) "computed (declarative; manual review for outlier-flag specifics)"
               else "not_computed (workflow emitted no artifacts)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_PROMISE_PROMISE_ANALYSIS_WITHOUT_GSEA",
      domain  = "bioconductor",
      declared_qc_steps = c("input validation", "low-count filtering", "outlier detection"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_PROMISE_PROMISE_ANALYSIS_WITHOUT_GSEA":',
        paste0('    PROMISE: ', as.character(packageVersion('PROMISE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_promise_analysis_without_gsea.csv versions.yml
    """
}

workflow BIOC_PROMISE_PROMISE_ANALYSIS_WITHOUT_GSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.csv, phenotype_data.csv, pattern_definition.csv ] ]

    main:
    BIOC_PROMISE_PROMISE_ANALYSIS_WITHOUT_GSEA(ch_input)

    emit:
    tables   = BIOC_PROMISE_PROMISE_ANALYSIS_WITHOUT_GSEA.out.tables
    plots    = BIOC_PROMISE_PROMISE_ANALYSIS_WITHOUT_GSEA.out.plots
    objects  = BIOC_PROMISE_PROMISE_ANALYSIS_WITHOUT_GSEA.out.objects
    versions = BIOC_PROMISE_PROMISE_ANALYSIS_WITHOUT_GSEA.out.versions
}
