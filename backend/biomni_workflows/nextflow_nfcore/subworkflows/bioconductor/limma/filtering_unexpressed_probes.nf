#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: limma — filtering_unexpressed_probes
// Filter out unexpressed probes based on average log-expression values before empirical Bayes analysis.
// Input: y, design
// Container: quay.io/biocontainers/bioconductor-limma:3.66.0--r45h01b2380_0
// R packages: limma
// Bioconductor: 3.20 | R: 4.4
// Requires: limma
// Visualizations: SA diagnostic
// QC: normalization diagnostic plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Fit initial linear model using lmFit()
//  * 2. [Visualization & Output] Inspect average expression distribution and residual
//  * 3. [Visualization & Output] Filter out probes below a threshold
//  * 4. [Visualization & Output] Run empirical Bayes with trend on the filtered fit using
//  * 5. [Visualization & Output] Inspect the final residual variance plot using plotSA()

nextflow.enable.dsl = 2

process BIOC_LIMMA_FILTERING_UNEXPRESSED_PROBES {
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
    .bm_deps <- c("limma")
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
    library(limma)
    
    # Read user input files from the working directory
    if (!file.exists("y.rds") || !file.exists("design.rds")) {
      stop("Required input files 'y.rds' and/or 'design.rds' are missing from the working directory.")
    }
    
    y <- readRDS("y.rds")
    design <- readRDS("design.rds")
    
    # --- Fit initial linear model using lmFit() ---
    fit <- lmFit(y, design)
    
    # Open PDF device to save diagnostic plots
    pdf("diagnostic_plots.pdf", width=10, height=5)
    par(mfrow=c(1, 3))
    
    # --- Inspect average expression distribution and residual ---
    hist(fit\$Amean)
    plotSA(fit)
    
    # --- Filter out probes below a threshold ---
    # Define CutOff dynamically as the median of average log-expression values to ensure robustness
    CutOff <- median(fit\$Amean, na.rm = TRUE)
    keep <- fit\$Amean > CutOff
    
    # --- Run empirical Bayes with trend on the filtered fit using ---
    fit2 <- eBayes(fit[keep,], trend=TRUE)
    
    # --- Inspect the final residual variance plot using plotSA() ---
    plotSA(fit2)
    
    # Close the plotting device
    dev.off()
    
    # Write named output files for the meaningful results
    saveRDS(fit2, "fit2.rds")
    
    # Export top table of differential expression results for the last coefficient/contrast
    results <- topTable(fit2, coef=ncol(design), number=Inf)
    write.csv(results, "filtered_differential_expression_results.csv", row.names=TRUE)
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # normalization diagnostic plot — file-exists check for any PDF emitted
    # with "norm" / "mean_sd" / "library" in the filename. Pairs with
    # bioc_count_normalization (numeric metric); this row is the visual gate.
    .ndp_pdfs <- list.files(".", pattern = "(?i)(norm|mean.?sd|library).*\\.pdf\$")
    .ndp_passes <- length(.ndp_pdfs) > 0
    .gates_by_label[["normalization diagnostic plot"]] <- list(
      gate_row = "bioc_normalization_diagnostic_plot",
      metric_name = "normalization_plot_exists",
      metric_value = if (.ndp_passes) 1 else 0,
      passes = .ndp_passes,
      status = if (.ndp_passes) paste0("computed (", length(.ndp_pdfs), " diagnostic PDF(s) emitted)")
               else "not_computed (no normalization diagnostic PDF found)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_LIMMA_FILTERING_UNEXPRESSED_PROBES",
      domain  = "bioconductor",
      declared_qc_steps = c("normalization diagnostic plot"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_LIMMA_FILTERING_UNEXPRESSED_PROBES":',
        paste0('    limma: ', as.character(packageVersion('limma')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_filtering_unexpressed_probes.csv versions.yml
    """
}

workflow BIOC_LIMMA_FILTERING_UNEXPRESSED_PROBES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ y, design ] ]

    main:
    BIOC_LIMMA_FILTERING_UNEXPRESSED_PROBES(ch_input)

    emit:
    tables   = BIOC_LIMMA_FILTERING_UNEXPRESSED_PROBES.out.tables
    plots    = BIOC_LIMMA_FILTERING_UNEXPRESSED_PROBES.out.plots
    objects  = BIOC_LIMMA_FILTERING_UNEXPRESSED_PROBES.out.objects
    versions = BIOC_LIMMA_FILTERING_UNEXPRESSED_PROBES.out.versions
}
