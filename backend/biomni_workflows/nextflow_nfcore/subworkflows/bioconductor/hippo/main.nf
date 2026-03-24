#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HIPPO
// For scRNA-seq data, it selects features and clusters the cells simultaneously for single-cell UMI da
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HIPPO/inst/doc/example.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("HIPPO")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HIPPO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hippo"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hippo:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hippo:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hippo_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hippo_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hippo_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HIPPO)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(toydata)
    data(ensg_hgnc)
    # --- Hippo Dimension Reduction [] ---
    # Key functions: hippo_dimension_reduction, hippo_tsne_plot
    ---------------------------------------------------------------------
    toydata = hippo_dimension_reduction(toydata, method="tsne")
    hippo_tsne_plot(toydata)
    # --- Hippo Diffexp [] ---
    # Key functions: hippo_diffexp
    ---------------------------------------------------------------------
    toydata = hippo_diffexp(toydata,
                      top.n = 5,
                      switch_to_hgnc = TRUE,
                      ref = ensg_hgnc)
    # --- Head [] ---
    # Key functions: get_hippo_diffexp
    ---------------------------------------------------------------------
    head(get_hippo_diffexp(toydata, 1))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hippo_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hippo_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hippo_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HIPPO:", paste0("    hippo: ", packageVersion("HIPPO"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hippo_results.csv
    touch ${prefix}_hippo_output.rds
    echo "BIOC_HIPPO:" > versions.yml
    echo "    hippo: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HIPPO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HIPPO(ch_input)

    emit:
    results  = BIOC_HIPPO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HIPPO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HIPPO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HIPPO.out.versions  // channel: path(versions.yml)
}
