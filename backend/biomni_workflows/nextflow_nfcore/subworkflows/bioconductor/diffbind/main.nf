#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: diffbind — standard_differential_binding
// Perform a standard differential binding analysis comparing two groups using a single-factor design.
// Input: tamoxifen.csv, reads/Chr18_BT474_ER_1.bam, peaks/BT474_ER_1.bed.gz
// Container: quay.io/biocontainers/bioconductor-diffbind:3.20.0--r45ha27e39d_0
// R packages: DiffBind, magrittr, xtable
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: MA plot, PCA plot, volcano plot
// QC: diagnostic MA/PCA QC

nextflow.enable.dsl = 2

process BIOC_DIFFBIND_STANDARD_DIFFERENTIAL_BINDING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-diffbind:3.20.0--r45ha27e39d_0"

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
    .bm_deps <- c("DiffBind", "magrittr", "xtable")
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
    library(DiffBind)
    library(magrittr)
    
    # Execute the standard differential binding workflow exactly as documented
    tamoxifen <- dba(sampleSheet="tamoxifen.csv") %>%
      dba.blacklist() %>%
      dba.count()     %>%
      dba.normalize() %>%
      dba.contrast()  %>%
      dba.analyze()
    
    # Retrieve the report of differentially bound sites
    tamoxifen.DB <- dba.report(tamoxifen)
    
    # Save the results to output files
    # --- Save the complete DBA object ---
    saveRDS(tamoxifen, file="tamoxifen_dba_object.rds")
    
    # --- Save the differential binding report as a CSV ---
    if (!is.null(tamoxifen.DB) && length(tamoxifen.DB) > 0) {
      write.csv(as.data.frame(tamoxifen.DB), file="tamoxifen_differential_binding_report.csv", row.names=FALSE)
    } else {
      write.csv(data.frame(Message="No significantly differentially bound sites found."), file="tamoxifen_differential_binding_report.csv", row.names=FALSE)
    }
    
    # --- Generate diagnostic and results plots ---
    pdf("tamoxifen_differential_binding_plots.pdf", width=8, height=8)
    
    tryCatch({
      plot(tamoxifen)
    }, error=function(e) {
      message("Could not generate correlation heatmap: ", e\$message)
    })
    
    tryCatch({
      dba.plotPCA(tamoxifen, label=DBA_CONDITION)
    }, error=function(e) {
      message("Could not generate PCA plot: ", e\$message)
    })
    
    tryCatch({
      dba.plotMA(tamoxifen)
    }, error=function(e) {
      message("Could not generate MA plot: ", e\$message)
    })
    
    tryCatch({
      dba.plotVolcano(tamoxifen)
    }, error=function(e) {
      message("Could not generate Volcano plot: ", e\$message)
    })
    
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # diagnostic MA/PCA QC — PC1 variance explained on any large matrix.
    # Pass when PC1 > 10% (Risso 2014 RUV-seq diagnostic).
    .pca_pc1 <- NA_real_; .pca_files <- character(0)
    for (.pca_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_DIFFBIND_STANDARD_DIFFERENTIAL_BINDING",
      domain  = "bioconductor",
      declared_qc_steps = c("diagnostic MA/PCA QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DIFFBIND_STANDARD_DIFFERENTIAL_BINDING":',
        paste0('        diffbind: ', as.character(packageVersion("diffbind")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_differential_binding.csv versions.yml
    """
}

workflow BIOC_DIFFBIND_STANDARD_DIFFERENTIAL_BINDING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tamoxifen.csv, reads/Chr18_BT474_ER_1.bam, peaks/BT474_ER_1.bed.gz ] ]

    main:
    BIOC_DIFFBIND_STANDARD_DIFFERENTIAL_BINDING(ch_input)

    emit:
    tables   = BIOC_DIFFBIND_STANDARD_DIFFERENTIAL_BINDING.out.tables
    plots    = BIOC_DIFFBIND_STANDARD_DIFFERENTIAL_BINDING.out.plots
    objects  = BIOC_DIFFBIND_STANDARD_DIFFERENTIAL_BINDING.out.objects
    versions = BIOC_DIFFBIND_STANDARD_DIFFERENTIAL_BINDING.out.versions
}
