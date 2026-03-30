#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pengls
// Combine generalised least squares methodology from the nlme package for dealing with autocorrelation
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pengls/inst/doc/penglsVignette.R
// Upstream  : BiocManager, BiocParallel, nlme
// Downstream: none
//
// Install: BiocManager::install("pengls")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PENGLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pengls"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pengls:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pengls:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pengls_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pengls_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pengls_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pengls)
    library(jsonlite)

    # --- Rnorm analysis [] ---
    # Key functions: rnorm, corGaus, pengls, coef, predict, corAR1, register, makeFolds
    Define the correlation structure (see ?nlme::gls), with initial nugget 0.5 and range 5
    corStruct <- corGaus(form = ~ x + y, nugget = TRUE, value = c("range" = 5, "nugget" = 0.5))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pengls_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pengls_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pengls_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PENGLS:", paste0("    pengls: ", packageVersion("pengls"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pengls_results.csv
    touch ${prefix}_pengls_output.rds
    echo "BIOC_PENGLS:" > versions.yml
    echo "    pengls: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PENGLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PENGLS(ch_input)

    emit:
    results  = BIOC_PENGLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PENGLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PENGLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PENGLS.out.versions  // channel: path(versions.yml)
}
