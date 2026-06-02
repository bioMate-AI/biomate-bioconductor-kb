#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: matter
// Toolbox for larger-than-memory scientific computing and visualization, providing efficient out-of-co
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/matter/inst/doc/matter2-guide.R
// Upstream  : none
// Downstream: CardinalIO
//
// Install: BiocManager::install("matter")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MATTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-matter"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-matter:2.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-matter:2.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_matter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_matter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_matter_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(matter)
    library(jsonlite)

    # --- Matter vec analysis [] ---
    # Key functions: matter_vec, atomdata, array, matter_arr, path, matter_mat, rowMaj, matter_list
    set.seed(1)
    l1 <- list(A=runif(10), B=rnorm(15), C=rlnorm(5), D="This is a string!")
    l2 <- matter_list(l1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_matter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_matter_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_matter_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MATTER:", paste0("    matter: ", packageVersion("matter"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matter_results.csv
    touch ${prefix}_matter_output.rds
    echo "BIOC_MATTER:" > versions.yml
    echo "    matter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MATTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MATTER(ch_input)

    emit:
    results  = BIOC_MATTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MATTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MATTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MATTER.out.versions  // channel: path(versions.yml)
}
