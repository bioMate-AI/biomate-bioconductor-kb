#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: corral — single_dataset_dimension_reduction
// Perform correspondence analysis (CA) for dimensionality reduction on a single single-cell dataset.
// Input: zm4eq.sce, zm4eq.countmat
// Container: quay.io/biocontainers/bioconductor-corral:1.20.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, corral, ggplot2, gridExtra, scater
// Visualizations: plot (ggplot/base)
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run corral on the SingleCellExperiment specifying the count assay
//  * 2. [Visualization & Output] Visualize the embedding using plot_embedding_sce
//  * 3. [Visualization & Output] Run downstream visualization like UMAP or tSNE using scater on the corral reduced dimension
//  * 4. [Visualization & Output] Run corral on a raw count matrix to get coordinates and SVD output
//  * 5. [Visualization & Output] Generate a biplot using biplot_corral to visualize links between features and cells

nextflow.enable.dsl = 2

process BIOC_CORRAL_SINGLE_DATASET_DIMENSION_REDUCTION {
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
    .bm_deps <- c("corral", "ggplot2", "scater", "gridExtra", "SummarizedExperiment")
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
        library(corral)
        library(ggplot2)
        library(scater)
        library(gridExtra)
        
        # Read user input files from the working directory
        zm4eq.sce <- readRDS("zm4eq.sce")
        zm4eq.countmat <- readRDS("zm4eq.countmat")
        
        # 1. Run corral on the SingleCellExperiment specifying the count assay
        zm4eq.sce <- corral(inp = zm4eq.sce, 
                            whichmat = 'counts')
        
        # Set up PDF device to save all generated plots
        pdf("corral_analysis_plots.pdf", width = 11, height = 8)
        
        # 2. Visualize the embedding using plot_embedding_sce
        plot_embedding_sce(sce = zm4eq.sce,
                           which_embedding = 'corral',
                           plot_title = 'corral on Zhengmix4eq',
                           color_attr = 'phenoid',
                           color_title = 'cell type',
                           saveplot = FALSE)
        
        # 3. Run downstream visualization like UMAP or tSNE using scater on the corral reduced dimension
        zm4eq.sce <- runUMAP(zm4eq.sce,
                             dimred = 'corral',
                             name = 'corral_UMAP')
        zm4eq.sce <- runTSNE(zm4eq.sce,
                             dimred = 'corral',
                             name = 'corral_TSNE')
        
        ggplot_umap <- plot_embedding_sce(sce = zm4eq.sce,
                                          which_embedding = 'corral_UMAP',
                                          plot_title = 'Zhengmix4eq corral with UMAP',
                                          color_attr = 'phenoid',
                                          color_title = 'cell type',
                                          returngg = TRUE,
                                          showplot = FALSE,
                                          saveplot = FALSE)
        
        ggplot_tsne <- plot_embedding_sce(sce = zm4eq.sce,
                                          which_embedding = 'corral_TSNE',
                                          plot_title = 'Zhengmix4eq corral with tSNE',
                                          color_attr = 'phenoid',
                                          color_title = 'cell type',
                                          returngg = TRUE,
                                          showplot = FALSE,
                                          saveplot = FALSE)
        
        gridExtra::grid.arrange(ggplot_umap, ggplot_tsne, ncol = 2)
        
        # 4. Run corral on a raw count matrix to get coordinates and SVD output
        zm4eq.countcorral <- corral(zm4eq.countmat)
        
        celltype_vec <- zm4eq.sce\$phenoid
        plot_embedding(embedding = zm4eq.countcorral\$v,
                       plot_title = 'corral on Zhengmix4eq',
                       color_vec = celltype_vec,
                       color_title = 'cell type',
                       saveplot = FALSE)
        
        # 5. Generate a biplot using biplot_corral to visualize links between features and cells
        gene_names <- rowData(zm4eq.sce)\$symbol
        
        biplot_corral(corral_obj = zm4eq.countcorral, color_vec = celltype_vec, text_vec = gene_names)
        
        # Close the PDF plotting device
        dev.off()
        
        # Save processed RDS objects
        saveRDS(zm4eq.sce, "zm4eq_processed.sce.rds")
        saveRDS(zm4eq.countcorral, "zm4eq_countcorral.rds")
        
        # Export low-dimensional embeddings to CSV files
        write.csv(as.data.frame(reducedDim(zm4eq.sce, "corral")), "corral_sce_embeddings.csv", row.names = TRUE)
        write.csv(as.data.frame(zm4eq.countcorral\$v), "corral_matrix_v_embeddings.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_CORRAL_SINGLE_DATASET_DIMENSION_REDUCTION":',
        paste0('    corral: ', as.character(packageVersion('corral')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_dataset_dimension_reduction.csv versions.yml
    """
}

workflow BIOC_CORRAL_SINGLE_DATASET_DIMENSION_REDUCTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ zm4eq.sce, zm4eq.countmat ] ]

    main:
    BIOC_CORRAL_SINGLE_DATASET_DIMENSION_REDUCTION(ch_input)

    emit:
    tables   = BIOC_CORRAL_SINGLE_DATASET_DIMENSION_REDUCTION.out.tables
    plots    = BIOC_CORRAL_SINGLE_DATASET_DIMENSION_REDUCTION.out.plots
    objects  = BIOC_CORRAL_SINGLE_DATASET_DIMENSION_REDUCTION.out.objects
    versions = BIOC_CORRAL_SINGLE_DATASET_DIMENSION_REDUCTION.out.versions
}
