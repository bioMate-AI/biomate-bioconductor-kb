#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OUTRIDER — autoencoder_outlier_detection
// Detect aberrantly expressed genes in RNA-seq data using a denoising autoencoder to control for confounders.
// Input: ctsTable, annoTable
// Container: quay.io/biocontainers/bioconductor-outrider:1.28.0--r45ha27e39d_0
// R packages: AnnotationDbi, beeswarm, OUTRIDER, peer, rmariadb
// Bioconductor: 3.20 | R: 4.4
// Requires: OUTRIDER
// Visualizations: plot (ggplot/base)
// QC: dispersion/size-factor estimation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read User Input Files
//  * 2. [Input & Preparation] OUTRIDER Analysis Pipeline
//  * 3. [Input & Preparation] Save Outputs

nextflow.enable.dsl = 2

process BIOC_OUTRIDER_AUTOENCODER_OUTLIER_DETECTION {
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
    .bm_deps <- c("AnnotationDbi", "beeswarm", "OUTRIDER", "peer", "rmariadb")
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
    library(OUTRIDER)
    
    # ==========================================
    # --- Read User Input Files ---
    # ==========================================
    # The pipeline expects 'ctsTable.csv' (or .tsv) and 'annoTable.csv' (or .tsv)
    # in the current working directory.
    
    if (file.exists("ctsTable.csv")) {
        ctsTable <- read.csv("ctsTable.csv", row.names=1, check.names=FALSE)
    } else if (file.exists("ctsTable.tsv")) {
        ctsTable <- read.table("ctsTable.tsv", header=TRUE, row.names=1, check.names=FALSE)
    } else {
        stop("Error: 'ctsTable.csv' or 'ctsTable.tsv' not found in the working directory.")
    }
    
    if (file.exists("annoTable.csv")) {
        annoTable <- read.csv("annoTable.csv", row.names=1, check.names=FALSE)
    } else if (file.exists("annoTable.tsv")) {
        annoTable <- read.table("annoTable.tsv", header=TRUE, row.names=1, check.names=FALSE)
    } else {
        stop("Error: 'annoTable.csv' or 'annoTable.tsv' not found in the working directory.")
    }
    
    # Ensure count data is a matrix
    ctsTable <- as.matrix(ctsTable)
    
    # ==========================================
    # --- OUTRIDER Analysis Pipeline ---
    # ==========================================
    
    # create OutriderDataSet object
    ods <- OutriderDataSet(countData=ctsTable, colData=annoTable)
    
    # label not expressed genes
    ods <- filterExpression(ods, minCounts=TRUE, filterGenes=FALSE)
    
    # do the actual subsetting based on the filtering labels
    ods <- ods[mcols(ods)\$passedFilter,]
    
    # automatically control for confounders
    ods <- estimateSizeFactors(ods)
    
    # Optimal Hard Thresholding (default)
    ods <- estimateBestQ(ods)
    
    # set exclusion mask
    sampleExclusionMask(ods) <- FALSE
    
    # Control for confounders using the autoencoder
    ods <- controlForConfounders(ods)
    
    # compute P-values (nominal and adjusted)
    ods <- computePvalues(ods, alternative="two.sided", method="BY")
    
    # compute the Z-scores
    ods <- computeZscores(ods)
    
    # get results (default only significant, padj < 0.05)
    res <- results(ods)
    
    # ==========================================
    # --- Save Outputs ---
    # ==========================================
    
    # Save the significant results table
    write.csv(as.data.frame(res), "outrider_results.csv", row.names=FALSE)
    
    # Save the complete OutriderDataSet object
    saveRDS(ods, "outrider_ods.rds")
    
    # Generate and save diagnostic plots
    pdf("outrider_diagnostic_plots.pdf", width=7, height=7)
    tryCatch({
        plotFPKM(ods)
    }, error = function(e) message("Could not plot FPKM distribution."))
    
    tryCatch({
        plotExpressedGenes(ods)
    }, error = function(e) message("Could not plot expressed genes summary."))
    
    tryCatch({
        plotCountCorHeatmap(ods, normalized=TRUE)
    }, error = function(e) message("Could not plot sample correlation heatmap."))
    
    tryCatch({
        plotAberrantPerSample(ods)
    }, error = function(e) message("Could not plot aberrant events per sample."))
    dev.off()
    
    message("OUTRIDER pipeline completed successfully. Outputs saved to 'outrider_results.csv', 'outrider_ods.rds', and 'outrider_diagnostic_plots.pdf'.")
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

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_OUTRIDER_AUTOENCODER_OUTLIER_DETECTION",
      domain  = "bioconductor",
      declared_qc_steps = c("dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_OUTRIDER_AUTOENCODER_OUTLIER_DETECTION":',
        paste0('    OUTRIDER: ', as.character(packageVersion('OUTRIDER')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_autoencoder_outlier_detection.csv versions.yml
    """
}

workflow BIOC_OUTRIDER_AUTOENCODER_OUTLIER_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ctsTable, annoTable ] ]

    main:
    BIOC_OUTRIDER_AUTOENCODER_OUTLIER_DETECTION(ch_input)

    emit:
    tables   = BIOC_OUTRIDER_AUTOENCODER_OUTLIER_DETECTION.out.tables
    plots    = BIOC_OUTRIDER_AUTOENCODER_OUTLIER_DETECTION.out.plots
    objects  = BIOC_OUTRIDER_AUTOENCODER_OUTLIER_DETECTION.out.objects
    versions = BIOC_OUTRIDER_AUTOENCODER_OUTLIER_DETECTION.out.versions
}
