#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SPOTlight — single_step_deconvolution
// Deconvolute spatial transcriptomics spots in a single step using a single-cell RNA-seq reference.
// Input: sce, spe
// Container: quay.io/biocontainers/bioconductor-spotlight:1.14.0--r45ha27e39d_0
// R packages: ggplot2, NMF, scater, scran, SingleCellExperiment, SpatialExperiment, SPOTlight, tabulamurissenisdata, tenxvisiumdata
// Bioconductor: 3.20 | R: 4.4
// Requires: SPOTlight, SingleCellExperiment, SpatialExperiment, ggplot2, scater, scran
// Visualizations: heatmap, network plot, scatter plot
// QC: cell QC metrics, count normalization, highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess single-cell data (log normalization, variance modeling with modelGeneVar, and highly variable gene selection with getTo
//  * 2. [Core Analysis] Identify marker genes using scoreMarkers and filter/format them
//  * 3. [Core Analysis] Downsample cells per cell identity to optimize computational performance
//  * 4. [Core Analysis] Run deconvolution in a single step using SPOTlight
//  * 5. [Core Analysis] Extract deconvolution matrix and NMF model fit
//  * 6. [Visualization & Output] Visualize results using plotTopicProfiles, plotCorrelationMatrix, plotInteractions, and plotSpatialScatterpie

nextflow.enable.dsl = 2

process BIOC_SPOTLIGHT_SINGLE_STEP_DECONVOLUTION {
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
    .bm_deps <- c("ggplot2", "NMF", "scater", "scran", "SingleCellExperiment", "SpatialExperiment", "SPOTlight", "tabulamurissenisdata", "tenxvisiumdata")
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
        library(ggplot2)
        library(SPOTlight)
        library(SpatialExperiment)
        library(scater)
        library(scran)
        
        # Read user input files from the working directory
        sce <- readRDS("sce.rds")
        spe <- readRDS("spe.rds")
        
        # 1. Preprocess single-cell data
        sce <- logNormCounts(sce)
        genes <- !grepl(pattern = "^Rp[l|s]|Mt", x = rownames(sce))
        dec <- modelGeneVar(sce, subset.row = genes)
        hvg <- getTopHVGs(dec, n = 3000)
        
        # 2. Identify marker genes
        mgs <- scoreMarkers(sce, subset.row = genes)
        mgs_fil <- lapply(names(mgs), function(i) {
            x <- mgs[[i]]
            x <- x[x\$mean.AUC > 0.8, ]
            x <- x[order(x\$mean.AUC, decreasing = TRUE), ]
            x\$gene <- rownames(x)
            x\$cluster <- i
            data.frame(x)
        })
        mgs_df <- do.call(rbind, mgs_fil)
        
        # 3. Downsample cells per cell identity
        idx <- split(seq(ncol(sce)), colLabels(sce))
        n_cells <- 50
        cs_keep <- lapply(idx, function(i) {
            n <- length(i)
            if (n < n_cells)
                n_cells <- n
            sample(i, n_cells)
        })
        sce <- sce[, unlist(cs_keep)]
        
        # 4. Run deconvolution in a single step using SPOTlight
        res <- SPOTlight(
            x = sce,
            y = spe,
            groups = as.character(colLabels(sce)),
            mgs = mgs_df,
            hvg = hvg,
            weight_id = "mean.AUC",
            group_id = "cluster",
            gene_id = "gene")
        
        # 5. Extract deconvolution matrix and NMF model fit
        mat <- res\$mat
        mod <- res\$NMF
        sign <- mod\$w
        
        # Save tabular outputs
        write.csv(as.data.frame(mat), "deconvolution_matrix.csv", row.names = TRUE)
        write.csv(as.data.frame(sign), "nmf_basis_signatures.csv", row.names = TRUE)
        saveRDS(res, "spotlight_results.rds")
        
        # 6. Visualize results
        
        # Topic profiles (unfaceted)
        pdf("topic_profiles_unfaceted.pdf", width = 6, height = 7)
        p1 <- plotTopicProfiles(
            x = mod,
            y = colLabels(sce),
            facet = FALSE,
            min_prop = 0.01,
            ncol = 1) +
            theme(aspect.ratio = 1)
        print(p1)
        dev.off()
        
        # Topic profiles (faceted)
        pdf("topic_profiles_faceted.pdf", width = 9, height = 6)
        p2 <- plotTopicProfiles(
            x = mod,
            y = colLabels(sce),
            facet = TRUE,
            min_prop = 0.01,
            ncol = 6)
        print(p2)
        dev.off()
        
        # Spatial Correlation Matrix
        pdf("spatial_correlation_matrix.pdf", width = 9, height = 9)
        print(plotCorrelationMatrix(mat))
        dev.off()
        
        # Co-localization / Interactions
        pdf("interactions_heatmap_prop.pdf", width = 9, height = 9)
        print(plotInteractions(mat, which = "heatmap", metric = "prop"))
        dev.off()
        
        pdf("interactions_heatmap_jaccard.pdf", width = 9, height = 9)
        print(plotInteractions(mat, which = "heatmap", metric = "jaccard"))
        dev.off()
        
        pdf("interactions_network.pdf", width = 9, height = 9)
        print(plotInteractions(mat, which = "network"))
        dev.off()
        
        # Scatterpie visualization
        ct <- colnames(mat)
        mat[mat < 0.1] <- 0
        paletteMartin <- c(
            "#000000", "#004949", "#009292", "#ff6db6", "#ffb6db", 
            "#490092", "#006ddb", "#b66dff", "#6db6ff", "#b6dbff", 
            "#920000", "#924900", "#db6d00", "#24ff24", "#ffff6d")
        pal <- colorRampPalette(paletteMartin)(length(ct))
        names(pal) <- ct
        
        pdf("spatial_scatterpie.pdf", width = 9, height = 6)
        p3 <- plotSpatialScatterpie(
            x = spe,
            y = mat,
            cell_types = colnames(mat),
            img = FALSE,
            scatterpie_alpha = 1,
            pie_scale = 0.4) +
            scale_fill_manual(
                values = pal,
                breaks = names(pal))
        print(p3)
        dev.off()
        
        pdf("spatial_scatterpie_rotated.pdf", width = 9, height = 6)
        p4 <- plotSpatialScatterpie(
            x = spe,
            y = mat,
            cell_types = colnames(mat),
            img = FALSE,
            scatterpie_alpha = 1,
            pie_scale = 0.4,
            degrees = -90,
            axis = "h") +
            scale_fill_manual(
                values = pal,
                breaks = names(pal))
        print(p4)
        dev.off()
        
        # Residuals
        spe\$res_ss <- res[[2]][colnames(spe)]
        xy <- spatialCoords(spe)
        spe\$x <- xy[, 1]
        spe\$y <- xy[, 2]
        
        pdf("residuals_plot.pdf", width = 7, height = 6)
        p5 <- ggcells(spe, aes(x, y, color = res_ss)) +
            geom_point() +
            scale_color_viridis_c() +
            coord_fixed() +
            theme_bw()
        print(p5)
        dev.off()

    writeLines(c(
        '"BIOC_SPOTLIGHT_SINGLE_STEP_DECONVOLUTION":',
        paste0('    SPOTlight: ', as.character(packageVersion('SPOTlight')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_step_deconvolution.csv versions.yml
    """
}

workflow BIOC_SPOTLIGHT_SINGLE_STEP_DECONVOLUTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce, spe ] ]

    main:
    BIOC_SPOTLIGHT_SINGLE_STEP_DECONVOLUTION(ch_input)

    emit:
    tables   = BIOC_SPOTLIGHT_SINGLE_STEP_DECONVOLUTION.out.tables
    plots    = BIOC_SPOTLIGHT_SINGLE_STEP_DECONVOLUTION.out.plots
    objects  = BIOC_SPOTLIGHT_SINGLE_STEP_DECONVOLUTION.out.objects
    versions = BIOC_SPOTLIGHT_SINGLE_STEP_DECONVOLUTION.out.versions
}
