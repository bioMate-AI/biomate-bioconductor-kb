#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: topconfects — limma_confects
// Rank genes by confident fold change from a limma linear model fit.
// Input: y, design
// Container: quay.io/biocontainers/bioconductor-topconfects:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, edgeR, ggplot2, limma, topconfects
// Visualizations: plot (ggplot/base)
// QC: voom mean-variance modelling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit linear model using voom and lmFit
//  * 2. [Core Analysis] Calculate confident effect sizes using limma_confects
//  * 3. [Visualization & Output] Visualize results using confects_plot and confects_plot_me2

nextflow.enable.dsl = 2

process BIOC_TOPCONFECTS_LIMMA_CONFECTS {
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
    .bm_deps <- c("limma", "edgeR", "topconfects", "dplyr", "ggplot2")
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
    library(limma)
    library(edgeR)
    library(topconfects)
    library(dplyr)
    library(ggplot2)
    
    # Read user input files from the working directory
    if (file.exists("y.rds")) {
      y <- readRDS("y.rds")
    } else if (file.exists("y")) {
      y <- readRDS("y")
    } else {
      stop("Error: Input file 'y' or 'y.rds' (DGEList) not found in the working directory.")
    }
    
    if (file.exists("design.rds")) {
      design <- readRDS("design.rds")
    } else if (file.exists("design")) {
      design <- readRDS("design")
    } else {
      stop("Error: Input file 'design' or 'design.rds' (model matrix) not found in the working directory.")
    }
    
    # 1. Fit linear model using voom and lmFit
    fit <-
        voom(y, design) %>%
        lmFit(design)
    
    # 2. Calculate confident effect sizes using limma_confects
    confects <- limma_confects(fit, coef=ncol(design), fdr=0.05)
    
    # Save tabular results
    write.csv(confects\$table, "confects_table.csv", row.names = FALSE)
    saveRDS(confects, "confects.rds")
    
    # 3. Visualize results using confects_plot and confects_plot_me2
    pdf("confects_plot.pdf", width = 7, height = 7)
    p1 <- confects_plot(confects)
    print(p1)
    dev.off()
    
    pdf("confects_plot_me2.pdf", width = 7, height = 6)
    p2 <- confects_plot_me2(confects, breaks=c(0,1,2))
    print(p2)
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # voom — limma EList\$weights present, range > 0 (Law 2014 GB).
    .voom_w_range <- NA_real_
    for (.voom_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .voom_obj <- tryCatch(readRDS(.voom_rds), error = function(e) NULL)
      if (!is.null(.voom_obj) && inherits(.voom_obj, "EList")) {
        .voom_w <- tryCatch(.voom_obj\$weights, error = function(e) NULL)
        if (!is.null(.voom_w) && length(.voom_w) > 0) {
          .voom_w_range <- round(diff(range(.voom_w, na.rm = TRUE)), 4); break
        }
      }
    }
    .gates_by_label[["voom mean-variance modelling"]] <- list(
      gate_row = "bioc_voom_mean_variance",
      metric_name = "voom_weight_range",
      metric_value = .voom_w_range,
      passes = isTRUE(is.finite(.voom_w_range) && .voom_w_range > 0),
      status = if (is.finite(.voom_w_range)) "computed (EList\$weights range)"
               else "not_computed (no limma EList .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_TOPCONFECTS_LIMMA_CONFECTS",
      domain  = "bioconductor",
      declared_qc_steps = c("voom mean-variance modelling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_TOPCONFECTS_LIMMA_CONFECTS":',
        paste0('    topconfects: ', as.character(packageVersion('topconfects')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_limma_confects.csv versions.yml
    """
}

workflow BIOC_TOPCONFECTS_LIMMA_CONFECTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ y, design ] ]

    main:
    BIOC_TOPCONFECTS_LIMMA_CONFECTS(ch_input)

    emit:
    tables   = BIOC_TOPCONFECTS_LIMMA_CONFECTS.out.tables
    plots    = BIOC_TOPCONFECTS_LIMMA_CONFECTS.out.plots
    objects  = BIOC_TOPCONFECTS_LIMMA_CONFECTS.out.objects
    versions = BIOC_TOPCONFECTS_LIMMA_CONFECTS.out.versions
}
