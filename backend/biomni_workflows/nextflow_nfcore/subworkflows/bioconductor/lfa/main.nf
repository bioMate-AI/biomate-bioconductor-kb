#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: lfa
// Logistic Factor Analysis is a method for a PCA analogue on Binomial data via estimation of latent st
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/lfa/inst/doc/lfa.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("lfa")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LFA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-lfa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-lfa:2.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-lfa:2.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_lfa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_lfa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_lfa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(lfa)
    library(jsonlite)

    # --- lfa [] ---
    # Key functions: lfa
    LF <- lfa(hgdp_subset, 4)
    dim(LF)
    head(LF)
    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, coord_fixed
    dat <- data.frame(LF[,1], LF[,2], colnames(hgdp_subset))
    colnames(dat) = c("LF1", "LF2", "geo")
    library(ggplot2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_lfa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_lfa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_lfa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LFA:", paste0("    lfa: ", packageVersion("lfa"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lfa_results.csv
    touch ${prefix}_lfa_output.rds
    echo "BIOC_LFA:" > versions.yml
    echo "    lfa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LFA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LFA(ch_input)

    emit:
    results  = BIOC_LFA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LFA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LFA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LFA.out.versions  // channel: path(versions.yml)
}
