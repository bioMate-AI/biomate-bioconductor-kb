#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CRImage — aperio_slide_processing
// Process large-scale pathological images from Aperio scanners by analyzing subimages in parallel and calculating section-specific cellularity.
// Input: trainingData.txt, inputFolder
// Container: quay.io/biocontainers/bioconductor-crimage:1.58.0--r45hdfd78af_0
// R packages: CRImage
// Bioconductor: 3.20 | R: 4.4
// Requires: CRImage
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Train the classifier using createClassifier
//  * 2. [Visualization & Output] Create an output directory
//  * 3. [Visualization & Output] Process subimages, perform automatic section clustering, and output cellularity values and heatmaps using processAperio

nextflow.enable.dsl = 2

process BIOC_CRIMAGE_APERIO_SLIDE_PROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20"

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
    
    # Load the required Bioconductor package
    library(CRImage)
    
    # Define input paths as specified by the user input requirements
    training_data_file <- "trainingData.txt"
    f <- "inputFolder"
    
    # Validate that the required inputs exist before proceeding
    if (!file.exists(training_data_file)) {
      stop(paste("Error: Required input file '", training_data_file, "' not found in the working directory.", sep = ""))
    }
    
    if (!file.exists(f)) {
      stop(paste("Error: Required input folder '", f, "' not found in the working directory.", sep = ""))
    }
    
    # 1. Train the classifier using createClassifier
    message("Loading training data...")
    trainingData <- read.table(training_data_file, header = TRUE, sep = "\t")
    
    message("Training the classifier...")
    classifier <- createClassifier(trainingData)[[1]]
    
    # Save the trained classifier object as an RDS file for downstream use
    saveRDS(classifier, file = "trained_classifier.rds")
    message("Trained classifier saved to 'trained_classifier.rds'.")
    
    # 2. Create an output directory
    message("Creating output directory...")
    if (!dir.exists("AperiOutput")) {
      dir.create("AperiOutput")
    }
    
    # 3. Process subimages, perform automatic section clustering, and output cellularity values and heatmaps using processAperio
    message("Processing Aperio slide images...")
    processAperio(
      classifier = classifier,
      inputFolder = f,
      outputFolder = "AperiOutput",
      identifier = "Da",
      numSections = 2,
      cancerIdentifier = "c",
      maxShape = 800,
      minShape = 40,
      failureRegion = 2000
    )
    
    message("Pipeline completed successfully. Results are saved in the 'AperiOutput' directory.")

    writeLines(c(
        '"BIOC_CRIMAGE_APERIO_SLIDE_PROCESSING":',
        paste0('    CRImage: ', as.character(packageVersion('CRImage')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_aperio_slide_processing.csv versions.yml
    """
}

workflow BIOC_CRIMAGE_APERIO_SLIDE_PROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ trainingData.txt, inputFolder ] ]

    main:
    BIOC_CRIMAGE_APERIO_SLIDE_PROCESSING(ch_input)

    emit:
    tables   = BIOC_CRIMAGE_APERIO_SLIDE_PROCESSING.out.tables
    plots    = BIOC_CRIMAGE_APERIO_SLIDE_PROCESSING.out.plots
    objects  = BIOC_CRIMAGE_APERIO_SLIDE_PROCESSING.out.objects
    versions = BIOC_CRIMAGE_APERIO_SLIDE_PROCESSING.out.versions
}
