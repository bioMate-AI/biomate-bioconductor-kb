#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clustifyr — correlation_based_annotation
// Annotate cell clusters from a normalized count matrix and metadata table using a reference expression matrix.
// Input: pbmc_matrix, pbmc_meta, cbmc_ref
// Container: quay.io/biocontainers/bioconductor-clustifyr:1.22.0--r45hdfd78af_0
// R packages: Matrix, clustifyr, cowplot, ggplot2, SingleCellExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: Matrix, clustifyr, cowplot, ggplot2
// Visualizations: heatmap, UMAP plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate correlation coefficients for each cluster using clustify
//  * 2. [Core Analysis] Call cell types from the correlation matrix using cor_to_call
//  * 3. [Core Analysis] Insert called cell types back into the metadata using call_to_metadata
//  * 4. [Visualization & Output] Visualize correlation coefficients and cell type assignments using plot_cor_heatmap, plot_cor, plot_best_call, and plot_dims

nextflow.enable.dsl = 2

process BIOC_CLUSTIFYR_CORRELATION_BASED_ANNOTATION {
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
    .bm_deps <- c("Matrix", "clustifyr", "cowplot", "ggplot2", "SingleCellExperiment")
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
        library(clustifyr)
        library(ggplot2)
        library(cowplot)
        library(Matrix)
        
        # Helper function to read inputs robustly
        read_input <- function(file_base) {
          if (file.exists(paste0(file_base, ".rds"))) {
            return(readRDS(paste0(file_base, ".rds")))
          }
          if (file.exists(paste0(file_base, ".csv"))) {
            return(read.csv(paste0(file_base, ".csv"), row.names = 1, check.names = FALSE))
          }
          if (file.exists(paste0(file_base, ".tsv"))) {
            return(read.delim(paste0(file_base, ".tsv"), row.names = 1, check.names = FALSE))
          }
          if (file.exists(file_base)) {
            res <- tryCatch(readRDS(file_base), error = function(e) NULL)
            if (!is.null(res)) return(res)
            res <- tryCatch(read.csv(file_base, row.names = 1, check.names = FALSE), error = function(e) NULL)
            if (!is.null(res)) return(res)
            stop(paste("Could not read file:", file_base))
          }
          stop(paste("File not found:", file_base))
        }
        
        # Read user inputs
        pbmc_matrix <- read_input("pbmc_matrix")
        pbmc_meta <- read_input("pbmc_meta")
        cbmc_ref <- read_input("cbmc_ref")
        
        # Ensure correct formats
        if (!is.matrix(pbmc_matrix) && !inherits(pbmc_matrix, "sparseMatrix")) {
          pbmc_matrix <- as.matrix(pbmc_matrix)
        }
        if (!is.matrix(cbmc_ref)) {
          cbmc_ref <- as.matrix(cbmc_ref)
        }
        pbmc_meta <- as.data.frame(pbmc_meta)
        
        # Dynamically determine the cluster column (use the first column of metadata)
        cluster_col <- colnames(pbmc_meta)[1]
        
        # Calculate highly variable genes (vargenes) from the input matrix
        # to replace the bundled 'pbmc_vargenes'
        if (inherits(pbmc_matrix, "sparseMatrix")) {
          mean_val <- Matrix::rowMeans(pbmc_matrix)
          var_val <- Matrix::rowSums(pbmc_matrix^2)/(ncol(pbmc_matrix)-1) - (mean_val^2)*ncol(pbmc_matrix)/(ncol(pbmc_matrix)-1)
          names(var_val) <- rownames(pbmc_matrix)
        } else {
          var_val <- apply(pbmc_matrix, 1, var)
        }
        var_val[is.na(var_val)] <- 0
        vargenes <- names(sort(var_val, decreasing = TRUE))[1:min(500, length(var_val))]
        
        # 1. Calculate correlation coefficients for each cluster using clustify
        res <- clustify(
            input = pbmc_matrix, # matrix of normalized scRNA-seq counts (or SCE/Seurat object)
            metadata = pbmc_meta, # meta.data table containing cell clusters
            cluster_col = cluster_col, # name of column in meta.data containing cell clusters
            ref_mat = cbmc_ref, # matrix of RNA-seq expression data for each cell type
            query_genes = vargenes # list of highly varible genes identified with Seurat
        )
        
        # Peek at correlation matrix
        res[1:min(5, nrow(res)), 1:min(5, ncol(res))]
        
        # 2. Call cell types from the correlation matrix using cor_to_call
        res2 <- cor_to_call(
            cor_mat = res, # matrix correlation coefficients
            cluster_col = cluster_col # name of column in meta.data containing cell clusters
        )
        res2[1:min(5, nrow(res2)), ]
        
        # 3. Insert called cell types back into the metadata using call_to_metadata
        pbmc_meta2 <- call_to_metadata(
            res = res2, # data.frame of called cell type for each cluster
            metadata = pbmc_meta, # original meta.data table containing cell clusters
            cluster_col = cluster_col # name of column in meta.data containing cell clusters
        )
        
        # Save tabular outputs
        write.csv(res, "correlation_matrix.csv", row.names = TRUE)
        write.csv(res2, "cell_type_assignments.csv", row.names = FALSE)
        write.csv(pbmc_meta2, "annotated_metadata.csv", row.names = TRUE)
        
        # 4. Visualize correlation coefficients and cell type assignments
        # Create heatmap of correlation coefficients using clustifyr() output
        pdf("correlation_heatmap.pdf", width = 7, height = 5)
        print(plot_cor_heatmap(cor_mat = res))
        dev.off()
        
        # Overlay correlation coefficients on UMAPs for the first two cell types
        corr_umaps <- plot_cor(
            cor_mat = res, # matrix of correlation coefficients from clustifyr()
            metadata = pbmc_meta, # meta.data table containing UMAP or tSNE data
            data_to_plot = colnames(res)[1:2], # name of cell type(s) to plot correlation coefficients
            cluster_col = cluster_col # name of column in meta.data containing cell clusters
        )
        
        pdf("correlation_umaps.pdf", width = 9, height = 3.5)
        print(plot_grid(
            plotlist = corr_umaps,
            rel_widths = c(0.47, 0.53)
        ))
        dev.off()
        
        # Label clusters with clustifyr cell identities
        clustifyr_types <- plot_best_call(
            cor_mat = res, # matrix of correlation coefficients from clustifyr()
            metadata = pbmc_meta, # meta.data table containing UMAP or tSNE data
            do_label = TRUE, # should the feature label be shown on each cluster?
            do_legend = FALSE, # should the legend be shown?
            do_repel = FALSE, # use ggrepel to avoid overlapping labels
            cluster_col = cluster_col
        ) +
            ggtitle("clustifyr cell types")
        
        # Compare clustifyr results with known cell identities
        known_types <- plot_dims(
            data = pbmc_meta, # meta.data table containing UMAP or tSNE data
            feature = cluster_col, # name of column in meta.data to color clusters by
            do_label = TRUE, # should the feature label be shown on each cluster?
            do_legend = FALSE, # should the legend be shown?
            do_repel = FALSE
        ) +
            ggtitle("Known cell types")
        
        pdf("cell_type_comparison.pdf", width = 12, height = 5.5)
        print(plot_grid(known_types, clustifyr_types))
        dev.off()

    writeLines(c(
        '"BIOC_CLUSTIFYR_CORRELATION_BASED_ANNOTATION":',
        paste0('    clustifyr: ', as.character(packageVersion('clustifyr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_correlation_based_annotation.csv versions.yml
    """
}

workflow BIOC_CLUSTIFYR_CORRELATION_BASED_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmc_matrix, pbmc_meta, cbmc_ref ] ]

    main:
    BIOC_CLUSTIFYR_CORRELATION_BASED_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_CLUSTIFYR_CORRELATION_BASED_ANNOTATION.out.tables
    plots    = BIOC_CLUSTIFYR_CORRELATION_BASED_ANNOTATION.out.plots
    objects  = BIOC_CLUSTIFYR_CORRELATION_BASED_ANNOTATION.out.objects
    versions = BIOC_CLUSTIFYR_CORRELATION_BASED_ANNOTATION.out.versions
}
