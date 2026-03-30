#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MPFE
// Estimate distribution of methylation patterns from a table of counts from a bisulphite sequencing ex
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MPFE/inst/doc/MPFE.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MPFE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MPFE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mpfe"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mpfe:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mpfe:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mpfe_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mpfe_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mpfe_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MPFE)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: estimatePatterns
    library(MPFE)
    data(patternsExample)
    patternsExample
    estimatePatterns(patternsExample, epsilon=0.01, column=2)
    # --- Estimatepatterns [] ---
    # Key functions: estimatePatterns
    estimates <- estimatePatterns(patternsExample,
                                  epsilon=0.01,
                                  eta=c(0.008, 0.01, 0.01, 0.01, 0.008))
    estimates
    # --- Plotpatterns [] ---
    # Key functions: plotPatterns
    plotPatterns(estimates[[2]])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mpfe_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mpfe_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mpfe_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MPFE:", paste0("    mpfe: ", packageVersion("MPFE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mpfe_results.csv
    touch ${prefix}_mpfe_output.rds
    echo "BIOC_MPFE:" > versions.yml
    echo "    mpfe: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MPFE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MPFE(ch_input)

    emit:
    results  = BIOC_MPFE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MPFE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MPFE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MPFE.out.versions  // channel: path(versions.yml)
}
