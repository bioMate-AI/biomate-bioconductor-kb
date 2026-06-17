#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dexseq — r_based_bam_workflow
// Perform differential exon usage analysis starting from BAM files and a GTF annotation entirely within R.
// Input: annotation.gtf, sample1.bam, sample2.bam
// Container: quay.io/biocontainers/bioconductor-dexseq:1.56.0--r45hdfd78af_0
// R packages: GenomeInfoDb, GenomicAlignments, GenomicFeatures, Rsamtools, DEXSeq, txdbmaker
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: MA plot, dispersion plot
// QC: dispersion/size-factor estimation, dispersion QC plot, diagnostic MA/PCA QC, alignment/mapping QC

nextflow.enable.dsl = 2

process BIOC_DEXSEQ_R_BASED_BAM_WORKFLOW {
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
    .bm_deps <- c("GenomeInfoDb", "GenomicAlignments", "GenomicFeatures", "Rsamtools", "DEXSeq", "txdbmaker", "SummarizedExperiment")
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
    l    library(SummarizedExperiment)
ibrary(GenomicFeatures)
    library(txdbmaker)
    library(Rsamtools)
    library(GenomicAlignments)
    library(GenomeInfoDb)
    library(DEXSeq)
    
    # --- Prepare annotation using makeTxDbFromGFF() and ---
    txdb = makeTxDbFromGFF("annotation.gtf")
    flattenedAnnotation = exonicParts( txdb, linked.to.single.gene.only=TRUE )
    names(flattenedAnnotation) =
        sprintf("%s:E%0.3d", flattenedAnnotation\$gene_id, flattenedAnnotation\$exonic_part)
    
    # --- Count reads overlapping exonic parts using BamFileList() ---
    bamFiles = c( "sample1.bam", "sample2.bam" )
    bamFiles = BamFileList( bamFiles )
    
    # Safely attempt to set seqlevelsStyle to UCSC as in the documented code
    tryCatch({
        seqlevelsStyle(flattenedAnnotation) = "UCSC"
    }, error = function(e) {
        message("Warning: Could not set seqlevelsStyle to UCSC. Proceeding with default style.")
    })
    
    se = summarizeOverlaps(
        flattenedAnnotation, BamFileList(bamFiles), singleEnd=FALSE,
        fragments=TRUE, ignore.strand=TRUE )
    
    # --- Build a DEXSeqDataSet using DEXSeqDataSetFromSE() ---
    colData(se)\$condition = factor(c("untreated1", "untreated3"))
    colData(se)\$libType = factor(c("single-end", "paired-end"))
    dxd = DEXSeqDataSetFromSE( se, design= ~ sample + exon + condition:exon )
    
    # --- Estimate size factors using estimateSizeFactors() ---
    dxd = estimateSizeFactors( dxd )
    
    # --- Estimate dispersions using estimateDispersions() ---
    dxd = estimateDispersions( dxd )
    
    # --- Test for differential exon usage using testForDEU() ---
    dxd = testForDEU( dxd )
    
    # --- Estimate exon fold changes using estimateExonFoldChanges() ---
    dxd = estimateExonFoldChanges( dxd, fitExpToVar="condition")
    
    # --- Extract results using DEXSeqResults() ---
    dxr1 = DEXSeqResults( dxd )
    
    # Write meaningful output files
    write.csv(as.data.frame(dxr1), file="dexseq_results.csv", row.names=TRUE)
    saveRDS(dxd, file="dexseq_dxd.rds")
    saveRDS(dxr1, file="dexseq_results.rds")
    
    # Generate diagnostic and results plots
    pdf("dispersion_plots.pdf")
    plotDispEsts( dxd )
    dev.off()
    
    pdf("ma_plot.pdf")
    plotMA( dxr1, cex=0.8 )
    dev.off()
    
    # Plot the first gene in the results if available
    if (nrow(dxr1) > 0) {
        first_gene = dxr1\$groupID[1]
        pdf("dexseq_plot.pdf")
        plotDEXSeq( dxr1, first_gene, legend=TRUE, cex.axis=1.2, cex=1.3, lwd=2 )
        dev.off()
    }
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

    # alignment/mapping QC — workflow-emitted artifact check for common log
    # files (.log, .summary, alignment metrics tables). Binary pass.
    .amqc_logs <- c(list.files(".", pattern = "(?i)(align|map|samtools|flagstat).*\\.(log|txt|summary)\$"),
                    list.files(".", pattern = "(?i)flagstat\\."))
    .amqc_passes <- length(.amqc_logs) > 0
    .gates_by_label[["alignment/mapping QC"]] <- list(
      gate_row = "bioc_alignment_mapping_qc",
      metric_name = "alignment_qc_artifacts",
      metric_value = length(.amqc_logs),
      passes = .amqc_passes,
      status = if (.amqc_passes) paste0("computed (", length(.amqc_logs), " alignment log(s) emitted)")
               else "not_computed (no alignment log/summary artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_DEXSEQ_R_BASED_BAM_WORKFLOW",
      domain  = "bioconductor",
      declared_qc_steps = c("dispersion/size-factor estimation", "dispersion QC plot", "diagnostic MA/PCA QC", "alignment/mapping QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DEXSEQ_R_BASED_BAM_WORKFLOW":',
        paste0('        dexseq: ', as.character(packageVersion("dexseq")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_r_based_bam_workflow.csv versions.yml
    """
}

workflow BIOC_DEXSEQ_R_BASED_BAM_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ annotation.gtf, sample1.bam, sample2.bam ] ]

    main:
    BIOC_DEXSEQ_R_BASED_BAM_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_DEXSEQ_R_BASED_BAM_WORKFLOW.out.tables
    plots    = BIOC_DEXSEQ_R_BASED_BAM_WORKFLOW.out.plots
    objects  = BIOC_DEXSEQ_R_BASED_BAM_WORKFLOW.out.objects
    versions = BIOC_DEXSEQ_R_BASED_BAM_WORKFLOW.out.versions
}
