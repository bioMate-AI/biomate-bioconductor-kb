#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DepecheR — group_probability_plotting
// Display differences between groups at single-cell resolution based on nearest neighbor group composition without requiring prior clustering.
// Input: testData, testDataSNE
// Container: quay.io/biocontainers/bioconductor-depecher:1.26.0--r45h617649d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DepecheR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Subset the multidimensional data to the markers of interest
//  * 2. [Visualization & Output] Compute and plot the group probability vector on the 2D representation using groupProbPlot

nextflow.enable.dsl = 2

process BIOC_DEPECHER_GROUP_PROBABILITY_PLOTTING {
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
    .bm_deps <- c("DepecheR")
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
    library(DepecheR)
    
    # 1. Read User Input Files
    # The pipeline expects 'testData' and 'testDataSNE' in the working directory.
    # We support both RDS and CSV formats.
    
    if (file.exists("testData.rds")) {
      testData <- readRDS("testData.rds")
    } else if (file.exists("testData.csv")) {
      testData <- read.csv("testData.csv", check.names = FALSE)
    } else {
      stop("Error: 'testData.rds' or 'testData.csv' not found in the working directory.")
    }
    
    if (file.exists("testDataSNE.rds")) {
      testDataSNE_input <- readRDS("testDataSNE.rds")
    } else if (file.exists("testDataSNE.csv")) {
      testDataSNE_input <- read.csv("testDataSNE.csv", check.names = FALSE)
    } else {
      stop("Error: 'testDataSNE.rds' or 'testDataSNE.csv' not found in the working directory.")
    }
    
    # Ensure testDataSNE is structured as a list with a 'Y' element containing the 2D coordinates,
    # matching the documented code's expectation of 'testDataSNE\$Y'.
    if (is.list(testDataSNE_input) && !is.data.frame(testDataSNE_input) && "Y" %in% names(testDataSNE_input)) {
      testDataSNE <- testDataSNE_input
    } else {
      testDataSNE <- list(Y = as.matrix(testDataSNE_input))
    }
    
    # Verify the existence of the group label column
    if ("label" %in% colnames(testData)) {
      group_col <- "label"
    } else {
      possible_cols <- c("group", "Group", "condition", "Condition")
      found_cols <- intersect(possible_cols, colnames(testData))
      if (length(found_cols) > 0) {
        group_col <- found_cols[1]
      } else {
        stop("Error: 'label' column not found in testData. Please provide a group vector column.")
      }
    }
    
    # 2. Subset the multidimensional data to the markers of interest
    # Dynamically identify marker columns by excluding known metadata columns
    exclude_cols <- c("ids", "id", "donor", "sample", "cell", "barcode", group_col)
    marker_cols <- setdiff(colnames(testData), exclude_cols)
    
    # Ensure marker columns are numeric
    marker_cols <- marker_cols[sapply(testData[, marker_cols, drop = FALSE], is.numeric)]
    
    if (length(marker_cols) == 0) {
      stop("Error: No numeric marker columns found in testData.")
    }
    
    dataTrans <- testData[, marker_cols, drop = FALSE]
    
    # 3. Compute and plot the group probability vector on the 2D representation
    # This function automatically saves a high-resolution plot to the working directory.
    testData\$groupProb <- groupProbPlot(xYData = testDataSNE\$Y,
                                        groupVector = testData[[group_col]],
                                        groupName1 = "Group_1",
                                        groupName2 = "Group_2",
                                        dataTrans = dataTrans)
    
    # 4. Save the resulting dataset containing the group probability values
    write.csv(testData, "testData_with_groupProb.csv", row.names = FALSE)
    saveRDS(testData, "testData_with_groupProb.rds")

    writeLines(c(
        '"BIOC_DEPECHER_GROUP_PROBABILITY_PLOTTING":',
        paste0('    DepecheR: ', as.character(packageVersion('DepecheR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_group_probability_plotting.csv versions.yml
    """
}

workflow BIOC_DEPECHER_GROUP_PROBABILITY_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ testData, testDataSNE ] ]

    main:
    BIOC_DEPECHER_GROUP_PROBABILITY_PLOTTING(ch_input)

    emit:
    tables   = BIOC_DEPECHER_GROUP_PROBABILITY_PLOTTING.out.tables
    plots    = BIOC_DEPECHER_GROUP_PROBABILITY_PLOTTING.out.plots
    objects  = BIOC_DEPECHER_GROUP_PROBABILITY_PLOTTING.out.objects
    versions = BIOC_DEPECHER_GROUP_PROBABILITY_PLOTTING.out.versions
}
