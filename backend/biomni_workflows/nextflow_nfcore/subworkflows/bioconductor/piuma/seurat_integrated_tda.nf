#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PIUMA — seurat_integrated_tda
// Integrate PIUMA's geometry-informed TDA clustering into a standard Seurat single-cell RNA-seq workflow.
// Input: pbmc3k
// Container: quay.io/biocontainers/bioconductor-piuma:1.5.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: PIUMA, Seurat, SummarizedExperiment, aricode, dplyr, ggplot2, ggrepel, mclust, patchwork, viridis
// Visualizations: UMAP/t-SNE plot, UMAP plot
// QC: highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess the Seurat object (normalize, scale, find variable features, run PCA and UMAP)
//  * 2. [Visualization & Output] Convert the Seurat object into a SummarizedExperiment
//  * 3. [Visualization & Output] Initialize the TDAobj from the SummarizedExperiment
//  * 4. [Input & Preparation] Compute the distance matrix and import Seurat's UMAP coordinates as the projection lens
//  * 5. [Core Analysis] Run the Mapper algorithm
//  * 6. [Core Analysis] Calculate the Jaccard similarity matrix, set the graph, and predict the mapper class
//  * 7. [Core Analysis] Perform community detection using a specified method (e.g., walktrap)
//  * 8. [Core Analysis] Map the identified TDA clusters back to the Seurat object metadata for downstream analysis

nextflow.enable.dsl = 2

process BIOC_PIUMA_SEURAT_INTEGRATED_TDA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("Seurat", "PIUMA", "ggplot2", "dplyr", "ggrepel", "mclust", "aricode", "viridis", "patchwork")
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
    library(Seurat)
    library(PIUMA)
    library(ggplot2)
    library(dplyr)
    library(ggrepel)
    library(mclust)
    library(aricode)
    library(viridis)
    library(patchwork)
    
    # Set seed for reproducibility
    set.seed(42)
    
    # -----------------------------------------------------------------------------
    # 1. Load User Input
    # -----------------------------------------------------------------------------
    if (file.exists("pbmc3k.rds")) {
      pbmc3k <- readRDS("pbmc3k.rds")
    } else if (file.exists("pbmc3k")) {
      pbmc3k <- readRDS("pbmc3k")
    } else {
      stop("Error: Required input file 'pbmc3k.rds' or 'pbmc3k' not found in the working directory.")
    }
    
    # Ensure 'seurat_annotations' column exists in metadata
    if (!"seurat_annotations" %in% colnames(pbmc3k@meta.data)) {
      if ("seurat_clusters" %in% colnames(pbmc3k@meta.data)) {
        pbmc3k@meta.data\$seurat_annotations <- pbmc3k@meta.data\$seurat_clusters
      } else {
        pbmc3k@meta.data\$seurat_annotations <- Idents(pbmc3k)
      }
    }
    
    # -----------------------------------------------------------------------------
    # 2. Preprocess the Seurat Object
    # -----------------------------------------------------------------------------
    pbmc3k <- UpdateSeuratObject(pbmc3k)
    pbmc3k <- NormalizeData(pbmc3k)
    pbmc3k <- ScaleData(pbmc3k)
    pbmc3k <- FindVariableFeatures(pbmc3k)
    pbmc3k <- RunPCA(pbmc3k)
    pbmc3k <- RunUMAP(pbmc3k, dims = 1:20)
    
    # Extract counts and logcounts layers safely for Seurat v4/v5 compatibility
    if (.hasSlot(pbmc3k@assays\$RNA, "layers")) {
      counts_mat <- pbmc3k@assays\$RNA@layers\$counts
      logcounts_mat <- pbmc3k@assays\$RNA@layers\$data
      
      colnames(counts_mat) <- rownames(pbmc3k@meta.data)
      colnames(logcounts_mat) <- rownames(pbmc3k@meta.data)
      
      feat_names <- NULL
      if (.hasSlot(pbmc3k@assays\$RNA, "features")) {
        feat_names <- rownames(pbmc3k@assays\$RNA@features@.Data)
      }
      if (is.null(feat_names)) {
        feat_names <- rownames(pbmc3k)
      }
      rownames(counts_mat) <- feat_names
      rownames(logcounts_mat) <- feat_names
    } else {
      counts_mat <- pbmc3k@assays\$RNA@counts
      logcounts_mat <- pbmc3k@assays\$RNA@data
      
      colnames(counts_mat) <- rownames(pbmc3k@meta.data)
      colnames(logcounts_mat) <- rownames(pbmc3k@meta.data)
      
      rownames(counts_mat) <- rownames(pbmc3k)
      rownames(logcounts_mat) <- rownames(pbmc3k)
    }
    
    counts_dense    <- as.matrix(counts_mat)
    logcounts_dense <- as.matrix(logcounts_mat)
    cell_meta     <- pbmc3k@meta.data
    
    gene_meta     <- DataFrame(
      gene_id = rownames(counts_mat),
      row.names = rownames(counts_mat)
    )
    
    # -----------------------------------------------------------------------------
    # 3. Convert to SummarizedExperiment and Initialize TDA Object
    # -----------------------------------------------------------------------------
    se <- SummarizedExperiment(
      assays   = list(
        counts    = counts_dense,
        logcounts = logcounts_dense
      ),
      colData = cell_meta,
      rowData = gene_meta
    )
    
    colData(se)\$seurat_annotations <- factor(
      ifelse(
        is.na(colData(se)\$seurat_annotations),
        "Unknown",
        as.character(colData(se)\$seurat_annotations)
      )
    )
    
    tda_obj <- makeTDAobjFromSE(se, 'seurat_annotations')
    
    # -----------------------------------------------------------------------------
    # 4. Distance Matrix and UMAP Projection Lens
    # -----------------------------------------------------------------------------
    tda_obj <- dfToDistance(tda_obj, distMethod = "euclidean")
    umap <- pbmc3k@reductions\$umap@cell.embeddings
    colnames(umap) <- c('comp1', 'comp2')
    
    tda_obj@comp <- as.data.frame(umap)
    
    # -----------------------------------------------------------------------------
    # 5. Run Mapper Algorithm and Community Detection
    # -----------------------------------------------------------------------------
    tda_obj <- mapperCore(x = tda_obj, nBins = 33, overlap = 0.15)
    tda_obj <- jaccardMatrix(tda_obj)
    tda_obj <- setGraph(tda_obj)
    tda_obj <- predict_mapper_class(tda_obj)
    tda_obj <- autoClusterMapper(tda_obj, method = 'walktrap')
    
    # -----------------------------------------------------------------------------
    # 6. Map TDA Clusters Back to Seurat Object
    # -----------------------------------------------------------------------------
    clusters_piuma <- tda_obj@clustering\$obs_cluster
    all_cells     <- rownames(pbmc3k@meta.data)
    piuma_clusters <- setNames(
      rep(NA_integer_, length(all_cells)),
      all_cells
    )
    piuma_clusters[ clusters_piuma\$obs ] <- clusters_piuma\$cluster
    pbmc3k@meta.data\$PIUMA_clusters <- as.factor(piuma_clusters)
    
    # -----------------------------------------------------------------------------
    # 7. Save Outputs and Generate Plots
    # -----------------------------------------------------------------------------
    # Save RDS objects
    saveRDS(pbmc3k, "pbmc3k_piuma.rds")
    saveRDS(tda_obj, "tda_obj.rds")
    
    # Save cluster assignments table
    cluster_assignments <- data.frame(
      Cell = rownames(pbmc3k@meta.data),
      Seurat_Annotation = pbmc3k@meta.data\$seurat_annotations,
      PIUMA_Cluster = pbmc3k@meta.data\$PIUMA_clusters
    )
    write.csv(cluster_assignments, "piuma_cluster_assignments.csv", row.names = FALSE)
    
    # Calculate and save concordance metrics (ARI & NMI)
    valid <- which(!is.na(pbmc3k\$seurat_annotations) & !is.na(pbmc3k\$PIUMA_clusters))
    if (length(valid) > 0) {
      ari <- mclust::adjustedRandIndex(pbmc3k\$seurat_annotations[valid], pbmc3k\$PIUMA_clusters[valid])
      nmi <- aricode::NMI(pbmc3k\$seurat_annotations[valid], pbmc3k\$PIUMA_clusters[valid])
      metrics_df <- data.frame(Metric = c("ARI", "NMI"), Value = c(ari, nmi))
      write.csv(metrics_df, "clustering_concordance_metrics.csv", row.names = FALSE)
    }
    
    # Generate and save comparison UMAP plot
    pdf("piuma_vs_seurat_umap.pdf", width = 12, height = 6)
    p1 <- DimPlot(pbmc3k, group.by = 'PIUMA_clusters', label = TRUE, label.box = TRUE, repel = TRUE) + 
      ggtitle("PIUMA TDA Clusters")
    p2 <- DimPlot(pbmc3k, group.by = 'seurat_annotations', label = TRUE, label.box = TRUE, repel = TRUE) + 
      ggtitle("Original Seurat Annotations")
    print(p1 + p2)
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_PIUMA_SEURAT_INTEGRATED_TDA":',
        paste0('    PIUMA: ', as.character(packageVersion('PIUMA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seurat_integrated_tda.csv versions.yml
    """
}

workflow BIOC_PIUMA_SEURAT_INTEGRATED_TDA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmc3k ] ]

    main:
    BIOC_PIUMA_SEURAT_INTEGRATED_TDA(ch_input)

    emit:
    tables   = BIOC_PIUMA_SEURAT_INTEGRATED_TDA.out.tables
    plots    = BIOC_PIUMA_SEURAT_INTEGRATED_TDA.out.plots
    objects  = BIOC_PIUMA_SEURAT_INTEGRATED_TDA.out.objects
    versions = BIOC_PIUMA_SEURAT_INTEGRATED_TDA.out.versions
}
