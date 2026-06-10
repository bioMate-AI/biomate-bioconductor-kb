#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: twoddpcr — knn_training_classification
// Classify a ddPCR plate using the k-nearest neighbor (k-NN) algorithm trained on a low-noise subset of wells.
// Input: data/amplitudes
// Container: quay.io/biocontainers/bioconductor-twoddpcr:1.34.0--r45hdfd78af_0
// Requires: ggplot2, twoddpcr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the full plate and extract a subset of wells to use as a training set. 2. Classify the training wells using k-means and remov

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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(twoddpcr)
    library(ggplot2)
    
    # Create output directory
    dir.create("output", showWarnings = FALSE, recursive = TRUE)
    
    # 1. Load the full plate from the user-specified directory
    plate <- ddpcrPlate(well="data/amplitudes")
    
    # 2. Extract a subset of wells to use as a training set
    train_well_names <- names(plate)[1:min(2, length(names(plate)))]
    trainWells <- plate[train_well_names]
    trainPlate <- ddpcrPlate(wells=trainWells)
    
    # 3. Classify the training wells using k-means and remove noise by applying Mahalanobis rain
    trainPlate <- kmeansClassify(trainPlate)
    trainPlate <- mahalanobisRain(trainPlate, cMethod="kmeans", maxDistances=3)
    
    # 4. Extract the clean training amplitudes and classifications, discarding "Rain" droplets
    trainSet <- removeDropletClasses(trainPlate, cMethod="kmeansMahRain")
    trainSet <- do.call(rbind, trainSet)
    trainAmplitudes <- trainSet[, c("Ch1.Amplitude", "Ch2.Amplitude")]
    trainCl <- trainSet\$kmeansMahRain
    
    # 5. Classify the entire plate using the k-NN algorithm based on the training set
    plate <- knnClassify(plate, trainData=trainAmplitudes, cl=trainCl, k=3)
    
    # 6. Save meaningful results
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
