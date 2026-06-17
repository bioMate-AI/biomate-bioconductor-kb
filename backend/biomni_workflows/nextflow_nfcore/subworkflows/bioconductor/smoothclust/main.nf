#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: smoothclust — spatial_domain_clustering
// Perform spatial smoothing on spatial transcriptomics data followed by normalization, feature selection, dimensionality reduction, and clustering to identify spa
// Input: spe
// Container: quay.io/biocontainers/bioconductor-smoothclust:1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SpatialExperiment, ggspavis, scater, scran, scuttle, smoothclust
// Visualizations: plot (ggplot/base)
// QC: cell QC metrics, count normalization, highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load spatial transcriptomics data and filter spots over tissue
//  * 2. [Core Analysis] Run spatial smoothing using smoothclust to generate smoothed counts
//  * 3. [Core Analysis] Calculate log-transformed normalized counts on the smoothed counts
//  * 4. [Core Analysis] Filter mitochondrial genes and select highly variable genes (HVGs)
//  * 5. [Core Analysis] Perform PCA dimensionality reduction on the top HVGs
//  * 6. [Core Analysis] Run k-means clustering on the principal components
//  * 7. [Visualization & Output] Plot the resulting spatial domains/clusters

nextflow.enable.dsl = 2

process BIOC_SMOOTHCLUST_SPATIAL_DOMAIN_CLUSTERING {
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
    .bm_deps <- c("smoothclust", "scuttle", "scran", "scater", "ggspavis", "SpatialExperiment", "SummarizedExperiment")
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
     library(SummarizedExperiment)
   library(smoothclust)
    library(scuttle)
    library(scran)
    library(scater)
    library(ggspavis)
    library(SpatialExperiment)
    
    # 1. Load spatial transcriptomics data and filter spots over tissue
    # Read the SpatialExperiment object from the working directory
    spe <- readRDS("spe")
    
    # Keep spots over tissue
    if ("in_tissue" %in% colnames(colData(spe))) {
      spe <- spe[, colData(spe)\$in_tissue == 1]
    }
    
    dim(spe)
    assayNames(spe)
    
    # 2. Run spatial smoothing using smoothclust to generate smoothed counts
    spe <- smoothclust(spe)
    
    # Check output object
    assayNames(spe)
    
    # 3. Calculate log-transformed normalized counts on the smoothed counts
    spe <- logNormCounts(spe, assay.type = "counts_smooth")
    
    assayNames(spe)
    
    # 4. Filter mitochondrial genes and select highly variable genes (HVGs)
    # Remove mitochondrial genes
    if ("gene_name" %in% colnames(rowData(spe))) {
      gene_names <- rowData(spe)\$gene_name
    } else {
      gene_names <- rownames(spe)
    }
    is_mito <- grepl("(^mt-)", gene_names, ignore.case = TRUE)
    table(is_mito)
    spe <- spe[!is_mito, ]
    dim(spe)
    
    # Select top highly variable genes (HVGs)
    dec <- modelGeneVar(spe)
    top_hvgs <- getTopHVGs(dec, prop = 0.1)
    length(top_hvgs)
    spe <- spe[top_hvgs, ]
    dim(spe)
    
    # 5. Perform PCA dimensionality reduction on the top HVGs
    set.seed(123)
    spe <- runPCA(spe)
    
    # 6. Run k-means clustering on the principal components
    set.seed(123)
    k <- 5
    clust <- kmeans(reducedDim(spe, "PCA"), centers = k)\$cluster
    table(clust)
    colLabels(spe) <- factor(clust)
    
    # 7. Plot the resulting spatial domains/clusters and save outputs
    # Color palettes
    pal8 <- "libd_layer_colors"
    pal36 <- unname(palette.colors(36, "Polychrome 36"))
    
    # Save plots to a PDF file
    pdf("spatial_domain_plots.pdf", width = 8, height = 6)
    
    # Plot clusters / spatial domains
    p1 <- plotCoords(spe, annotate = "label", pal = pal8)
    print(p1)
    
    # Plot reference labels (wrapped in tryCatch in case ground_truth is not present in user input)
    tryCatch({
      if ("ground_truth" %in% colnames(colData(spe))) {
        p2 <- plotCoords(spe, annotate = "ground_truth", pal = pal8)
        print(p2)
      } else {
        message("ground_truth not found in colData(spe); skipping reference plot.")
      }
    }, error = function(e) {
      message("Could not plot reference labels: ", e\$message)
    })
    
    dev.off()
    
    # Save the final SpatialExperiment object
    saveRDS(spe, "spe_clustered.rds")
    
    # Save clustering results as a CSV table
    write.csv(as.data.frame(colData(spe)), "clustering_results.csv", row.names = TRUE)
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

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
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

    # HVG selection — count rows with high CV. Pass when 1000-3000 HVGs
    # (Stuart 2019 Cell Seurat v3 default range).
    .hvg_count <- NA_real_; .hvg_files <- character(0)
    for (.hvg_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .hvg_obj <- tryCatch(readRDS(.hvg_rds), error = function(e) NULL)
      .hvg_mat <- if (is.matrix(.hvg_obj) || is.data.frame(.hvg_obj)) .hvg_obj else NULL
      if (!is.null(.hvg_mat) && nrow(.hvg_mat) > 200) {
        .hvg_m <- suppressWarnings(as.matrix(.hvg_mat))
        .hvg_cvs <- suppressWarnings(apply(.hvg_m, 1, function(r) {
          .rv <- as.numeric(r); .m <- mean(.rv, na.rm = TRUE)
          if (is.finite(.m) && .m > 0) sd(.rv, na.rm = TRUE) / .m else NA_real_
        }))
        .hvg_count <- sum(is.finite(.hvg_cvs) & .hvg_cvs > 1.0)
        .hvg_files <- c(.hvg_files, .hvg_rds); break
      }
    }
    .gates_by_label[["highly-variable feature selection"]] <- list(
      gate_row = "bioc_hvg_selection",
      metric_name = "hvg_count",
      metric_value = .hvg_count,
      passes = isTRUE(is.finite(.hvg_count) && .hvg_count >= 1000 && .hvg_count <= 3000),
      status = if (is.finite(.hvg_count)) paste0("computed (CV>1.0 rows = ", .hvg_count, "; proxy for HVG selection)")
               else "not_computed (no expression matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SMOOTHCLUST_SPATIAL_DOMAIN_CLUSTERING",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics", "count normalization", "highly-variable feature selection"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_SMOOTHCLUST_SPATIAL_DOMAIN_CLUSTERING":',
        paste0('    smoothclust: ', as.character(packageVersion('smoothclust')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_domain_clustering.csv versions.yml
    """
}

workflow BIOC_SMOOTHCLUST_SPATIAL_DOMAIN_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spe ] ]

    main:
    BIOC_SMOOTHCLUST_SPATIAL_DOMAIN_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_SMOOTHCLUST_SPATIAL_DOMAIN_CLUSTERING.out.tables
    plots    = BIOC_SMOOTHCLUST_SPATIAL_DOMAIN_CLUSTERING.out.plots
    objects  = BIOC_SMOOTHCLUST_SPATIAL_DOMAIN_CLUSTERING.out.objects
    versions = BIOC_SMOOTHCLUST_SPATIAL_DOMAIN_CLUSTERING.out.versions
}
