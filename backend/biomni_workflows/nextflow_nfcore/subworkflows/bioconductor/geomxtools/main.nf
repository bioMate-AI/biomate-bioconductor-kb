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

    # --- unzip [] ---
    # Key functions: unzip, isS4

    # --- assay Data [] ---
    # Key functions: assayData, pData, fData, featureType, annotation
    assayData(demoData)[["exprs"]][1:3, 1:3]
    pData(demoData)[1:3, ]
    pData(protocolData(demoData))[1:3, ]
    # --- svar Labels [] ---
    # Key functions: svarLabels
    svarLabels(demoData)
    head(sData(demoData), 2)
    # --- design [] ---
    # Key functions: design, dimLabels
    design(demoData) <- ~ `segments`
    design(demoData)
    dimLabels(demoData)
    # --- with [] ---
    # Key functions: with
    dim(demoData)
    dim(demoData[, demoData$`slide name` == "6panel-old-slide1 (PTL-10891)"])
    dim(subset(demoData, select = phenoData(demoData)[["slide name"]] == "6panel-old-slide1 (PTL-10891)"))
    # --- assay Data Element [] ---
    # Key functions: assayDataElement, assayDataApply
    assayDataElement(demoData, "demoElem") <-
    assayDataApply(demoData, MARGIN=2, FUN=log, base=10, elt="exprs")
    assayDataElement(demoData, "demoElem")[1:3, 1:2]
    # --- shift Counts One [] ---
    # Key functions: shiftCountsOne, setSegmentQCFlags, setBioProbeQCFlags, featureData
    demoData <- shiftCountsOne(demoData, useDALogic=TRUE)
    demoData <- setSegmentQCFlags(demoData)
    head(protocolData(demoData)[["QCFlags"]])
    # --- normalize [] ---
    # Key functions: normalize, assayDataElement

    # --- negative Control Subset [] ---
    # Key functions: negativeControlSubset, munge
    neg_set <- negativeControlSubset(demoData)
    class(neg_set)
    neg_ctrls <- munge(neg_set, ~ exprs)
    # --- assay Data Apply [] ---
    # Key functions: assayDataApply, transform, assayDataElementNames
    thresh <- assayDataApply(negativeControlSubset(demoData), 2, max)

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
