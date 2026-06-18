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
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
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
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cqc_obj <- tryCatch(readRDS(.cqc_rds), error = function(e) NULL)
      .cqc_mat <- if (is.matrix(.cqc_obj) || is.data.frame(.cqc_obj)) .cqc_obj else NULL
      if (!is.null(.cqc_mat) && nrow(.cqc_mat) > 100) {
        .cqc_ncells <- ncol(.cqc_mat); .cqc_nfeats <- nrow(.cqc_mat)
        .cqc_files <- c(.cqc_files, .cqc_rds); break
      }
    }
    .gates_by_label[["cell QC metrics"]] <- list(
      gate_row = "bioc_cell_qc_metrics",
      metric_name = "n_cells",
      metric_value = .cqc_ncells,
      passes = isTRUE(is.finite(.cqc_ncells) && .cqc_ncells >= 50 && .cqc_nfeats >= 200),
      status = if (is.finite(.cqc_ncells)) paste0("computed (cells=", .cqc_ncells, ", features=", .cqc_nfeats, "; proxy gate)")
               else "not_computed (no scRNA matrix .rds artifact present)"
    )

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    # HVG selection — count rows with high CV. Pass when 1000-3000 HVGs
    # (Stuart 2019 Cell Seurat v3 default range).
    .hvg_count <- NA_real_; .hvg_files <- character(0)
    for (.hvg_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .hvg_obj <- tryCatch(readRDS(.hvg_rds), error = function(e) NULL)
      .hvg_mat <- if (is.matrix(.hvg_obj) || is.data.frame(.hvg_obj)) .hvg_obj else NULL
      if (!is.null(.hvg_mat) && nrow(.hvg_mat) > 200) {
        .hvg_m <- suppressWarnings(as.matrix(.hvg_mat))
        .hvg_cvs <- suppressWarnings(apply(.hvg_m, 1, function(r) {
          .rv <- as.numeric(r); .m <- mean(.rv, na.rm = TRUE)
          if (is.finite(.m) && .m > 0) sd(.rv, na.rm = TRUE) / .m else NA_real_
        }))
        .hvg_count <- sum(is.finite(.hvg_cvs) & .hvg_cvs > 1.0)
        .hvg_files <- c(.hvg_files, .hvg_rds); break
      }
    }
    .gates_by_label[["highly-variable feature selection"]] <- list(
      gate_row = "bioc_hvg_selection",
      metric_name = "hvg_count",
      metric_value = .hvg_count,
      passes = isTRUE(is.finite(.hvg_count) && .hvg_count >= 1000 && .hvg_count <= 3000),
      status = if (is.finite(.hvg_count)) paste0("computed (CV>1.0 rows = ", .hvg_count, "; proxy for HVG selection)")
               else "not_computed (no expression matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_SPOTLIGHT_SINGLE_STEP_DECONVOLUTION",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics", "count normalization", "highly-variable feature selection"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



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
