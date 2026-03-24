#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DeMAND
// DEMAND predicts Drug MoA by interrogating a cell context specific regulatory network with a small nu
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DeMAND/inst/doc/DeMAND.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("DeMAND")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEMAND {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-demand"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-demand:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-demand:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_demand_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_demand_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_demand_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DeMAND)
    library(jsonlite)

    # --- Demandclass [] ---
    # Key functions: demandClass, printDeMAND
    dobj <- demandClass(exp=bcellExp, anno=bcellAnno, network=bcellNetwork)
    printDeMAND(dobj)
    # --- Rundemand [] ---
    # Key functions: runDeMAND, printDeMAND
    dobj <- runDeMAND(dobj, fgIndex=caseIndex, bgIndex=controlIndex)
    printDeMAND(dobj)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_demand_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_demand_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_demand_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEMAND:", paste0("    demand: ", packageVersion("DeMAND"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_demand_results.csv
    touch ${prefix}_demand_output.rds
    echo "BIOC_DEMAND:" > versions.yml
    echo "    demand: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEMAND_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DEMAND(ch_input)

    emit:
    results  = BIOC_DEMAND.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEMAND.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEMAND.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEMAND.out.versions  // channel: path(versions.yml)
}
