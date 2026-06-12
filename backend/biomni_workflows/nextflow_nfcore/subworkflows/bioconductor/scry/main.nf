#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scry — sce_deviance_glmpca
// Perform deviance-based feature selection and GLM-PCA dimension reduction on a SingleCellExperiment object.
// Input: sce
// Container: quay.io/biocontainers/bioconductor-scry:1.22.0--r45hdfd78af_0
// R packages: duoclustering2018, ggplot2, scry, SingleCellExperiment, tenxpbmcdata
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, ggplot2, scry
// Visualizations: PCA plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Rank genes based on binomial deviance using devianceFeatureSelection
//  * 2. [Core Analysis] Subset the SingleCellExperiment to keep only high-deviance genes
//  * 3. [Core Analysis] Run GLM-PCA to reduce dimensionality
//  * 4. [Visualization & Output] Extract latent factors from metadata for visualization

nextflow.enable.dsl = 2

process BIOC_SCRY_SCE_DEVIANCE_GLMPCA {
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
    .bm_deps <- c("duoclustering2018", "ggplot2", "scry", "SingleCellExperiment", "tenxpbmcdata", "SummarizedExperiment")
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
    
    # Set ggplot theme
    theme_set(theme_bw())
    
    # 1. Read the input SingleCellExperiment object
    input_file <- "sce"
    if (!file.exists(input_file) && file.exists("sce.rds")) {
      input_file <- "sce.rds"
    }
    
    if (!file.exists(input_file)) {
      stop("Error: Input file 'sce' or 'sce.rds' not found in the working directory.")
    }
    
    sce <- readRDS(input_file)
    
    # Ensure the "counts" assay exists
    if (!"counts" %in% assayNames(sce)) {
      stop("Error: The input SingleCellExperiment object must contain a 'counts' assay.")
    }
    
    # 2. Rank genes based on binomial deviance
    sce<-devianceFeatureSelection(sce, assay="counts", sorted=TRUE)
    
    # Save deviance feature selection plot
    pdf("deviance_plot.pdf", width=6, height=4)
    plot(rowData(sce)\$binomial_deviance, type="l", xlab="ranked genes",
         ylab="binomial deviance", main="Feature Selection with Deviance")
    abline(v=min(2000, nrow(sce)), lty=2, col="red")
    dev.off()
    
    # Save deviance features table
    write.csv(as.data.frame(rowData(sce)), "deviance_features.csv", row.names=TRUE)
    
    # 3. Subset the SingleCellExperiment to keep only high-deviance genes
    # Use min(1000, nrow(sce)) to handle cases where the input has fewer than 1000 genes
    num_genes_to_keep <- min(1000, nrow(sce))
    sce2<-sce[1:num_genes_to_keep, ]
    
    # 4. Run GLM-PCA to reduce dimensionality
    set.seed(101)
    sce2<-GLMPCA(sce2, 2, assay="counts")
    
    # 5. Extract latent factors from metadata for visualization
    fit<-metadata(sce2)\$glmpca
    pd<-cbind(as.data.frame(colData(sce2)), fit\$factors)
    
    # Save GLM-PCA factors table
    write.csv(pd, "glmpca_factors.csv", row.names=TRUE)
    
    # Save the updated SingleCellExperiment object
    saveRDS(sce2, "sce_glmpca_out.rds")
    
    # Generate and save GLM-PCA plot
    pdf("glmpca_plot.pdf", width=6, height=4)
    # Dynamically check for a cell type or phenotype column to color the plot
    color_col <- NULL
    possible_cols <- c("phenoid", "celltype", "cell_type", "CellType", "label", "cluster")
    for (col in possible_cols) {
      if (col %in% colnames(pd)) {
        color_col <- col
        break
      }
    }
    
    if (!is.null(color_col)) {
      p <- ggplot(pd, aes(x=dim1, y=dim2, colour=.data[[color_col]])) +
           geom_point(size=.8) +
           ggtitle("GLM-PCA applied to high deviance genes")
    } else {
      p <- ggplot(pd, aes(x=dim1, y=dim2)) +
           geom_point(size=.8) +
           ggtitle("GLM-PCA applied to high deviance genes")
    }
    print(p)
    dev.off()

    writeLines(c(
        '"BIOC_SCRY_SCE_DEVIANCE_GLMPCA":',
        paste0('    scry: ', as.character(packageVersion('scry')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sce_deviance_glmpca.csv versions.yml
    """
}

workflow BIOC_SCRY_SCE_DEVIANCE_GLMPCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce ] ]

    main:
    BIOC_SCRY_SCE_DEVIANCE_GLMPCA(ch_input)

    emit:
    tables   = BIOC_SCRY_SCE_DEVIANCE_GLMPCA.out.tables
    plots    = BIOC_SCRY_SCE_DEVIANCE_GLMPCA.out.plots
    objects  = BIOC_SCRY_SCE_DEVIANCE_GLMPCA.out.objects
    versions = BIOC_SCRY_SCE_DEVIANCE_GLMPCA.out.versions
}
