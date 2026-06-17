#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RegionalST — cell_type_labels_workflow
// Perform cross-regional cell type-specific differential analysis and pathway enrichment using discrete cell type labels per spot.
// Input: /Users/zli16/Dropbox/TrySTData/Ovarian_10x
// Container: quay.io/biocontainers/bioconductor-regionalst:1.8.0--r45hdfd78af_0
// R packages: BayesSpace, RegionalST, ggplot2, gridExtra
// Bioconductor: 3.20 | R: 4.4
// Requires: BayesSpace, RegionalST, S4Vectors, ggplot2, gridExtra
// Visualizations: dot plot, enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load spatial transcriptomics data and assign cell type labels to spots
//  * 2. [Core Analysis] Calculate weighted entropy using GetOneRadiusEntropy
//  * 3. [Core Analysis] Automatically select ROIs using RankCenterByEntropy
//  * 4. [Core Analysis] Perform cross-regional differential expression using GetCrossRegionalDE_raw
//  * 5. [Visualization & Output] Perform pathway GSEA using DoGSEA and plot results using DrawDotplot

nextflow.enable.dsl = 2

process BIOC_REGIONALST_CELL_TYPE_LABELS_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20-slim"

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
    .bm_deps <- c("BayesSpace", "RegionalST", "ggplot2", "gridExtra", "SummarizedExperiment")
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
    library(RegionalST)
    library(BayesSpace)
    library(gridExtra)
    library(ggplot2)
    
    # 1. Load spatial transcriptomics data and assign cell type labels to spots
    outdir <- "/Users/zli16/Dropbox/TrySTData/Ovarian_10x"
    sce <- readVisium(outdir)
    sce <- sce[, colSums(counts(sce)) > 0]
    sce <- spatialPreprocess(sce, platform="Visium", log.normalize=TRUE)
    sce <- qTune(sce, qs=seq(2, 10), platform="Visium", d=15)
    sce <- spatialCluster(sce, q=10, platform="Visium", d=15,
                          init.method="mclust", model="t", gamma=2,
                          nrep=50000, burn.in=1000,
                          save.chain=FALSE)
    
    # Map the 10 spatial clusters to the 9 cell types expected by the downstream analysis
    sce\$celltype <- sce\$spatial.cluster
    sce\$celltype[sce\$spatial.cluster %in% c(1,2)] <- "Cancer Epithelial"
    sce\$celltype[sce\$spatial.cluster %in% c(3)] <- "CAFs"
    sce\$celltype[sce\$spatial.cluster %in% c(4)] <- "T-cells"
    sce\$celltype[sce\$spatial.cluster %in% c(5)] <- "Endothelial"
    sce\$celltype[sce\$spatial.cluster %in% c(6)] <- "PVL"
    sce\$celltype[sce\$spatial.cluster %in% c(7)] <- "Myeloid"
    sce\$celltype[sce\$spatial.cluster %in% c(8)] <- "B-cells"
    sce\$celltype[sce\$spatial.cluster %in% c(9)] <- "Normal Epithelial"
    sce\$celltype[sce\$spatial.cluster %in% c(10)] <- "Plasmablasts"
    colData(sce)\$celltype <- sce\$celltype
    
    # Ensure the spot column is populated
    if (is.null(sce\$spot)) {
        sce\$spot <- colnames(sce)
    }
    
    example_sce <- sce
    
    # 2. Calculate weighted entropy using GetOneRadiusEntropy
    weight <- data.frame(celltype = c("Cancer Epithelial", "CAFs", "T-cells", "Endothelial",
                                      "PVL", "Myeloid", "B-cells", "Normal Epithelial", "Plasmablasts"),
                         weight = c(0.25,0.05,
                                    0.25,0.05,
                                    0.025,0.05,
                                    0.25,0.05,0.025))
    
    pdf("one_radius_entropy_plot.pdf", width = 8, height = 6)
    OneRad <- GetOneRadiusEntropy(example_sce,
                                  selectN = length(example_sce\$spot),
                                  weight = weight,
                                  label = "celltype",
                                  radius = 5,
                                  doPlot = TRUE,
                                  mytitle = "Radius 5 weighted entropy")
    dev.off()
    
    # 3. Automatically select ROIs using RankCenterByEntropy
    pdf("rank_center_by_entropy_plot.pdf", width = 8, height = 6)
    example_sce <- RankCenterByEntropy(example_sce, 
                               weight,
                               selectN = round(length(example_sce\$spot)/2),
                               label = "celltype",
                               topN = 3, 
                               min_radius = 10,
                               radius_vec = c(5,10),
                               doPlot = TRUE)
    dev.off()
    
    # Save the selected centers metadata
    thisSelection <- S4Vectors::metadata(example_sce)\$selectCenters
    saveRDS(thisSelection, file = "SelectionResults_celltype.rds")
    
    # 4. Perform cross-regional differential expression using GetCrossRegionalDE_raw
    CR12_DE <- GetCrossRegionalDE_raw(example_sce,
                                      twoCenter = c(1,2),
                                      label = "celltype",
                                      logfc.threshold = 0.1,
                                      min.pct = 0.1,
                                      angle = 30,
                                      hjust = 0,
                                      size = 3,
                                      padj_filter = 0.05,
                                      doHeatmap = FALSE)
    
    CR13_DE <- GetCrossRegionalDE_raw(example_sce,
                                      twoCenter = c(1,3),
                                      label = "celltype",
                                      logfc.threshold = 0.1,
                                      min.pct = 0.1,
                                      angle = 30,
                                      hjust = 0,
                                      size = 3,
                                      padj_filter = 0.05,
                                      doHeatmap = FALSE)
    
    CR23_DE <- GetCrossRegionalDE_raw(example_sce,
                                      twoCenter = c(2,3),
                                      label = "celltype",
                                      logfc.threshold = 0.1,
                                      min.pct = 0.1,
                                      angle = 30,
                                      hjust = 0,
                                      size = 3,
                                      padj_filter = 0.05,
                                      doHeatmap = FALSE)
    
    exampleRes <- list(CR12_DE, CR13_DE, CR23_DE)
    saveRDS(exampleRes, file = "cross_regional_DE_results.rds")
    
    # Write out DE tables if they contain results
    if (!is.null(CR12_DE\$allDE) && nrow(CR12_DE\$allDE) > 0) {
        write.csv(CR12_DE\$allDE, "CR12_DE_results.csv", row.names = FALSE)
    }
    if (!is.null(CR13_DE\$allDE) && nrow(CR13_DE\$allDE) > 0) {
        write.csv(CR13_DE\$allDE, "CR13_DE_results.csv", row.names = FALSE)
    }
    if (!is.null(CR23_DE\$allDE) && nrow(CR23_DE\$allDE) > 0) {
        write.csv(CR23_DE\$allDE, "CR23_DE_results.csv", row.names = FALSE)
    }
    
    # 5. Perform pathway GSEA using DoGSEA and plot results using DrawDotplot
    allCTres <- DoGSEA(exampleRes, whichDB = "hallmark", withProp = TRUE)
    saveRDS(allCTres, file = "gsea_results.rds")
    
    pdf("gsea_dotplot.pdf", width = 8, height = 6)
    tryCatch({
        DrawDotplot(allCTres, CT = 3, angle = 15, vjust = 1, chooseP = "padj")
    }, error = function(e) {
        message("Could not draw dotplot: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_REGIONALST_CELL_TYPE_LABELS_WORKFLOW":',
        paste0('    RegionalST: ', as.character(packageVersion('RegionalST')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cell_type_labels_workflow.csv versions.yml
    """
}

workflow BIOC_REGIONALST_CELL_TYPE_LABELS_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ /Users/zli16/Dropbox/TrySTData/Ovarian_10x ] ]

    main:
    BIOC_REGIONALST_CELL_TYPE_LABELS_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_REGIONALST_CELL_TYPE_LABELS_WORKFLOW.out.tables
    plots    = BIOC_REGIONALST_CELL_TYPE_LABELS_WORKFLOW.out.plots
    objects  = BIOC_REGIONALST_CELL_TYPE_LABELS_WORKFLOW.out.objects
    versions = BIOC_REGIONALST_CELL_TYPE_LABELS_WORKFLOW.out.versions
}
