#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epiregulon — sc_multiomic_tf_activity_inference
// Construct gene regulatory networks and infer single-cell transcription factor activity by integrating scRNA-seq and scATAC-seq data.
// Input: PeakMatrix, GeneExpressionMatrix, reducedDimMatrix
// Container: quay.io/biocontainers/bioconductor-epiregulon:2.0.2--r45ha27e39d_0
// R packages: BiocParallel, SingleCellExperiment, epiregulon, scuttle
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, SingleCellExperiment, epiregulon, scuttle
// Visualizations: plot (ggplot/base)
// QC: count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read User Input Files
//  * 2. [Core Analysis] Retrieve bulk TF ChIP-seq binding sites or motif info
//  * 3. [Core Analysis] Optimize the number of metacells
//  * 4. [Core Analysis] Calculate Peak-to-Gene (P2G) links
//  * 5. [Core Analysis] Add TF binding information to peaks
//  * 6. [Core Analysis] Generate regulons
//  * 7. [Core Analysis] Network pruning
//  * 8. [Core Analysis] Estimate regulatory weights
//  * 9. [Core Analysis] Calculate TF activity scores

nextflow.enable.dsl = 2

process BIOC_EPIREGULON_SC_MULTIOMIC_TF_ACTIVITY_INFERENCE {
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
    .bm_deps <- c("BiocParallel", "SingleCellExperiment", "epiregulon", "scuttle", "SummarizedExperiment")
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
    library(SummarizedExperiment)
    library(epiregulon)
    library(scuttle)
    library(BiocParallel)
    
    # -----------------------------------------------------------------------------
    # --- Read User Input Files ---
    # -----------------------------------------------------------------------------
    # The pipeline reads exactly these files from the working directory:
    # - PeakMatrix (SingleCellExperiment containing chromatin accessibility peak matrix)
    # - GeneExpressionMatrix (SingleCellExperiment containing gene expression matrix)
    # - reducedDimMatrix (dimensionality reduction matrix from scATAC-seq or joint profiling)
    
    if (!file.exists("PeakMatrix.rds") || 
        !file.exists("GeneExpressionMatrix.rds") || 
        !file.exists("reducedDimMatrix.rds")) {
      stop("Required input files (PeakMatrix.rds, GeneExpressionMatrix.rds, reducedDimMatrix.rds) not found in the working directory.")
    }
    
    PeakMatrix <- readRDS("PeakMatrix.rds")
    GeneExpressionMatrix <- readRDS("GeneExpressionMatrix.rds")
    reducedDimMatrix <- readRDS("reducedDimMatrix.rds")
    
    # Ensure rownames of GeneExpressionMatrix are set to gene names if available
    if ("name" %in% colnames(rowData(GeneExpressionMatrix))) {
      rownames(GeneExpressionMatrix) <- rowData(GeneExpressionMatrix)\$name
    }
    
    # -----------------------------------------------------------------------------
    # --- Retrieve bulk TF ChIP-seq binding sites or motif info ---
    # -----------------------------------------------------------------------------
    message("Retrieving TF motif/ChIP-seq info...")
    grl <- getTFMotifInfo(genome = "hg38")
    
    # -----------------------------------------------------------------------------
    # --- Optimize the number of metacells ---
    # -----------------------------------------------------------------------------
    message("Optimizing metacell number...")
    cellNum <- optimizeMetacellNumber(peakMatrix = PeakMatrix,
                                      expMatrix = GeneExpressionMatrix,
                                      reducedDim = reducedDimMatrix,
                                      exp_assay = "normalizedCounts",
                                      peak_assay = "counts",
                                      BPPARAM = BiocParallel::SerialParam(progressbar = FALSE))
    
    # Save optimization plot
    pdf("metacell_optimization_plot.pdf")
    plot(cellNum)
    dev.off()
    
    # -----------------------------------------------------------------------------
    # --- Calculate Peak-to-Gene (P2G) links ---
    # -----------------------------------------------------------------------------
    message("Calculating Peak-to-Gene links...")
    set.seed(1010)
    p2g <- calculateP2G(peakMatrix = PeakMatrix, 
                        expMatrix = GeneExpressionMatrix, 
                        reducedDim = reducedDimMatrix,
                        exp_assay = "normalizedCounts",
                        peak_assay = "counts",
                        cellNum = cellNum,
                        BPPARAM = BiocParallel::SerialParam(progressbar = FALSE))
    
    # Save P2G links
    saveRDS(p2g, "p2g_links.rds")
    write.csv(as.data.frame(p2g), "p2g_links.csv", row.names = FALSE)
    
    # -----------------------------------------------------------------------------
    # --- Add TF binding information to peaks ---
    # -----------------------------------------------------------------------------
    message("Adding TF motif information to peaks...")
    overlap <- addTFMotifInfo(grl = grl, 
                              p2g = p2g, 
                              peakMatrix = PeakMatrix)
    
    # Save overlap information
    saveRDS(overlap, "tf_peak_overlap.rds")
    write.csv(as.data.frame(overlap), "tf_peak_overlap.csv", row.names = FALSE)
    
    # -----------------------------------------------------------------------------
    # --- Generate regulons ---
    # -----------------------------------------------------------------------------
    message("Generating regulons...")
    regulon <- getRegulon(p2g = p2g, 
                          overlap = overlap)
    
    # Save initial regulons
    saveRDS(regulon, "initial_regulon.rds")
    
    # -----------------------------------------------------------------------------
    # --- Network pruning ---
    # -----------------------------------------------------------------------------
    message("Pruning regulon network...")
    # Ensure Clusters column exists in GeneExpressionMatrix
    if (!"Clusters" %in% colnames(colData(GeneExpressionMatrix))) {
      stop("GeneExpressionMatrix must contain a 'Clusters' column in colData for pruning.")
    }
    
    pruned.regulon <- pruneRegulon(expMatrix = GeneExpressionMatrix,
                                   exp_assay = "normalizedCounts",
                                   peakMatrix = PeakMatrix,
                                   peak_assay = "counts",
                                   test = "chi.sq",
                                   regulon = regulon,
                                   clusters = GeneExpressionMatrix\$Clusters,
                                   prune_value = "pval",
                                   regulon_cutoff = 0.05
                                   )
    
    # Save pruned regulons
    saveRDS(pruned.regulon, "pruned_regulon.rds")
    
    # -----------------------------------------------------------------------------
    # --- Estimate regulatory weights ---
    # -----------------------------------------------------------------------------
    message("Estimating regulatory weights...")
    regulon.w <- addWeights(regulon = pruned.regulon,
                            expMatrix  = GeneExpressionMatrix,
                            exp_assay  = "normalizedCounts",
                            peakMatrix = PeakMatrix,
                            peak_assay = "counts",
                            clusters = GeneExpressionMatrix\$Clusters,
                            method = "wilcox")
    
    # Save weighted regulons
    saveRDS(regulon.w, "weighted_regulon.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 8: (Optional) Annotate peaks with motifs
    # -----------------------------------------------------------------------------
    message("Annotating peaks with motifs...")
    tryCatch({
      regulon.w.motif <- addMotifScore(regulon = regulon.w,
                                       peaks = rowRanges(PeakMatrix),
                                       species = "human",
                                       genome = "hg38")
    
      regulon.w.motif\$weight[regulon.w.motif\$motif == 0] <- 0
      saveRDS(regulon.w.motif, "weighted_regulon_motif.rds")
    }, error = function(e) {
      warning("Failed to annotate peaks with motifs: ", e\$message)
    })
    
    # -----------------------------------------------------------------------------
    # Stage 9: (Optional) Calculate log fold changes
    # -----------------------------------------------------------------------------
    message("Calculating log fold changes...")
    GeneExpressionMatrix <- scuttle::logNormCounts(GeneExpressionMatrix)
    
    # Ensure Clusters column exists in GeneExpressionMatrix
    if ("Clusters" %in% colnames(colData(GeneExpressionMatrix))) {
      regulon.w <- addLogFC(regulon = regulon.w,
                            clusters = GeneExpressionMatrix\$Clusters,
                            expMatrix  = GeneExpressionMatrix,
                            assay.type  = "logcounts",
                            pval.type = "any")
      saveRDS(regulon.w, "weighted_regulon_with_logFC.rds")
    } else {
      warning("Clusters column not found in GeneExpressionMatrix. Skipping addLogFC.")
    }
    
    # -----------------------------------------------------------------------------
    # --- Calculate TF activity scores ---
    # -----------------------------------------------------------------------------
    message("Calculating TF activity scores...")
    score.combine <- calculateActivity(expMatrix = GeneExpressionMatrix,
                                       regulon = regulon.w, 
                                       mode = "weight", 
                                       method = "weightedMean", 
                                       exp_assay = "normalizedCounts",
                                       normalize = FALSE)
    
    # Save final activity scores
    saveRDS(score.combine, "tf_activity_scores.rds")
    
    message("Pipeline completed successfully!")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_EPIREGULON_SC_MULTIOMIC_TF_ACTIVITY_INFERENCE",
      domain  = "bioconductor",
      declared_qc_steps = c("count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_EPIREGULON_SC_MULTIOMIC_TF_ACTIVITY_INFERENCE":',
        paste0('    epiregulon: ', as.character(packageVersion('epiregulon')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sc_multiomic_tf_activity_inference.csv versions.yml
    """
}

workflow BIOC_EPIREGULON_SC_MULTIOMIC_TF_ACTIVITY_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ PeakMatrix, GeneExpressionMatrix, reducedDimMatrix ] ]

    main:
    BIOC_EPIREGULON_SC_MULTIOMIC_TF_ACTIVITY_INFERENCE(ch_input)

    emit:
    tables   = BIOC_EPIREGULON_SC_MULTIOMIC_TF_ACTIVITY_INFERENCE.out.tables
    plots    = BIOC_EPIREGULON_SC_MULTIOMIC_TF_ACTIVITY_INFERENCE.out.plots
    objects  = BIOC_EPIREGULON_SC_MULTIOMIC_TF_ACTIVITY_INFERENCE.out.objects
    versions = BIOC_EPIREGULON_SC_MULTIOMIC_TF_ACTIVITY_INFERENCE.out.versions
}
