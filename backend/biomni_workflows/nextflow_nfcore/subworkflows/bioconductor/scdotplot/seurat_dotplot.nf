#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scDotPlot — seurat_dotplot
// Generate an annotated, hierarchically clustered dot plot from a Seurat object.
// Input: pbmc_small
// Container: quay.io/biocontainers/bioconductor-scdotplot:1.4.0--r45hdfd78af_0
// R packages: Seurat, SeuratObject, dplyr, ggplot2, ggsci, scDotPlot, tibble
// Bioconductor: 3.20 | R: 4.4
// Requires: Seurat, SeuratObject, dplyr, ggplot2, ggsci, scDotPlot, tibble
// Visualizations: dot plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Identify marker genes for each cluster
//  * 2. [Core Analysis] Add marker annotations to the Seurat assay metadata
//  * 3. [Visualization & Output] Generate the clustered dot plot with annotations using scDotPlot

nextflow.enable.dsl = 2

process BIOC_SCDOTPLOT_SEURAT_DOTPLOT {
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
    .bm_deps <- c("Seurat", "SeuratObject", "dplyr", "ggplot2", "ggsci", "scDotPlot", "tibble")
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
    library(Seurat)
    library(SeuratObject)
    library(tibble)
    library(dplyr)
    library(scDotPlot)
    library(ggsci)
    library(ggplot2)
    
    # 1. Read the input Seurat object
    pbmc_small <- readRDS("pbmc_small.rds")
    
    # 2. Identify marker genes for each cluster
    features_df <- pbmc_small |>
        FindAllMarkers(only.pos = TRUE, verbose = FALSE) |>
        group_by(cluster) |>
        dplyr::slice(1:6) |>
        dplyr::select(cluster, gene)
    
    # Save the identified marker genes to a CSV file
    write.csv(features_df, "marker_genes.csv", row.names = FALSE)
    
    # 3. Add marker annotations to the Seurat assay metadata
    pbmc_small[[DefaultAssay(pbmc_small)]][[]] <- pbmc_small[[DefaultAssay(pbmc_small)]][[]] |>
        rownames_to_column("gene") |> 
        left_join(features_df, by = "gene") |> 
        column_to_rownames("gene")
    
    # Save the annotated Seurat object
    saveRDS(pbmc_small, "pbmc_small_annotated.rds")
    
    # Deframe features for scDotPlot
    features <- features_df |> 
        deframe()
    
    # 4. Generate and save the unscaled (logcounts) dot plot
    p1 <- pbmc_small |>
        scDotPlot(features = features,
                  group = "RNA_snn_res.1",
                  groupAnno = "RNA_snn_res.1",
                  featureAnno = "cluster",
                  annoColors = list("RNA_snn_res.1" = pal_d3()(7),
                                    "cluster" = pal_d3()(7)),
                  groupLegends = FALSE,
                  annoWidth = 0.075)
    
    pdf("scdotplot_logcounts.pdf", width = 8, height = 8)
    print(p1)
    dev.off()
    
    # 5. Generate and save the scaled (Z-score) dot plot
    p2 <- pbmc_small |>
        scDotPlot(scale = TRUE,
                  features = features,
                  group = "RNA_snn_res.1",
                  groupAnno = "RNA_snn_res.1",
                  featureAnno = "cluster",
                  annoColors = list("RNA_snn_res.1" = pal_d3()(7),
                                    "cluster" = pal_d3()(7)),
                  groupLegends = FALSE,
                  annoWidth = 0.075)
    
    pdf("scdotplot_zscores.pdf", width = 8, height = 8)
    print(p2)
    dev.off()

    writeLines(c(
        '"BIOC_SCDOTPLOT_SEURAT_DOTPLOT":',
        paste0('    scDotPlot: ', as.character(packageVersion('scDotPlot')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seurat_dotplot.csv versions.yml
    """
}

workflow BIOC_SCDOTPLOT_SEURAT_DOTPLOT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmc_small ] ]

    main:
    BIOC_SCDOTPLOT_SEURAT_DOTPLOT(ch_input)

    emit:
    tables   = BIOC_SCDOTPLOT_SEURAT_DOTPLOT.out.tables
    plots    = BIOC_SCDOTPLOT_SEURAT_DOTPLOT.out.plots
    objects  = BIOC_SCDOTPLOT_SEURAT_DOTPLOT.out.objects
    versions = BIOC_SCDOTPLOT_SEURAT_DOTPLOT.out.versions
}
