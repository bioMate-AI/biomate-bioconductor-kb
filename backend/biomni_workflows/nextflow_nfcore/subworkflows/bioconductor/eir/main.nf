#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: eiR
// The eiR package provides utilities for accelerated structure similarity searching of very large smal
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/eiR/inst/doc/eiR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("eiR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EIR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-eir"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-eir:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-eir:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_eir_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_eir_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_eir_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(eiR)
    library(jsonlite)

    # --- term=FALSE [] ---
    # Key functions: cid
    result=eiQuery(runId,sdfsample[45],K=10,asSimilarity=TRUE)
    print(result)
    data(apset)
    # --- term=FALSE [] ---
    # Key functions: eiAdd
    eiAdd(runId,sdfsample[100])
    # --- term=FALSE [] ---
    # Key functions: eiPerformanceTest
    eiPerformanceTest(runId,K=22)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_eir_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_eir_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_eir_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EIR:", paste0("    eir: ", packageVersion("eiR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_eir_results.csv
    touch ${prefix}_eir_output.rds
    echo "BIOC_EIR:" > versions.yml
    echo "    eir: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EIR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EIR(ch_input)

    emit:
    results  = BIOC_EIR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EIR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EIR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EIR.out.versions  // channel: path(versions.yml)
}
