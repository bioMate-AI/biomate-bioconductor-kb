#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cancerclass
// The classification protocol starts with a feature selection step and continues with nearest-centroid
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cancerclass/inst/doc/vignette_cancerclass.R
// Upstream  : cancerdata
// Downstream: none
//
// Install: BiocManager::install("cancerclass")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CANCERCLASS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cancerclass"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cancerclass:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cancerclass:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cancerclass_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cancerclass_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cancerclass_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cancerclass)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(cancerclass)
    data(GOLUB1)
    GOLUB1
    # --- Nvalidate [] ---
    # Key functions: nvalidate
    nval <- nvalidate(GOLUB1[1:200, ], ngenes=c(5, 10, 20, 50, 100, 200))
    # --- Validate [] ---
    # Key functions: validate
    val <- validate(GOLUB1[1:200, ], ngenes=10, ntrain="balanced")
    # --- Data [] ---
    # Key functions: setdiff, sampleNames, fit, predict
    library(cancerdata)
    data(VEER)
    data(VIJVER)
    VIJVER2 <- VIJVER[, setdiff(sampleNames(VIJVER), sampleNames(VEER))]
    predictor <- fit(VEER, method="welch.test")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cancerclass_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cancerclass_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cancerclass_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CANCERCLASS:", paste0("    cancerclass: ", packageVersion("cancerclass"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cancerclass_results.csv
    touch ${prefix}_cancerclass_output.rds
    echo "BIOC_CANCERCLASS:" > versions.yml
    echo "    cancerclass: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CANCERCLASS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CANCERCLASS(ch_input)

    emit:
    results  = BIOC_CANCERCLASS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CANCERCLASS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CANCERCLASS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CANCERCLASS.out.versions  // channel: path(versions.yml)
}
