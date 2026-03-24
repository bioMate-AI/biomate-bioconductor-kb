#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CAEN
// With the development of high-throughput techniques, more and more gene expression analysis tend to r
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CAEN/inst/doc/CAEN.R
// Upstream  : SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("CAEN")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CAEN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-caen"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-caen:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-caen:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_caen_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_caen_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_caen_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CAEN)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("realData")
    realData
    # --- Newcountdataset [] ---
    # Key functions: newCountDataSet
    ---------------------------------------------------------------------
    dat <- newCountDataSet(n = 100, p = 500, K = 4, param = 10, sdsignal = 2,
                           drate = 0.2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_caen_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_caen_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_caen_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CAEN:", paste0("    caen: ", packageVersion("CAEN"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_caen_results.csv
    touch ${prefix}_caen_output.rds
    echo "BIOC_CAEN:" > versions.yml
    echo "    caen: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CAEN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CAEN(ch_input)

    emit:
    results  = BIOC_CAEN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CAEN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CAEN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CAEN.out.versions  // channel: path(versions.yml)
}
