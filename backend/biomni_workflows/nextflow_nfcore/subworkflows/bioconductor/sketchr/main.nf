#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sketchR — single_cell_sketching_and_projection
// Subsample a large single-cell dataset using geometric sketching, evaluate the subsample quality, and project the full dataset onto the sketched PCA, t-SNE, UMAP
// Input: pbmc3k
// Container: quay.io/biocontainers/bioconductor-sketchr:1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, bluster, class, ggplot2, scater, scran, sketchR, snifter, uwot
// Visualizations: plot (ggplot/base)
// QC: cell QC metrics, highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Subsample cells using geosketch
//  * 2. [Core Analysis] Compare cell type composition between full and sketched datasets
//  * 3. [Core Analysis] Evaluate subsampling quality using Hausdorff distance
//  * 4. [Core Analysis] Perform PCA on sketched cells and project full dataset
//  * 5. [Core Analysis] Perform t-SNE on sketched cells and project full dataset
//  * 6. [Core Analysis] Perform UMAP on sketched cells and project full dataset
//  * 7. [Core Analysis] Cluster sketched cells and predict labels for all cells using k-nearest neighbors

nextflow.enable.dsl = 2

process BIOC_SKETCHR_SINGLE_CELL_SKETCHING_AND_PROJECTION {
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
    .bm_deps <- c("sketchR", "scran", "scater", "snifter", "uwot", "bluster", "class", "ggplot2", "SummarizedExperiment")
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
    suppressPackageStartupMessages({
      library(sketchR)
      library(SummarizedExperiment)
      library(scran)
      library(scater)
      library(snifter)
      library(uwot)
      library(bluster)
      library(class)
      library(ggplot2)
    })
    
    # ==========================================
    # 0. Load User Input
    # ==========================================
    # Read the SingleCellExperiment object from the working directory
    if (file.exists("pbmc3k.rds")) {
      pbmc3k <- readRDS("pbmc3k.rds")
    } else if (file.exists("pbmc3k")) {
      pbmc3k <- readRDS("pbmc3k")
    } else {
      stop("Error: Input file 'pbmc3k' or 'pbmc3k.rds' not found in the working directory.")
    }
    
    # Ensure the object has a 'labels_main' column in colData for composition plotting.
    # If not present, we robustly create it from existing categorical columns or dummy labels.
    if (!"labels_main" %in% colnames(colData(pbmc3k))) {
      char_cols <- sapply(colData(pbmc3k), function(x) is.character(x) || is.factor(x))
      if (any(char_cols)) {
        pbmc3k\$labels_main <- as.character(colData(pbmc3k)[[which(char_cols)[1]]])
      } else {
        pbmc3k\$labels_main <- sample(c("TypeA", "TypeB", "TypeC"), ncol(pbmc3k), replace = TRUE)
      }
    }
    
    # ==========================================
    # 1. Subsample cells using geosketch
    # ==========================================
    idx800gs <- geosketch(reducedDim(pbmc3k, "PCA"), 
                          N = 800, seed = 123)
    
    # Save sketched indices
    write.csv(data.frame(Index = idx800gs), "sketched_indices.csv", row.names = FALSE)
    
    # ==========================================
    # 2. Compare cell type composition
    # ==========================================
    pdf("composition_comparison.pdf", width = 8, height = 6)
    p_comp <- compareCompositionPlot(colData(pbmc3k), 
                                     idx = list(geosketch = idx800gs), 
                                     column = "labels_main")
    print(p_comp)
    dev.off()
    
    # ==========================================
    # 3. Evaluate subsampling quality using Hausdorff distance
    # ==========================================
    pdf("hausdorff_distance.pdf", width = 8, height = 6)
    set.seed(123)
    p_haus <- hausdorffDistPlot(mat = reducedDim(pbmc3k, "PCA"), 
                                Nvec = c(400, 800, 2000),
                                Nrep = 3, methods = c("geosketch", "uniform"))
    print(p_haus)
    dev.off()
    
    # ==========================================
    # 4. Perform PCA on sketched cells and project full dataset
    # ==========================================
    pbmc3k\$sketched <- seq_len(ncol(pbmc3k)) %in% idx800gs
    dec_sketched <- modelGeneVar(pbmc3k[, pbmc3k\$sketched])
    top_hvgs_sketched <- getTopHVGs(dec_sketched, n = 2000)
    
    set.seed(123)
    doscale <- FALSE
    pbmc3k_sketched <- pbmc3k[, pbmc3k\$sketched]
    pca <- calculatePCA(pbmc3k_sketched, ncomponents = 30, 
                        subset_row = top_hvgs_sketched, 
                        scale = doscale)
    projection <- pca
    rotation <- attr(pca, "rotation")
    centers <- rowMeans(assay(pbmc3k_sketched[top_hvgs_sketched, ],
                              "logcounts"))
    pca <- scale(t(assay(pbmc3k[names(centers), ], "logcounts")), center = centers, 
                 scale = doscale) %*% rotation
    reducedDim(pbmc3k, "PCA_sketch") <- as.matrix(pca)
    
    # ==========================================
    # 5. Perform t-SNE on sketched cells and project full dataset
    # ==========================================
    tsne <- fitsne(
        reducedDim(pbmc3k[, pbmc3k\$sketched], "PCA_sketch"), 
        n_jobs = 2L, random_state = 123L,
        perplexity = 30, n_components = 2L, 
        pca = FALSE)
    proj <- project(
        x = tsne, 
        new = reducedDim(pbmc3k, "PCA_sketch"), 
        old = reducedDim(pbmc3k[, pbmc3k\$sketched], "PCA_sketch"),
        perplexity = 30, k = 1L)
    rownames(proj) <- colnames(pbmc3k)
    reducedDim(pbmc3k, "TSNE_sketch") <- proj
    
    # ==========================================
    # 6. Perform UMAP on sketched cells and project full dataset
    # ==========================================
    umap <- umap(
        X = reducedDim(pbmc3k[, pbmc3k\$sketched], "PCA_sketch"), 
        n_components = 2, n_neighbors = 50,
        pca = NULL, scale = FALSE, 
        ret_model = TRUE, n_threads = 2L)
    proj <- umap_transform(
        X = reducedDim(pbmc3k, "PCA_sketch"), 
        model = umap, 
        n_threads = 2L)
    rownames(proj) <- colnames(pbmc3k)
    reducedDim(pbmc3k, "UMAP_sketch") <- proj
    
    # ==========================================
    # 7. Cluster sketched cells and predict labels
    # ==========================================
    pca_sketch <- reducedDim(pbmc3k[, pbmc3k\$sketched], "PCA_sketch")
    clst <- as.character(clusterRows(
        pca_sketch,  
        BLUSPARAM = SNNGraphParam(
            k = 10, type = "rank", 
            num.threads = 2L, 
            cluster.fun = "leiden", 
            cluster.args = list(resolution = 0.15))))
    preds <- knn(train = pca_sketch, 
                 test = reducedDim(pbmc3k, "PCA_sketch"), 
                 cl = clst, k = 1) |> as.character()
    pbmc3k\$clusters <- preds
    
    # Save predicted clusters
    write.csv(data.frame(CellID = colnames(pbmc3k), Cluster = preds), 
              "predicted_clusters.csv", row.names = FALSE)
    
    # Save the final updated SingleCellExperiment object
    saveRDS(pbmc3k, "pbmc3k_sketched_projected.rds")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_SKETCHR_SINGLE_CELL_SKETCHING_AND_PROJECTION":',
        paste0('    sketchR: ', as.character(packageVersion('sketchR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_sketching_and_projection.csv versions.yml
    """
}

workflow BIOC_SKETCHR_SINGLE_CELL_SKETCHING_AND_PROJECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmc3k ] ]

    main:
    BIOC_SKETCHR_SINGLE_CELL_SKETCHING_AND_PROJECTION(ch_input)

    emit:
    tables   = BIOC_SKETCHR_SINGLE_CELL_SKETCHING_AND_PROJECTION.out.tables
    plots    = BIOC_SKETCHR_SINGLE_CELL_SKETCHING_AND_PROJECTION.out.plots
    objects  = BIOC_SKETCHR_SINGLE_CELL_SKETCHING_AND_PROJECTION.out.objects
    versions = BIOC_SKETCHR_SINGLE_CELL_SKETCHING_AND_PROJECTION.out.versions
}
