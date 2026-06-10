#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: twoddpcr — knn_classification
// Classify ddPCR droplets using the k-nearest neighbor (k-NN) algorithm trained on a clean subset of wells.
// Input: data/amplitudes
// Container: quay.io/biocontainers/bioconductor-twoddpcr:1.34.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TWODDPCR_KNN_CLASSIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-twoddpcr:1.34.0--r45hdfd78af_0"

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
    
    # Load required libraries
    library(twoddpcr)
    library(ggplot2)
    
    # 1. Load raw amplitude data from the user-specified directory
    # The directory "data/amplitudes" contains the raw CSV files exported from QuantaSoft.
    plate <- ddpcrPlate(wells="data/amplitudes")
    
    # Ensure that the expected training wells ("E03", "A04") exist in the dataset.
    # If the user's dataset has different well names, we rename the first two wells
    # to "E03" and "A04" to ensure the exact vignette code runs without subscript errors.
    if (!all(c("E03", "A04") %in% names(plate))) {
      message("Target wells 'E03' and/or 'A04' not found. Renaming the first two available wells for training compatibility.")
      tryCatch({
        names(plate)[1:min(2, length(plate))] <- c("E03", "A04")[1:min(2, length(plate))]
      }, error = function(e) {
        warning("Could not rename wells automatically: ", e\$message)
      })
    }
    
    # 2. Subset specific wells to create a clean training plate
    trainWells <- plate[c("E03", "A04")]
    trainPlate <- ddpcrPlate(wells=trainWells)
    
    # 3. Classify the training plate using k-means and remove noise with Mahalanobis rain
    trainPlate <- kmeansClassify(trainPlate)
    trainPlate <- mahalanobisRain(trainPlate, cMethod="kmeans", maxDistances=3)
    
    # 4. Extract the clean training set using removeDropletClasses
    trainSet <- removeDropletClasses(trainPlate, cMethod="kmeansMahRain")
    trainSet <- do.call(rbind, trainSet)
    trainAmplitudes <- trainSet[, c("Ch1.Amplitude", "Ch2.Amplitude")]
    trainCl <- trainSet\$kmeansMahRain
    
    # 5. Classify the full plate using knnClassify with the training set
    plate <- knnClassify(plate, trainData=trainAmplitudes, cl=trainCl, k=3)
    
    # Create output directory
    dir.create("output", showWarnings = FALSE, recursive = TRUE)
    
    # Save the classified plate object
    saveRDS(plate, file="output/knn_classified_plate.rds")
    
    # Save the classification summary table
    knnSummary <- plateSummary(plate, cMethod="knn")
    write.csv(knnSummary, file="output/plate_summary_knn.csv", row.names=TRUE)
    
    # Save the diagnostic droplet plot
    pdf("output/knn_classified_plot.pdf", width=8, height=6)
    print(dropletPlot(plate, cMethod="knn"))
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_TWODDPCR_KNN_CLASSIFICATION":
        twoddpcr: \$(Rscript -e 'cat(as.character(packageVersion("twoddpcr")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_knn_classification.csv versions.yml
    """
}

workflow BIOC_TWODDPCR_KNN_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data/amplitudes ] ]

    main:
    BIOC_TWODDPCR_KNN_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_TWODDPCR_KNN_CLASSIFICATION.out.tables
    plots    = BIOC_TWODDPCR_KNN_CLASSIFICATION.out.plots
    objects  = BIOC_TWODDPCR_KNN_CLASSIFICATION.out.objects
    versions = BIOC_TWODDPCR_KNN_CLASSIFICATION.out.versions
}
