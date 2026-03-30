#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowVS
// Per-channel variance stabilization from a collection of flow cytometry samples by Bertlett test for 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowVS/inst/doc/flowVS.R
// Upstream  : flowStats, vsn
// Downstream: none
//
// Install: BiocManager::install("flowVS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWVS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowvs"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowvs:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowvs:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowvs_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowvs_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowvs_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowVS)
    library(jsonlite)

    # --- densityplot [] ---
    # Key functions: densityplot
    HD.VS = transFlowVS(HD, channels=c('CD3', 'CD4'), cofactors)
    density plot (from flowViz package)
    densityplot(~CD3+CD4, HD.VS, main="Transfromed CD3 and CD4 channels in HD data")
    # --- plot Mean Sd [] ---
    # Key functions: plotMeanSd
    suppressMessages(library(vsn))
    data(kidney)
    kidney.vsn = vsn2(exprs(kidney)) #variance stabilization by vsn

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowvs_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowvs_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowvs_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWVS:", paste0("    flowvs: ", packageVersion("flowVS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowvs_results.csv
    touch ${prefix}_flowvs_output.rds
    echo "BIOC_FLOWVS:" > versions.yml
    echo "    flowvs: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWVS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWVS(ch_input)

    emit:
    results  = BIOC_FLOWVS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWVS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWVS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWVS.out.versions  // channel: path(versions.yml)
}
