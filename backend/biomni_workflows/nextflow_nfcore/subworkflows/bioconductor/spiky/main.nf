#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: spiky
// spiky implements methods and model generation for cfMeDIP (cell-free methylated DNA immunoprecipitat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/spiky/inst/doc/spiky_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("spiky")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPIKY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spiky"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spiky:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spiky:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spiky_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spiky_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spiky_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(spiky)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(spike)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spiky_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spiky_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spiky_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPIKY:", paste0("    spiky: ", packageVersion("spiky"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spiky_results.csv
    touch ${prefix}_spiky_output.rds
    echo "BIOC_SPIKY:" > versions.yml
    echo "    spiky: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPIKY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPIKY(ch_input)

    emit:
    results  = BIOC_SPIKY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPIKY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPIKY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPIKY.out.versions  // channel: path(versions.yml)
}
