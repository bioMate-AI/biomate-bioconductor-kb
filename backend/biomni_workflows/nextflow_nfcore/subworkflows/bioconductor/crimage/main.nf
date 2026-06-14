#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CRImage — cell_classification_and_cellularity
// Segment cells, classify cell types using a trained classifier, and calculate tumor cellularity from a tissue image.
// Input: trainingData.txt, exImg2.jpg
// Container: quay.io/biocontainers/bioconductor-crimage:1.58.0--r45hdfd78af_0
// R packages: CRImage
// Bioconductor: 3.20 | R: 4.4
// Requires: CRImage
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load training data and train an SVM classifier using createClassifier
//  * 2. [Core Analysis] Classify cells in the target image using classifyCells
//  * 3. [Core Analysis] Calculate tumor cellularity using calculateCellularity

nextflow.enable.dsl = 2

process BIOC_CRIMAGE_CELL_CLASSIFICATION_AND_CELLULARITY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20-deps"

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
    .bm_deps <- c("CRImage")
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
    
    # Load the required library
    library(CRImage)
    
    # Define input file paths (must exist in the working directory)
    training_data_path <- "trainingData.txt"
    image_path <- "exImg2.jpg"
    
    # 1. Load training data and train an SVM classifier using createClassifier
    trainingData <- read.table(training_data_path, header=TRUE)
    classifier <- createClassifier(trainingData)[[1]]
    
    # Save the trained classifier object
    saveRDS(classifier, file="classifier.rds")
    
    # 2. Classify cells in the target image using classifyCells
    f <- image_path
    classValues <- classifyCells(classifier, filename=f, KS=TRUE, maxShape=800, minShape=40, failureRegion=2000)
    
    # Save classification results
    saveRDS(classValues, file="classified_cells.rds")
    
    # 3. Calculate tumor cellularity using calculateCellularity
    # Open a PDF device to capture any plots generated during cellularity calculation
    pdf("cellularity_plots.pdf", width=10, height=5)
    cellularity <- calculateCellularity(classifier=classifier, filename=f, KS=TRUE, maxShape=800, minShape=40, failureRegion=2000, classifyStructures=FALSE, cancerIdentifier="1", numDensityWindows=2, colors=c("green","red"))
    dev.off()
    
    # Save cellularity results
    saveRDS(cellularity, file="cellularity_results.rds")
    
    # Write a text summary of the cellularity results
    sink("cellularity_summary.txt")
    cat("=== Cellularity Analysis Summary ===\n")
    print(cellularity)
    sink()

    writeLines(c(
        '"BIOC_CRIMAGE_CELL_CLASSIFICATION_AND_CELLULARITY":',
        paste0('    CRImage: ', as.character(packageVersion('CRImage')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cell_classification_and_cellularity.csv versions.yml
    """
}

workflow BIOC_CRIMAGE_CELL_CLASSIFICATION_AND_CELLULARITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ trainingData.txt, exImg2.jpg ] ]

    main:
    BIOC_CRIMAGE_CELL_CLASSIFICATION_AND_CELLULARITY(ch_input)

    emit:
    tables   = BIOC_CRIMAGE_CELL_CLASSIFICATION_AND_CELLULARITY.out.tables
    plots    = BIOC_CRIMAGE_CELL_CLASSIFICATION_AND_CELLULARITY.out.plots
    objects  = BIOC_CRIMAGE_CELL_CLASSIFICATION_AND_CELLULARITY.out.objects
    versions = BIOC_CRIMAGE_CELL_CLASSIFICATION_AND_CELLULARITY.out.versions
}
