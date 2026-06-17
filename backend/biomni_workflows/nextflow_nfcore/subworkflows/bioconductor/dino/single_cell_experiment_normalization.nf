#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Dino — single_cell_experiment_normalization
// Normalize scRNA-seq data formatted as a SingleCellExperiment object using Dino.
// Input: pbmcSmall
// Container: quay.io/biocontainers/bioconductor-dino:1.16.0--r45hdfd78af_0
// R packages: Dino, Matrix, SingleCellExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: Dino, Matrix, SingleCellExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a SingleCellExperiment object from the count matrix
//  * 2. [Core Analysis] Run Dino normalization directly on the SingleCellExperiment object using Dino_SCE
//  * 3. [Core Analysis] Inspect or extract the normalized counts using normcounts

nextflow.enable.dsl = 2

process BIOC_DINO_SINGLE_CELL_EXPERIMENT_NORMALIZATION {
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
    .bm_deps <- c("Dino", "Matrix", "SingleCellExperiment")
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
    library(Dino)
    library(Matrix)
    
    # 1. Read the user input file from the working directory
    # Supports RDS, CSV, or TSV formats for pbmcSmall
    if (file.exists("pbmcSmall.rds")) {
      pbmcSmall <- readRDS("pbmcSmall.rds")
    } else if (file.exists("pbmcSmall.csv")) {
      pbmcSmall <- read.csv("pbmcSmall.csv", row.names = 1, check.names = FALSE)
      pbmcSmall <- as.matrix(pbmcSmall)
    } else if (file.exists("pbmcSmall.txt")) {
      pbmcSmall <- read.table("pbmcSmall.txt", header = TRUE, row.names = 1, check.names = FALSE)
      pbmcSmall <- as.matrix(pbmcSmall)
    } else {
      stop("Error: pbmcSmall input file (pbmcSmall.rds, pbmcSmall.csv, or pbmcSmall.txt) not found in the working directory.")
    }
    
    # Ensure pbmcSmall is in a matrix format
    if (!is(pbmcSmall, "Matrix") && !is.matrix(pbmcSmall)) {
      pbmcSmall <- as.matrix(pbmcSmall)
    }
    
    # 2. Create a SingleCellExperiment object from the count matrix
    pbmc_SCE <- SingleCellExperiment(assays = list("counts" = pbmcSmall))
    
    # 3. Run Dino normalization directly on the SingleCellExperiment object using Dino_SCE
    pbmc_SCE <- Dino_SCE(pbmc_SCE)
    
    # 4. Inspect or extract the normalized counts using normcounts
    str(normcounts(pbmc_SCE))
    
    # 5. Write named output files for the meaningful results
    # Save the full SingleCellExperiment object
    saveRDS(pbmc_SCE, file = "pbmc_SCE_normalized.rds")
    
    # Save the normalized counts matrix as a CSV
    norm_counts_matrix <- normcounts(pbmc_SCE)
    if (is(norm_counts_matrix, "sparseMatrix")) {
      write.csv(as.matrix(norm_counts_matrix), file = "normalized_counts.csv", row.names = TRUE)
    } else {
      write.csv(norm_counts_matrix, file = "normalized_counts.csv", row.names = TRUE)
    }

    writeLines(c(
        '"BIOC_DINO_SINGLE_CELL_EXPERIMENT_NORMALIZATION":',
        paste0('    Dino: ', as.character(packageVersion('Dino')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_experiment_normalization.csv versions.yml
    """
}

workflow BIOC_DINO_SINGLE_CELL_EXPERIMENT_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmcSmall ] ]

    main:
    BIOC_DINO_SINGLE_CELL_EXPERIMENT_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_DINO_SINGLE_CELL_EXPERIMENT_NORMALIZATION.out.tables
    plots    = BIOC_DINO_SINGLE_CELL_EXPERIMENT_NORMALIZATION.out.plots
    objects  = BIOC_DINO_SINGLE_CELL_EXPERIMENT_NORMALIZATION.out.objects
    versions = BIOC_DINO_SINGLE_CELL_EXPERIMENT_NORMALIZATION.out.versions
}
