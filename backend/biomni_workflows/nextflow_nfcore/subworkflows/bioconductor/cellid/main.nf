#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CelliD — cell_type_prediction
// Predict cell types for individual cells in a single-cell dataset using pre-established marker gene lists without clustering.
// Input: expression_matrix.rds, metadata.rds, marker_database.tsv
// Container: quay.io/biocontainers/bioconductor-cellid:1.18.0--r45ha27e39d_0
// R packages: Seurat, CelliD, ggplot2, ggpubr, msigdbr, tidyverse
// Bioconductor: 3.20 | R: 4.4
// Requires: CelliD, Seurat, ggplot2, tidyverse
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter expression matrix for protein-coding genes using HgProteinCodingGenes
//  * 2. [Input & Preparation] Create and normalize Seurat object using CreateSeuratObject, NormalizeData, and ScaleData
//  * 3. [Core Analysis] Perform MCA dimensionality reduction using RunMCA
//  * 4. [Input & Preparation] Prepare marker gene sets as a named list of vectors
//  * 5. [Core Analysis] Assess per-cell gene signature enrichment against marker lists using RunCellHGT
//  * 6. [Core Analysis] Assign cell types based on the lowest significant corrected p-value

nextflow.enable.dsl = 2

process BIOC_CELLID_CELL_TYPE_PREDICTION {
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
    .bm_deps <- c("Seurat", "CelliD", "ggplot2", "ggpubr", "msigdbr", "tidyverse")
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
    library(CelliD)
    library(tidyverse)
    library(Seurat)
    library(ggplot2)
    
    # 1. Read user input files
    BaronMatrix <- readRDS("expression_matrix.rds")
    BaronMetaData <- readRDS("metadata.rds")
    
    # Retrieve protein-coding genes list from CelliD package without using data()
    HgProteinCodingGenes <- CelliD::HgProteinCodingGenes
    BaronMatrixProt <- BaronMatrix[rownames(BaronMatrix) %in% HgProteinCodingGenes,]
    
    # 2. Create and normalize Seurat object
    # Ensure cell.type metadata column exists or create a fallback to avoid downstream plotting errors
    if (!"cell.type" %in% colnames(BaronMetaData)) {
      if (ncol(BaronMetaData) > 0) {
        BaronMetaData\$cell.type <- BaronMetaData[[1]]
      } else {
        BaronMetaData\$cell.type <- "unknown"
      }
    }
    
    Baron <- CreateSeuratObject(counts = BaronMatrixProt, project = "Baron", min.cells = 5, meta.data = BaronMetaData)
    Baron <- NormalizeData(Baron)
    Baron <- ScaleData(Baron, features = rownames(Baron))
    
    # 3. Perform MCA dimensionality reduction
    Baron <- RunMCA(Baron)
    
    # Generate and save MCA plot
    pdf("mca_plot.pdf", width = 10, height = 8)
    plot_features <- intersect(c("CTRL", "INS", "MYZAP", "CDH11"), rownames(Baron))
    if (length(plot_features) > 0) {
      p <- DimPlotMC(Baron, reduction = "mca", group.by = "cell.type", features = plot_features, as.text = TRUE) + 
        ggtitle("MCA with some key gene markers")
      print(p)
    } else {
      p <- DimPlotMC(Baron, reduction = "mca", group.by = "cell.type", as.text = TRUE) + 
        ggtitle("MCA Plot")
      print(p)
    }
    dev.off()
    
    # 4. Prepare marker gene sets as a named list of vectors
    panglao <- read_tsv("marker_database.tsv")
    
    # Robust filtering in case the input database has different column values
    panglao_pancreas <- panglao
    if ("organ" %in% colnames(panglao) && "Pancreas" %in% panglao\$organ) {
      panglao_pancreas <- panglao_pancreas %>% filter(organ == "Pancreas")
    }
    if ("species" %in% colnames(panglao)) {
      panglao_pancreas <- panglao_pancreas %>% filter(str_detect(species, "Hs"))
    }
    
    # Ensure standard PanglaoDB column names exist or map them
    if (!"cell type" %in% colnames(panglao_pancreas)) {
      colnames(panglao_pancreas)[1] <- "cell type"
    }
    if (!"official gene symbol" %in% colnames(panglao_pancreas)) {
      colnames(panglao_pancreas)[2] <- "official gene symbol"
    }
    
    panglao_pancreas <- panglao_pancreas %>%  
      group_by(`cell type`) %>%  
      summarise(geneset = list(`official gene symbol`))
    
    pancreas_gs <- setNames(panglao_pancreas\$geneset, panglao_pancreas\$`cell type`)
    
    # 5. Assess per-cell gene signature enrichment against marker lists
    HGT_pancreas_gs <- RunCellHGT(Baron, pathways = pancreas_gs, dims = 1:50, n.features = 200)
    
    # 6. Assign cell types based on the lowest significant corrected p-value
    pancreas_gs_prediction <- rownames(HGT_pancreas_gs)[apply(HGT_pancreas_gs, 2, which.max)]
    pancreas_gs_prediction_signif <- ifelse(apply(HGT_pancreas_gs, 2, max) > 2, yes = pancreas_gs_prediction, "unassigned")
    Baron\$pancreas_gs_prediction <- pancreas_gs_prediction_signif
    
    # Save outputs
    saveRDS(Baron, "predicted_cells_seurat.rds")
    
    predictions_df <- data.frame(
      cell_id = colnames(Baron),
      predicted_cell_type = Baron\$pancreas_gs_prediction,
      stringsAsFactors = FALSE
    )
    write.csv(predictions_df, "cell_type_predictions.csv", row.names = FALSE)
    write.csv(as.data.frame(HGT_pancreas_gs), "hgt_pvalues.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_CELLID_CELL_TYPE_PREDICTION":',
        paste0('    CelliD: ', as.character(packageVersion('CelliD')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cell_type_prediction.csv versions.yml
    """
}

workflow BIOC_CELLID_CELL_TYPE_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.rds, metadata.rds, marker_database.tsv ] ]

    main:
    BIOC_CELLID_CELL_TYPE_PREDICTION(ch_input)

    emit:
    tables   = BIOC_CELLID_CELL_TYPE_PREDICTION.out.tables
    plots    = BIOC_CELLID_CELL_TYPE_PREDICTION.out.plots
    objects  = BIOC_CELLID_CELL_TYPE_PREDICTION.out.objects
    versions = BIOC_CELLID_CELL_TYPE_PREDICTION.out.versions
}
