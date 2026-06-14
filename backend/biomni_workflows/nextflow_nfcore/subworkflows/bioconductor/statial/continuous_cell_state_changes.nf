#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Statial — continuous_cell_state_changes
// Identify continuous changes in cell state (marker expression) as a function of spatial proximity to other cell types, correcting for lateral marker spillover.
// Input: SingleCellExperiment_object.rds
// Container: quay.io/biocontainers/bioconductor-statial:1.12.0--r45hdfd78af_0
// R packages: ClassifyR, SingleCellExperiment, Statial, dplyr, ggplot2, ggsurvfit, lisaClust, spicyR, survival, tibble
// Bioconductor: 3.20 | R: 4.4
// Requires: ClassifyR, SingleCellExperiment, Statial, dplyr, ggplot2, ggsurvfit, lisaClust, spicyR, survival, tibble
// Visualizations: scatter plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate spatial distances and abundances using getDistances and getAbundances
//  * 2. [Core Analysis] Calculate contamination probabilities using calcContamination
//  * 3. [Core Analysis] Calculate continuous state changes using calcStateChanges (with or without contamination correction)
//  * 4. [Visualization & Output] Visualize state changes using plotStateChanges
//  * 5. [Input & Preparation] Prepare the state change matrix using prepMatrix and associate with survival using colTest

nextflow.enable.dsl = 2

process BIOC_STATIAL_CONTINUOUS_CELL_STATE_CHANGES {
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
    .bm_deps <- c("ClassifyR", "SingleCellExperiment", "Statial", "dplyr", "ggplot2", "ggsurvfit", "lisaClust", "spicyR", "survival", "tibble", "SummarizedExperiment")
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
       library(Statial)
        library(spicyR)
        library(ClassifyR)
        library(lisaClust)
        library(dplyr)
        library(ggplot2)
        library(ggsurvfit)
        library(survival)
        library(tibble)
        
        # 1. Load the user-provided SingleCellExperiment object
        if (!file.exists("SingleCellExperiment_object.rds")) {
          stop("Error: SingleCellExperiment_object.rds not found in the working directory.")
        }
        
        kerenSCE <- readRDS("SingleCellExperiment_object.rds")
        
        # Prepare survival data from the SCE object to construct kerenSurv
        if (!"survival" %in% colnames(colData(kerenSCE))) {
          surv_cols <- sapply(colData(kerenSCE), function(x) inherits(x, "Surv"))
          if (any(surv_cols)) {
            kerenSCE\$survival <- colData(kerenSCE)[[which(surv_cols)[1]]]
          } else if ("time" %in% colnames(colData(kerenSCE)) && "event" %in% colnames(colData(kerenSCE))) {
            kerenSCE\$survival <- survival::Surv(kerenSCE\$time, kerenSCE\$event)
          } else if ("time" %in% colnames(colData(kerenSCE)) && "status" %in% colnames(colData(kerenSCE))) {
            kerenSCE\$survival <- survival::Surv(kerenSCE\$time, kerenSCE\$status)
          } else {
            stop("Error: Survival data not found. Please provide a 'survival' column of class Surv, or 'time' and 'event'/'status' columns.")
          }
        }
        
        survData <- kerenSCE |>
          colData() |>
          as.data.frame() |>
          dplyr::select(imageID, survival) |>
          unique()
        
        kerenSurv <- survData\$survival
        names(kerenSurv) <- as.character(survData\$imageID)
        
        # 2. Calculate spatial distances and abundances
        kerenSCE <- getDistances(kerenSCE,
          maxDist = 200,
          nCores = 1
        )
        
        kerenSCE <- getAbundances(kerenSCE,
          r = 200,
          nCores = 1
        )
        
        # 3. Calculate continuous state changes for a single image
        image_id <- as.character(unique(kerenSCE\$imageID)[1])
        img_cells <- kerenSCE[, kerenSCE\$imageID == image_id]
        cell_types <- unique(img_cells\$cellType)
        from_cell <- as.character(cell_types[1])
        to_cell <- if (length(cell_types) > 1) as.character(cell_types[2]) else from_cell
        marker_name <- rownames(kerenSCE)[1]
    
        stateChangesSingle <- calcStateChanges(
          cells = kerenSCE,
          type = "distances",
          image = image_id,
          from = from_cell,
          to = to_cell,
          marker = marker_name,
          nCores = 1
        )
        
        write.csv(stateChangesSingle, paste0("state_changes_single_image_", image_id, ".csv"), row.names = FALSE)
        
        # 4. Visualize state changes
        p <- plotStateChanges(
          cells = kerenSCE,
          type = "distances",
          image = image_id,
          from = from_cell,
          to = to_cell,
          marker = marker_name,
          size = 1,
          shape = 19,
          interactive = FALSE,
          plotModelFit = FALSE,
          method = "lm"
        )
        
        # Save the visualization plots if they exist in the returned list
        if (is.list(p)) {
          if ("scatter" %in% names(p)) {
            ggplot2::ggsave("plot_state_changes_scatter.pdf", plot = p\$scatter, width = 6, height = 5)
          }
          if ("image" %in% names(p)) {
            ggplot2::ggsave("plot_state_changes_spatial.pdf", plot = p\$image, width = 6, height = 5)
          }
        }
        
        # 5. Calculate continuous state changes across all images
        stateChanges <- calcStateChanges(
          cells = kerenSCE,
          type = "distances",
          nCores = 1,
          minCells = 100
        )
        
        write.csv(stateChanges, "state_changes_all_images.csv", row.names = FALSE)
        
        # 6. Calculate contamination probabilities and run corrected state changes
        kerenSCE <- calcContamination(kerenSCE)
        
        stateChangesCorrected <- calcStateChanges(
          cells = kerenSCE,
          type = "distances",
          nCores = 1,
          minCells = 100,
          contamination = TRUE
        )
        
        write.csv(stateChangesCorrected, "state_changes_corrected.csv", row.names = FALSE)
        
        # 7. Prepare the state change matrix and associate with survival
        stateMat <- prepMatrix(stateChanges)
        
        # Align kerenSurv names with the state matrix rownames to avoid subscript out of bounds
        common_images <- intersect(names(kerenSurv), rownames(stateMat))
        kerenSurv <- kerenSurv[common_images]
        
        stateMat <- stateMat[names(kerenSurv), ]
        
        stateMat <- stateMat[, colMeans(abs(stateMat) > 0.0001) > .8]
        
        survivalResults <- colTest(stateMat, kerenSurv, type = "survival")
        
        write.csv(survivalResults, "survival_association_results.csv", row.names = TRUE)
        
        # Save the final processed SingleCellExperiment object
        saveRDS(kerenSCE, "SingleCellExperiment_processed.rds")

    writeLines(c(
        '"BIOC_STATIAL_CONTINUOUS_CELL_STATE_CHANGES":',
        paste0('    Statial: ', as.character(packageVersion('Statial')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_continuous_cell_state_changes.csv versions.yml
    """
}

workflow BIOC_STATIAL_CONTINUOUS_CELL_STATE_CHANGES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SingleCellExperiment_object.rds ] ]

    main:
    BIOC_STATIAL_CONTINUOUS_CELL_STATE_CHANGES(ch_input)

    emit:
    tables   = BIOC_STATIAL_CONTINUOUS_CELL_STATE_CHANGES.out.tables
    plots    = BIOC_STATIAL_CONTINUOUS_CELL_STATE_CHANGES.out.plots
    objects  = BIOC_STATIAL_CONTINUOUS_CELL_STATE_CHANGES.out.objects
    versions = BIOC_STATIAL_CONTINUOUS_CELL_STATE_CHANGES.out.versions
}
