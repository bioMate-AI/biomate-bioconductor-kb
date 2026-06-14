#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: muscat — differential_state_and_detection
// Perform differential state (DS), differential detection (DD), and joint stagewise DS-DD analysis on multi-sample multi-condition single-cell RNA-seq data.
// Input: counts.csv, coldata.csv
// Container: 1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, dplyr, ggplot2, muscat, patchwork, scater, scuttle, tidyr
// Visualizations: MDS plot, heatmap
// QC: per-cell QC metrics, outlier detection, low-count filtering, cell QC metrics, count normalization
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MUSCAT_DIFFERENTIAL_STATE_AND_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("scater", "scuttle", "muscat", "dplyr", "tidyr", "ggplot2", "patchwork")
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
    
    library(scater)
    library(scuttle)
    library(muscat)
    library(dplyr)
    library(tidyr)
    library(ggplot2)
    library(patchwork)
    
    # --- Load data ---
    counts <- read.csv("counts.csv", check.names = FALSE)
    if ("gene_id" %in% colnames(counts)) {
      rownames(counts) <- counts\$gene_id
      counts\$gene_id <- NULL
    } else {
      rownames(counts) <- counts[, 1]
      counts <- counts[, -1, drop = FALSE]
    }
    
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    if (colnames(coldata)[1] == "X" || colnames(coldata)[1] == "") {
      rownames(coldata) <- coldata[, 1]
      coldata <- coldata[, -1, drop = FALSE]
    } else if (!any(colnames(coldata) == "cell_id") && nrow(coldata) == ncol(counts)) {
      rownames(coldata) <- colnames(counts)
    } else if ("cell_id" %in% colnames(coldata)) {
      rownames(coldata) <- coldata\$cell_id
    } else {
      rownames(coldata) <- coldata[, 1]
    }
    
    # Ensure alignment
    common_cells <- intersect(colnames(counts), rownames(coldata))
    counts <- counts[, common_cells, drop = FALSE]
    coldata <- coldata[common_cells, drop = FALSE]
    
    # Create SingleCellExperiment
    sce <- SingleCellExperiment(assays = list(counts = as.matrix(counts)), colData = coldata)
    
    # --- QC and Filtering ---
    sce <- sce[rowSums(counts(sce) > 0) > 0, ]
    qc <- perCellQCMetrics(sce)
    ol <- isOutlier(metric = qc\$detected, nmads = 2, log = TRUE)
    sce <- sce[, !ol]
    sce <- sce[rowSums(counts(sce) > 1) >= 5, ]
    
    # --- Normalization & Clustering (to get cluster_id) ---
    sce <- logNormCounts(sce)
    sce <- runPCA(sce, ncomponents = 10)
    
    # Perform simple k-means clustering on PCA to get cluster_id
    pca_coords <- reducedDim(sce, "PCA")
    num_clusters <- min(3, ncol(sce))
    set.seed(42)
    clusters <- kmeans(pca_coords, centers = num_clusters)\$cluster
    sce\$cluster_id <- factor(paste0("cluster_", clusters))
    
    # Map sample and group IDs
    sce\$sample_id <- factor(sce\$sample)
    sce\$group_id <- factor(sce\$condition)
    
    # Prepare SCE for muscat
    sce <- prepSCE(sce, kid = "cluster_id", sid = "sample_id", gid = "group_id", drop = TRUE)
    
    # --- Pseudobulk Aggregation ---
    # For DS (sum of counts)
    pb_sum <- aggregateData(sce, assay = "counts", fun = "sum", by = c("cluster_id", "sample_id"))
    # For DD (number of detected cells)
    pb_det <- aggregateData(sce, assay = "counts", fun = "num.detected", by = c("cluster_id", "sample_id"))
    
    # --- MDS Plot ---
    pdf("pb_mds_plot.pdf", width = 8, height = 6)
    tryCatch({
      p_mds_sum <- pbMDS(pb_sum) + ggtitle("MDS: Sum of Counts")
      p_mds_det <- pbMDS(pb_det) + ggtitle("MDS: Number of Detected Cells")
      print(p_mds_sum + p_mds_det)
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("MDS Plot omitted:\n", e\$message), cex = 1.2)
    })
    dev.off()
    
    # --- Differential State (DS) Analysis ---
    res_DS <- pbDS(pb_sum, min_cells = 0, filter = "none", verbose = FALSE)
    tbl_DS <- tryCatch({
      resDS(sce, res_DS, bind = "row")
    }, error = function(e) {
      data.frame(gene = character(), cluster_id = character(), logFC = numeric(), p_val = numeric(), p_adj.loc = numeric())
    })
    write.csv(tbl_DS, "ds_results.csv", row.names = FALSE)
    
    # --- Differential Detection (DD) Analysis ---
    res_DD <- pbDD(pb_det, min_cells = 0, filter = "none", verbose = FALSE)
    tbl_DD <- tryCatch({
      resDS(sce, res_DD, bind = "row")
    }, error = function(e) {
      data.frame(gene = character(), cluster_id = character(), logFC = numeric(), p_val = numeric(), p_adj.loc = numeric())
    })
    write.csv(tbl_DD, "dd_results.csv", row.names = FALSE)
    
    # --- Stagewise DS-DD Analysis ---
    res_stage <- tryCatch({
      stagewise_DS_DD(res_DS, res_DD, verbose = FALSE)
    }, error = function(e) {
      NULL
    })
    
    if (!is.null(res_stage)) {
      stage_list <- lapply(names(res_stage), function(contrast) {
        contrast_res <- res_stage[[contrast]]
        lapply(names(contrast_res), function(cluster) {
          df <- contrast_res[[cluster]]
          df_std <- as.data.frame(df)
          df_std\$res_DS <- NULL
          df_std\$res_DD <- NULL
          df_std
        }) %>% bind_rows()
      }) %>% bind_rows()
      write.csv(stage_list, "stagewise_results.csv", row.names = FALSE)
    } else {
      write.csv(data.frame(Status = "Stagewise analysis skipped or failed"), "stagewise_results.csv", row.names = FALSE)
    }
    
    # --- Visualization: Heatmap of top DS genes ---
    pdf("top_genes_heatmap.pdf", width = 10, height = 8)
    tryCatch({
      p_heat <- pbHeatmap(sce, res_DS, top_n = 5)
      print(p_heat)
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("Heatmap omitted:\n", e\$message), cex = 1.2)
    })
    dev.off()

    writeLines(c(
        '"BIOC_MUSCAT_DIFFERENTIAL_STATE_AND_DETECTION":',
        paste0('    muscat: ', as.character(packageVersion('muscat')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_state_and_detection.csv versions.yml
    """
}

workflow BIOC_MUSCAT_DIFFERENTIAL_STATE_AND_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_MUSCAT_DIFFERENTIAL_STATE_AND_DETECTION(ch_input)

    emit:
    tables   = BIOC_MUSCAT_DIFFERENTIAL_STATE_AND_DETECTION.out.tables
    plots    = BIOC_MUSCAT_DIFFERENTIAL_STATE_AND_DETECTION.out.plots
    objects  = BIOC_MUSCAT_DIFFERENTIAL_STATE_AND_DETECTION.out.objects
    versions = BIOC_MUSCAT_DIFFERENTIAL_STATE_AND_DETECTION.out.versions
}
