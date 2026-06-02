#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GeomxTools
// Tools for NanoString Technologies GeoMx Technology. Package provides functions for reading in DCC an
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GeomxTools/inst/doc/Developer_Introduction_to_the_NanoStringGeoMxSet.R
// Upstream  : EnvStats, NanoStringNCTools, Seurat, SpatialDecon, SpatialExperiment
// Downstream: GeoMxWorkflows
//
// Install: BiocManager::install("GeomxTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GEOMXTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-geomxtools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-geomxtools:3.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-geomxtools:3.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_geomxtools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_geomxtools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_geomxtools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GeomxTools)
    library(jsonlite)

    # --- Quality Control and Filtering [] ---
    # Key functions: shiftCountsOne, setSegmentQCFlags, setBioProbeQCFlags
    demoData <- shiftCountsOne(demoData, useDALogic = TRUE)
    demoData <- setSegmentQCFlags(demoData)
    demoData <- setBioProbeQCFlags(demoData)
    QCResultsIndex <- which(apply(
        protocolData(demoData)[["QCFlags"]],
        1L,
        function(x) sum(x) == 0L
    ))
    QCPassed <- demoData[, QCResultsIndex]


    # --- Target Aggregation [] ---
    # Key functions: aggregateCounts, featureType
    target_demoData <- aggregateCounts(QCPassed)
    feat_type <- featureType(target_demoData)


    # --- Normalization [] ---
    # Key functions: normalize, assayDataElement
    target_demoData <- normalize(target_demoData,
                                 norm_method = "quant",
                                 desiredQuantile = 0.9,
                                 toElt = "q_norm")
    target_demoData <- normalize(target_demoData,
                                 norm_method = "neg",
                                 fromElt = "exprs",
                                 toElt = "neg_norm")
    target_demoData <- normalize(target_demoData,
                                 norm_method = "hk",
                                 fromElt = "exprs",
                                 toElt = "hk_norm")


    # --- Data Transformation and Subsetting [] ---
    # Key functions: negativeControlSubset, transform, assayDataApply
    neg_set <- negativeControlSubset(demoData)
    thresh <- assayDataApply(neg_set, 2, max)
    demoData <- transform(
        demoData,
        negCtrlZeroed = sweep(exprs(demoData), 2, thresh),
        log1p_negCtrlZeroed = log1p(pmax(exprs(demoData) - thresh, 0))
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_geomxtools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_geomxtools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_geomxtools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GEOMXTOOLS:", paste0("    geomxtools: ", packageVersion("GeomxTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_geomxtools_results.csv
    touch ${prefix}_geomxtools_output.rds
    echo "BIOC_GEOMXTOOLS:" > versions.yml
    echo "    geomxtools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GEOMXTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GEOMXTOOLS(ch_input)

    emit:
    results  = BIOC_GEOMXTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GEOMXTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GEOMXTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GEOMXTOOLS.out.versions  // channel: path(versions.yml)
}
