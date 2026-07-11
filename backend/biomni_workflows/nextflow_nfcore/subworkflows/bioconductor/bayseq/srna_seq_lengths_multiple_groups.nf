#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: baySeq — srna_seq_lengths_multiple_groups
// Analyze sRNA-seq data incorporating feature lengths and evaluating multiple complex experimental models simultaneously.
// Input: mobData, mobAnnotation
// Container: quay.io/biocontainers/bioconductor-bayseq:2.44.0--r45hdfd78af_0
// R packages: baySeq
// Bioconductor: 3.20 | R: 4.4
// Requires: baySeq
// Visualizations: MA plot
// QC: diagnostic MA/PCA QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate segment lengths
//  * 2. [Input & Preparation] Create countData object with seglens
//  * 3. [Core Analysis] Estimate library sizes using quantile method
//  * 4. [Input & Preparation] Define multiple group models
//  * 5. [Core Analysis] Estimate priors
//  * 6. [Core Analysis] Calculate likelihoods with nullData = TRUE
//  * 7. [Core Analysis] Extract top counts for specific models

nextflow.enable.dsl = 2

process BIOC_BAYSEQ_SRNA_SEQ_LENGTHS_MULTIPLE_GROUPS {
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
    .bm_deps <- c("baySeq")
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
    library(baySeq)
    library(parallel)
    
    # ---------------------------------------------------------
    # 1. Load User Input Files
    # ---------------------------------------------------------
    # The pipeline reads 'mobData' and 'mobAnnotation' from the working directory.
    # We support both RDS and CSV formats.
    
    load_mobData <- function() {
      if (file.exists("mobData")) {
        obj <- tryCatch(readRDS("mobData"), error = function(e) NULL)
        if (!is.null(obj)) return(as.matrix(obj))
      }
      if (file.exists("mobData.rds")) {
        obj <- tryCatch(readRDS("mobData.rds"), error = function(e) NULL)
        if (!is.null(obj)) return(as.matrix(obj))
      }
      if (file.exists("mobData.csv")) {
        obj <- tryCatch(read.csv("mobData.csv", header = TRUE, row.names = 1), error = function(e) NULL)
        if (!is.null(obj)) return(as.matrix(obj))
      }
      stop("Error: Could not find or read 'mobData' from the working directory.")
    }
    
    load_mobAnnotation <- function() {
      if (file.exists("mobAnnotation")) {
        obj <- tryCatch(readRDS("mobAnnotation"), error = function(e) NULL)
        if (!is.null(obj)) return(obj)
        obj <- tryCatch(read.csv("mobAnnotation", header = TRUE), error = function(e) NULL)
        if (!is.null(obj)) return(obj)
      }
      if (file.exists("mobAnnotation.rds")) {
        obj <- tryCatch(readRDS("mobAnnotation.rds"), error = function(e) NULL)
        if (!is.null(obj)) return(obj)
      }
      if (file.exists("mobAnnotation.csv")) {
        obj <- tryCatch(read.csv("mobAnnotation.csv", header = TRUE), error = function(e) NULL)
        if (!is.null(obj)) return(obj)
      }
      stop("Error: Could not find or read 'mobAnnotation' from the working directory.")
    }
    
    mobData <- load_mobData()
    mobAnnotation <- load_mobAnnotation()
    
    # ---------------------------------------------------------
    # 2. Parallel Cluster Setup
    # ---------------------------------------------------------
    cores <- min(2, parallel::detectCores() - 1)
    if (cores > 0) {
      cl <- makeCluster(cores)
    } else {
      cl <- NULL
    }
    
    # ---------------------------------------------------------
    # 3. Execute baySeq Workflow
    # ---------------------------------------------------------
    
    # Stage 1: Calculate segment lengths
    seglens <- mobAnnotation\$end - mobAnnotation\$start + 1
    
    # Stage 2: Create countData object with seglens
    cD <- new("countData", data = mobData, seglens = seglens, annotation = mobAnnotation)
    
    # Stage 3: Estimate library sizes using quantile method
    libsizes(cD) <- getLibsizes(cD, estimationType = "quantile")
    
    # Stage 4: Define multiple group models
    cD@replicates <- as.factor(c("D3/D3", "D3/D3", "WT/D3", "WT/D3", "WT/WT", "WT/WT"))
    NDE <- factor(c(1,1,1,1,1,1))
    d3dep <- c("wtRoot","wtRoot","wtRoot","wtRoot","dicerRoot","dicerRoot")
    mobile <- c("dicerShoot","dicerShoot","wtShoot","wtShoot","wtShoot","wtShoot")
    groups(cD) <- list(NDE = NDE, d3dep = d3dep, mobile = mobile)  
    
    # Stage 5: Estimate priors
    cD <- getPriors.NB(cD, cl = cl)
    
    # Stage 6: Calculate likelihoods with nullData = TRUE
    cD <- getLikelihoods(cD, nullData = TRUE, cl = cl)
    
    # Stage 7: Extract top counts for specific models
    top_mobile <- topCounts(cD, group = "mobile", normaliseData = TRUE)  
    top_d3dep <- topCounts(cD, group = "d3dep", normaliseData = TRUE)
    
    # ---------------------------------------------------------
    # 4. Save Outputs
    # ---------------------------------------------------------
    write.csv(top_mobile, file = "top_counts_mobile.csv", row.names = FALSE)
    write.csv(top_d3dep, file = "top_counts_d3dep.csv", row.names = FALSE)
    saveRDS(cD, file = "baySeq_analyzed_cD.rds")
    
    # Generate diagnostic plot
    pdf("MA_plot_mobile.pdf")
    plotMA.CD(cD, samplesA = c(1,2), samplesB = c(3,4,5,6),
              col = rgb(red = exp(cD@posteriors[, "mobile"]), green = 0, blue = 0))
    dev.off()
    
    # Clean up cluster
    if (!is.null(cl)) {
      stopCluster(cl)
    }
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # diagnostic MA/PCA QC — PC1 variance explained on any large matrix.
    # Pass when PC1 > 10% (Risso 2014 RUV-seq diagnostic).
    .pca_pc1 <- NA_real_; .pca_files <- character(0)
    for (.pca_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_BAYSEQ_SRNA_SEQ_LENGTHS_MULTIPLE_GROUPS",
      domain  = "bioconductor",
      declared_qc_steps = c("diagnostic MA/PCA QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_BAYSEQ_SRNA_SEQ_LENGTHS_MULTIPLE_GROUPS":',
        paste0('    baySeq: ', as.character(packageVersion('baySeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_srna_seq_lengths_multiple_groups.csv versions.yml
    """
}

workflow BIOC_BAYSEQ_SRNA_SEQ_LENGTHS_MULTIPLE_GROUPS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mobData, mobAnnotation ] ]

    main:
    BIOC_BAYSEQ_SRNA_SEQ_LENGTHS_MULTIPLE_GROUPS(ch_input)

    emit:
    tables   = BIOC_BAYSEQ_SRNA_SEQ_LENGTHS_MULTIPLE_GROUPS.out.tables
    plots    = BIOC_BAYSEQ_SRNA_SEQ_LENGTHS_MULTIPLE_GROUPS.out.plots
    objects  = BIOC_BAYSEQ_SRNA_SEQ_LENGTHS_MULTIPLE_GROUPS.out.objects
    versions = BIOC_BAYSEQ_SRNA_SEQ_LENGTHS_MULTIPLE_GROUPS.out.versions
}
