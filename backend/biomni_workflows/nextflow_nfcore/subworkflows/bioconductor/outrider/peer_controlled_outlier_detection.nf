#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OUTRIDER — peer_controlled_outlier_detection
// Detect aberrantly expressed genes in RNA-seq data using PEER to control for confounders instead of the autoencoder.
// Input: ctsTable, annoTable
// Container: quay.io/biocontainers/bioconductor-outrider:1.28.0--r45ha27e39d_0
// R packages: OUTRIDER, peer
// Bioconductor: 3.20 | R: 4.4
// Requires: OUTRIDER, peer
// Visualizations: heatmap
// QC: dispersion/size-factor estimation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create the OutriderDataSet object and filter
//  * 2. [Input & Preparation] Estimate size factors
//  * 3. [Input & Preparation] Run the PEER model to calculate residuals and expected
//  * 4. [Input & Preparation] Fit the negative binomial model
//  * 5. [Input & Preparation] Compute Z-scores using PEER residuals
//  * 6. [Input & Preparation] Compute P-values and extract results

nextflow.enable.dsl = 2

process BIOC_OUTRIDER_PEER_CONTROLLED_OUTLIER_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("OUTRIDER", "peer")
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
    library(OUTRIDER)
    
    # Helper function to robustly read input files (TSV or CSV)
    read_input <- function(file_path) {
      tryCatch({
        read.table(file_path, header=TRUE, sep="\t", check.names=FALSE, stringsAsFactors=FALSE)
      }, error = function(e) {
        read.csv(file_path, header=TRUE, check.names=FALSE, stringsAsFactors=FALSE)
      })
    }
    
    # Locate input files in the working directory
    cts_file <- list.files(pattern = "^ctsTable(\\\\..+)?\$", ignore.case = TRUE)[1]
    anno_file <- list.files(pattern = "^annoTable(\\\\..+)?\$", ignore.case = TRUE)[1]
    
    if (is.na(cts_file)) {
      stop("Error: ctsTable file not found in the working directory.")
    }
    if (is.na(anno_file)) {
      stop("Error: annoTable file not found in the working directory.")
    }
    
    # Read raw data
    cts_raw <- read_input(cts_file)
    anno_raw <- read_input(anno_file)
    
    # Format count matrix (ensure gene IDs are row names)
    if (!is.numeric(cts_raw[[1]])) {
      rownames(cts_raw) <- cts_raw[[1]]
      cts_raw <- cts_raw[, -1, drop=FALSE]
    }
    ctsTable <- as.matrix(cts_raw)
    
    # Format annotation table
    if (!"sampleID" %in% colnames(anno_raw)) {
      if ("RNA_ID" %in% colnames(anno_raw)) {
        anno_raw\$sampleID <- anno_raw\$RNA_ID
      } else if (!is.numeric(anno_raw[[1]])) {
        anno_raw\$sampleID <- anno_raw[[1]]
      } else {
        anno_raw\$sampleID <- colnames(ctsTable)[1:nrow(anno_raw)]
      }
    }
    rownames(anno_raw) <- anno_raw\$sampleID
    annoTable <- anno_raw
    
    # Align samples between counts and annotations
    common_samples <- intersect(colnames(ctsTable), rownames(annoTable))
    if (length(common_samples) == 0) {
      stop("Error: No common sample IDs found between ctsTable columns and annoTable sampleIDs.")
    }
    ctsTable <- ctsTable[, common_samples, drop=FALSE]
    annoTable <- annoTable[common_samples, , drop=FALSE]
    
    # --- Create the OutriderDataSet object and filter ---
    ods <- OutriderDataSet(countData=ctsTable, colData=annoTable)
    ods <- filterExpression(ods, minCounts=TRUE, filterGenes=TRUE)
    
    # PEER implementation function (reproduced faithfully from documented code)
    peer <- function(ods, maxFactors=NA, maxItr=1000){
    
        # check for PEER
        if(!require(peer)){
            stop("Please install the 'peer' package from GitHub to use this ",
                    "functionality.")
        }
    
        # default and recommendation by PEER: min(0.25*n, 100)
        if(is.na(maxFactors)){
            maxFactors <- min(as.integer(0.25* ncol(ods)), 100)
        }
    
        # log counts
        logCts <- log2(t(t(counts(ods)+1)/sizeFactors(ods)))
    
        # prepare PEER model
        model <- PEER()
        PEER_setNmax_iterations(model, maxItr)
        PEER_setNk(model, maxFactors)
        PEER_setPhenoMean(model, logCts)
        PEER_setAdd_mean(model, TRUE)
    
        # run fullpeer pipeline
        PEER_update(model)
    
        # extract PEER data
        peerResiduals <- PEER_getResiduals(model)
        peerMean <- t(t(2^(logCts - peerResiduals)) * sizeFactors(ods))
    
        # save model in object
        normalizationFactors(ods) <- pmax(peerMean, 1E-8)
        metadata(ods)[["PEER_model"]] <- list(
                alpha     = PEER_getAlpha(model),
                residuals = PEER_getResiduals(model),
                W         = PEER_getW(model))
    
        return(ods)
    }
    
    # --- Estimate size factors ---
    ods <- estimateSizeFactors(ods)
    
    # --- Run the PEER model to calculate residuals and expected ---
    ods <- peer(ods)
    
    # --- Fit the negative binomial model ---
    ods <- fit(ods)
    
    # --- Compute Z-scores using PEER residuals ---
    ods <- computeZscores(ods, peerResiduals=TRUE)
    
    # --- Compute P-values and extract results ---
    ods <- computePvalues(ods)
    
    # Extract results table
    res <- results(ods)
    
    # Write output files
    write.csv(as.data.frame(res), "outrider_results.csv", row.names=FALSE)
    saveRDS(ods, "outrider_ods.rds")
    
    # Save summary of aberrant genes per sample
    ab_sample <- aberrant(ods, by="sample")
    write.csv(data.frame(sampleID=names(ab_sample), aberrantGeneCount=ab_sample),
              "aberrant_genes_per_sample.csv", row.names=FALSE)
    
    # Generate diagnostic plots
    pdf("sample_correlation_heatmap.pdf", width=7, height=7)
    tryCatch({
      plotCountCorHeatmap(ods, normalized=TRUE)
    }, error = function(e) {
      warning("Could not plot correlation heatmap: ", e\$message)
    })
    dev.off()
    
    pdf("power_analysis_plot.pdf", width=7, height=7)
    tryCatch({
      plotPowerAnalysis(ods)
    }, error = function(e) {
      warning("Could not plot power analysis: ", e\$message)
    })
    dev.off()
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
      process = "BIOC_OUTRIDER_PEER_CONTROLLED_OUTLIER_DETECTION",
      domain  = "bioconductor",
      declared_qc_steps = c("dispersion/size-factor estimation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_OUTRIDER_PEER_CONTROLLED_OUTLIER_DETECTION":',
        paste0('    OUTRIDER: ', as.character(packageVersion('OUTRIDER')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peer_controlled_outlier_detection.csv versions.yml
    """
}

workflow BIOC_OUTRIDER_PEER_CONTROLLED_OUTLIER_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ctsTable, annoTable ] ]

    main:
    BIOC_OUTRIDER_PEER_CONTROLLED_OUTLIER_DETECTION(ch_input)

    emit:
    tables   = BIOC_OUTRIDER_PEER_CONTROLLED_OUTLIER_DETECTION.out.tables
    plots    = BIOC_OUTRIDER_PEER_CONTROLLED_OUTLIER_DETECTION.out.plots
    objects  = BIOC_OUTRIDER_PEER_CONTROLLED_OUTLIER_DETECTION.out.objects
    versions = BIOC_OUTRIDER_PEER_CONTROLLED_OUTLIER_DETECTION.out.versions
}
