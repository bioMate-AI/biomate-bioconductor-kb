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

    # --- Ddpcrplate [] ---
    # Key functions: ddpcrPlate
    ---------------------------------------------------------------------
    plate <- ddpcrPlate(wells=KRASdata)
    # --- Commonclassificationmethod [] ---
    # Key functions: commonClassificationMethod
    ---------------------------------------------------------------------
    commonClassificationMethod(plate)
    # --- Thresholdclassify [] ---
    # Key functions: thresholdClassify
    ---------------------------------------------------------------------
    plate <- thresholdClassify(plate, ch1Threshold=6789, ch2Threshold=3000)
    # --- Commonclassificationmethod [] ---
    # Key functions: commonClassificationMethod
    ---------------------------------------------------------------------
    commonClassificationMethod(plate)
    # --- Mahalanobisrain [] ---
    # Key functions: mahalanobisRain
    ---------------------------------------------------------------------
    plate <- mahalanobisRain(plate, cMethod="kmeans", maxDistances=3)
    # --- Commonclassificationmethod [] ---
    # Key functions: commonClassificationMethod
    ---------------------------------------------------------------------
    commonClassificationMethod(plate)
    # --- Mahalanobisrain [] ---
    # Key functions: mahalanobisRain, commonClassificationMethod
    ---------------------------------------------------------------------
    plate <- mahalanobisRain(plate, cMethod="kmeans",
                             maxDistances=list(NN=35, NP=35, PN=35, PP=35))
    commonClassificationMethod(plate)
    # --- Summary [] ---
    # Key functions: lm
    ---------------------------------------------------------------------
    bioradLmSummary <- summary(lm(x ~ Cluster, data=mtConcentrations))
    kmLmSummary <- summary(lm(x ~ kmeans, data=mtConcentrations))
    kmMahRainLmSummary <- summary(lm(x ~ kmeansMahRain, data=mtConcentrations))
    # --- Removedropletclasses [] ---
    # Key functions: removeDropletClasses, call
    ---------------------------------------------------------------------
    trainSet <- removeDropletClasses(trainPlate, cMethod="kmeansMahRain")
    trainSet <- do.call(rbind, trainSet)
    colnames(trainSet)
    # --- Commonclassificationmethod [] ---
    # Key functions: commonClassificationMethod
    ---------------------------------------------------------------------
    commonClassificationMethod(plate)
    # --- Gridclassify [] ---
    # Key functions: gridClassify, dropletPlot
    ---------------------------------------------------------------------
    # --- Sdrain [] ---
    # Key functions: sdRain, dropletPlot
    ---------------------------------------------------------------------
    plate <- sdRain(plate, cMethod="kmeans")
    dropletPlot(plate, cMethod="kmeansSdRain")

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
