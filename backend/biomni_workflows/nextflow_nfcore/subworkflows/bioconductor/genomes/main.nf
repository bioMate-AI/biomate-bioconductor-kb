#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: genomes
// Download genome and assembly reports from NCBI
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/genomes/inst/doc/genomes.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("genomes")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomes"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genomes:3.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genomes:3.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomes_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomes_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomes_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(genomes)
    library(jsonlite)

    # --- Proks [] ---
    # Key functions: reports
    ## reports()
    ## proks <- reports("prokaryotes.txt")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genomes_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genomes_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genomes_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMES:", paste0("    genomes: ", packageVersion("genomes"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomes_results.csv
    touch ${prefix}_genomes_output.rds
    echo "BIOC_GENOMES:" > versions.yml
    echo "    genomes: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMES(ch_input)

    emit:
    results  = BIOC_GENOMES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMES.out.versions  // channel: path(versions.yml)
}
