#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SNAGEE
// Signal-to-Noise applied to Gene Expression Experiments. Signal-to-noise ratios can be used as a prox
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SNAGEE/inst/doc/SNAGEE.R
// Upstream  : ALL
// Downstream: none
//
// Install: BiocManager::install("SNAGEE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SNAGEE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-snagee"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-snagee:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-snagee:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_snagee_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_snagee_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_snagee_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SNAGEE)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(SNAGEE)
    library(ALL)
    data(ALL)
    # --- Qualstudy [] ---
    # Key functions: qualStudy
    q = qualStudy(ALL)
    print(q)
    # --- Qualsample [] ---
    # Key functions: qualSample
    qs = qualSample(ALL, multicore=FALSE)
    sum(qs < -5)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_snagee_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_snagee_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_snagee_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SNAGEE:", paste0("    snagee: ", packageVersion("SNAGEE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snagee_results.csv
    touch ${prefix}_snagee_output.rds
    echo "BIOC_SNAGEE:" > versions.yml
    echo "    snagee: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SNAGEE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SNAGEE(ch_input)

    emit:
    results  = BIOC_SNAGEE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SNAGEE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SNAGEE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SNAGEE.out.versions  // channel: path(versions.yml)
}
