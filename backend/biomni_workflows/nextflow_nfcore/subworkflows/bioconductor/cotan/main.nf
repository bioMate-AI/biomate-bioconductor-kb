#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: COTAN — dataset_cleaning
// Clean raw single-cell UMI count datasets by identifying and removing doublets, dead cells, and low-efficiency cells.
// Input: rawDataset, vignette.cells.origin
// Container: quay.io/biocontainers/bioconductor-cotan:2.10.3--r45hdfd78af_0
// R packages: ComplexHeatmap, COTAN, GEOquery, qpdf, rlang, Rtsne, zeallot
// Bioconductor: 3.20 | R: 4.4
// Requires: COTAN, conflicted, zeallot
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Initialize the COTAN object and metadata. 2. Assign cell origin conditions. 3. Generate quality control plots (empirical cumulativ

nextflow.enable.dsl = 2

process BIOC_COTAN_DATASET_CLEANING {
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
    .bm_deps <- c("ComplexHeatmap", "COTAN", "GEOquery", "qpdf", "rlang", "Rtsne", "zeallot")
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
    library(COTAN)
    library(zeallot)
    conflicted::conflict_prefer("%<-%", "zeallot")
    
    # ==========================================
    # 1. READ USER INPUT FILES
    # ==========================================
    
    # Find rawDataset file in the working directory
    raw_files <- list.files(pattern = "^rawDataset\\\\.(csv|tsv|txt)\$")
    if (length(raw_files) == 0) {
      raw_files <- list.files(pattern = "rawDataset")
    }
    if (length(raw_files) == 0) {
      stop("rawDataset file not found in the working directory.")
    }
    raw_file <- raw_files[1]
    sep <- if (grepl("\\\\.(tsv|txt)\$", raw_file, ignore.case = TRUE)) "\t" else ","
    rawDataset <- read.csv(raw_file, sep = sep, row.names = 1, check.names = FALSE)
    
    # Find vignette.cells.origin file in the working directory
    origin_files <- list.files(pattern = "vignette\\\\.cells\\\\.origin")
    if (length(origin_files) == 0) {
      stop("vignette.cells.origin file not found in the working directory.")
    }
    origin_file <- origin_files[1]
    
    if (grepl("\\\\.rds\$", origin_file, ignore.case = TRUE)) {
      vignette.cells.origin <- readRDS(origin_file)
    } else {
      sep_orig <- if (grepl("\\\\.(tsv|txt)\$", origin_file, ignore.case = TRUE)) "\t" else ","
      orig_df <- read.csv(origin_file, sep = sep_orig, header = TRUE)
      if (ncol(orig_df) >= 2) {
        vignette.cells.origin <- setNames(orig_df[[2]], orig_df[[1]])
      } else {
        vignette.cells.origin <- setNames(orig_df[[1]], rownames(orig_df))
      }
      vignette.cells.origin <- as.factor(vignette.cells.origin)
    }
    
    # Align cells between rawDataset and vignette.cells.origin
    common_cells <- intersect(names(vignette.cells.origin), colnames(rawDataset))
    if (length(common_cells) == 0) {
      stop("No matching cell IDs between rawDataset and vignette.cells.origin.")
    }
    rawDataset <- rawDataset[, common_cells, drop = FALSE]
    vignette.cells.origin <- vignette.cells.origin[common_cells]
    
    # Define metadata placeholders
    GEO <- "GEO_placeholder"
    cond <- "custom_condition"
    
    # ==========================================
    # STAGE 1: Initialize the COTAN object and metadata
    # ==========================================
    obj <- COTAN(raw = rawDataset)
    obj <- initializeMetaDataset( obj, GEO = GEO, sequencingMethod = "Drop_seq", sampleCondition = cond )
    
    # ==========================================
    # STAGE 2: Assign cell origin conditions
    # ==========================================
    obj <- addCondition(obj, condName = "origin", conditions = vignette.cells.origin)
    
    # ==========================================
    # STAGE 3: Generate quality control plots
    # ==========================================
    pdf("qc_plots.pdf")
    plot(ECDPlot(obj, condName = "origin"))
    plot(cellSizePlot(obj, condName = "origin"))
    plot(genesSizePlot(obj, condName = "origin"))
    plot(scatterPlot(obj, condName = "origin"))
    dev.off()
    
    # Set thresholds dynamically based on the dataset to ensure robustness
    cellsSizeThr <- 6000L
    if (max(getCellsSize(obj)) <= 6000L) {
      cellsSizeThr <- as.integer(quantile(getCellsSize(obj), 0.99))
    }
    
    genesSizeHighThr <- 3000L
    if (max(getNumExpressedGenes(obj)) <= 3000L) {
      genesSizeHighThr <- as.integer(quantile(getNumExpressedGenes(obj), 0.99))
    }
    
    genesSizeLowThr <- 500L
    if (min(getNumExpressedGenes(obj)) >= 500L) {
      genesSizeLowThr <- as.integer(quantile(getNumExpressedGenes(obj), 0.01))
    }
    
    # ==========================================
    # STAGE 4: Drop cells exceeding library size or gene count thresholds
    # ==========================================
    obj <- addElementToMetaDataset(obj, "Cells size threshold", cellsSizeThr)
    cellsToRem <- getCells(obj)[getCellsSize(obj) > cellsSizeThr]
    obj <- dropGenesCells(obj, cells = cellsToRem)
    
    # Drop cells by gene count thresholds (as documented in vignette text)
    obj <- addElementToMetaDataset(obj, "Num genes high threshold", genesSizeHighThr)
    cellsToRem <- getCells(obj)[getNumExpressedGenes(obj) > genesSizeHighThr]
    obj <- dropGenesCells(obj, cells = cellsToRem)
    
    obj <- addElementToMetaDataset(obj, "Num genes low threshold", genesSizeLowThr)
    cellsToRem <- getCells(obj)[getNumExpressedGenes(obj) < genesSizeLowThr]
    obj <- dropGenesCells(obj, cells = cellsToRem)
    
    # ==========================================
    # STAGE 5: Identify and drop cells with high mitochondrial gene percentages
    # ==========================================
    c(mitPlot, mitSizes) %<-% mitochondrialPercentagePlot(obj, genePrefix = "^mt-", condName = "origin")
    
    pdf("mitochondrial_plots.pdf")
    plot(mitPlot)
    dev.off()
    
    mitPercThr <- 3.5
    if (all(mitSizes[["mit.percentage"]] == 0)) {
      mitPercThr <- 100.0 # Do not drop if no mitochondrial genes are detected
    } else if (max(mitSizes[["mit.percentage"]]) < 3.5) {
      mitPercThr <- quantile(mitSizes[["mit.percentage"]], 0.99)
    }
    
    obj <- addElementToMetaDataset(obj, "Mitoc. perc. threshold", mitPercThr)
    cellsToRem <- rownames(mitSizes)[mitSizes[["mit.percentage"]] > mitPercThr]
    obj <- dropGenesCells(obj, cells = cellsToRem)
    
    # ==========================================
    # STAGE 6: Run the clean function to estimate parameters and drop low-expression genes/cells
    # ==========================================
    obj <- addElementToMetaDataset(obj, "Num drop B group", 0L)
    obj <- clean(obj)
    
    # ==========================================
    # STAGE 7: Generate clean plots
    # ==========================================
    c(pcaCellsPlot, pcaCellsData, genesPlot, UDEPlot, nuPlot, zoomedNuPlot) %<-% cleanPlots(obj)
    
    pdf("clean_plots.pdf")
    plot(pcaCellsPlot)
    plot(genesPlot)
    plot(UDEPlot)
    plot(nuPlot)
    plot(zoomedNuPlot)
    dev.off()
    
    # ==========================================
    # STAGE 8: Drop low-efficiency cells and re-run parameter estimation
    # ==========================================
    # Drop group B if present in the PCA clustering
    if ("groups" %in% colnames(pcaCellsData) && "B" %in% pcaCellsData[["groups"]]) {
      cellsToRem <- rownames(pcaCellsData)[pcaCellsData[["groups"]] == "B"]
      obj <- dropGenesCells(obj, cells = cellsToRem)
      obj <- addElementToMetaDataset(obj, "Num drop B group", 1L)
    }
    
    udeLowThr <- 0.34
    if (min(getNu(obj)) >= 0.34) {
      udeLowThr <- quantile(getNu(obj), 0.01)
    }
    
    obj <- addElementToMetaDataset(obj, "Low UDE cells' threshold", udeLowThr)
    obj <- estimateNuLinear(obj)
    cellsToRem <- getCells(obj)[getNu(obj) < udeLowThr]
    obj <- dropGenesCells(obj, cells = cellsToRem)
    
    # Final parameter estimation and cleaning
    obj <- clean(obj)
    
    # Save final outputs
    saveRDS(obj, file = "cleaned_cotan_object.rds")
    
    meta_df <- data.frame(
      CellID = getCells(obj),
      Nu = getNu(obj),
      CellSize = getCellsSize(obj),
      Origin = getCondition(obj, condName = "origin"),
      stringsAsFactors = FALSE
    )
    write.csv(meta_df, "cleaned_cells_metadata.csv", row.names = FALSE)
    
    message("COTAN dataset cleaning pipeline completed successfully.")

    writeLines(c(
        '"BIOC_COTAN_DATASET_CLEANING":',
        paste0('    COTAN: ', as.character(packageVersion('COTAN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dataset_cleaning.csv versions.yml
    """
}

workflow BIOC_COTAN_DATASET_CLEANING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rawDataset, vignette.cells.origin ] ]

    main:
    BIOC_COTAN_DATASET_CLEANING(ch_input)

    emit:
    tables   = BIOC_COTAN_DATASET_CLEANING.out.tables
    plots    = BIOC_COTAN_DATASET_CLEANING.out.plots
    objects  = BIOC_COTAN_DATASET_CLEANING.out.objects
    versions = BIOC_COTAN_DATASET_CLEANING.out.versions
}
