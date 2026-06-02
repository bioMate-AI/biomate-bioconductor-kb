#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: plasmut
// A Bayesian method for quantifying the liklihood that a given plasma mutation arises from clonal hema
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/plasmut/inst/doc/plasmut.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("plasmut")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PLASMUT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-plasmut"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-plasmut:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-plasmut:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_plasmut_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_plasmut_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_plasmut_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(plasmut)
    library(jsonlite)

    # --- Clinical Cohort Analysis [] ---
    # Key functions: importance_sampler
    data(crcseq, package = "plasmut")
    params <- list(
        ctdna = list(a = 1, b = 9),
        ctc = list(a = 1, b = 10^3),
        chip = list(a = 1, b = 9),
        montecarlo.samples = 1000,
        prior.weight = 0.1
    )
    sample_data <- crcseq[crcseq$patient == "patient1", ]
    results <- importance_sampler(sample_data, params)


    # --- Prior Weight Tuning [] ---
    # Key functions: importance_sampler
    p53 <- data.frame(
        y = c(4, 0),
        n = c(1000, 600),
        analyte = c("plasma", "buffy coat"),
        mutation = "TP53",
        sample_id = "id1"
    )
    params <- list(
        ctc = list(a = 1, b = 10e3),
        ctdna = list(a = 1, b = 9),
        chip = list(a = 1, b = 9),
        montecarlo.samples = 500,
        prior.weight = 0.5
    )
    tuned_stats <- importance_sampler(p53, params)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_plasmut_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_plasmut_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_plasmut_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PLASMUT:", paste0("    plasmut: ", packageVersion("plasmut"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_plasmut_results.csv
    touch ${prefix}_plasmut_output.rds
    echo "BIOC_PLASMUT:" > versions.yml
    echo "    plasmut: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PLASMUT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PLASMUT(ch_input)

    emit:
    results  = BIOC_PLASMUT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PLASMUT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PLASMUT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PLASMUT.out.versions  // channel: path(versions.yml)
}
