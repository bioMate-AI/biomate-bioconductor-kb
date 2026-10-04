#!/usr/bin/env nextflow
/*
 * single_cell/visium_voyager_spatial_esda
 *
 * Self-contained 10X Visium spatial ESDA (Exploratory Spatial Data Analysis)
 * on a SpatialFeatureExperiment (SFE) with the Voyager package.
 *
 * This is the MINIMAL-CORRECT runnable implementation. The prior versions depended
 * on an image that was never built:
 *   - bioc-spatial:v1 (original), then bioc-domain-spatial:3.20-deps, neither of
 *     which exists in ECR; and
 *   - a bespoke /opt/biomate/voyager/esda_run.R script baked ONLY into that unbuilt
 *     image, so the workflow could never run (container-pull / script-missing).
 *
 * FIX (2026-10-03): the ESDA R logic (formerly esda_run.R) is now INLINED here, and
 * the process runs on the EXISTING, Batch-ready ECR image
 *   399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim
 * — the same image the sibling bioconductor/voyager workflow uses for the Voyager
 * stack. The Voyager/SpatialFeatureExperiment/SFEData/scater/scran deps are resolved
 * at runtime via a BiocManager .bm_deps guard; if they cannot be resolved the run
 * HONEST-FAILS (non-zero exit) rather than fabricating output.
 *
 * It:
 *   1. Loads a real 10X Visium SFE (built-in SFEData example, default
 *      McKellarMuscleData, or a user SFE .rds via --sfe_rds).
 *   2. Keeps in-tissue spots, filters low-count spots, log-normalizes, selects HVGs.
 *   3. Builds the Visium spatial neighborhood graph (findVisiumGraph; k-NN fallback).
 *   4. Computes univariate Moran's I (global spatial autocorrelation) for HVGs.
 *   5. Emits: SFE .rds, Moran's I table (CSV), per-spot QC table (CSV),
 *      a Moran's-I bar plot + a spatial feature plot (PNG), a JSON summary.
 *
 * DB note (owner): set workflow id 14438 docker_image to the transcriptomics ECR
 * image above (was the non-existent bioc-domain-spatial:3.20-deps).
 *
 * References:
 *   - Moses & Pachter, Voyager, 2023 Nat Methods
 *   - Righelli et al. 2022 SpatialExperiment (Bioinformatics)
 *   - McKellar et al. 2021 (10X Visium mouse skeletal muscle regeneration)
 */

nextflow.enable.dsl = 2

params.outdir            = './results'
// SFEData example to load when no user SFE is supplied. Any function name in the
// SFEData package that returns a Visium SFE (e.g. McKellarMuscleData).
params.sfe_dataset       = 'McKellarMuscleData'
// Optional: path to a user-supplied SpatialFeatureExperiment .rds. Overrides sfe_dataset.
params.sfe_rds           = 'null'
params.min_counts_per_spot = '100'
params.n_hvgs            = '200'
params.max_spots         = '2000'   // subsample cap to bound runtime/cost
params.sample_id         = 'sample'
// EXISTING Batch-ready image carrying the Voyager stack (same as sibling
// bioconductor/voyager). Overridable by the executor via params.container.
params.container         = '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim'

process VISIUM_VOYAGER_SPATIAL_ESDA {
    tag "${params.sample_id}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container "${params.container}"

    output:
    path "sfe_esda.rds",          emit: sfe
    path "univariate_moran.csv",  emit: moran
    path "qc_metrics.csv",        emit: qc
    path "moran_top_genes.png",   emit: moran_plot
    path "spatial_feature.png",   emit: spatial_plot
    path "esda_summary.json",     emit: summary
    path "versions.yml",          emit: versions

    script:
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve the Voyager spatial stack at runtime so the workflow runs on
    # an EXISTING image (bioc-domain-transcriptomics:3.20-slim) instead of the never-built
    # bespoke bioc-domain-spatial image. Same pattern as the sibling bioconductor/voyager.
    .bm_deps <- c("SpatialFeatureExperiment","SpatialExperiment","Voyager","SFEData",
                  "scater","scran","ggplot2","jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }

    # Honest-fail: if the Voyager spatial stack cannot be resolved, STOP (non-zero exit).
    # Never fabricate spatial results on a container/dependency gap (CLAUDE.md: no fabrication).
    suppressWarnings(suppressPackageStartupMessages({
      library(SpatialFeatureExperiment)
      library(SpatialExperiment)
      library(Voyager)
      library(SFEData)
      library(scater)
      library(scran)
      library(ggplot2)
    }))

    opt <- list(
      sfe_dataset = "${params.sfe_dataset}",
      sfe_rds     = "${params.sfe_rds}",
      min_counts  = as.numeric("${params.min_counts_per_spot}"),
      n_hvgs      = as.integer("${params.n_hvgs}"),
      max_spots   = as.integer("${params.max_spots}"),
      sample_id   = "${params.sample_id}"
    )
    cat("[esda] options:\n"); str(opt)

    ## ---- 1. load the SFE --------------------------------------------------------
    if (!is.null(opt\$sfe_rds) && nchar(opt\$sfe_rds) && opt\$sfe_rds != "null" &&
        file.exists(opt\$sfe_rds)) {
      cat("[esda] loading user SFE from", opt\$sfe_rds, "\n")
      sfe <- readRDS(opt\$sfe_rds)
    } else {
      cat("[esda] loading SFEData example:", opt\$sfe_dataset, "\n")
      fn <- get(opt\$sfe_dataset, envir = asNamespace("SFEData"))
      sfe <- fn()
    }
    stopifnot(is(sfe, "SpatialFeatureExperiment"))
    cat("[esda] loaded SFE:", nrow(sfe), "genes x", ncol(sfe), "spots\n")

    ## ---- 2. QC: keep in-tissue spots, filter low-count spots ---------------------
    if ("in_tissue" %in% colnames(colData(sfe))) {
      sfe <- sfe[, colData(sfe)\$in_tissue]
      cat("[esda] kept", ncol(sfe), "in-tissue spots\n")
    }
    tot <- colSums(counts(sfe))
    colData(sfe)\$nCounts <- tot
    colData(sfe)\$nGenes  <- colSums(counts(sfe) > 0)
    keep_spot <- tot >= opt\$min_counts
    sfe <- sfe[, keep_spot]
    cat("[esda] kept", ncol(sfe), "spots with >=", opt\$min_counts, "counts\n")

    sfe <- sfe[rowSums(counts(sfe)) > 0, ]

    if (ncol(sfe) > opt\$max_spots) {
      set.seed(7)
      sel <- sort(sample(seq_len(ncol(sfe)), opt\$max_spots))
      sfe <- sfe[, sel]
      cat("[esda] subsampled to", ncol(sfe), "spots (max_spots cap)\n")
    }

    qc <- data.frame(
      spot_id = colnames(sfe),
      nCounts = colData(sfe)\$nCounts,
      nGenes  = colData(sfe)\$nGenes
    )
    write.csv(qc, "qc_metrics.csv", row.names = FALSE)

    ## ---- 3. normalize -----------------------------------------------------------
    sfe <- logNormCounts(sfe)

    ## ---- 4. HVG selection -------------------------------------------------------
    gv <- modelGeneVar(sfe)
    n_hvg <- min(opt\$n_hvgs, nrow(sfe))
    hvgs <- getTopHVGs(gv, n = n_hvg)
    cat("[esda] selected", length(hvgs), "HVGs\n")

    sym_col <- NULL
    if ("symbol" %in% colnames(rowData(sfe))) sym_col <- "symbol"

    ## ---- 5. spatial neighborhood graph ------------------------------------------
    sample_ids <- unique(colData(sfe)\$sample_id)
    graph_ok <- TRUE
    tryCatch({
      colGraph(sfe, "visium") <- findVisiumGraph(sfe)
    }, error = function(e) {
      cat("[esda] findVisiumGraph failed (", conditionMessage(e),
          ") - falling back to k-NN graph\n")
      colGraph(sfe, "visium") <<- findSpatialNeighbors(sfe, method = "knearneigh", k = 6)
    })

    ## ---- 6. univariate Moran's I ------------------------------------------------
    sfe <- runUnivariate(
      sfe, type = "moran", features = hvgs,
      colGraphName = "visium",
      swap_rownames = sym_col
    )

    rd <- rowData(sfe)
    moran_col <- grep("^moran", colnames(rd), value = TRUE)[1]
    moran_vals <- rd[hvgs, moran_col]
    gene_label <- if (!is.null(sym_col)) rd[hvgs, sym_col] else hvgs
    moran <- data.frame(
      gene       = hvgs,
      symbol     = gene_label,
      morans_I   = as.numeric(moran_vals)
    )
    moran <- moran[order(-moran\$morans_I), ]
    write.csv(moran, "univariate_moran.csv", row.names = FALSE)
    cat("[esda] wrote Moran's I for", nrow(moran), "genes; top:\n")
    print(utils::head(moran, 5))

    saveRDS(sfe, "sfe_esda.rds")

    ## ---- 7. plots ---------------------------------------------------------------
    topn <- utils::head(moran, 20)
    topn\$symbol <- factor(topn\$symbol, levels = rev(topn\$symbol))
    p1 <- ggplot(topn, aes(x = symbol, y = morans_I)) +
      geom_col(fill = "#2c7fb8") + coord_flip() +
      labs(title = "Top spatially autocorrelated genes (Moran's I)",
           x = NULL, y = "Moran's I") + theme_bw()
    ggsave("moran_top_genes.png", p1, width = 6, height = 6, dpi = 120)

    top_gene <- moran\$gene[1]
    p2 <- tryCatch(
      plotSpatialFeature(sfe, features = top_gene, colGeometryName = "spotPoly",
                         swap_rownames = sym_col) +
        ggtitle(paste0("Spatial expression: ", moran\$symbol[1])),
      error = function(e) {
        cat("[esda] plotSpatialFeature failed (", conditionMessage(e),
            ") - using nCounts scatter fallback\n")
        xy <- spatialCoords(sfe)
        df <- data.frame(x = xy[, 1], y = xy[, 2], v = colData(sfe)\$nCounts)
        ggplot(df, aes(x, y, color = v)) + geom_point(size = 0.8) +
          scale_color_viridis_c() + coord_equal() +
          labs(title = "Spatial nCounts", color = "nCounts") + theme_bw()
      }
    )
    ggsave("spatial_feature.png", p2, width = 6, height = 6, dpi = 120)

    ## ---- 8. JSON summary --------------------------------------------------------
    summary <- list(
      sample_id     = opt\$sample_id,
      dataset       = if (opt\$sfe_rds != "null") opt\$sfe_rds else opt\$sfe_dataset,
      n_spots       = ncol(sfe),
      n_genes       = nrow(sfe),
      n_hvgs        = length(hvgs),
      min_counts    = opt\$min_counts,
      top_gene      = moran\$symbol[1],
      top_morans_I  = round(moran\$morans_I[1], 4),
      median_morans_I = round(stats::median(moran\$morans_I, na.rm = TRUE), 4),
      Voyager_version = as.character(packageVersion("Voyager"))
    )
    writeLines(jsonlite::toJSON(summary, auto_unbox = TRUE, pretty = TRUE),
               "esda_summary.json")

    writeLines(c(
      '"VISIUM_VOYAGER_SPATIAL_ESDA":',
      paste0('    Voyager: ', as.character(packageVersion('Voyager'))),
      paste0('    SpatialFeatureExperiment: ', as.character(packageVersion('SpatialFeatureExperiment'))),
      paste0('    SFEData: ', as.character(packageVersion('SFEData')))
    ), "versions.yml")

    cat("[esda] DONE. Outputs: sfe_esda.rds, univariate_moran.csv, qc_metrics.csv,",
        "moran_top_genes.png, spatial_feature.png, esda_summary.json\n")
    """
}

workflow VISIUM_VOYAGER_SPATIAL_ESDA_WORKFLOW {
    main:
    VISIUM_VOYAGER_SPATIAL_ESDA()

    emit:
    sfe           = VISIUM_VOYAGER_SPATIAL_ESDA.out.sfe
    moran         = VISIUM_VOYAGER_SPATIAL_ESDA.out.moran
    qc            = VISIUM_VOYAGER_SPATIAL_ESDA.out.qc
    moran_plot    = VISIUM_VOYAGER_SPATIAL_ESDA.out.moran_plot
    spatial_plot  = VISIUM_VOYAGER_SPATIAL_ESDA.out.spatial_plot
    summary       = VISIUM_VOYAGER_SPATIAL_ESDA.out.summary
    versions      = VISIUM_VOYAGER_SPATIAL_ESDA.out.versions
}

workflow {
    VISIUM_VOYAGER_SPATIAL_ESDA_WORKFLOW()
}
