#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SpatialDecon — geomx_set_workflow
// Perform spatial deconvolution, cell type collapsing, tumor profile merging, and reverse deconvolution using a NanoStringGeoMxSet object.
// Input: nsclc
// Container: quay.io/biocontainers/bioconductor-spatialdecon:1.20.0--r45hdfd78af_0
// R packages: GeomxTools, Seurat, SeuratObject, SpatialDecon
// Bioconductor: 3.20 | R: 4.4
// Requires: GeomxTools, SpatialDecon
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Update and prepare the GeoMxSet object
//  * 2. [Core Analysis] Estimate background using derive_GeoMx_background
//  * 3. [Core Analysis] Run basic deconvolution using runspatialdecon
//  * 4. [Core Analysis] Run advanced deconvolution with tumor modeling, cell merging, and cell count estimation using runspatialdecon
//  * 5. [Visualization & Output] Plot results using TIL_barplot and florets
//  * 6. [Core Analysis] Collapse closely-related cell types using runCollapseCellTypes
//  * 7. [Core Analysis] Merge tumor profiles into the cell profile matrix using runMergeTumorIntoX
//  * 8. [Core Analysis] Perform reverse deconvolution using runReverseDecon

nextflow.enable.dsl = 2

process BIOC_SPATIALDECON_GEOMX_SET_WORKFLOW {
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
    .bm_deps <- c("GeomxTools", "Seurat", "SeuratObject", "SpatialDecon")
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
    library(SpatialDecon)
    library(GeomxTools)
    
    # ==========================================
    # 1. Update and prepare the GeoMxSet object
    # ==========================================
    
    # Read the user input file 'nsclc' from the working directory
    if (file.exists("nsclc.rds")) {
      nsclc <- readRDS("nsclc.rds")
    } else if (file.exists("nsclc")) {
      nsclc <- readRDS("nsclc")
    } else {
      stop("Required input file 'nsclc' or 'nsclc.rds' not found in the working directory.")
    }
    
    # Update and prepare the GeoMxSet object
    nsclc <- updateGeoMxSet(nsclc)
    featureType(nsclc) <- "Target"
    
    # ==========================================
    # 2. Estimate background using derive_GeoMx_background
    # ==========================================
    
    # Dynamically identify the probe pool and negative probes
    probepool <- if ("Module" %in% colnames(fData(nsclc))) fData(nsclc)\$Module else rep(1, nrow(nsclc))
    
    negnames <- NULL
    if ("Negative" %in% colnames(fData(nsclc))) {
      negnames <- rownames(nsclc)[fData(nsclc)\$Negative]
    }
    if (length(negnames) == 0) {
      negnames <- grep("NegProbe", rownames(nsclc), ignore.case = TRUE, value = TRUE)
    }
    
    bg = derive_GeoMx_background(norm = nsclc@assayData\$exprs_norm,
                                 probepool = probepool,
                                 negnames = negnames)
    
    # Load reference datasets directly from the package namespace to avoid data() calls
    safeTME <- SpatialDecon::safeTME
    safeTME.matches <- SpatialDecon::safeTME.matches
    cellcols <- SpatialDecon::cellcols
    
    # ==========================================
    # 3. Run basic deconvolution using runspatialdecon
    # ==========================================
    
    res = runspatialdecon(object = nsclc,
                          norm_elt = "exprs_norm",
                          raw_elt = "exprs",
                          X = safeTME,
                          align_genes = TRUE,
                          bg = bg)
    
    # ==========================================
    # 4. Run advanced deconvolution with tumor modeling, cell merging, and cell count estimation
    # ==========================================
    
    # Dynamically identify tumor segments and nuclei counts
    is_tumor <- apply(pData(nsclc), 1, function(x) any(grepl("tumor", as.character(x), ignore.case = TRUE)))
    nsclc\$istumor <- is_tumor
    
    nuclei_col <- grep("nuclei", colnames(pData(nsclc)), ignore.case = TRUE, value = TRUE)[1]
    if (!is.na(nuclei_col)) {
      cell_counts <- pData(nsclc)[[nuclei_col]]
    } else {
      cell_counts <- NULL
    }
    
    restils = runspatialdecon(object = nsclc,
                              norm_elt = "exprs_norm",
                              raw_elt = "exprs",
                              X = safeTME,
                              bg = bg,
                              cellmerges = safeTME.matches,
                              cell_counts = cell_counts,
                              is_pure_tumor = nsclc\$istumor,
                              n_tumor_clusters = 5)
    
    # ==========================================
    # 5. Plot results using TIL_barplot and florets
    # ==========================================
    
    pdf("deconvolution_plots.pdf", width = 12, height = 6)
    
    # Plot 1: TIL barplot of cell counts
    if (!is.null(restils\$cell.counts)) {
      counts_mat <- t(restils\$cell.counts\$cell.counts)
      if (ncol(counts_mat) > 1) {
        o = hclust(dist(t(counts_mat)))\$order
        counts_mat <- counts_mat[, o, drop = FALSE]
      }
      layout(mat = (matrix(c(1, 2), 1)), widths = c(7, 3))
      TIL_barplot(counts_mat, draw_legend = TRUE, cex.names = 0.5)
    }
    
    # Plot 2: TIL barplot of proportions of non-tumor cells
    temp = replace(restils\$prop_of_nontumor, is.na(restils\$prop_of_nontumor), 0)
    is_tme <- !nsclc\$istumor
    if (any(is_tme)) {
      prop_mat <- t(temp[is_tme, , drop = FALSE])
    } else {
      prop_mat <- t(temp)
    }
    
    if (ncol(prop_mat) > 1) {
      o = hclust(dist(t(prop_mat)))\$order
      prop_mat <- prop_mat[, o, drop = FALSE]
    }
    TIL_barplot(prop_mat, draw_legend = TRUE, cex.names = 0.75)
    
    # Plot 3: Florets plot on PCA space
    pc = prcomp(t(log2(pmax(nsclc@assayData\$exprs_norm, 1))))\$x[, c(1, 2)]
    par(mar = c(5,5,1,1))
    layout(mat = (matrix(c(1, 2), 1)), widths = c(6, 2))
    florets(x = pc[, 1], y = pc[, 2],
            b = t(restils\$beta), cex = .5,
            xlab = "PC1", ylab = "PC2")
    par(mar = c(0,0,0,0))
    frame()
    legend("center", fill = cellcols[colnames(restils\$beta)], 
           legend = colnames(restils\$beta), cex = 0.7)
    
    dev.off()
    
    # ==========================================
    # 6. Collapse closely-related cell types using runCollapseCellTypes
    # ==========================================
    
    matching = list()
    matching\$myeloid = c( "macrophages", "monocytes", "mDCs")
    matching\$T.NK = c("CD4.T.cells","CD8.T.cells", "Treg", "NK")
    matching\$B = c("B")
    matching\$mast = c("mast")
    matching\$neutrophils = c("neutrophils")
    matching\$stroma = c("endothelial.cells", "fibroblasts")
    
    collapsed = runCollapseCellTypes(object = restils, 
                                     matching = matching)
    
    # ==========================================
    # 7. Merge tumor profiles into the cell profile matrix using runMergeTumorIntoX
    # ==========================================
    
    pure.tumor.ids = nsclc\$istumor
    safeTME.with.tumor = runMergeTumorIntoX(object = nsclc,
                                            norm_elt = "exprs_norm", 
                                            pure_tumor_ids = pure.tumor.ids,
                                            X = safeTME,
                                            K = 3)
    
    # ==========================================
    # 8. Perform reverse deconvolution using runReverseDecon
    # ==========================================
    
    rdecon = runReverseDecon(object = nsclc,
                             norm_elt = "exprs_norm",
                             beta = res\$beta)
    
    # ==========================================
    # 9. Save outputs to files
    # ==========================================
    
    # Save RDS objects
    saveRDS(res, "basic_deconvolution_results.rds")
    saveRDS(restils, "advanced_deconvolution_results.rds")
    saveRDS(collapsed, "collapsed_cell_types.rds")
    saveRDS(safeTME.with.tumor, "safeTME_with_tumor.rds")
    saveRDS(rdecon, "reverse_deconvolution_results.rds")
    
    # Save CSV tables
    write.csv(as.data.frame(res\$beta), "basic_beta.csv", row.names = TRUE)
    write.csv(as.data.frame(restils\$beta), "advanced_beta.csv", row.names = TRUE)
    write.csv(as.data.frame(collapsed\$beta), "collapsed_beta.csv", row.names = TRUE)
    write.csv(as.data.frame(rdecon@assayData\$resids), "reverse_decon_residuals.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_SPATIALDECON_GEOMX_SET_WORKFLOW":',
        paste0('    SpatialDecon: ', as.character(packageVersion('SpatialDecon')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_geomx_set_workflow.csv versions.yml
    """
}

workflow BIOC_SPATIALDECON_GEOMX_SET_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ nsclc ] ]

    main:
    BIOC_SPATIALDECON_GEOMX_SET_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_SPATIALDECON_GEOMX_SET_WORKFLOW.out.tables
    plots    = BIOC_SPATIALDECON_GEOMX_SET_WORKFLOW.out.plots
    objects  = BIOC_SPATIALDECON_GEOMX_SET_WORKFLOW.out.objects
    versions = BIOC_SPATIALDECON_GEOMX_SET_WORKFLOW.out.versions
}
