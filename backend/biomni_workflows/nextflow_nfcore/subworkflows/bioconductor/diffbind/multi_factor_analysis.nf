#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DiffBind — multi_factor_analysis
// Perform differential binding analysis incorporating multiple metadata factors (e.g., pairing or batch effects) in the design matrix.
// Input: tamoxifen.csv, BAM files, BED/Peak files
// Container: quay.io/biocontainers/bioconductor-diffbind:3.20.0--r45ha27e39d_0
// R packages: DiffBind
// Bioconductor: 3.20 | R: 4.4
// Requires: DiffBind
// Visualizations: MA plot, PCA plot, volcano plot
// QC: diagnostic MA/PCA QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and count reads
//  * 2. [Input & Preparation] Set up multi-factor design formula using dba.contrast
//  * 3. [Core Analysis] Run differential analysis using dba.analyze
//  * 4. [Visualization & Output] Retrieve multi-factor report using dba.report

nextflow.enable.dsl = 2

process BIOC_DIFFBIND_MULTI_FACTOR_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("DiffBind")
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
    
    # ==========================================
    # STAGE 1: Load and count reads
    # ==========================================
    # Read the user-provided sample sheet and construct the DBA object
    tamoxifen <- dba(sampleSheet = "tamoxifen.csv")
    
    # Count reads overlapping the consensus peakset
    tamoxifen <- dba.count(tamoxifen)
    
    # ==========================================
    # STAGE 2: Set up multi-factor design formula
    # ==========================================
    # Reproducing documented code exactly:
    tamoxifen <- dba.contrast(tamoxifen,design="~Tissue + Condition")
    
    # ==========================================
    # STAGE 3: Run differential analysis
    # ==========================================
    # Reproducing documented code exactly:
    tamoxifen <- dba.analyze(tamoxifen)
    
    # ==========================================
    # STAGE 4: Retrieve multi-factor report
    # ==========================================
    # Reproducing documented code exactly:
    multifactor.DB <- dba.report(tamoxifen)
    
    # ==========================================
    # STAGE 5: Write outputs
    # ==========================================
    # Save the differential binding report as a CSV file
    if (!is.null(multifactor.DB) && length(multifactor.DB) > 0) {
      write.csv(as.data.frame(multifactor.DB), file = "multifactor_report.csv", row.names = FALSE)
    } else {
      # Create an empty file or write a message if no DB sites are found
      write.csv(data.frame(Message = "No significantly differentially bound sites found."), 
                file = "multifactor_report.csv", row.names = FALSE)
    }
    
    # Save the complete analyzed DBA object as an RDS file
    saveRDS(tamoxifen, file = "tamoxifen_analyzed.rds")
    
    # Generate diagnostic and results plots
    pdf("diffbind_plots.pdf", width = 8, height = 8)
    
    # 1. Correlation Heatmap
    tryCatch({
      plot(tamoxifen)
    }, error = function(e) {
      warning("Could not generate correlation heatmap: ", e\$message)
    })
    
    # 2. PCA Plot
    tryCatch({
      dba.plotPCA(tamoxifen, contrast = 1)
    }, error = function(e) {
      warning("Could not generate PCA plot: ", e\$message)
    })
    
    # 3. MA Plot
    tryCatch({
      dba.plotMA(tamoxifen, contrast = 1)
    }, error = function(e) {
      warning("Could not generate MA plot: ", e\$message)
    })
    
    # 4. Volcano Plot
    tryCatch({
      dba.plotVolcano(tamoxifen, contrast = 1)
    }, error = function(e) {
      warning("Could not generate Volcano plot: ", e\$message)
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
      process = "BIOC_DIFFBIND_MULTI_FACTOR_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("diagnostic MA/PCA QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DIFFBIND_MULTI_FACTOR_ANALYSIS":',
        paste0('    DiffBind: ', as.character(packageVersion('DiffBind')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_factor_analysis.csv versions.yml
    """
}

workflow BIOC_DIFFBIND_MULTI_FACTOR_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tamoxifen.csv, BAM files, BED/Peak files ] ]

    main:
    BIOC_DIFFBIND_MULTI_FACTOR_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DIFFBIND_MULTI_FACTOR_ANALYSIS.out.tables
    plots    = BIOC_DIFFBIND_MULTI_FACTOR_ANALYSIS.out.plots
    objects  = BIOC_DIFFBIND_MULTI_FACTOR_ANALYSIS.out.objects
    versions = BIOC_DIFFBIND_MULTI_FACTOR_ANALYSIS.out.versions
}
