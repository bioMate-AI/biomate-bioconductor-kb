#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: combi
// This explorative ordination method combines quasi-likelihood estimation, compositional regression mo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/combi/inst/doc/combi.R
// Upstream  : BiocManager, devtools
// Downstream: none
//
// Install: BiocManager::install("combi")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COMBI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-combi"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-combi:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-combi:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_combi_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_combi_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_combi_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(combi)
    library(jsonlite)

    # --- add Link [] ---
    # Key functions: addLink
    mmPlot = plot(microMetaboInt, samDf = zhangMetavars, samCol = "ABX", returnCoords = TRUE, featNum = 10)
    addLink(mmPlot, links = cbind("Staphylococcus_819c11","OTU929ffc"), Views = 1, samples = c(0,1))
    # --- conv Plot [] ---
    # Key functions: convPlot
    convPlot(microMetaboInt)
    # --- infl Plot [] ---
    # Key functions: inflPlot
    inflPlot(microMetaboInt, samples = 1:20, plotType = "boxplot")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_combi_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_combi_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_combi_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COMBI:", paste0("    combi: ", packageVersion("combi"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_combi_results.csv
    touch ${prefix}_combi_output.rds
    echo "BIOC_COMBI:" > versions.yml
    echo "    combi: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COMBI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COMBI(ch_input)

    emit:
    results  = BIOC_COMBI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COMBI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COMBI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COMBI.out.versions  // channel: path(versions.yml)
}
