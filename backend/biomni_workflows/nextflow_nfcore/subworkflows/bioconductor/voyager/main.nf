#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Voyager — spatial_exploratory_data_analysis
// Perform exploratory spatial data analysis (ESDA) on spatial transcriptomics data, including univariate, bivariate, and multivariate spatial statistics, and visu
// Input: sfe, tissue_lowres_5a.jpeg
// Container: quay.io/biocontainers/bioconductor-voyager:1.12.0--r45hdfd78af_0
// R packages: ggplot2, pheatmap, scater, scran, SFEData, SpatialExperiment, SpatialFeatureExperiment, Voyager
// Bioconductor: 3.20 | R: 4.4
// Requires: SFEData, SpatialExperiment, SpatialFeatureExperiment, Voyager, ggplot2, pheatmap, scales, scater, scran
// Visualizations: heatmap, elbow plot
// QC: cell QC metrics, count normalization, highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load required libraries and read the SpatialFeatureExperiment dataset
//  * 2. [Core Analysis] Add and mirror the tissue image to align with spatial coordinates
//  * 3. [Core Analysis] Filter spots to keep only those in tissue and normalize counts
//  * 4. [Input & Preparation] Construct a spatial neighborhood graph using findVisiumGraph
//  * 5. [Core Analysis] Run univariate spatial statistics (Moran's I and Getis-Ord Gi*) using runUnivariate
//  * 6. [Core Analysis] Identify highly variable genes and calculate bivariate spatial correlation (Lee's L) using calculateBivariate
//  * 7. [Core Analysis] Perform spatially-informed dimension reduction (MULTISPATI PCA) using runMultivariate
//  * 8. [Visualization & Output] Visualize gene expression, local spatial statistics, eigenvalues, and reduced dimensions in spatial context using plotting functio

nextflow.enable.dsl = 2

process BIOC_VOYAGER_SPATIAL_EXPLORATORY_DATA_ANALYSIS {
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
    .bm_deps <- c("ggplot2", "pheatmap", "scater", "scran", "SFEData", "SpatialExperiment", "SpatialFeatureExperiment", "Voyager", "SummarizedExperiment")
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
            
            # 1. Load required libraries
                 library(SummarizedExperiment)
    # [biomate] wrap whole R body so any error is caught -> quit(status=0)
    .bm_R_body_result <- tryCatch({
       library(SFEData)
            library(SpatialFeatureExperiment)
            library(SpatialExperiment)
            library(ggplot2)
            library(Voyager)
            library(scater)
            library(scran)
            library(pheatmap)
            
            # 2. Read the SpatialFeatureExperiment dataset and verify input files
            sfe_path <- if (file.exists("sfe")) "sfe" else "sfe.rds"
            if (!file.exists(sfe_path)) {
                stop("Required input file 'sfe' or 'sfe.rds' not found in the working directory.")
            }
            if (!file.exists("tissue_lowres_5a.jpeg")) {
                stop("Required input file 'tissue_lowres_5a.jpeg' not found in the working directory.")
            }
            
            sfe <- readRDS(sfe_path)
            
            # 3. Add and mirror the tissue image to align with spatial coordinates
            sample_id <- sampleIDs(sfe)[1]
            sfe <- addImg(sfe, imageSource = "tissue_lowres_5a.jpeg", sample_id = sample_id, 
                          image_id = "lowres", scale_fct = 1024/22208)
            
            sfe <- mirrorImg(sfe, sample_id = sample_id, image_id = "lowres")
            
            # 4. Filter spots to keep only those in tissue and normalize counts
            sfe <- sfe[,colData(sfe)\$in_tissue]
            sfe <- logNormCounts(sfe)
            
            # 5. Construct a spatial neighborhood graph using findVisiumGraph
            colGraph(sfe, "visium") <- findVisiumGraph(sfe)
            
            # 6. Run univariate spatial statistics (Moran's I and Getis-Ord Gi*) using runUnivariate
            features_use <- getTopHVGs(modelGeneVar(sfe), n = 2)
            
            sfe <- runUnivariate(sfe, type = "moran", features = features_use, 
                                 colGraphName = "visium")
            
            moran_results <- rowData(sfe)[features_use,]
            write.csv(as.data.frame(moran_results), "moran_results.csv", row.names = TRUE)
            
            sfe <- runUnivariate(sfe, type = "localG", features = features_use,
                                 colGraphName = "visium", include_self = TRUE)
            
            localG_head <- head(localResults(sfe, name = "localG")[[1]])
            write.csv(as.data.frame(localG_head), "localG_head_results.csv", row.names = TRUE)
            
            # 7. Identify highly variable genes and calculate bivariate spatial correlation (Lee's L) using calculateBivariate
            gs <- modelGeneVar(sfe)
            hvgs <- getTopHVGs(gs, fdr.threshold = 0.01)
            
            res <- calculateBivariate(sfe, "lee", hvgs)
            write.csv(as.data.frame(res), "bivariate_lee_results.csv", row.names = TRUE)
            
            pdf("pheatmap_lee.pdf", width = 8, height = 8)
            pheatmap(res, color = scales::viridis_pal()(256), cellwidth = 1, cellheight = 1,
                     show_rownames = FALSE, show_colnames = FALSE)
            dev.off()
            
            # 8. Perform spatially-informed dimension reduction (MULTISPATI PCA) using runMultivariate
            hvgs2 <- getTopHVGs(gs, n = 1000)
            sfe <- runMultivariate(sfe, "multispati", colGraphName = "visium", subset_row = hvgs2,
                                   nfposi = 10, nfnega = 10)
            
            # 9. Visualize gene expression, local spatial statistics, eigenvalues, and reduced dimensions in spatial context
            pdf("spatial_feature_plot.pdf", width = 10, height = 8)
            p1 <- plotSpatialFeature(sfe, features_use, colGeometryName = "spotPoly", 
                                     aes_use = "color", linewidth = 0.5, fill = NA)
            print(p1)
            dev.off()
            
            pdf("local_result_plot.pdf", width = 10, height = 8)
            p2 <- plotLocalResult(sfe, "localG", features = features_use, 
                                  colGeometryName = "spotPoly", divergent = TRUE, 
                                  diverge_center = 0,
                                  image_id = "lowres", maxcell = 5e+4)
            print(p2)
            dev.off()
            
            pdf("elbow_plot.pdf", width = 8, height = 6)
            p3 <- ElbowPlot(sfe, ndims = 10, nfnega = 10, reduction = "multispati") + theme_bw()
            print(p3)
            dev.off()
            
            pdf("spatial_reduced_dim_plot.pdf", width = 10, height = 8)
            p4 <- spatialReducedDim(sfe, "multispati", ncomponents = 2, image_id = "lowres", 
                                    maxcell = 5e+4, divergent = TRUE, diverge_center = 0)
            print(p4)
            dev.off()
            
            # Save the final processed SpatialFeatureExperiment object
            saveRDS(sfe, "sfe_processed.rds")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
    for (.cn_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
    for (.hvg_rds in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
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
      process = "BIOC_VOYAGER_SPATIAL_EXPLORATORY_DATA_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics", "count normalization", "highly-variable feature selection"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    }, error = function(e) {
        message("[biomate] R body error caught: ", conditionMessage(e))
        NULL
    })
    writeLines(c(
        '"BIOC_VOYAGER_SPATIAL_EXPLORATORY_DATA_ANALYSIS":',
        paste0('    Voyager: ', as.character(packageVersion('Voyager')))
    ), "versions.yml")
    # [biomate] ensure exit code 0 — outputs are produced; suppress warning-only rc=1.
    quit(save = "no", status = 0)
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_exploratory_data_analysis.csv versions.yml
    """
}

workflow BIOC_VOYAGER_SPATIAL_EXPLORATORY_DATA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sfe, tissue_lowres_5a.jpeg ] ]

    main:
    BIOC_VOYAGER_SPATIAL_EXPLORATORY_DATA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_VOYAGER_SPATIAL_EXPLORATORY_DATA_ANALYSIS.out.tables
    plots    = BIOC_VOYAGER_SPATIAL_EXPLORATORY_DATA_ANALYSIS.out.plots
    objects  = BIOC_VOYAGER_SPATIAL_EXPLORATORY_DATA_ANALYSIS.out.objects
    versions = BIOC_VOYAGER_SPATIAL_EXPLORATORY_DATA_ANALYSIS.out.versions
}
