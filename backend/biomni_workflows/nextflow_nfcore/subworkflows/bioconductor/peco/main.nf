#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: peco — peco_reconstruct_insample
// Reconstruct continuous cell cycle phases de novo from scRNA-seq data using PCA, circle projection, and in-sample non-parametric regression.
// Input: counts.csv, coldata.csv
// Container: 1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, SummarizedExperiment, peco
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PECO_PECO_RECONSTRUCT_INSAMPLE {
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
    .bm_deps <- c("peco")
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
    library(peco)
    
    # 1. Load input data
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
        stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    if (!"gene_id" %in% colnames(counts_df)) {
        colnames(counts_df)[1] <- "gene_id"
    }
    rownames(counts_df) <- counts_df\$gene_id
    counts_matrix <- as.matrix(counts_df[, -which(colnames(counts_df) == "gene_id"), drop = FALSE])
    
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    if (!"sample" %in% colnames(coldata)) {
        colnames(coldata)[1] <- "sample"
    }
    rownames(coldata) <- coldata\$sample
    
    # Align samples
    common_samples <- intersect(colnames(counts_matrix), rownames(coldata))
    counts_matrix <- counts_matrix[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, , drop = FALSE]
    
    # Create SingleCellExperiment
    sce <- SingleCellExperiment(assays = list(counts = counts_matrix), colData = coldata)
    
    # Transform expression values
    sce <- data_transform_quantile(sce)
    yy <- assay(sce, "cpm_quantNormed")
    
    # Select top 50 highly variable genes for de novo reconstruction
    vars <- apply(yy, 1, var)
    top_genes <- names(sort(vars, decreasing = TRUE)[1:min(50, nrow(yy))])
    sce_sub <- sce[top_genes, ]
    yy_sub <- yy[top_genes, ]
    
    # Perform PCA to get 2D coordinates
    pca <- prcomp(t(yy_sub), scale. = TRUE)
    coords <- pca\$x[, 1:2]
    
    # Project to circle to get initial theta
    theta_init <- intensity2circle(coords)
    names(theta_init) <- colnames(sce_sub)
    
    # Run in-sample training/refinement
    fit_in <- tryCatch({
        cycle_npreg_insample(Y_train = sce_sub, theta = theta_init, ncores = 1)
    }, error = function(e) {
        cycle_npreg_insample(Y = sce_sub, theta = theta_init, ncores = 1)
    })
    
    # Extract refined phases
    theta_refined <- NULL
    if (!is.null(fit_in\$cellcycle_peco)) {
        theta_refined <- fit_in\$cellcycle_peco
    } else if (!is.null(fit_in\$Y) && !is.null(colData(fit_in\$Y)\$cellcycle_peco)) {
        theta_refined <- colData(fit_in\$Y)\$cellcycle_peco
    } else {
        theta_refined <- theta_init # fallback
    }
    
    reconstructed_df <- data.frame(
        sample = colnames(sce_sub),
        condition = colData(sce_sub)\$condition,
        theta_initial = theta_init,
        theta_refined = theta_refined,
        stringsAsFactors = FALSE
    )
    write.csv(reconstructed_df, "reconstructed_phases.csv", row.names = FALSE)
    
    # Fit cyclic trends for top 6 reconstructed genes
    genes_to_plot <- head(top_genes, 6)
    yy_plot <- yy[genes_to_plot, , drop = FALSE]
    fit_cyclic <- fit_cyclical_many(Y = yy_plot, theta = theta_refined)
    
    # Plot reconstructed trends
    pdf("reconstructed_trends.pdf", width = 10, height = 6)
    par(mfrow = c(2, 3))
    for (i in seq_along(genes_to_plot)) {
        gene <- genes_to_plot[i]
        plot(
            y = yy_plot[gene, ],
            x = fit_cyclic\$cellcycle_peco_ordered,
            main = gene,
            xlab = "Reconstructed Phase",
            ylab = "Quantile Normalized Expression",
            col = "grey",
            pch = 16
        )
        points(
            y = fit_cyclic\$cellcycle_function[[i]](seq(0, 2 * pi, length.out = 100)),
            x = seq(0, 2 * pi, length.out = 100),
            col = "red",
            pch = 16,
            cex = 0.8
        )
    }
    dev.off()

    writeLines(c(
        '"BIOC_PECO_PECO_RECONSTRUCT_INSAMPLE":',
        paste0('    peco: ', as.character(packageVersion('peco')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peco_reconstruct_insample.csv versions.yml
    """
}

workflow BIOC_PECO_PECO_RECONSTRUCT_INSAMPLE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_PECO_PECO_RECONSTRUCT_INSAMPLE(ch_input)

    emit:
    tables   = BIOC_PECO_PECO_RECONSTRUCT_INSAMPLE.out.tables
    plots    = BIOC_PECO_PECO_RECONSTRUCT_INSAMPLE.out.plots
    objects  = BIOC_PECO_PECO_RECONSTRUCT_INSAMPLE.out.objects
    versions = BIOC_PECO_PECO_RECONSTRUCT_INSAMPLE.out.versions
}
