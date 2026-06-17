#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SiPSiC — pathway_activity_scoring
// Calculate per-cell pathway activity scores from single-cell RNA-seq data using a user-defined gene list.
// Input: geneCountsMatrix, pathwayGenesList
// Container: quay.io/biocontainers/bioconductor-sipsic:1.10.0--r45hdfd78af_0
// R packages: Matrix, SingleCellExperiment, SiPSiC
// Bioconductor: 3.20 | R: 4.4
// Requires: Matrix, SiPSiC, SingleCellExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Format the expression matrix as a sparse matrix (dgCMatrix) and wrap it in a SingleCellExperiment object
//  * 2. [Input & Preparation] Define the pathway gene list
//  * 3. [Core Analysis] Run getPathwayScores to calculate pathway scores and retrieve gene indices

nextflow.enable.dsl = 2

process BIOC_SIPSIC_PATHWAY_ACTIVITY_SCORING {
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
    .bm_deps <- c("Matrix", "SingleCellExperiment", "SiPSiC")
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
    library(SiPSiC)
    library(Matrix)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read geneCountsMatrix
    if (file.exists("geneCountsMatrix.rds")) {
      geneCountsMatrix <- readRDS("geneCountsMatrix.rds")
    } else if (file.exists("geneCountsMatrix.csv")) {
      geneCountsMatrix <- as.matrix(read.csv("geneCountsMatrix.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("geneCountsMatrix.tsv")) {
      geneCountsMatrix <- as.matrix(read.delim("geneCountsMatrix.tsv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: geneCountsMatrix file not found. Please provide 'geneCountsMatrix.rds', 'geneCountsMatrix.csv', or 'geneCountsMatrix.tsv' in the working directory.")
    }
    
    # Ensure the matrix is a sparse matrix of type dgCMatrix
    if (!inherits(geneCountsMatrix, "dgCMatrix")) {
      geneCountsMatrix <- as(geneCountsMatrix, "dgCMatrix")
    }
    
    # Read pathwayGenesList
    if (file.exists("pathwayGenesList.txt")) {
      pathwayGenesList <- readLines("pathwayGenesList.txt")
    } else if (file.exists("pathwayGenesList.rds")) {
      pathwayGenesList <- readRDS("pathwayGenesList.rds")
    } else if (file.exists("pathwayGenesList.csv")) {
      pathwayGenesList <- read.csv("pathwayGenesList.csv", header = FALSE, stringsAsFactors = FALSE)[[1]]
    } else {
      stop("Error: pathwayGenesList file not found. Please provide 'pathwayGenesList.txt', 'pathwayGenesList.rds', or 'pathwayGenesList.csv' in the working directory.")
    }
    
    # Clean pathway gene list (remove empty strings or whitespace)
    pathwayGenesList <- trimws(pathwayGenesList)
    pathwayGenesList <- pathwayGenesList[pathwayGenesList != ""]
    
    # ==========================================
    # 2. Run Documented Workflow
    # ==========================================
    
    # Wrap the sparse matrix in a SingleCellExperiment object
    assayData <- SingleCellExperiment(assays = list(counts = geneCountsMatrix))
    
    # Run getPathwayScores to calculate pathway scores and retrieve gene indices
    scoresAndIndices <- getPathwayScores(counts(assayData), pathwayGenesList)
    
    # Extract results
    pathwayScoresOfCells <- scoresAndIndices\$pathwayScores
    pathwayGeneIndices <- scoresAndIndices\$index
    
    # ==========================================
    # 3. Save Outputs
    # ==========================================
    
    # Save pathway scores as a CSV file
    scores_df <- data.frame(
      Cell = names(pathwayScoresOfCells),
      PathwayScore = pathwayScoresOfCells,
      stringsAsFactors = FALSE
    )
    write.csv(scores_df, "pathway_scores.csv", row.names = FALSE)
    
    # Save pathway gene indices as a CSV file
    indices_df <- data.frame(
      Gene = names(pathwayGeneIndices),
      Index = pathwayGeneIndices,
      stringsAsFactors = FALSE
    )
    write.csv(indices_df, "pathway_gene_indices.csv", row.names = FALSE)
    
    # Save the complete results object as an RDS file
    saveRDS(scoresAndIndices, "scores_and_indices.rds")
    
    cat("Workflow completed successfully. Outputs saved to 'pathway_scores.csv', 'pathway_gene_indices.csv', and 'scores_and_indices.rds'.\n")

    writeLines(c(
        '"BIOC_SIPSIC_PATHWAY_ACTIVITY_SCORING":',
        paste0('    SiPSiC: ', as.character(packageVersion('SiPSiC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_activity_scoring.csv versions.yml
    """
}

workflow BIOC_SIPSIC_PATHWAY_ACTIVITY_SCORING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ geneCountsMatrix, pathwayGenesList ] ]

    main:
    BIOC_SIPSIC_PATHWAY_ACTIVITY_SCORING(ch_input)

    emit:
    tables   = BIOC_SIPSIC_PATHWAY_ACTIVITY_SCORING.out.tables
    plots    = BIOC_SIPSIC_PATHWAY_ACTIVITY_SCORING.out.plots
    objects  = BIOC_SIPSIC_PATHWAY_ACTIVITY_SCORING.out.objects
    versions = BIOC_SIPSIC_PATHWAY_ACTIVITY_SCORING.out.versions
}
