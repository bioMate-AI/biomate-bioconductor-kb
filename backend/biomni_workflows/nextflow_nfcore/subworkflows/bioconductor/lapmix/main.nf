#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: lapmix
// Laplace mixture modelling of microarray experiments. A hierarchical Bayesian approach is used, and t
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/lapmix/inst/doc/lapmix-example.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("lapmix")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LAPMIX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-lapmix"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-lapmix:1.72.0--r44_0' :
        'quay.io/biocontainers/bioconductor-lapmix:1.72.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_lapmix_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_lapmix_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_lapmix_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Fit)
    library(jsonlite)

    # --- Sim [] ---
    # Key functions: rgamma, rexp, sample, rnorm
    set.seed(1011)
    G <- 3000
    Y <- NULL
    sigma_sq <- 1/rgamma(G, shape=2.8, scale=0.04)
    mu <- rexp(G, rate=1/(sigma_sq*1.2))-rexp(G, rate=1/(sigma_sq*1.2))
    # --- Fit [] ---
    # Key functions: Fit
    res <- lapmix.Fit(Y)
    # --- Table [] ---
    # Key functions: laptopTable
    m <- 12
    laptopTable(res, m)
    # --- Lapmix Example.Rnw:57 58 [] ---
    # Key functions: volcanoplot
    lap.volcanoplot(res)
    # --- Fitasym [] ---
    # Key functions: Fit
    res2 <- lapmix.Fit(Y, asym=TRUE)
    res2$estimates

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_lapmix_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_lapmix_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_lapmix_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LAPMIX:", paste0("    lapmix: ", packageVersion("lapmix"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lapmix_results.csv
    touch ${prefix}_lapmix_output.rds
    echo "BIOC_LAPMIX:" > versions.yml
    echo "    lapmix: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LAPMIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LAPMIX(ch_input)

    emit:
    results  = BIOC_LAPMIX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LAPMIX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LAPMIX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LAPMIX.out.versions  // channel: path(versions.yml)
}
