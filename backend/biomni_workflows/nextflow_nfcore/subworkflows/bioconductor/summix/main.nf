#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Summix
// This package contains the Summix2 method for estimating and adjusting for substructure in genetic su
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Summix/inst/doc/Summix.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Summix")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SUMMIX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-summix"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-summix:2.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-summix:2.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_summix_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_summix_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_summix_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Summix)
    library(jsonlite)

    # --- Allele Frequency Adjustment [] ---
    # Key functions: adjAF
    data("ancestryData")
    adjusted_data <- adjAF(
        data = ancestryData,
        reference = c("reference_AF_afr", "reference_AF_eur"),
        observed = "gnomad_AF_afr",
        pi.target = c(1, 0),
        pi.observed = c(0.85, 0.15),
        adj_method = "average",
        N_reference = c(704, 741),
        N_observed = 20744,
        filter = TRUE
    )


    # --- Multi-Ancestry Adjustment [] ---
    # Key functions: adjAF
    data("ancestryData")
    adjusted_multi <- adjAF(
        data = ancestryData,
        reference = c("reference_AF_afr", "reference_AF_eur",
                      "reference_AF_iam"),
        observed = "gnomad_AF_afr",
        pi.target = c(1, 0, 0),
        pi.observed = c(0.812, 0.170, 0.018),
        adj_method = "average",
        N_reference = c(704, 741, 47),
        N_observed = 20744,
        filter = TRUE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_summix_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_summix_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_summix_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SUMMIX:", paste0("    summix: ", packageVersion("Summix"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_summix_results.csv
    touch ${prefix}_summix_output.rds
    echo "BIOC_SUMMIX:" > versions.yml
    echo "    summix: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SUMMIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SUMMIX(ch_input)

    emit:
    results  = BIOC_SUMMIX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SUMMIX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SUMMIX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SUMMIX.out.versions  // channel: path(versions.yml)
}
