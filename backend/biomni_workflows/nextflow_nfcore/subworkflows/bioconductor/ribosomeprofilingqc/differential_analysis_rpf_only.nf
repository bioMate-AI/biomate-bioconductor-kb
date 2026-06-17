#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ribosomeprofilingqc — differential_analysis_rpf_only
// Count RPF reads and perform differential expression or alternative splicing analysis using RPF data alone.
// Input: RPFs, gtf
// Container: quay.io/biocontainers/bioconductor-ribosomeprofilingqc:1.22.0--r45hdfd78af_0
// R packages: Rsamtools, edgeR, ribosomeProfilingQC, txdbmaker
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)
// QC: TMM normalization, dispersion/size-factor estimation

nextflow.enable.dsl = 2

process BIOC_RIBOSOMEPROFILINGQC_DIFFERENTIAL_ANALYSIS_RPF_ONLY {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ribosomeprofilingqc:1.22.0--r45hdfd78af_0"

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
    .bm_deps <- c("Rsamtools", "edgeR", "ribosomeProfilingQC", "txdbmaker")
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
    library(ribosomeProfilingQC)
    library(txdbmaker)
    library(edgeR)
    library(Rsamtools)
    
    # ==========================================
    # 1. USER INPUT & ENVIRONMENT SETUP
    # ==========================================
    
    # Locate BAM files in the working directory
    user_bams <- list.files(pattern = "\\\\.bam\$", full.names = TRUE)
    if (length(user_bams) < 4) {
      stop("This workflow requires at least 4 BAM files (2 for KD, 2 for WT) in the working directory.")
    }
    
    # Locate GTF file in the working directory
    gtf_files <- list.files(pattern = "\\\\.gtf(\\\\.gz)?\$", full.names = TRUE)
    if (length(gtf_files) == 0) {
      stop("No GTF file found in the working directory.")
    }
    gtf <- gtf_files[1]
    
    # Create TxDb object from GTF
    txdb <- makeTxDbFromGFF(gtf)
    
    # To faithfully reproduce the vignette's grepl and group structure,
    # we copy/symlink the user's BAM files to the expected names.
    expected_names <- c("RPF.KD1.1.bam", "RPF.KD1.2.bam", "RPF.WT.1.bam", "RPF.WT.2.bam")
    RPFs <- c()
    
    for (i in 1:4) {
      dest <- expected_names[i]
      if (file.exists(dest)) {
        file.remove(dest)
      }
      file.copy(user_bams[i], dest)
      
      # Handle BAM index files
      user_bai <- paste0(user_bams[i], ".bai")
      dest_bai <- paste0(dest, ".bai")
      if (file.exists(dest_bai)) {
        file.remove(dest_bai)
      }
      if (file.exists(user_bai)) {
        file.copy(user_bai, dest_bai)
      } else {
        # Generate index if missing
        indexBam(dest)
      }
      RPFs <- c(RPFs, dest)
    }
    
    # Define groups and sample names matching the vignette
    gp <- c("KD", "KD", "CTL", "CTL")
    group1 <- c("RPF.KD1.1", "RPF.KD1.2")
    group2 <- c("RPF.WT.1", "RPF.WT.2")
    
    # ==========================================
    # 2. EXECUTING THE WORKFLOW
    # ==========================================
    
    # --- Count RPF reads ---
    cnts <- countReads(RPFs, gtf=gtf, level="gene", bestpsite=13, readsLen=c(28,29))
    
    # Save raw counts
    write.csv(cnts\$RPFs, "rpf_counts.csv", row.names = TRUE)
    
    # --- Differential expression analysis using edgeR ---
    y <- DGEList(counts = cnts\$RPFs, group = gp)
    y <- calcNormFactors(y)
    design <- model.matrix(~0+gp)
    colnames(design) <- sub("gp", "", colnames(design))
    y <- estimateDisp(y, design)
    
    # Quasi-likelihood F-tests
    fit <- glmQLFit(y, design)
    qlf <- glmQLFTest(fit)
    qlf_tags <- topTags(qlf, n=3)
    write.csv(as.data.frame(topTags(qlf, n=nrow(qlf))), "edgeR_qlf_results.csv")
    
    # Likelihood ratio tests
    fit <- glmFit(y, design)
    lrt <- glmLRT(fit)
    lrt_tags <- topTags(lrt, n=3)
    write.csv(as.data.frame(topTags(lrt, n=nrow(lrt))), "edgeR_lrt_results.csv")
    
    # --- Calculate coverage depth ---
    coverage <- coverageDepth(RPFs[grepl("KD1|WT", RPFs)], gtf=txdb, level="gene", region="feature with extension")
    
    # --- Alternative splicing/translation events detection and ---
    se <- spliceEvent(coverage, group1, group2)
    write.csv(as.data.frame(se), "splice_events.csv", row.names = FALSE)
    
    # Plot the first detected splice event if available
    if (nrow(se) > 0 && !is.na(se\$feature[1])) {
      pdf("splice_event_plot.pdf", width = 8, height = 6)
      plotSpliceEvent(se, se\$feature[1], coverage, group1, group2)
      dev.off()
    } else {
      message("No alternative splicing events detected to plot.")
    }
    
    # Clean up temporary copied BAM files and indices
    file.remove(expected_names)
    file.remove(paste0(expected_names, ".bai"))
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # TMM normalization — DGEList\$samples\$norm.factors set (Robinson & Oshlack 2010).
    .tmm_factors <- NULL; .tmm_n_nontrivial <- NA_real_
    for (.tmm_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .tmm_obj <- tryCatch(readRDS(.tmm_rds), error = function(e) NULL)
      if (!is.null(.tmm_obj) && inherits(.tmm_obj, "DGEList")) {
        .tmm_f <- tryCatch(.tmm_obj\$samples\$norm.factors, error = function(e) NULL)
        if (!is.null(.tmm_f) && length(.tmm_f) > 0) {
          .tmm_factors <- .tmm_f; .tmm_n_nontrivial <- sum(abs(.tmm_f - 1.0) > 1e-6); break
        }
      }
    }
    .gates_by_label[["TMM normalization"]] <- list(
      gate_row = "bioc_tmm_normalization",
      metric_name = "n_nontrivial_norm_factors",
      metric_value = .tmm_n_nontrivial,
      passes = isTRUE(is.finite(.tmm_n_nontrivial) && .tmm_n_nontrivial > 0),
      status = if (is.finite(.tmm_n_nontrivial)) paste0("computed (n=", length(.tmm_factors), ", nontrivial=", .tmm_n_nontrivial, ")")
               else "not_computed (no DGEList .rds artifact present)"
    )

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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_RIBOSOMEPROFILINGQC_DIFFERENTIAL_ANALYSIS_RPF_ONLY",
      domain  = "bioconductor",
      declared_qc_steps = c("TMM normalization", "dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_RIBOSOMEPROFILINGQC_DIFFERENTIAL_ANALYSIS_RPF_ONLY":',
        paste0('        ribosomeprofilingqc: ', as.character(packageVersion("ribosomeprofilingqc")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_analysis_rpf_only.csv versions.yml
    """
}

workflow BIOC_RIBOSOMEPROFILINGQC_DIFFERENTIAL_ANALYSIS_RPF_ONLY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ RPFs, gtf ] ]

    main:
    BIOC_RIBOSOMEPROFILINGQC_DIFFERENTIAL_ANALYSIS_RPF_ONLY(ch_input)

    emit:
    tables   = BIOC_RIBOSOMEPROFILINGQC_DIFFERENTIAL_ANALYSIS_RPF_ONLY.out.tables
    plots    = BIOC_RIBOSOMEPROFILINGQC_DIFFERENTIAL_ANALYSIS_RPF_ONLY.out.plots
    objects  = BIOC_RIBOSOMEPROFILINGQC_DIFFERENTIAL_ANALYSIS_RPF_ONLY.out.objects
    versions = BIOC_RIBOSOMEPROFILINGQC_DIFFERENTIAL_ANALYSIS_RPF_ONLY.out.versions
}
