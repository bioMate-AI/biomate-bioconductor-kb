#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Banksy — single_sample_spatial_clustering
// Perform spatially-informed cell-typing or domain segmentation on a single spatial transcriptomics sample.
// Input: gcm_path, mdata_path
// Container: quay.io/biocontainers/bioconductor-banksy:1.6.0--r45hdfd78af_0
// R packages: Banksy, cowplot, data.table, ExperimentHub, ggplot2, scater, Seurat, SpatialExperiment, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: Banksy, SpatialExperiment, SummarizedExperiment, data.table, ggplot2, scater
// Visualizations: cluster plot
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and preprocess data into a SpatialExperiment object
//  * 2. [Core Analysis] Compute neighborhood feature matrices
//  * 3. [Core Analysis] Run PCA on the BANKSY matrix
//  * 4. [Core Analysis] Cluster the BANKSY embedding
//  * 5. [Core Analysis] Relabel clusters to minimize differences
//  * 6. [Visualization & Output] Compare cluster outputs using Adjusted Rand Index (ARI)

nextflow.enable.dsl = 2

process BIOC_BANKSY_SINGLE_SAMPLE_SPATIAL_CLUSTERING {
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
    .bm_deps <- c("Banksy", "cowplot", "data.table", "ExperimentHub", "ggplot2", "scater", "Seurat", "SpatialExperiment", "SummarizedExperiment")
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
        library(Banksy)
        library(SummarizedExperiment)
        library(data.table)
        library(SpatialExperiment)
        library(scater)
        library(ggplot2)
        
        # Define input file paths in the working directory
        gcm_path <- "gcm_path.csv"
        mdata_path <- "mdata_path.csv"
        
        # Check if input files exist
        if (!file.exists(gcm_path)) {
            stop(paste("Error: Input file not found:", gcm_path))
        }
        if (!file.exists(mdata_path)) {
            stop(paste("Error: Input file not found:", mdata_path))
        }
        
        # 1. Load and preprocess data into a SpatialExperiment object
        message("Loading gene expression matrix...")
        gcm_dt <- data.table::fread(gcm_path)
        if ("GENE" %in% colnames(gcm_dt)) {
            genes <- gcm_dt\$GENE
            gcm <- as.matrix(gcm_dt[, -1, with = FALSE])
            rownames(gcm) <- genes
        } else {
            genes <- gcm_dt[[1]]
            gcm <- as.matrix(gcm_dt[, -1, with = FALSE])
            rownames(gcm) <- genes
        }
        
        message("Loading spatial coordinates and metadata...")
        mdata <- data.table::fread(mdata_path)
        mdata <- data.frame(mdata)
        rownames(mdata) <- colnames(gcm)
        
        # Identify spatial coordinate columns robustly
        if (all(c("X", "Y", "Z") %in% colnames(mdata))) {
            locs <- as.matrix(mdata[, c("X", "Y", "Z")])
        } else if (all(c("X", "Y") %in% colnames(mdata))) {
            locs <- as.matrix(mdata[, c("X", "Y")])
        } else if (all(c("sdimx", "sdimy") %in% colnames(mdata))) {
            locs <- as.matrix(mdata[, c("sdimx", "sdimy")])
        } else {
            numeric_cols <- colnames(mdata)[sapply(mdata, is.numeric)]
            if (length(numeric_cols) >= 2) {
                locs <- as.matrix(mdata[, numeric_cols[1:2]])
            } else {
                stop("Error: Could not identify spatial coordinate columns in metadata.")
            }
        }
        
        # Define parameters
        lambda <- c(0, 0.8)
        k_geom <- 30
        npcs <- 50
        aname <- "processedExp"
        
        message("Initializing SpatialExperiment object...")
        se <- SpatialExperiment(
            assay = list(processedExp = gcm),
            spatialCoords = locs,
            colData = mdata
        )
        
        # 2. Compute neighborhood feature matrices
        message("Computing BANKSY neighborhood feature matrices...")
        se <- Banksy::computeBanksy(se, assay_name = aname, k_geom = k_geom)
        
        # 3. Run PCA on the BANKSY matrix
        message("Running PCA on the BANKSY matrix...")
        set.seed(1000)
        se <- Banksy::runBanksyPCA(se, lambda = lambda, npcs = npcs)
        
        # 4. Cluster the BANKSY embedding
        message("Clustering the BANKSY embedding...")
        set.seed(1000)
        se <- Banksy::clusterBanksy(se, lambda = lambda, npcs = npcs, resolution = 0.8)
        
        # 5. Relabel clusters to minimize differences
        message("Relabeling clusters to minimize differences...")
        se <- connectClusters(se)
        
        # 6. Compare cluster outputs using Adjusted Rand Index (ARI)
        message("Comparing cluster outputs using Adjusted Rand Index (ARI)...")
        ari_matrix <- compareClusters(se, func = "ARI")
        
        # Save outputs
        message("Saving results...")
        
        # Save the SpatialExperiment object
        saveRDS(se, file = "banksy_spatial_experiment.rds")
        
        # Save cluster labels and metadata
        write.csv(as.data.frame(colData(se)), file = "banksy_clustered_metadata.csv", row.names = TRUE)
        
        # Save ARI comparison matrix
        write.csv(as.data.frame(ari_matrix), file = "ari_comparison_matrix.csv", row.names = TRUE)
        
        # Generate and save spatial clustering plot
        cnames <- colnames(colData(se))
        cnames <- cnames[grep("^clust", cnames)]
        
        if (length(cnames) > 0) {
            pdf("banksy_clusters_spatial_plot.pdf", width = 8, height = 7)
            plot_df <- data.frame(
                X = spatialCoords(se)[, 1],
                Y = spatialCoords(se)[, 2],
                Cluster = as.factor(colData(se)[[cnames[1]]])
            )
            p <- ggplot(plot_df, aes(x = X, y = Y, color = Cluster)) +
                geom_point(size = 0.5, alpha = 0.8) +
                theme_classic() +
                coord_equal() +
                labs(
                    title = "BANKSY Spatial Domain Segmentation",
                    subtitle = paste("Parameter: lambda =", paste(lambda, collapse = ", "), "| Resolution = 0.8"),
                    x = "Spatial X",
                    y = "Spatial Y"
                ) +
                theme(legend.position = "right")
            print(p)
            dev.off()
            message("Spatial plot saved to 'banksy_clusters_spatial_plot.pdf'")
        }
        
        message("Pipeline completed successfully!")
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
      process = "BIOC_BANKSY_SINGLE_SAMPLE_SPATIAL_CLUSTERING",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_BANKSY_SINGLE_SAMPLE_SPATIAL_CLUSTERING":',
        paste0('    Banksy: ', as.character(packageVersion('Banksy')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_sample_spatial_clustering.csv versions.yml
    """
}

workflow BIOC_BANKSY_SINGLE_SAMPLE_SPATIAL_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gcm_path, mdata_path ] ]

    main:
    BIOC_BANKSY_SINGLE_SAMPLE_SPATIAL_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_BANKSY_SINGLE_SAMPLE_SPATIAL_CLUSTERING.out.tables
    plots    = BIOC_BANKSY_SINGLE_SAMPLE_SPATIAL_CLUSTERING.out.plots
    objects  = BIOC_BANKSY_SINGLE_SAMPLE_SPATIAL_CLUSTERING.out.objects
    versions = BIOC_BANKSY_SINGLE_SAMPLE_SPATIAL_CLUSTERING.out.versions
}
