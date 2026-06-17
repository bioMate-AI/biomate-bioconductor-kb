#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: celda — decontx_decontamination
// Estimate and remove ambient RNA contamination from single-cell RNA-seq data and visualize the decontamination results.
// Input: sce, sce.raw
// Container: quay.io/biocontainers/bioconductor-celda:1.26.0--r45ha27e39d_0
// R packages: SingleCellExperiment, celda
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, celda
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run decontX with or without background counts
//  * 2. [Core Analysis] Retrieve decontaminated counts using decontXcounts
//  * 3. [Visualization & Output] Visualize cell clusters and contamination levels on UMAP using plotDimReduceCluster and plotDecontXContamination
//  * 4. [Visualization & Output] Compare marker gene expression before and after decontamination using plotDecontXMarkerPercentage and plotDecontXMarkerExpression
//  * 5. [Core Analysis] (Optional) Adjust priors using the delta parameter to force more aggressive decontamination

nextflow.enable.dsl = 2

process BIOC_CELDA_DECONTX_DECONTAMINATION {
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
    .bm_deps <- c("SingleCellExperiment", "celda")
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
        library(celda)
        
        # 1. Load User Input Files
        if (!file.exists("sce.rds")) {
          stop("Error: 'sce.rds' containing the SingleCellExperiment object is required in the working directory.")
        }
        
        sce <- readRDS("sce.rds")
        
        # Ensure the counts assay is present and named correctly
        if (!"counts" %in% assayNames(sce)) {
          if (length(assayNames(sce)) > 0) {
            assayNames(sce)[1] <- "counts"
          } else {
            stop("Error: The input SingleCellExperiment object must contain at least one count assay.")
          }
        }
        
        # Handle optional background counts and run decontX
        if (file.exists("sce.raw.rds")) {
          sce.raw <- readRDS("sce.raw.rds")
          if (!"counts" %in% assayNames(sce.raw)) {
            if (length(assayNames(sce.raw)) > 0) {
              assayNames(sce.raw)[1] <- "counts"
            }
          }
          # 2. Run decontX with background counts
          sce <- decontX(sce, background = sce.raw)
        } else {
          # 2. Run decontX without background counts
          sce <- decontX(sce)
        }
        
        # Retrieve decontaminated counts
        decont_counts <- decontXcounts(sce)
        saveRDS(decont_counts, "decontX_counts.rds")
        
        # 3. Dynamic Setup for Markers and Cell Type Mappings to Ensure Robustness
        if (is.null(rownames(sce))) {
          rownames(sce) <- paste0("Gene_", seq_len(nrow(sce)))
        }
        all_genes <- rownames(sce)
        
        # Define standard markers from the vignette
        markers <- list(
          Tcell_Markers = c("CD3E", "CD3D"),
          Bcell_Markers = c("CD79A", "CD79B", "MS4A1"),
          Monocyte_Markers = c("S100A8", "S100A9", "LYZ"),
          NKcell_Markers = "GNLY"
        )
        
        # Filter to markers present in the dataset
        markers <- lapply(markers, function(g) g[g %in% all_genes])
        
        # Fallback if none of the standard markers are present
        if (sum(lengths(markers)) == 0) {
          markers <- list(
            Tcell_Markers = all_genes[1:min(2, length(all_genes))],
            Bcell_Markers = all_genes[min(3, length(all_genes)):min(5, length(all_genes))],
            Monocyte_Markers = all_genes[min(6, length(all_genes)):min(8, length(all_genes))],
            NKcell_Markers = all_genes[min(9, length(all_genes))]
          )
        }
        
        # Ensure Monocyte_Markers is populated for the specific violin plot call
        if (length(markers[["Monocyte_Markers"]]) == 0) {
          markers[["Monocyte_Markers"]] <- all_genes[1:min(3, length(all_genes))]
        }
        
        # Map cell clusters dynamically based on decontX output
        clusters <- unique(sce\$decontX_clusters)
        cellTypeMappings <- list()
        if (length(clusters) >= 1) cellTypeMappings\$Monocytes <- clusters[1]
        if (length(clusters) >= 2) cellTypeMappings\$Tcells <- clusters[2]
        if (length(clusters) >= 3) cellTypeMappings\$Bcells <- clusters[3]
        if (length(clusters) >= 4) cellTypeMappings\$NKcells <- clusters[4]
        
        if (length(cellTypeMappings) == 0) {
          cellTypeMappings <- list(AllCells = 1)
        }
        
        # 4. Visualization
        pdf("decontx_decontamination_plots.pdf", width = 10, height = 8)
        
        # Retrieve UMAP coordinates
        umap <- reducedDim(sce, "decontX_UMAP")
        
        # Plot cell clusters on UMAP
        print(plotDimReduceCluster(x = sce\$decontX_clusters, dim1 = umap[, 1], dim2 = umap[, 2]))
        
        # Plot contamination levels on UMAP
        print(plotDecontXContamination(sce))
        
        # Compare marker gene expression percentages before and after decontamination
        print(plotDecontXMarkerPercentage(sce, markers = markers, groupClusters = cellTypeMappings, assayName = "counts"))
        print(plotDecontXMarkerPercentage(sce, markers = markers, groupClusters = cellTypeMappings, assayName = "decontXcounts"))
        print(plotDecontXMarkerPercentage(sce, markers = markers, groupClusters = cellTypeMappings, assayName = c("counts", "decontXcounts")))
        
        # Compare marker gene expression distributions using violin plots
        print(plotDecontXMarkerExpression(sce, markers = markers[["Monocyte_Markers"]], groupClusters = cellTypeMappings, ncol = 3))
        
        dev.off()
        
        # 5. Adjust priors using the delta parameter for aggressive decontamination
        sce.delta <- decontX(sce, delta = c(9, 20), estimateDelta = FALSE)
        
        # Save final SingleCellExperiment objects
        saveRDS(sce, "sce_decontX.rds")
        saveRDS(sce.delta, "sce_decontX_delta.rds")

    writeLines(c(
        '"BIOC_CELDA_DECONTX_DECONTAMINATION":',
        paste0('    celda: ', as.character(packageVersion('celda')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_decontx_decontamination.csv versions.yml
    """
}

workflow BIOC_CELDA_DECONTX_DECONTAMINATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce, sce.raw ] ]

    main:
    BIOC_CELDA_DECONTX_DECONTAMINATION(ch_input)

    emit:
    tables   = BIOC_CELDA_DECONTX_DECONTAMINATION.out.tables
    plots    = BIOC_CELDA_DECONTX_DECONTAMINATION.out.plots
    objects  = BIOC_CELDA_DECONTX_DECONTAMINATION.out.objects
    versions = BIOC_CELDA_DECONTX_DECONTAMINATION.out.versions
}
