#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: bioDist
// A collection of software tools for calculating distance measures.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/bioDist/inst/doc/bioDist.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("bioDist")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIODIST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biodist"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biodist:1.78.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biodist:1.78.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biodist_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biodist_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biodist_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(bioDist)
    library(jsonlite)

    # --- Loadlib [] ---
    # Key functions: exprs
    library("bioDist")
    data(sample.ExpressionSet)
    exData = t(exprs(sample.ExpressionSet))
    # --- Tau [] ---
    # Key functions: dist
    eS = sample.ExpressionSet[401:500,]
    tauD = tau.dist(eS, sample=FALSE)
    sp = spearman.dist(eS, sample=FALSE)
    # --- Closest [] ---
    # Key functions: featureNames, top
    f1 = featureNames(eS)[1]
    closest.top(f1, sp, 3)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biodist_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biodist_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biodist_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIODIST:", paste0("    biodist: ", packageVersion("bioDist"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biodist_results.csv
    touch ${prefix}_biodist_output.rds
    echo "BIOC_BIODIST:" > versions.yml
    echo "    biodist: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIODIST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIODIST(ch_input)

    emit:
    results  = BIOC_BIODIST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIODIST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIODIST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIODIST.out.versions  // channel: path(versions.yml)
}
