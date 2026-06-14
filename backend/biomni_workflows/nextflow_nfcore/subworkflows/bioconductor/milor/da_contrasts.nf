#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: miloR — da_contrasts
// Perform differential abundance testing using contrasts to compare specific groups in multi-group experimental designs.
// Input: thy.sce, thy.design
// Container: quay.io/biocontainers/bioconductor-milor:2.6.0--r45ha27e39d_0
// R packages: SingleCellExperiment, dplyr, miloR, patchwork, scater, scran
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, dplyr, miloR, patchwork, scater, scran
// Visualizations: plot (ggplot/base)
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create Milo object
//  * 2. [Input & Preparation] Build KNN graph
//  * 3. [Input & Preparation] Define representative neighbourhoods
//  * 4. [Core Analysis] Count cells in neighbourhoods
//  * 5. [Core Analysis] Test for differential abundance using specified contrasts

nextflow.enable.dsl = 2

process BIOC_MILOR_DA_CONTRASTS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20"

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
    .bm_deps <- c("SingleCellExperiment", "dplyr", "miloR", "patchwork", "scater", "scran", "SummarizedExperiment")
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
    library(miloR)
    library(SummarizedExperiment)
    library(scater)
    library(scran)
    library(dplyr)
    library(patchwork)
    
    # 1. Load user input files from the working directory
    if (!file.exists("thy.sce")) {
        stop("Error: 'thy.sce' file not found in the working directory.")
    }
    if (!file.exists("thy.design")) {
        stop("Error: 'thy.design' file not found in the working directory.")
    }
    
    thy.sce <- readRDS("thy.sce")
    
    # Ensure 'Sample' column exists in colData(thy.sce) for countCells to use
    if (!"Sample" %in% colnames(colData(thy.sce))) {
        stop("Error: colData(thy.sce) must contain a 'Sample' column to map cells to samples.")
    }
    
    # Robust reader for thy.design (handles RDS, CSV, or TSV)
    read_design <- function(path) {
        out <- tryCatch({
            readRDS(path)
        }, error = function(e) {
            tryCatch({
                read.csv(path, header = TRUE, stringsAsFactors = FALSE)
            }, error = function(e2) {
                read.table(path, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
            })
        })
        return(out)
    }
    thy.design <- read_design("thy.design")
    
    # Ensure 'Sample' column exists in thy.design and matches rownames
    if (!"Sample" %in% colnames(thy.design) && !is.null(rownames(thy.design))) {
        thy.design\$Sample <- rownames(thy.design)
    }
    
    # Ensure 'Age' column exists in thy.design for the formula ~ 0 + Age
    if (!"Age" %in% colnames(thy.design)) {
        stop("Error: 'thy.design' must contain an 'Age' column for the specified design formula (~ 0 + Age).")
    }
    
    # Convert Age to a factor to ensure it is treated as a categorical group rather than a continuous slope
    thy.design\$Age <- as.factor(thy.design\$Age)
    
    # Dynamically define contrast.1 based on the unique levels of Age in thy.design
    age_levels <- levels(thy.design\$Age)
    if (length(age_levels) < 2) {
        stop("Error: 'Age' column in thy.design must have at least 2 unique levels to perform contrast testing.")
    }
    contrast.1 <- paste0("Age", age_levels[1], " - Age", age_levels[2])
    
    # 2. Create Milo object
    thy.milo <- Milo(thy.sce)
    reducedDim(thy.milo, "UMAP") <- reducedDim(thy.sce, "UMAP")
    
    # 3. Build KNN graph
    thy.milo <- buildGraph(thy.milo, k = 11, d = 40)
    
    # 4. Define representative neighbourhoods
    thy.milo <- makeNhoods(thy.milo, prop = 0.2, k = 11, d=40, refined = TRUE, refinement_scheme="graph")
    
    # 5. Count cells in neighbourhoods
    thy.milo <- countCells(thy.milo, meta.data = data.frame(colData(thy.milo)), samples="Sample")
    
    # Align design matrix rownames to match the columns of nhoodCounts(thy.milo)
    samples_in_milo <- colnames(nhoodCounts(thy.milo))
    rownames(thy.design) <- thy.design\$Sample
    thy.design <- thy.design[samples_in_milo, , drop = FALSE]
    
    # 6. Test for differential abundance using specified contrasts
    da_results <- testNhoods(thy.milo, design = ~ 0 + Age, design.df = thy.design, model.contrasts = contrast.1, fdr.weighting="graph-overlap", norm.method="TMM")
    
    # Save meaningful results to files
    write.csv(da_results, file = "da_results.csv", row.names = TRUE)
    saveRDS(thy.milo, file = "thy_milo_results.rds")
    
    # Generate diagnostic and visualization plots
    tryCatch({
        pdf("milo_da_contrasts_plots.pdf", width = 10, height = 8)
        
        # Plot 1: Neighbourhood size histogram
        print(plotNhoodSizeHist(thy.milo))
        
        # Plot 2: Abstracted graph of neighbourhoods displaying DA
        thy.milo <- buildNhoodGraph(thy.milo)
        print(plotNhoodGraphDA(thy.milo, da_results, alpha = 0.1))
        
        dev.off()
    }, error = function(e) {
        warning("Visualization plotting encountered an error: ", e\$message)
    })

    writeLines(c(
        '"BIOC_MILOR_DA_CONTRASTS":',
        paste0('    miloR: ', as.character(packageVersion('miloR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_da_contrasts.csv versions.yml
    """
}

workflow BIOC_MILOR_DA_CONTRASTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ thy.sce, thy.design ] ]

    main:
    BIOC_MILOR_DA_CONTRASTS(ch_input)

    emit:
    tables   = BIOC_MILOR_DA_CONTRASTS.out.tables
    plots    = BIOC_MILOR_DA_CONTRASTS.out.plots
    objects  = BIOC_MILOR_DA_CONTRASTS.out.objects
    versions = BIOC_MILOR_DA_CONTRASTS.out.versions
}
