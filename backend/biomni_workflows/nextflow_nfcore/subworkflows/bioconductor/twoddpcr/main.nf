#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: twoddpcr
// The twoddpcr package takes Droplet Digital PCR (ddPCR) droplet amplitude data from Bio-Rad's QuantaS
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/twoddpcr/inst/doc/twoddpcr.R
// Upstream  : ggplot2, reshape2
// Downstream: none
//
// Install: BiocManager::install("twoddpcr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TWODDPCR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-twoddpcr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-twoddpcr:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-twoddpcr:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_twoddpcr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_twoddpcr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_twoddpcr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(twoddpcr)
    library(jsonlite)

    # --- Threshold and K-means Classification [] ---
    # Key functions: thresholdClassify, kmeansClassify, commonClassificationMethod
    plate <- thresholdClassify(plate, ch1Threshold=6789, ch2Threshold=3000)
    plate <- kmeansClassify(plate)
    method <- commonClassificationMethod(plate)
    dropletPlot(plate, cMethod="kmeans")


    # --- Mahalanobis Distance Rain Filtering [] ---
    # Key functions: mahalanobisRain, plateSummary
    plate <- mahalanobisRain(plate, cMethod="kmeans", maxDistances=3)
    kmeansMahRainSummary <- plateSummary(plate, cMethod="kmeansMahRain")
    head(kmeansMahRainSummary)


    # --- Supervised Classification using KNN [] ---
    # Key functions: removeDropletClasses, knnClassify
    trainWells <- plate[c("E03", "A04")]
    trainPlate <- ddpcrPlate(wells=trainWells)
    trainPlate <- kmeansClassify(trainPlate)
    trainPlate <- mahalanobisRain(trainPlate, cMethod="kmeans", maxDistances=3)
    trainSet <- removeDropletClasses(trainPlate, cMethod="kmeansMahRain")
    trainSet <- do.call(rbind, trainSet)
    trainAmplitudes <- trainSet[, c("Ch1.Amplitude", "Ch2.Amplitude")]
    trainCl <- trainSet$kmeansMahRain
    plate <- knnClassify(plate, trainData=trainAmplitudes, cl=trainCl, k=3)


    # --- Alternative Classification Methods [] ---
    # Key functions: gridClassify, sdRain
    plate <- gridClassify(plate,
                          ch1NNThreshold=6500, ch2NNThreshold=2110,
                          ch1NPThreshold=5765, ch2NPThreshold=5150,
                          ch1PNThreshold=8550, ch2PNThreshold=2450,
                          ch1PPThreshold=6700, ch2PPThreshold=3870)
    plate <- sdRain(plate, cMethod="kmeans",
                    errorLevel=list(NN=5, NP=5, PN=3, PP=3))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_twoddpcr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_twoddpcr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_twoddpcr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TWODDPCR:", paste0("    twoddpcr: ", packageVersion("twoddpcr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_twoddpcr_results.csv
    touch ${prefix}_twoddpcr_output.rds
    echo "BIOC_TWODDPCR:" > versions.yml
    echo "    twoddpcr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TWODDPCR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TWODDPCR(ch_input)

    emit:
    results  = BIOC_TWODDPCR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TWODDPCR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TWODDPCR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TWODDPCR.out.versions  // channel: path(versions.yml)
}
