#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GenVisR
// Produce highly customizable publication quality graphics for genomic data primarily at the cohort le
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GenVisR/inst/doc/Intro.R
// Upstream  : ggplot2, knitr, reshape2
// Downstream: none
//
// Install: BiocManager::install("GenVisR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENVISR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genvisr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genvisr:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genvisr:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genvisr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genvisr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genvisr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GenVisR)
    library(jsonlite)

    # --- kable 1 [] ---
    # Key functions: kable
    library(knitr)
    # --- kable [] ---
    # Key functions: kable
    kable(as.data.frame(cbind(sample=as.character(brcaMAF[1:10,16]),
    mut_burden=as.numeric(rnorm(10, mean=2, sd=.5)))))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genvisr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genvisr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genvisr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENVISR:", paste0("    genvisr: ", packageVersion("GenVisR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genvisr_results.csv
    touch ${prefix}_genvisr_output.rds
    echo "BIOC_GENVISR:" > versions.yml
    echo "    genvisr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENVISR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENVISR(ch_input)

    emit:
    results  = BIOC_GENVISR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENVISR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENVISR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENVISR.out.versions  // channel: path(versions.yml)
}
