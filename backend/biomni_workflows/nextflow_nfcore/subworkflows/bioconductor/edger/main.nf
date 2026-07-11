#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: edgeR — quasi_likelihood_pipeline
// Perform differential expression analysis using the robust quasi-likelihood F-test framework.
// Input: TableOfCounts.txt
// Container: quay.io/biocontainers/bioconductor-edger:4.8.2--r45h01b2380_0
// R packages: edgeR
// Bioconductor: 3.20 | R: 4.4
// Requires: edgeR
// Visualizations: mean-difference plot
// QC: filter low-expression genes
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read count data and define groups
//  * 2. [Input & Preparation] Create DGEList object
//  * 3. [Core Analysis] Filter lowly expressed genes
//  * 4. [Core Analysis] Normalize library sizes
//  * 5. [Input & Preparation] Define design matrix
//  * 6. [Core Analysis] Fit QL GLM model
//  * 7. [Core Analysis] Perform quasi-likelihood F-test
//  * 8. [Core Analysis] Extract top differentially expressed genes

nextflow.enable.dsl = 2

process BIOC_EDGER_QUASI_LIKELIHOOD_PIPELINE {
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
    .bm_deps <- c("edgeR")
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
    
    # Load required library
    library(edgeR)
    
    # 1. Read count data and define groups
    x <- read.delim("TableOfCounts.txt", row.names="Symbol")
    group <- factor(c(1, 1, 2, 2))
    
    # 2. Create DGEList object
    y <- DGEList(counts=x, group=group)
    
    # 3. Filter lowly expressed genes
    keep <- filterByExpr(y)
    y <- y[keep, , keep.lib.sizes=FALSE]
    
    # 4. Normalize library sizes
    y <- normLibSizes(y)
    
    # 5. Define design matrix
    design <- model.matrix(~group)
    
    # 6. Fit QL GLM model
    fit <- glmQLFit(y, design)
    
    # 7. Perform quasi-likelihood F-test
    qlf <- glmQLFTest(fit, coef=2)
    
    # 8. Extract top differentially expressed genes
    top_tags_all <- topTags(qlf, n=Inf)
    
    # Print the default top tags to console as in the documented code
    print(topTags(qlf))
    
    # Write outputs to files
    # Save the complete table of differential expression results
    write.csv(as.data.frame(top_tags_all), file="differential_expression_results.csv", row.names=TRUE)
    
    # Save the QL F-test object as an RDS file for downstream analysis
    saveRDS(qlf, file="qlf_results.rds")
    
    # Generate and save a Mean-Difference (MD) plot
    pdf("md_plot.pdf", width=7, height=7)
    plotMD(qlf)
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # filter low-expression genes — alias of low-count filtering metric
    # (Chen 2016 F1000 edgeR filterByExpr semantics).
    .fleg_kept <- NA_real_; .fleg_files <- character(0)
    for (.fleg_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .fleg_obj <- tryCatch(readRDS(.fleg_rds), error = function(e) NULL)
      .fleg_mat <- if (is.matrix(.fleg_obj) || is.data.frame(.fleg_obj)) .fleg_obj else NULL
      if (!is.null(.fleg_mat) && nrow(.fleg_mat) > 100) {
        .fleg_m <- suppressWarnings(as.matrix(.fleg_mat))
        .fleg_rowmed <- suppressWarnings(apply(.fleg_m, 1, function(r) median(as.numeric(r), na.rm = TRUE)))
        .fleg_kept <- sum(is.finite(.fleg_rowmed) & .fleg_rowmed >= 1) / nrow(.fleg_m)
        .fleg_files <- c(.fleg_files, .fleg_rds); break
      }
    }
    .gates_by_label[["filter low-expression genes"]] <- list(
      gate_row = "bioc_low_count_filtering",
      metric_name = "genes_kept_fraction",
      metric_value = if (is.finite(.fleg_kept)) round(.fleg_kept, 4) else NA_real_,
      passes = isTRUE(is.finite(.fleg_kept) && .fleg_kept >= 0.3 && .fleg_kept <= 0.6),
      status = if (is.finite(.fleg_kept)) paste0("computed (median count >= 1 rows / total)")
               else "not_computed (no expression matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_EDGER_QUASI_LIKELIHOOD_PIPELINE",
      domain  = "bioconductor",
      declared_qc_steps = c("filter low-expression genes"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_EDGER_QUASI_LIKELIHOOD_PIPELINE":',
        paste0('    edgeR: ', as.character(packageVersion('edgeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quasi_likelihood_pipeline.csv versions.yml
    """
}

workflow BIOC_EDGER_QUASI_LIKELIHOOD_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ TableOfCounts.txt ] ]

    main:
    BIOC_EDGER_QUASI_LIKELIHOOD_PIPELINE(ch_input)

    emit:
    tables   = BIOC_EDGER_QUASI_LIKELIHOOD_PIPELINE.out.tables
    plots    = BIOC_EDGER_QUASI_LIKELIHOOD_PIPELINE.out.plots
    objects  = BIOC_EDGER_QUASI_LIKELIHOOD_PIPELINE.out.objects
    versions = BIOC_EDGER_QUASI_LIKELIHOOD_PIPELINE.out.versions
}
