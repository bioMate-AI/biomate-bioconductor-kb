#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: phosphonormalizer
// It uses the overlap between enriched and non-enriched datasets to compensate for the bias introduced
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/phosphonormalizer/inst/doc/phosphonormalizer.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("phosphonormalizer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHOSPHONORMALIZER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-phosphonormalizer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-phosphonormalizer:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-phosphonormalizer:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_phosphonormalizer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_phosphonormalizer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_phosphonormalizer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(phosphonormalizer)
    library(jsonlite)

    # --- Frame [] ---
    # Key functions: frame, factor, normalizePhospho
    #Load the library
    library(phosphonormalizer)
    #Specify the column numbers of abundances in the original
    #data.frame, from both enriched and non-enriched runs
    samplesCols <- data.frame(enriched=3:17, non.enriched=3:17)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_phosphonormalizer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_phosphonormalizer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_phosphonormalizer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PHOSPHONORMALIZER:", paste0("    phosphonormalizer: ", packageVersion("phosphonormalizer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phosphonormalizer_results.csv
    touch ${prefix}_phosphonormalizer_output.rds
    echo "BIOC_PHOSPHONORMALIZER:" > versions.yml
    echo "    phosphonormalizer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PHOSPHONORMALIZER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PHOSPHONORMALIZER(ch_input)

    emit:
    results  = BIOC_PHOSPHONORMALIZER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PHOSPHONORMALIZER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PHOSPHONORMALIZER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PHOSPHONORMALIZER.out.versions  // channel: path(versions.yml)
}
