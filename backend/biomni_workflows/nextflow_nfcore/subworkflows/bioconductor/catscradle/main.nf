#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CatsCradle — gene_clustering_and_annotation
// Transpose a cell-by-gene expression matrix to cluster genes, visualize them, and analyze their relationship with cell clusters.
// Input: cell_seurat_object.rds
// Container: quay.io/biocontainers/bioconductor-catscradle:1.4.2--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CatsCradle, Seurat, htmlwidgets
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Transpose the Seurat object using transposeObject
//  * 2. [Core Analysis] Calculate average expression of gene clusters across cell clusters using getAverageExpressionMatrix
//  * 3. [Core Analysis] Tag row and column names using tagRowAndColNames
//  * 4. [Core Analysis] Generate a Sankey graph using sankeyFromMatrix
//  * 5. [Core Analysis] Calculate gene clustering significance using getObjectSubsetClusteringStatistics or getObjectSubsetClusteringPValue
//  * 6. [Core Analysis] Find subclusters within a gene subset using getSubsetComponents
//  * 7. [Core Analysis] Calculate mean z-scores per cluster on UMAP using meanZPerClusterOnUMAP

nextflow.enable.dsl = 2

process BIOC_CATSCRADLE_GENE_CLUSTERING_AND_ANNOTATION {
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
    .bm_deps <- c("CatsCradle", "Seurat", "htmlwidgets")
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
    library(CatsCradle, quietly = TRUE)
    library(Seurat, quietly = TRUE)
    library(htmlwidgets, quietly = TRUE)
    
    # 1. Read the user input file
    if (!file.exists("cell_seurat_object.rds")) {
      stop("Error: 'cell_seurat_object.rds' not found in the working directory.")
    }
    exSeuratObj = readRDS("cell_seurat_object.rds")
    
    # Ensure the Seurat object has the required metadata and active idents
    if (is.null(Seurat::Idents(exSeuratObj))) {
      if ("seurat_clusters" %in% colnames(exSeuratObj@meta.data)) {
        Seurat::Idents(exSeuratObj) <- exSeuratObj\$seurat_clusters
      } else {
        Seurat::Idents(exSeuratObj) <- factor(rep("Cluster1", ncol(exSeuratObj)))
      }
    }
    exSeuratObj\$shortName = as.character(Seurat::Idents(exSeuratObj))
    
    # 2. Execute the documented workflow steps exactly as specified
    STranspose = transposeObject (exSeuratObj)
    
    averageExpMatrix = getAverageExpressionMatrix (exSeuratObj,STranspose, layer= 'data' )
    
    averageExpMatrix = tagRowAndColNames (averageExpMatrix, ccTag= 'cellClusters_' , gcTag= 'geneClusters_' )
    
    catsCradle = sankeyFromMatrix (averageExpMatrix, disambiguation= c ( 'cells_' , 'genes_' ), plus= 'cyan' , minus= 'pink' , height= 800 )
    
    # Define gene subsets for downstream analysis based on the transposed object
    available_genes = colnames(STranspose)
    g2mGenes = head(available_genes, min(50, length(available_genes)))
    idx = colnames(STranspose) %in% g2mGenes
    theSubset = head(available_genes, min(30, length(available_genes)))
    alpha = 0.5
    
    stats = getObjectSubsetClusteringStatistics (STranspose, g2mGenes, numTrials= 1000 )
    
    pValue = getObjectSubsetClusteringPValue (STranspose,idx)
    
    clusters = getSubsetComponents (STranspose,theSubset,alpha)
    
    meanZDF = meanZPerClusterOnUMAP (exSeuratObj, STranspose, 'shortName' )
    
    # 3. Write outputs to files
    saveRDS(STranspose, "STranspose.rds")
    write.csv(averageExpMatrix, "average_expression_matrix.csv", row.names = TRUE)
    htmlwidgets::saveWidget(catsCradle, "catsCradle_sankey.html", selfcontained = TRUE)
    
    if (is.list(stats)) {
      saveRDS(stats, "clustering_stats.rds")
      if ("randomSubsetDistance" %in% names(stats)) {
        write.csv(data.frame(randomSubsetDistance = stats\$randomSubsetDistance), "random_subset_distances.csv", row.names = FALSE)
      }
    } else {
      saveRDS(stats, "clustering_stats.rds")
    }
    
    write.csv(data.frame(pValue = pValue), "clustering_p_value.csv", row.names = FALSE)
    saveRDS(clusters, "subclusters.rds")
    write.csv(meanZDF, "mean_z_scores_umap.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_CATSCRADLE_GENE_CLUSTERING_AND_ANNOTATION":',
        paste0('    CatsCradle: ', as.character(packageVersion('CatsCradle')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_clustering_and_annotation.csv versions.yml
    """
}

workflow BIOC_CATSCRADLE_GENE_CLUSTERING_AND_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cell_seurat_object.rds ] ]

    main:
    BIOC_CATSCRADLE_GENE_CLUSTERING_AND_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_CATSCRADLE_GENE_CLUSTERING_AND_ANNOTATION.out.tables
    plots    = BIOC_CATSCRADLE_GENE_CLUSTERING_AND_ANNOTATION.out.plots
    objects  = BIOC_CATSCRADLE_GENE_CLUSTERING_AND_ANNOTATION.out.objects
    versions = BIOC_CATSCRADLE_GENE_CLUSTERING_AND_ANNOTATION.out.versions
}
