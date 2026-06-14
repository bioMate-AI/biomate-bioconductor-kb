#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scry — sce_null_residuals_pca
// Perform fast dimension reduction approximation by computing null residuals and running standard PCA.
// Input: sce
// Container: quay.io/biocontainers/bioconductor-scry:1.22.0--r45hdfd78af_0
// R packages: SingleCellExperiment, ggplot2, scry
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, ggplot2, scry
// Visualizations: PCA plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute deviance and Pearson null residuals using nullResiduals
//  * 2. [Core Analysis] Subset the SingleCellExperiment to high-deviance genes
//  * 3. [Core Analysis] Run standard PCA on the computed residuals

nextflow.enable.dsl = 2

process BIOC_SCRY_SCE_NULL_RESIDUALS_PCA {
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
    .bm_deps <- c("SingleCellExperiment", "ggplot2", "scry", "SummarizedExperiment")
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
    suppressPackageStartupMessage      library(SummarizedExperiment)
s({
      library(scry)
      library(ggplot2)
    })
    
    # 1. Read input file from the working directory
    sce_path <- "sce.rds"
    if (!file.exists(sce_path)) {
      sce_path <- "sce"
    }
    
    if (!file.exists(sce_path)) {
      stop("Error: Input file 'sce.rds' or 'sce' not found in the working directory.")
    }
    
    sce <- readRDS(sce_path)
    
    # Ensure deviance feature selection is run so that subsetting [1:1000, ] 
    # actually selects the high-deviance genes as intended.
    sce <- devianceFeatureSelection(sce, assay="counts", sorted=TRUE)
    
    # 2. Compute deviance and Pearson null residuals using nullResiduals
    sce <- nullResiduals(sce, assay="counts", type="deviance")
    sce <- nullResiduals(sce, assay="counts", type="pearson")
    
    # 3. Subset the SingleCellExperiment to high-deviance genes
    n_genes <- min(1000, nrow(sce))
    sce2 <- sce[1:n_genes, ]
    
    # 4. Run standard PCA on the computed residuals
    pca <- function(Y, L=2, center=TRUE, scale=TRUE){
        res <- prcomp(as.matrix(t(Y)), center=center, scale.=scale, rank.=L)
        factors <- as.data.frame(res\$x)
        colnames(factors) <- paste0("dim", 1:L)
        factors
    }
    
    pca_d <- pca(assay(sce2, "binomial_deviance_residuals"))
    pca_d\$resid_type <- "deviance_residuals"
    
    pca_p <- pca(assay(sce2, "binomial_pearson_residuals"))
    pca_p\$resid_type <- "pearson_residuals"
    
    # 5. Save outputs
    # Save the updated SingleCellExperiment object containing the residuals
    saveRDS(sce, "sce_residuals.rds")
    
    # Save PCA coordinates as CSV tables
    write.csv(pca_d, "pca_deviance_residuals.csv", row.names=TRUE)
    write.csv(pca_p, "pca_pearson_residuals.csv", row.names=TRUE)
    
    # Generate and save the visualization plot
    cm <- as.data.frame(colData(sce2))
    pd <- rbind(cbind(cm, pca_d), cbind(cm, pca_p))
    
    p <- ggplot(pd, aes(x=dim1, y=dim2))
    if ("phenoid" %in% colnames(pd)) {
      p <- p + geom_point(aes(colour=phenoid), alpha=0.7)
    } else if (ncol(cm) > 0) {
      # Fallback to the first column of colData if phenoid is not present
      color_col <- colnames(cm)[1]
      p <- p + geom_point(aes(colour=as.factor(.data[[color_col]])), alpha=0.7) + 
               labs(colour=color_col)
    } else {
      p <- p + geom_point(alpha=0.7)
    }
    
    p <- p + facet_wrap(~resid_type, scales="free", nrow=2) +
      theme_bw() +
      ggtitle("PCA applied to null residuals of high deviance genes")
    
    ggsave("pca_residuals_plot.pdf", plot=p, width=8, height=8)

    writeLines(c(
        '"BIOC_SCRY_SCE_NULL_RESIDUALS_PCA":',
        paste0('    scry: ', as.character(packageVersion('scry')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sce_null_residuals_pca.csv versions.yml
    """
}

workflow BIOC_SCRY_SCE_NULL_RESIDUALS_PCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce ] ]

    main:
    BIOC_SCRY_SCE_NULL_RESIDUALS_PCA(ch_input)

    emit:
    tables   = BIOC_SCRY_SCE_NULL_RESIDUALS_PCA.out.tables
    plots    = BIOC_SCRY_SCE_NULL_RESIDUALS_PCA.out.plots
    objects  = BIOC_SCRY_SCE_NULL_RESIDUALS_PCA.out.objects
    versions = BIOC_SCRY_SCE_NULL_RESIDUALS_PCA.out.versions
}
