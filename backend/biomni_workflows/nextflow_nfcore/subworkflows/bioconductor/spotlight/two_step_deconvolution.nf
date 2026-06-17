#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SPOTlight — two_step_deconvolution
// Train the NMF model first and then run deconvolution separately to allow model reuse across multiple spatial datasets.
// Input: sce, spe
// Container: quay.io/biocontainers/bioconductor-spotlight:1.14.0--r45ha27e39d_0
// R packages: SPOTlight, SingleCellExperiment, SpatialExperiment, ggplot2, scater, scran
// Bioconductor: 3.20 | R: 4.4
// Requires: SPOTlight, SingleCellExperiment, SpatialExperiment, ggplot2, scater, scran
// Visualizations: plot (ggplot/base)
// QC: cell QC metrics, count normalization, highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Train the NMF model using trainNMF
//  * 2. [Core Analysis] Run deconvolution on the spatial dataset using runDeconvolution with the trained model and topic profiles

nextflow.enable.dsl = 2

process BIOC_SPOTLIGHT_TWO_STEP_DECONVOLUTION {
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
    .bm_deps <- c("SPOTlight", "SingleCellExperiment", "SpatialExperiment", "ggplot2", "scater", "scran", "SummarizedExperiment")
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
       library(ggplot2)
        library(SPOTlight)
        library(SpatialExperiment)
        library(scater)
        library(scran)
        
        # 1. Load User Input Files
        if (!file.exists("sce.rds") || !file.exists("spe.rds")) {
            stop("Required input files 'sce.rds' and/or 'spe.rds' not found in the working directory.")
        }
        
        sce <- readRDS("sce.rds")
        spe <- readRDS("spe.rds")
        
        # Ensure cell type annotations are present
        if (is.null(sce\$free_annotation)) {
            stop("The input SingleCellExperiment object 'sce' must contain a 'free_annotation' column in its colData.")
        }
        
        # 2. Preprocessing & Feature Selection
        # Library size normalization
        sce <- logNormCounts(sce)
        
        # Identify highly variable genes (excluding ribosomal and mitochondrial genes)
        genes <- !grepl(pattern = "^Rp[l|s]|Mt", x = rownames(sce))
        dec <- modelGeneVar(sce, subset.row = genes)
        hvg <- getTopHVGs(dec, n = 3000)
        
        # Compute marker genes
        colLabels(sce) <- colData(sce)\$free_annotation
        mgs <- scoreMarkers(sce, subset.row = genes)
        
        # Filter and format marker genes
        mgs_fil <- lapply(names(mgs), function(i) {
            x <- mgs[[i]]
            # Filter and keep relevant marker genes (AUC > 0.8)
            x <- x[x\$mean.AUC > 0.8, ]
            # Sort the genes from highest to lowest weight
            x <- x[order(x\$mean.AUC, decreasing = TRUE), ]
            # Add gene and cluster id to the dataframe
            x\$gene <- rownames(x)
            x\$cluster <- i
            data.frame(x)
        })
        mgs_df <- do.call(rbind, mgs_fil)
        
        # Downsample cells to optimize performance (at most 50 cells per identity)
        idx <- split(seq(ncol(sce)), sce\$free_annotation)
        n_cells <- 50
        cs_keep <- lapply(idx, function(i) {
            n <- length(i)
            curr_n <- if (n < n_cells) n else n_cells
            sample(i, curr_n)
        })
        sce <- sce[, unlist(cs_keep)]
        
        # 3. Train NMF Model (First Step of Deconvolution)
        mod_ls <- trainNMF(
            x = sce,
            groups = sce\$free_annotation,
            mgs = mgs_df,
            hvg = hvg,
            weight_id = "mean.AUC",
            group_id = "cluster",
            gene_id = "gene")
        
        # 4. Run Deconvolution (Second Step of Deconvolution)
        res <- runDeconvolution(
            x = spe,
            mod = mod_ls[["mod"]],
            ref = mod_ls[["topic"]])
        
        # 5. Save Meaningful Results
        # Extract and save deconvolution matrix
        mat <- res\$mat
        write.csv(mat, "deconvolution_matrix.csv", row.names = TRUE)
        
        # Save trained model and deconvolution results
        saveRDS(mod_ls, "trained_nmf_model.rds")
        saveRDS(res, "deconvolution_results.rds")
        
        # 6. Visualization and Plot Generation
        pdf("spotlight_plots.pdf", width = 10, height = 10)
        
        # Topic Profiles
        mod <- mod_ls[["mod"]]
        p1 <- plotTopicProfiles(
            x = mod,
            y = sce\$free_annotation,
            facet = FALSE,
            min_prop = 0.01,
            ncol = 1) +
            theme(aspect.ratio = 1)
        print(p1)
        
        p2 <- plotTopicProfiles(
            x = mod,
            y = sce\$free_annotation,
            facet = TRUE,
            min_prop = 0.01,
            ncol = 6)
        print(p2)
        
        # Spatial Correlation Matrix
        p3 <- plotCorrelationMatrix(mat)
        print(p3)
        
        # Co-localization / Interactions
        p4 <- plotInteractions(mat, which = "heatmap", metric = "prop")
        print(p4)
        
        p5 <- plotInteractions(mat, which = "heatmap", metric = "jaccard")
        print(p5)
        
        tryCatch({
            plotInteractions(mat, which = "network")
        }, error = function(e) {
            message("Could not plot network interactions: ", e\$message)
        })
        
        # Spatial Scatterpie
        ct <- colnames(mat)
        mat_pie <- mat
        mat_pie[mat_pie < 0.1] <- 0
        
        paletteMartin <- c(
            "#000000", "#004949", "#009292", "#ff6db6", "#ffb6db", 
            "#490092", "#006ddb", "#b66dff", "#6db6ff", "#b6dbff", 
            "#920000", "#924900", "#db6d00", "#24ff24", "#ffff6d")
        
        pal <- colorRampPalette(paletteMartin)(length(ct))
        names(pal) <- ct
        
        p6 <- plotSpatialScatterpie(
            x = spe,
            y = mat_pie,
            cell_types = colnames(mat_pie),
            img = FALSE,
            scatterpie_alpha = 1,
            pie_scale = 0.4) +
            scale_fill_manual(
                values = pal,
                breaks = names(pal))
        print(p6)
        
        # Residuals Plot
        tryCatch({
            spe\$res_ss <- res[[2]][colnames(spe)]
            xy <- spatialCoords(spe)
            spe\$x <- xy[, 1]
            spe\$y <- xy[, 2]
            p7 <- ggcells(spe, aes(x, y, color = res_ss)) +
                geom_point() +
                scale_color_viridis_c() +
                coord_fixed() +
                theme_bw()
            print(p7)
        }, error = function(e) {
            message("Could not plot residuals: ", e\$message)
        })
        
        dev.off()
        
        message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_SPOTLIGHT_TWO_STEP_DECONVOLUTION":',
        paste0('    SPOTlight: ', as.character(packageVersion('SPOTlight')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_step_deconvolution.csv versions.yml
    """
}

workflow BIOC_SPOTLIGHT_TWO_STEP_DECONVOLUTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce, spe ] ]

    main:
    BIOC_SPOTLIGHT_TWO_STEP_DECONVOLUTION(ch_input)

    emit:
    tables   = BIOC_SPOTLIGHT_TWO_STEP_DECONVOLUTION.out.tables
    plots    = BIOC_SPOTLIGHT_TWO_STEP_DECONVOLUTION.out.plots
    objects  = BIOC_SPOTLIGHT_TWO_STEP_DECONVOLUTION.out.objects
    versions = BIOC_SPOTLIGHT_TWO_STEP_DECONVOLUTION.out.versions
}
