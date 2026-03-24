#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RLassoCox
// RLassoCox is a package that implements the RLasso-Cox model proposed by Wei Liu. The RLasso-Cox mode
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RLassoCox/inst/doc/RLassoCox.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("RLassoCox")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RLASSOCOX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rlassocox"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rlassocox:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rlassocox:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rlassocox_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rlassocox_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rlassocox_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RLassoCox)
    library(jsonlite)

    # --- Train model [] ---
    # Key functions: RLassoCox
    mod <- RLassoCox(x=x.train, y=y.train, globalGraph=dGMMirGraph)
    # --- predict [] ---
    # Key functions: predict
    lp <- predict(object = mod, newx = x.test, s = c(0.1, 0.2))
    head(lp)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rlassocox_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rlassocox_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rlassocox_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RLASSOCOX:", paste0("    rlassocox: ", packageVersion("RLassoCox"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rlassocox_results.csv
    touch ${prefix}_rlassocox_output.rds
    echo "BIOC_RLASSOCOX:" > versions.yml
    echo "    rlassocox: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RLASSOCOX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RLASSOCOX(ch_input)

    emit:
    results  = BIOC_RLASSOCOX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RLASSOCOX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RLASSOCOX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RLASSOCOX.out.versions  // channel: path(versions.yml)
}
