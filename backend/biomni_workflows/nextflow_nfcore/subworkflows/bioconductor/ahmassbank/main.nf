#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AHMassBank
// Supplies AnnotationHub with MassBank metabolite/compound annotations bundled in CompDb SQLite databa
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AHMassBank/inst/doc/creating-MassBank-CompDbs.R
// Upstream  : AnnotationHub, RMariaDB
// Downstream: none
//
// Install: BiocManager::install("AHMassBank")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AHMASSBANK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ahmassbank"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ahmassbank:1.6.1--r44_0' :
        'quay.io/biocontainers/bioconductor-ahmassbank:1.6.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ahmassbank_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ahmassbank_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ahmassbank_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnotationHub)
    library(jsonlite)

    # --- Access AnnotationHub resources [] ---
    # Key functions: AnnotationHub, query
    library(AnnotationHub)
    ah <- AnnotationHub()
    query(ah, "MassBank")
    # --- query [] ---
    # Key functions: query
    qr <- query(ah, c("MassBank", "2021.03"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ahmassbank_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ahmassbank_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ahmassbank_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AHMASSBANK:", paste0("    ahmassbank: ", packageVersion("AHMassBank"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ahmassbank_results.csv
    touch ${prefix}_ahmassbank_output.rds
    echo "BIOC_AHMASSBANK:" > versions.yml
    echo "    ahmassbank: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AHMASSBANK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AHMASSBANK(ch_input)

    emit:
    results  = BIOC_AHMASSBANK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AHMASSBANK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AHMASSBANK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AHMASSBANK.out.versions  // channel: path(versions.yml)
}
