#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dexseq — complex_design_workflow
// Perform differential exon usage analysis controlling for additional technical or experimental covariates (blocking factors).
// Input: dxd
// Container: quay.io/biocontainers/bioconductor-dexseq:1.56.0--r45hdfd78af_0
// R packages: DEXSeq
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: dispersion plot
// QC: dispersion/size-factor estimation, dispersion QC plot

nextflow.enable.dsl = 2

process BIOC_DEXSEQ_COMPLEX_DESIGN_WORKFLOW {
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
    
    # Define input file path
    input_file <- "dxd.rds"
    
    # Check if the input file exists
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # Read the user-provided DEXSeqDataSet object
    dxd <- readRDS(input_file)
    
    # Ensure the object is of the correct class
    if (!is(dxd, "DEXSeqDataSet")) {
      stop("Error: The loaded object is not a DEXSeqDataSet.")
    }
    
    # Ensure size factors are estimated (required before dispersion estimation)
    if (is.null(sizeFactors(dxd))) {
      message("Estimating size factors...")
      dxd <- estimateSizeFactors(dxd)
    }
    
    # === DOCUMENTED CODE ===
    formulaFullModel    =  ~ sample + exon + type:exon + condition:exon
    formulaReducedModel =  ~ sample + exon + type:exon 
    dxd = estimateDispersions( dxd, formula = formulaFullModel )
    dxd = testForDEU( dxd, 
    	reducedModel = formulaReducedModel, 
            fullModel = formulaFullModel )
    dxr2 = DEXSeqResults( dxd )
    # === END DOCUMENTED CODE ===
    
    # Save the DEXSeqResults object as an RDS file
    saveRDS(dxr2, "dexseq_results_complex.rds")
    
    # Save the results as a CSV table
    write.csv(as.data.frame(dxr2), "dexseq_results_complex.csv", row.names = TRUE)
    
    # Generate and save a diagnostic dispersion plot
    pdf("dispersion_plots.pdf", width = 7, height = 7)
    plotDispEsts(dxd)
    dev.off()
    
    # Generate and save a visualization plot for the most significant gene (if any)
    significant_genes <- dxr2\$groupID[which(dxr2\$padj < 0.1)]
    if (length(significant_genes) > 0) {
      # Select the top significant gene based on p-value
      top_gene <- dxr2\$groupID[order(dxr2\$pvalue, na.last = TRUE)][1]
      
      pdf("dexseq_top_gene_plot.pdf", width = 10, height = 7)
      plotDEXSeq(dxr2, top_gene, legend = TRUE, cex.axis = 1.2, cex = 1.3, lwd = 2)
      dev.off()
    } else {
      # Fallback to the first gene in the dataset if none are significant
      first_gene <- dxr2\$groupID[1]
      if (!is.null(first_gene)) {
        pdf("dexseq_first_gene_plot.pdf", width = 10, height = 7)
        plotDEXSeq(dxr2, first_gene, legend = TRUE, cex.axis = 1.2, cex = 1.3, lwd = 2)
        dev.off()
      }
    }
    
    message("Workflow completed successfully. Outputs written to 'dexseq_results_complex.rds', 'dexseq_results_complex.csv', and PDF plots.")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # dispersion/size-factor estimation — object-type-aware. Try DESeq2
    # DESeqDataSet (mcols\$dispOutlier), then edgeR DGEList (common.dispersion).
    .dsf_value <- NA_real_; .dsf_kind <- "none"
    for (.dsf_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .dsf_obj <- tryCatch(readRDS(.dsf_rds), error = function(e) NULL)
      if (!is.null(.dsf_obj)) {
        if (inherits(.dsf_obj, "DESeqDataSet")) {
          .dsf_o <- tryCatch(mcols(.dsf_obj)\$dispOutlier, error = function(e) NULL)
          if (!is.null(.dsf_o)) { .dsf_value <- round(mean(.dsf_o, na.rm = TRUE), 4); .dsf_kind <- "deseq2"; break }
        } else if (inherits(.dsf_obj, "DGEList")) {
          .dsf_v <- tryCatch(.dsf_obj\$common.dispersion, error = function(e) NULL)
          if (!is.null(.dsf_v) && is.finite(.dsf_v)) { .dsf_value <- round(sqrt(.dsf_v), 4); .dsf_kind <- "edger_bcv"; break }
        }
      }
    }
    .gates_by_label[["dispersion/size-factor estimation"]] <- list(
      gate_row = "bioc_dispersion_size_factor",
      metric_name = if (.dsf_kind == "edger_bcv") "common_bcv" else "disp_outlier_fraction",
      metric_value = .dsf_value,
      passes = isTRUE(
        (.dsf_kind == "deseq2" && is.finite(.dsf_value) && .dsf_value <= 0.01) ||
        (.dsf_kind == "edger_bcv" && is.finite(.dsf_value) && .dsf_value > 0 && .dsf_value < 1.0)
      ),
      status = if (is.finite(.dsf_value)) paste0("computed (", .dsf_kind, ")")
               else "not_computed (no DESeqDataSet/DGEList .rds artifact present)"
    )

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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_DEXSEQ_COMPLEX_DESIGN_WORKFLOW",
      domain  = "bioconductor",
      declared_qc_steps = c("dispersion/size-factor estimation", "dispersion QC plot"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DEXSEQ_COMPLEX_DESIGN_WORKFLOW":',
        paste0('        dexseq: ', as.character(packageVersion("dexseq")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_complex_design_workflow.csv versions.yml
    """
}

workflow BIOC_DEXSEQ_COMPLEX_DESIGN_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dxd ] ]

    main:
    BIOC_DEXSEQ_COMPLEX_DESIGN_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_DEXSEQ_COMPLEX_DESIGN_WORKFLOW.out.tables
    plots    = BIOC_DEXSEQ_COMPLEX_DESIGN_WORKFLOW.out.plots
    objects  = BIOC_DEXSEQ_COMPLEX_DESIGN_WORKFLOW.out.objects
    versions = BIOC_DEXSEQ_COMPLEX_DESIGN_WORKFLOW.out.versions
}
