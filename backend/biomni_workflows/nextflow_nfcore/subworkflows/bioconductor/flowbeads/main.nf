#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowBeads
// This package extends flowCore to provide functionality specific to bead data. One of the goals of th
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowBeads/inst/doc/HowTo-flowBeads.R
// Upstream  : xtable
// Downstream: none
//
// Install: BiocManager::install("flowBeads")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWBEADS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowbeads"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowbeads:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowbeads:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowbeads_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowbeads_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowbeads_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowBeads)
    library(BeadFlowFrame)
    library(Fluorochromes)
    library(jsonlite)

    # --- Gate Bead Populations [] ---
    # Key functions: gateBeads
    data(beads1)
    data(beads2)
    gbeads1 <- gateBeads(beads1)
    gbeads2 <- gateBeads(beads2)
    plot(gbeads1)
    plot(gbeads2)


    # --- MEF Transformation and Normalisation [] ---
    # Key functions: getTransformFunction, getMEFtransform
    data(beads1)
    data(beads2)
    gbeads1 <- gateBeads(beads1)
    gbeads2 <- gateBeads(beads2)
    trans_fun1 <- getTransformFunction(beads1)
    trans_fun2 <- getTransformFunction(beads2)
    mef_trans1 <- getMEFtransform(gbeads1)
    mef_trans2 <- getMEFtransform(gbeads2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowbeads_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowbeads_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowbeads_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWBEADS:", paste0("    flowbeads: ", packageVersion("flowBeads"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowbeads_results.csv
    touch ${prefix}_flowbeads_output.rds
    echo "BIOC_FLOWBEADS:" > versions.yml
    echo "    flowbeads: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWBEADS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWBEADS(ch_input)

    emit:
    results  = BIOC_FLOWBEADS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWBEADS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWBEADS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWBEADS.out.versions  // channel: path(versions.yml)
}
