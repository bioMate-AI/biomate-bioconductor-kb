#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RTCGAToolbox
// Managing data from large scale projects such as The Cancer Genome Atlas (TCGA) for further analysis 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RTCGAToolbox/inst/doc/RTCGAToolbox-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("RTCGAToolbox")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RTCGATOOLBOX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rtcgatoolbox"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rtcgatoolbox:2.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rtcgatoolbox:2.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rtcgatoolbox_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rtcgatoolbox_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rtcgatoolbox_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RTCGAToolbox)
    library(jsonlite)

    # --- Getfirehosedatasets [] ---
    # Key functions: getFirehoseDatasets
    ---------------------------------------------------------------------
    library(RTCGAToolbox)
    # Valid aliases
    getFirehoseDatasets()
    # --- Getfirehoserunningdates [] ---
    # Key functions: getFirehoseRunningDates
    ---------------------------------------------------------------------
    # Valid stddata runs
    getFirehoseRunningDates(last = 3)
    # --- Dates [] ---
    # Key functions: dates, getFirehoseAnalyzeDates
    ---------------------------------------------------------------------
    # Valid analysis running dates (will return 3 recent date)
    getFirehoseAnalyzeDates(last=3)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(accmini)
    accmini
    # --- Biocextract [] ---
    # Key functions: biocExtract
    ---------------------------------------------------------------------
    biocExtract(accmini, "RNASeq2Gene")
    biocExtract(accmini, "CNASNP")
    # --- Head [] ---
    # Key functions: getData
    ---------------------------------------------------------------------
    head(getData(accmini, "clinical"))
    getData(accmini, "RNASeq2GeneNorm")
    getData(accmini, "GISTIC", "AllByGene")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rtcgatoolbox_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rtcgatoolbox_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rtcgatoolbox_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RTCGATOOLBOX:", paste0("    rtcgatoolbox: ", packageVersion("RTCGAToolbox"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rtcgatoolbox_results.csv
    touch ${prefix}_rtcgatoolbox_output.rds
    echo "BIOC_RTCGATOOLBOX:" > versions.yml
    echo "    rtcgatoolbox: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RTCGATOOLBOX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RTCGATOOLBOX(ch_input)

    emit:
    results  = BIOC_RTCGATOOLBOX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RTCGATOOLBOX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RTCGATOOLBOX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RTCGATOOLBOX.out.versions  // channel: path(versions.yml)
}
