#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: regionalst — analysis_with_cell_type_labels
// Perform ROI selection, cross-regional differential expression, and pathway enrichment using discrete cell type labels (e.g., major cell type per spot).
// Input: path/to/spaceranger/outs/, cell_type_labels
// Container: quay.io/biocontainers/bioconductor-regionalst:1.8.0--r45hdfd78af_0
// R packages: BayesSpace, RegionalST, SingleCellExperiment, ggplot2, gridExtra
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REGIONALST_ANALYSIS_WITH_CELL_TYPE_LABELS {
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
    .bm_deps <- c("BayesSpace", "RegionalST", "SingleCellExperiment", "ggplot2", "gridExtra")
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
    library(SingleCellExperiment)
    library(gridExtra)
    library(ggplot2)
    
    # 1. Load and preprocess spatial data
    # Read Visium data from the specified user input directory
    sce <- readVisium("path/to/spaceranger/outs/")
    
    # Read discrete cell type labels from the specified user input file
    cell_type_labels_path <- "cell_type_labels"
    cell_labels <- tryCatch({
      read.csv(cell_type_labels_path, stringsAsFactors = FALSE)
    }, error = function(e) {
      read.delim(cell_type_labels_path, stringsAsFactors = FALSE)
    })
    
    # Align cell type labels with the spots in the SingleCellExperiment object
    # We assume the first column contains spot barcodes and the second contains cell types
    barcode_col <- colnames(cell_labels)[1]
    celltype_col <- colnames(cell_labels)[2]
    
    rownames(cell_labels) <- cell_labels[[barcode_col]]
    common_spots <- intersect(colnames(sce), rownames(cell_labels))
    sce <- sce[, common_spots]
    sce\$celltype <- cell_labels[common_spots, celltype_col]
    
    # Preprocess spatial transcriptomics data
    sce <- sce[, colSums(counts(sce)) > 0]
    sce <- mySpatialPreprocess(sce, platform="Visium")
    
    # Set required parameters for BayesSpace plotting
    sce\$"array_col" <- sce\$col
    sce\$"array_row" <- sce\$row
    sce\$"pxl_col_in_fullres" <- sce\$imagecol
    sce\$"pxl_row_in_fullres" <- sce\$imagerow
    
    if (is.null(sce\$spot)) {
      sce\$spot <- colnames(sce)
    }
    
    # Assign to example_sce to match the documented code variables
    example_sce <- sce
    
    # 2. Define cell type weights and calculate weighted entropy using discrete labels
    # Dynamically define weights based on the actual cell types in the input data
    unique_cts <- unique(example_sce\$celltype)
    if (all(c("Cancer Epithelial", "CAFs", "T-cells") %in% unique_cts)) {
      weight <- data.frame(celltype = c("Cancer Epithelial", "CAFs", "T-cells", "Endothelial",
                                        "PVL", "Myeloid", "B-cells", "Normal Epithelial", "Plasmablasts"),
                           weight = c(0.25,0.05,
                                      0.25,0.05,
                                      0.025,0.05,
                                      0.25,0.05,0.025))
    } else {
      weight <- data.frame(celltype = unique_cts,
                           weight = rep(1 / length(unique_cts), length(unique_cts)))
    }
    
    # Calculate weighted entropy
    OneRad <- GetOneRadiusEntropy(example_sce,
                                  selectN = length(example_sce\$spot),
                                  weight = weight,
                                  label = "celltype",
                                  radius = 5,
                                  doPlot = TRUE,
                                  mytitle = "Radius 5 weighted entropy")
    
    # Save the entropy plot
    pdf("radius_5_weighted_entropy.pdf")
    print(OneRad)
    dev.off()
    
    # 3. Automatically select ROIs based on label entropy
    example_sce <- RankCenterByEntropy(example_sce, 
                               weight,
                               selectN = round(length(example_sce\$spot)/2),
                               label = "celltype",
                               topN = 3, 
                               min_radius = 10,
                               radius_vec = c(5,10),
                               doPlot = TRUE)
    
    # Save the ranked SCE object and selected centers
    saveRDS(example_sce, "processed_sce_with_ROIs.rds")
    thisSelection <- S4Vectors::metadata(example_sce)\$selectCenters
    write.csv(thisSelection, "selected_ROI_centers.csv", row.names = FALSE)
    
    # 4. Perform cross-regional differential expression using raw labels
    CR12_DE <- tryCatch({
      GetCrossRegionalDE_raw(example_sce,
                             twoCenter = c(1,2),
                             label = "celltype",
                             logfc.threshold = 0.1,
                             min.pct = 0.1,
                             angle = 30,
                             hjust = 0,
                             size = 3,
                             padj_filter = 0.05,
                             doHeatmap = FALSE)
    }, error = function(e) {
      message("CR12_DE failed: ", e\$message)
      NULL
    })
    
    if (!is.null(CR12_DE) && !is.null(CR12_DE\$allDE)) {
      write.csv(CR12_DE\$allDE, "cross_regional_DE_CR12.csv", row.names = FALSE)
    }
    
    # Compute other pairs to construct exampleRes for GSEA
    CR13_DE <- tryCatch({
      GetCrossRegionalDE_raw(example_sce,
                             twoCenter = c(1,3),
                             label = "celltype",
                             logfc.threshold = 0.1,
                             min.pct = 0.1,
                             angle = 30,
                             hjust = 0,
                             size = 3,
                             padj_filter = 0.05,
                             doHeatmap = FALSE)
    }, error = function(e) {
      message("CR13_DE failed: ", e\$message)
      NULL
    })
    
    CR23_DE <- tryCatch({
      GetCrossRegionalDE_raw(example_sce,
                             twoCenter = c(2,3),
                             label = "celltype",
                             logfc.threshold = 0.1,
                             min.pct = 0.1,
                             angle = 30,
                             hjust = 0,
                             size = 3,
                             padj_filter = 0.05,
                             doHeatmap = FALSE)
    }, error = function(e) {
      message("CR23_DE failed: ", e\$message)
      NULL
    })
    
    exampleRes <- list(CR12_DE, CR13_DE, CR23_DE)
    saveRDS(exampleRes, "cross_regional_DE_all_pairs.rds")
    
    # 5. Run GSEA pathway enrichment on the DE results
    allCTres <- tryCatch({
      DoGSEA(exampleRes, whichDB = "hallmark", withProp = TRUE)
    }, error = function(e) {
      message("GSEA failed: ", e\$message)
      NULL
    })
    
    if (!is.null(allCTres)) {
      saveRDS(allCTres, "gsea_results.rds")
      
      # Draw and save the dotplot for cell type 3
      pdf("gsea_dotplot_ct3.pdf")
      tryCatch({
        DrawDotplot(allCTres, CT = 3, angle = 15, vjust = 1, chooseP = "padj")
      }, error = function(e) {
        message("DrawDotplot failed: ", e\$message)
      })
      dev.off()
    }

    cat <<-END_VERSIONS > versions.yml
    "BIOC_REGIONALST_ANALYSIS_WITH_CELL_TYPE_LABELS":
        regionalst: \$(Rscript -e 'cat(as.character(packageVersion("regionalst")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_analysis_with_cell_type_labels.csv versions.yml
    """
}

workflow BIOC_REGIONALST_ANALYSIS_WITH_CELL_TYPE_LABELS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ path/to/spaceranger/outs/, cell_type_labels ] ]

    main:
    BIOC_REGIONALST_ANALYSIS_WITH_CELL_TYPE_LABELS(ch_input)

    emit:
    tables   = BIOC_REGIONALST_ANALYSIS_WITH_CELL_TYPE_LABELS.out.tables
    plots    = BIOC_REGIONALST_ANALYSIS_WITH_CELL_TYPE_LABELS.out.plots
    objects  = BIOC_REGIONALST_ANALYSIS_WITH_CELL_TYPE_LABELS.out.objects
    versions = BIOC_REGIONALST_ANALYSIS_WITH_CELL_TYPE_LABELS.out.versions
}
