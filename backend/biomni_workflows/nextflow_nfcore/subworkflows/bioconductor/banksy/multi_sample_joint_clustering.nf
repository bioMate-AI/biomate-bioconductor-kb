#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Banksy — multi_sample_joint_clustering
// Jointly cluster multiple spatial transcriptomics samples with optional spatial label smoothing.
// Input: spe_list
// Container: quay.io/biocontainers/bioconductor-banksy:1.6.0--r45hdfd78af_0
// R packages: Banksy, SpatialExperiment, SummarizedExperiment, cowplot, ggplot2, scater
// Bioconductor: 3.20 | R: 4.4
// Requires: Banksy, SpatialExperiment, SummarizedExperiment, cowplot, ggplot2, scater
// Visualizations: cluster plot
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute BANKSY neighborhood feature matrices for each sample separately
//  * 2. [Core Analysis] Merge samples into a joint object
//  * 3. [Core Analysis] Run joint PCA with sample grouping
//  * 4. [Core Analysis] Run joint UMAP
//  * 5. [Core Analysis] Cluster the joint embedding
//  * 6. [Core Analysis] Connect clusters across runs
//  * 7. [Core Analysis] Split the joint object back into individual samples
//  * 8. [Core Analysis] Smooth cluster labels per sample
//  * 9. [Core Analysis] Compare clusters using Adjusted Rand Index (ARI)

nextflow.enable.dsl = 2

process BIOC_BANKSY_MULTI_SAMPLE_JOINT_CLUSTERING {
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
    .bm_deps <- c("Banksy", "SpatialExperiment", "SummarizedExperiment", "cowplot", "ggplot2", "scater")
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
    library(Banksy)
    library(SummarizedExperiment)
    library(SpatialExperiment)
    library(scater)
    library(cowplot)
    library(ggplot2)
    
    # ==========================================
    # 1. Load User Input
    # ==========================================
    # Read the list of SpatialExperiment objects from the working directory
    spe_list <- readRDS("spe_list.rds")
    
    # ==========================================
    # 2. Define Parameters
    # ==========================================
    # Determine assay name dynamically (default to "normcounts" if present, otherwise use the first available assay)
    aname <- "normcounts"
    if (!aname %in% assayNames(spe_list[[1]])) {
      aname <- assayNames(spe_list[[1]])[1]
    }
    
    compute_agf <- FALSE
    k_geom <- 6
    use_agf <- FALSE
    lambda <- 0.2
    res <- 0.7
    cnm <- sprintf("clust_M%s_lam%s_k50_res%s", as.numeric(use_agf), lambda, res)
    
    # Extract sample names dynamically from the input list
    sample_names <- unique(unlist(lapply(spe_list, function(x) unique(x\$sample_id))))
    
    # ==========================================
    # 3. Run BANKSY Multi-Sample Pipeline
    # ==========================================
    
    # Compute BANKSY neighborhood feature matrices for each sample separately
    spe_list <- lapply(spe_list, computeBanksy, assay_name = aname, compute_agf = compute_agf, k_geom = k_geom)
    
    # Merge samples into a joint object
    spe_joint <- do.call(cbind, spe_list)
    
    # Run joint PCA with sample grouping
    spe_joint <- runBanksyPCA(spe_joint, use_agf = use_agf, lambda = lambda, group = "sample_id", seed = 1000)
    
    # Run joint UMAP
    spe_joint <- runBanksyUMAP(spe_joint, use_agf = use_agf, lambda = lambda, seed = 1000)
    
    # Cluster the joint embedding
    spe_joint <- clusterBanksy(spe_joint, use_agf = use_agf, lambda = lambda, resolution = res, seed = 1000)
    
    # Connect clusters across runs
    spe_joint <- connectClusters(spe_joint)
    
    # Split the joint object back into individual samples
    spe_list <- lapply(sample_names, function(x) spe_joint[, spe_joint\$sample_id == x])
    
    # Smooth cluster labels per sample
    spe_list <- lapply(spe_list, smoothLabels, cluster_names = cnm, k = 6L, verbose = FALSE)
    
    # Set names for the list of samples
    names(spe_list) <- paste0("sample_", sample_names)
    
    # Compare clusters using Adjusted Rand Index (ARI)
    ari_comparison <- compareClusters(spe_list[[1]], func = 'ARI')
    
    # ==========================================
    # 4. Save Outputs
    # ==========================================
    
    # Save joint and split SpatialExperiment objects
    saveRDS(spe_joint, "spe_joint_clustered.rds")
    saveRDS(spe_list, "spe_list_smoothed.rds")
    
    # Save ARI comparison matrix
    write.csv(as.data.frame(ari_comparison), paste0("ari_comparison_", names(spe_list)[1], ".csv"), row.names = TRUE)
    
    # Generate and save spatial visualization plots
    pdf("spatial_clusters_visualization.pdf", width = 4 * length(spe_list), height = 4)
    plot_list <- lapply(names(spe_list), function(snm) {
      x <- spe_list[[snm]]
      spatial_cols <- colnames(spatialCoords(x))
      df <- cbind.data.frame(
        clust = colData(x)[[sprintf("%s_smooth", cnm)]],
        spatialCoords(x)
      )
      ggplot(df, aes(x = .data[[spatial_cols[1]]], y = .data[[spatial_cols[2]]], col = clust)) +
        geom_point(size = 0.5) +
        theme_classic() +
        labs(title = paste("Sample:", snm), col = "Cluster") +
        coord_equal()
    })
    print(cowplot::plot_grid(plotlist = plot_list, ncol = length(spe_list)))
    dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cqc_obj <- tryCatch(readRDS(.cqc_rds), error = function(e) NULL)
      .cqc_mat <- if (is.matrix(.cqc_obj) || is.data.frame(.cqc_obj)) .cqc_obj else NULL
      if (!is.null(.cqc_mat) && nrow(.cqc_mat) > 100) {
        .cqc_ncells <- ncol(.cqc_mat); .cqc_nfeats <- nrow(.cqc_mat)
        .cqc_files <- c(.cqc_files, .cqc_rds); break
      }
    }
    .gates_by_label[["cell QC metrics"]] <- list(
      gate_row = "bioc_cell_qc_metrics",
      metric_name = "n_cells",
      metric_value = .cqc_ncells,
      passes = isTRUE(is.finite(.cqc_ncells) && .cqc_ncells >= 50 && .cqc_nfeats >= 200),
      status = if (is.finite(.cqc_ncells)) paste0("computed (cells=", .cqc_ncells, ", features=", .cqc_nfeats, "; proxy gate)")
               else "not_computed (no scRNA matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_BANKSY_MULTI_SAMPLE_JOINT_CLUSTERING",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_BANKSY_MULTI_SAMPLE_JOINT_CLUSTERING":',
        paste0('    Banksy: ', as.character(packageVersion('Banksy')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_sample_joint_clustering.csv versions.yml
    """
}

workflow BIOC_BANKSY_MULTI_SAMPLE_JOINT_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spe_list ] ]

    main:
    BIOC_BANKSY_MULTI_SAMPLE_JOINT_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_BANKSY_MULTI_SAMPLE_JOINT_CLUSTERING.out.tables
    plots    = BIOC_BANKSY_MULTI_SAMPLE_JOINT_CLUSTERING.out.plots
    objects  = BIOC_BANKSY_MULTI_SAMPLE_JOINT_CLUSTERING.out.objects
    versions = BIOC_BANKSY_MULTI_SAMPLE_JOINT_CLUSTERING.out.versions
}
