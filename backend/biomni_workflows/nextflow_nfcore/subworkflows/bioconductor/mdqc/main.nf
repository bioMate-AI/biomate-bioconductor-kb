#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mdqc
// MDQC is a multivariate quality assessment method for microarrays based on quality control (QC) repor
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mdqc/inst/doc/mdqcvignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("mdqc")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MDQC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mdqc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mdqc:1.68.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mdqc:1.68.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mdqc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mdqc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mdqc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mdqc)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(mdqc)
    data(allQC)
    dim(allQC)
    allQC[1:2,]
    # --- Mdqc [] ---
    # Key functions: mdqc
    mdout <- mdqc(allQC, method="nogroups")
    plot(mdout)
    print(mdout)
    summary(mdout)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mdqc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mdqc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mdqc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MDQC:", paste0("    mdqc: ", packageVersion("mdqc"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mdqc_results.csv
    touch ${prefix}_mdqc_output.rds
    echo "BIOC_MDQC:" > versions.yml
    echo "    mdqc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MDQC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MDQC(ch_input)

    emit:
    results  = BIOC_MDQC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MDQC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MDQC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MDQC.out.versions  // channel: path(versions.yml)
}
