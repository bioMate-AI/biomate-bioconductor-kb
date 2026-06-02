#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RegionalST
// This package analyze spatial transcriptomics data through cross-regional cell type-specific analysis
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RegionalST/inst/doc/RegionalST.R
// Upstream  : BayesSpace, CARD, Matrix, ggplot2, gridExtra
// Downstream: none
//
// Install: BiocManager::install("RegionalST")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REGIONALST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-regionalst"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-regionalst:1.4.2--r44_0' :
        'quay.io/biocontainers/bioconductor-regionalst:1.4.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_regionalst_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_regionalst_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_regionalst_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RegionalST)
    library(CARD_deconvolution)
    library(GetOneRadiusEntropy_withProp)
    library(ManualSelectCenter)
    library(PlotOneSelectedCenter)
    library(RankCenterByEntropy_withProp)
    library(SingleCellExperiment)
    library(jsonlite)

    # --- Entropy Calculation [] ---
    # Key functions: GetOneRadiusEntropy_withProp
    weight <- data.frame(
        celltype = c("Cancer Epithelial", "CAFs", "T-cells", "Endothelial",
                     "PVL", "Myeloid", "B-cells", "Normal Epithelial",
                     "Plasmablasts"),
        weight = c(0.25, 0.05, 0.25, 0.05, 0.025, 0.05, 0.25, 0.05, 0.025)
    )
    OneRad <- GetOneRadiusEntropy_withProp(
        example_sce,
        selectN = length(example_sce$spot),
        weight = weight,
        radius = 5,
        doPlot = FALSE,
        mytitle = "Radius 5 weighted entropy"
    )


    # --- Region of Interest Selection [] ---
    # Key functions: RankCenterByEntropy_withProp, PlotOneSelectedCenter, DrawRegionProportion_withProp
    example_sce <- RankCenterByEntropy_withProp(
        example_sce,
        weight,
        selectN = round(length(example_sce$spot) / 5),
        topN = 3,
        min_radius = 10,
        radius_vec = c(5, 10),
        doPlot = FALSE
    )
    sel_plot <- PlotOneSelectedCenter(example_sce, ploti = 1)
    prop_plot <- DrawRegionProportion_withProp(
        example_sce,
        label = "CellType",
        selCenter = c(1, 2, 3)
    )


    # --- Cross-Regional Differential Expression [] ---
    # Key functions: GetCrossRegionalDE_withProp
    CR12_DE <- GetCrossRegionalDE_withProp(
        example_sce,
        twoCenter = c(1, 2),
        label = "celltype",
        angle = 30,
        hjust = 0,
        size = 3,
        padj_filter = 0.05,
        doHeatmap = FALSE
    )


    # --- Cell-Type Specific Regional Analysis [] ---
    # Key functions: FindRegionalCells, GetCellTypeSpecificDE_withProp
    thisID1 <- S4Vectors::metadata(example_sce)$selectCenters$selectID[1]
    OutRegRes1 <- FindRegionalCells(
        example_sce,
        centerID = thisID1,
        radius = 20,
        enhanced = FALSE,
        doPlot = FALSE,
        returnPlot = FALSE
    )
    thisID2 <- S4Vectors::metadata(example_sce)$selectCenters$selectID[2]
    OutRegRes2 <- FindRegionalCells(
        example_sce,
        centerID = thisID2,
        radius = 20,
        enhanced = FALSE,
        doPlot = FALSE,
        returnPlot = FALSE
    )
    CTS_DE <- GetCellTypeSpecificDE_withProp(
        example_sce,
        Regional1ID = OutRegRes1$closeID,
        Regional2ID = OutRegRes2$closeID,
        n_markers = 10,
        angle = 30,
        hjust = 0,
        size = 3,
        padj_filter = 1,
        doHeatmap = FALSE
    )


    # --- Pathway Enrichment Analysis [] ---
    # Key functions: DoGSEA, DrawDotplot
    lCTres <- list(CTS_DE)
    CTres <- DoGSEA(lCTres, whichDB = "hallmark", withProp = TRUE)
    gsea_plot <- DrawDotplot(
        CTres,
        CT = 1,
        angle = 15,
        vjust = 1,
        chooseP = "padj"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_regionalst_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_regionalst_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_regionalst_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REGIONALST:", paste0("    regionalst: ", packageVersion("RegionalST"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regionalst_results.csv
    touch ${prefix}_regionalst_output.rds
    echo "BIOC_REGIONALST:" > versions.yml
    echo "    regionalst: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REGIONALST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REGIONALST(ch_input)

    emit:
    results  = BIOC_REGIONALST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REGIONALST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REGIONALST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REGIONALST.out.versions  // channel: path(versions.yml)
}
