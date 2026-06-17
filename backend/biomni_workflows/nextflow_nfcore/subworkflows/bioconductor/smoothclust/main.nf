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

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
