#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: adverSCarial — max_change_attack
// Identify and apply the maximum number of gene perturbations to a cell cluster without altering its original cell-type classification.
// Input: counts_matrix.ext, cell_annotations.ext
// Container: quay.io/biocontainers/bioconductor-adverscarial:1.8.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DelayedArray, Matrix, adverSCarial
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run a dichotomic search for the maximum set of modifiable genes using advMaxChange
//  * 2. [Core Analysis] Apply the modifications to the expression matrix using advModifications
//  * 3. [Core Analysis] Verify that the classification remains unchanged using the classifier function

nextflow.enable.dsl = 2

process BIOC_ADVERSCARIAL_MAX_CHANGE_ATTACK {
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
    .bm_deps <- c("adverSCarial", "DelayedArray", "Matrix")
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
        library(adverSCarial)
        library(DelayedArray)
        library(Matrix)
        
        # Helper function to find input files with any extension
        find_input_file <- function(base_name) {
          files <- list.files(pattern = paste0("^", base_name, "\\\\.[a-zA-Z0-9]+\$"))
          if (length(files) == 0) {
            stop(paste("Error: Required input file starting with", base_name, "not found in the working directory."))
          }
          return(files[1])
        }
        
        # Locate the input files
        counts_file <- find_input_file("counts_matrix")
        ann_file <- find_input_file("cell_annotations")
        
        # Read counts matrix
        counts_ext <- tools::file_ext(counts_file)
        if (counts_ext == "rds") {
          matPbmc <- readRDS(counts_file)
        } else if (counts_ext %in% c("csv", "txt")) {
          matPbmc <- as.matrix(read.csv(counts_file, row.names = 1, check.names = FALSE))
        } else if (counts_ext == "tsv") {
          matPbmc <- as.matrix(read.delim(counts_file, row.names = 1, check.names = FALSE))
        } else {
          matPbmc <- as.matrix(read.table(counts_file, header = TRUE, row.names = 1))
        }
        
        # Read cell annotations
        ann_ext <- tools::file_ext(ann_file)
        if (ann_ext == "rds") {
          cellTypes <- readRDS(ann_file)
        } else if (ann_ext %in% c("csv", "txt", "tsv")) {
          df_ann <- read.table(ann_file, header = FALSE, stringsAsFactors = FALSE)
          if (ncol(df_ann) > 1) {
            cellTypes <- df_ann[[2]]
          } else {
            cellTypes <- df_ann[[1]]
          }
        } else {
          cellTypes <- readLines(ann_file)
        }
        cellTypes <- as.character(cellTypes)
        
        # Dynamically select the first available cell type as the target to avoid runtime errors on non-PBMC datasets
        target_cell_type <- unique(cellTypes)[1]
        if (is.na(target_cell_type)) {
          stop("Error: No cell types found in cell annotations.")
        }
        
        # 1. Run a dichotomic search for the maximum set of modifiable genes using advMaxChange
        genesMaxChange <- advMaxChange(matPbmc, cellTypes, target_cell_type, MClassifier, advMethod = "perc99")
        
        # 2. Apply the modifications to the expression matrix using advModifications
        matMaxAdver <- advModifications(matPbmc, genesMaxChange@values, cellTypes, target_cell_type)
        
        # 3. Verify that the classification remains unchanged using the classifier function
        resClassif <- MClassifier(matMaxAdver, cellTypes, target_cell_type)
        
        # Save outputs
        saveRDS(genesMaxChange, "genesMaxChange.rds")
        saveRDS(matMaxAdver, "matMaxAdver.rds")
        saveRDS(resClassif, "resClassif.rds")
        
        # Export a CSV table of the identified modifiable genes and their values
        if (length(genesMaxChange@values) > 0) {
          df_genes <- data.frame(
            Gene = names(genesMaxChange@values),
            Value = genesMaxChange@values,
            stringsAsFactors = FALSE
          )
          write.csv(df_genes, "max_change_genes.csv", row.names = FALSE)
        } else {
          write.csv(data.frame(Message = "No modifiable genes found"), "max_change_genes.csv", row.names = FALSE)
        }
        
        # Export classification summary
        sink("classification_summary.txt")
        cat("=== Classification Verification ===\n")
        cat("Target Cell Type:", target_cell_type, "\n")
        cat("Predicted Cell Type after Attack:", resClassif\$prediction, "\n")
        cat("Prediction Confidence Score (Odd):", resClassif\$odd, "\n")
        sink()

    writeLines(c(
        '"BIOC_ADVERSCARIAL_MAX_CHANGE_ATTACK":',
        paste0('    adverSCarial: ', as.character(packageVersion('adverSCarial')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_max_change_attack.csv versions.yml
    """
}

workflow BIOC_ADVERSCARIAL_MAX_CHANGE_ATTACK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_matrix.ext, cell_annotations.ext ] ]

    main:
    BIOC_ADVERSCARIAL_MAX_CHANGE_ATTACK(ch_input)

    emit:
    tables   = BIOC_ADVERSCARIAL_MAX_CHANGE_ATTACK.out.tables
    plots    = BIOC_ADVERSCARIAL_MAX_CHANGE_ATTACK.out.plots
    objects  = BIOC_ADVERSCARIAL_MAX_CHANGE_ATTACK.out.objects
    versions = BIOC_ADVERSCARIAL_MAX_CHANGE_ATTACK.out.versions
}
