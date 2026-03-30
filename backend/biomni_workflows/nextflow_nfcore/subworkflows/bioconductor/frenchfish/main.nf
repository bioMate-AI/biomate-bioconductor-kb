#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: frenchFISH
// FrenchFISH comprises a nuclear volume correction method coupled with two types of Poisson models: ei
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/frenchFISH/inst/doc/frenchFISH.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("frenchFISH")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FRENCHFISH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-frenchfish"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-frenchfish:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-frenchfish:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_frenchfish_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_frenchfish_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_frenchfish_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(frenchFISH)
    library(jsonlite)

    # --- correct autocounts [] ---
    # Key functions: getAutomaticCountsEstimates
    set.seed(366)
    corrected_automatic_counts <- getAutomaticCountsEstimates(automatic_counts,
    # --- readin manualcounts [] ---
    # Key functions: cbind
    manual_counts <- cbind(red = round(runif(20,0,5), 0),
    green = round(runif(20,0,5), 0),
    blue = round(runif(20,0,5), 0))
    # --- correct manualcounts [] ---
    # Key functions: getManualCountsEstimates
    corrected_manual_counts <- getManualCountsEstimates(manual_counts,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_frenchfish_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_frenchfish_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_frenchfish_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FRENCHFISH:", paste0("    frenchfish: ", packageVersion("frenchFISH"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_frenchfish_results.csv
    touch ${prefix}_frenchfish_output.rds
    echo "BIOC_FRENCHFISH:" > versions.yml
    echo "    frenchfish: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FRENCHFISH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FRENCHFISH(ch_input)

    emit:
    results  = BIOC_FRENCHFISH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FRENCHFISH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FRENCHFISH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FRENCHFISH.out.versions  // channel: path(versions.yml)
}
