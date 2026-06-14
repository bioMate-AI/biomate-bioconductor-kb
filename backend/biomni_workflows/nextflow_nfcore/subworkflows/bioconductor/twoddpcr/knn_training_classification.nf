#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: twoddpcr — knn_training_classification
// Classify a ddPCR plate using the k-nearest neighbor (k-NN) algorithm trained on a low-noise subset of wells.
// Input: data/amplitudes
// Container: quay.io/biocontainers/bioconductor-twoddpcr:1.34.0--r45hdfd78af_0
// R packages: ggplot2, twoddpcr
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, twoddpcr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the full plate from the user-specified directory
//  * 2. [Input & Preparation] Extract a subset of wells to use as a training set
//  * 3. [Input & Preparation] Classify the training wells using k-means and remove
//  * 4. [Input & Preparation] Extract the clean training amplitudes and
//  * 5. [Input & Preparation] Classify the entire plate using the k-NN algorithm based
//  * 6. [Input & Preparation] Save meaningful results

nextflow.enable.dsl = 2

process BIOC_TWODDPCR_KNN_TRAINING_CLASSIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("ggplot2", "twoddpcr")
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
    library(twoddpcr)
    library(ggplot2)
    
    # Create output directory
    dir.create("output", showWarnings = FALSE, recursive = TRUE)
    
    # --- Load the full plate from the user-specified directory ---
    plate <- ddpcrPlate(well="data/amplitudes")
    
    # --- Extract a subset of wells to use as a training set ---
    train_well_names <- names(plate)[1:min(2, length(names(plate)))]
    trainWells <- plate[train_well_names]
    trainPlate <- ddpcrPlate(wells=trainWells)
    
    # --- Classify the training wells using k-means and remove ---
    trainPlate <- kmeansClassify(trainPlate)
    trainPlate <- mahalanobisRain(trainPlate, cMethod="kmeans", maxDistances=3)
    
    # --- Extract the clean training amplitudes and ---
    trainSet <- removeDropletClasses(trainPlate, cMethod="kmeansMahRain")
    trainSet <- do.call(rbind, trainSet)
    trainAmplitudes <- trainSet[, c("Ch1.Amplitude", "Ch2.Amplitude")]
    trainCl <- trainSet\$kmeansMahRain
    
    # --- Classify the entire plate using the k-NN algorithm based ---
    plate <- knnClassify(plate, trainData=trainAmplitudes, cl=trainCl, k=3)
    
    # --- Save meaningful results ---
    saveRDS(plate, file = "output/classified_plate.rds")
    
    # Generate and save summary table
    knn_summary <- plateSummary(plate, cMethod="knn")
    write.csv(knn_summary, file = "output/plate_summary_knn.csv", row.names = TRUE)
    
    # Generate and save diagnostic plot
    pdf("output/droplet_plot_knn.pdf", width = 8, height = 6)
    print(dropletPlot(plate, cMethod="knn"))
    dev.off()

    writeLines(c(
        '"BIOC_TWODDPCR_KNN_TRAINING_CLASSIFICATION":',
        paste0('    twoddpcr: ', as.character(packageVersion('twoddpcr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_knn_training_classification.csv versions.yml
    """
}

workflow BIOC_TWODDPCR_KNN_TRAINING_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data/amplitudes ] ]

    main:
    BIOC_TWODDPCR_KNN_TRAINING_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_TWODDPCR_KNN_TRAINING_CLASSIFICATION.out.tables
    plots    = BIOC_TWODDPCR_KNN_TRAINING_CLASSIFICATION.out.plots
    objects  = BIOC_TWODDPCR_KNN_TRAINING_CLASSIFICATION.out.objects
    versions = BIOC_TWODDPCR_KNN_TRAINING_CLASSIFICATION.out.versions
}
