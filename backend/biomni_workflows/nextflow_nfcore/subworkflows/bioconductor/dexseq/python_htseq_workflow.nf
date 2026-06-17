#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dexseq — python_htseq_workflow
// Perform differential exon usage analysis starting from pre-calculated HTSeq count files and a flattened GFF file.
// Input: count_files, flattened.gff, sample_table.csv
// Container: quay.io/biocontainers/bioconductor-dexseq:1.56.0--r45hdfd78af_0
// R packages: DEXSeq
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: MA plot, dispersion plot
// QC: dispersion QC plot, diagnostic MA/PCA QC

nextflow.enable.dsl = 2

process BIOC_DEXSEQ_PYTHON_HTSEQ_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-dexseq:1.56.0--r45hdfd78af_0"

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
    .bm_deps <- c("DEXSeq")
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
    library(DEXSeq)
    
    # --- Define paths to count files and the flattened GFF file ---
    flattenedFile = "flattened.gff"
    
    # --- Create a sample metadata data frame ---
    # Read the sample metadata table from the working directory
    sampleTable = read.csv("sample_table.csv", row.names = 1, stringsAsFactors = TRUE)
    
    # Resolve and align the count files with the rows of the sample table
    all_files = list.files(".", full.names = TRUE)
    countFiles = sapply(rownames(sampleTable), function(sn) {
      match_file = all_files[grep(sn, basename(all_files))]
      if (length(match_file) > 0) {
        return(match_file[1])
      } else {
        # Fallback to sample_name.txt in the current directory if no direct match is found
        return(file.path(".", paste0(sn, ".txt")))
      }
    })
    
    # --- Build a DEXSeqDataSet using DEXSeqDataSetFromHTSeq() ---
    dxd = DEXSeqDataSetFromHTSeq(
       countFiles,
       sampleData=sampleTable,
       design= ~ sample + exon + condition:exon,
       flattenedfile=flattenedFile )
    
    # --- Run the complete analysis using the wrapper function ---
    dxr = DEXSeq(dxd)
    
    # Save meaningful results to output files
    # Save the DEXSeqResults and DEXSeqDataSet objects as RDS files
    saveRDS(dxd, "dexseq_dataset.rds")
    saveRDS(dxr, "dexseq_results.rds")
    
    # Export the results table to a CSV file
    dxr_df = as.data.frame(dxr)
    write.csv(dxr_df, "dexseq_results.csv", row.names = TRUE)
    
    # Generate diagnostic and visualization plots
    # 1. Dispersion estimation plot
    pdf("dispersion_plot.pdf")
    plotDispEsts(dxd)
    dev.off()
    
    # 2. MA plot (Mean expression vs log2 fold change)
    pdf("ma_plot.pdf")
    plotMA(dxr, cex = 0.8)
    dev.off()
    
    # 3. Expression plot for the top significant gene (or first gene if none are significant)
    sig_exons = dxr[which(dxr\$padj < 0.1), ]
    if (nrow(sig_exons) > 0) {
      top_gene = sig_exons\$groupID[1]
    } else {
      top_gene = dxr\$groupID[1]
    }
    
    if (!is.na(top_gene)) {
      pdf("top_gene_dexseq_plot.pdf", width = 12, height = 8)
      plotDEXSeq(dxr, top_gene, legend = TRUE, cex.axis = 1.2, cex = 1.3, lwd = 2)
      dev.off()
    }
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # dispersion QC plot — file-exists check for any PDF with "disp" or "bcv"
    # in the filename. Pairs with bioc_dispersion_size_factor.
    .dqp_pdfs <- list.files(".", pattern = "(?i)(disp|bcv).*\\.pdf\$")
    .dqp_passes <- length(.dqp_pdfs) > 0
    .gates_by_label[["dispersion QC plot"]] <- list(
      gate_row = "bioc_dispersion_qc_plot",
      metric_name = "dispersion_plot_exists",
      metric_value = if (.dqp_passes) 1 else 0,
      passes = .dqp_passes,
      status = if (.dqp_passes) paste0("computed (", length(.dqp_pdfs), " dispersion PDF(s) emitted)")
               else "not_computed (no dispersion PDF found)"
    )

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
      process = "BIOC_DEXSEQ_PYTHON_HTSEQ_WORKFLOW",
      domain  = "bioconductor",
      declared_qc_steps = c("dispersion QC plot", "diagnostic MA/PCA QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DEXSEQ_PYTHON_HTSEQ_WORKFLOW":',
        paste0('        dexseq: ', as.character(packageVersion("dexseq")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_python_htseq_workflow.csv versions.yml
    """
}

workflow BIOC_DEXSEQ_PYTHON_HTSEQ_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count_files, flattened.gff, sample_table.csv ] ]

    main:
    BIOC_DEXSEQ_PYTHON_HTSEQ_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_DEXSEQ_PYTHON_HTSEQ_WORKFLOW.out.tables
    plots    = BIOC_DEXSEQ_PYTHON_HTSEQ_WORKFLOW.out.plots
    objects  = BIOC_DEXSEQ_PYTHON_HTSEQ_WORKFLOW.out.objects
    versions = BIOC_DEXSEQ_PYTHON_HTSEQ_WORKFLOW.out.versions
}
