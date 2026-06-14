#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: regionalst — analysis_with_cell_type_proportions
// Perform ROI selection, cross-regional differential expression, and pathway enrichment using continuous cell type deconvolution proportions.
// Input: path/to/spaceranger/outs/, CARD_obj
// Container: quay.io/biocontainers/bioconductor-regionalst:1.8.0--r45hdfd78af_0
// R packages: S4Vectors, BayesSpace, card, ggplot2, gridExtra, Matrix, RegionalST
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: dot plot, enrichment plot

nextflow.enable.dsl = 2

process BIOC_REGIONALST_ANALYSIS_WITH_CELL_TYPE_PROPORTIONS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-regionalst:1.8.0--r45hdfd78af_0"

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
    .bm_deps <- c("S4Vectors", "BayesSpace", "card", "ggplot2", "gridExtra", "Matrix", "RegionalST")
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
    library(BayesSpace)
    library(RegionalST)
    library(S4Vectors)
    library(gridExtra)
    library(ggplot2)
    
    # Create output directory
    dir.create("outputs", showWarnings = FALSE, recursive = TRUE)
    
    # --- Load and preprocess spatial data using BayesSpace ---
    # Read Visium data from the declared user input directory
    sce <- BayesSpace::readVisium("path/to/spaceranger/outs/")
    
    # Read CARD deconvolution results from the declared user input file
    CARD_obj <- readRDS("CARD_obj")
    
    # Add deconvolution proportions to the SCE object metadata
    S4Vectors::metadata(sce)\$Proportions <- RegionalST::getProportions(CARD_obj)
    
    # Extract proportions and assign dominant cell type labels to the spots
    props <- S4Vectors::metadata(sce)\$Proportions
    dominant_celltype <- colnames(props)[apply(props, 1, which.max)]
    sce\$celltype <- dominant_celltype
    sce\$CellType <- dominant_celltype  # Ensure both cases are covered for downstream functions
    sce\$spot <- colnames(sce)
    
    # Preprocess spatial transcriptomics data
    sce <- sce[, colSums(counts(sce)) > 0]
    sce <- mySpatialPreprocess(sce, platform="Visium")
    
    # Set required spatial coordinate metadata for plotting
    sce\$"array_col" <- sce\$col
    sce\$"array_row" <- sce\$row
    sce\$"pxl_col_in_fullres" <- sce\$imagecol
    sce\$"pxl_row_in_fullres" <- sce\$imagerow
    
    # --- Define cell type weights and calculate weighted entropy ---
    # Dynamically construct the weight data frame based on the cell types present in the deconvolution results
    celltypes <- colnames(props)
    weight <- data.frame(
      celltype = celltypes,
      weight = rep(1 / length(celltypes), length(celltypes))
    )
    
    # Calculate and plot weighted entropy at radius 5
    pdf("outputs/weighted_entropy_radius5.pdf")
    OneRad <- GetOneRadiusEntropy_withProp(sce,
                                 selectN = length(sce\$spot),
                                 weight = weight,
                                 radius = 5,
                                 doPlot = TRUE,
                                 mytitle = "Radius 5 weighted entropy")
    dev.off()
    
    # --- Automatically select Regions of Interest (ROIs) based on ---
    pdf("outputs/roi_selection.pdf")
    sce <- RankCenterByEntropy_withProp(sce, 
                                        weight,
                                        selectN = round(length(sce\$spot)/5),
                                        topN = 3, 
                                        min_radius = 10,
                                        radius_vec = c(5,10),
                                        doPlot = TRUE)
    dev.off()
    
    # Visualize and save the first selected ROI
    pdf("outputs/selected_center_1.pdf")
    PlotOneSelectedCenter(sce, ploti = 1)
    dev.off()
    
    # Draw and save cell type proportions for the selected ROIs
    pdf("outputs/region_proportions.pdf")
    DrawRegionProportion_withProp(sce,
                                  label = "CellType",
                                  selCenter = c(1,2,3))
    dev.off()
    
    # --- Perform cross-regional cell type-specific differential ---
    # Compare the first and second ROIs
    CR12_DE <- GetCrossRegionalDE_withProp(sce, 
                                           twoCenter = c(1,2),
                                           label = "celltype",
                                           angle = 30,
                                           hjust = 0,
                                           size = 3,
                                           padj_filter = 0.05,
                                           doHeatmap = TRUE)
    
    write.csv(CR12_DE\$allDE, "outputs/cross_regional_DE_1_vs_2.csv", row.names = TRUE)
    
    # Identify regional cells for self-defined cross-regional analysis
    thisID1 <- S4Vectors::metadata(sce)\$selectCenters\$selectID[1]
    thisRadius1 <- S4Vectors::metadata(sce)\$selectCenters\$selectRadius[1]
    OutRegRes1 <- RegionalST::FindRegionalCells(sce,
                                                centerID = thisID1,
                                                radius = 20,
                                                enhanced = FALSE,
                                                doPlot = FALSE,
                                                returnPlot = FALSE)
    
    thisID2 <- S4Vectors::metadata(sce)\$selectCenters\$selectID[2]
    thisRadius2 <- S4Vectors::metadata(sce)\$selectCenters\$selectRadius[2]
    OutRegRes2 <- RegionalST::FindRegionalCells(sce,
                                                centerID = thisID2,
                                                radius = 20,
                                                enhanced = FALSE,
                                                doPlot = FALSE,
                                                returnPlot = FALSE)
    
    Regional1ID <- OutRegRes1\$closeID
    Regional2ID <- OutRegRes2\$closeID
    
    # Perform cell type-specific differential expression across the two regions
    CTS_DE <- GetCellTypeSpecificDE_withProp(sce,
                                             Regional1ID = Regional1ID,
                                             Regional2ID = Regional2ID,
                                             n_markers = 10,
                                             angle = 30,
                                             hjust = 0,
                                             size = 3,
                                             padj_filter = 1,
                                             doHeatmap = FALSE)
    
    write.csv(CTS_DE\$allDE, "outputs/cell_type_specific_DE.csv", row.names = TRUE)
    
    # --- Run GSEA pathway enrichment on the DE genes and visualize ---
    lCTres <- list(CTS_DE)
    CTres <- DoGSEA(lCTres, whichDB = "hallmark", withProp = TRUE)
    
    saveRDS(CTres, "outputs/gsea_results.rds")
    
    # Draw and save GSEA dotplots for the identified pathways
    pdf("outputs/gsea_dotplots.pdf")
    tryCatch({
      DrawDotplot(CTres, CT = 1, angle = 15, vjust = 1, chooseP = "padj")
    }, error = function(e) {
      message("Could not draw GSEA dotplot for CT = 1: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_REGIONALST_ANALYSIS_WITH_CELL_TYPE_PROPORTIONS":',
        paste0('        regionalst: ', as.character(packageVersion("regionalst")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_analysis_with_cell_type_proportions.csv versions.yml
    """
}

workflow BIOC_REGIONALST_ANALYSIS_WITH_CELL_TYPE_PROPORTIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ path/to/spaceranger/outs/, CARD_obj ] ]

    main:
    BIOC_REGIONALST_ANALYSIS_WITH_CELL_TYPE_PROPORTIONS(ch_input)

    emit:
    tables   = BIOC_REGIONALST_ANALYSIS_WITH_CELL_TYPE_PROPORTIONS.out.tables
    plots    = BIOC_REGIONALST_ANALYSIS_WITH_CELL_TYPE_PROPORTIONS.out.plots
    objects  = BIOC_REGIONALST_ANALYSIS_WITH_CELL_TYPE_PROPORTIONS.out.objects
    versions = BIOC_REGIONALST_ANALYSIS_WITH_CELL_TYPE_PROPORTIONS.out.versions
}
