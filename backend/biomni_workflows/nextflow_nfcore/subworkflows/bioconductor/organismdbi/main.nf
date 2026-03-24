#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: OrganismDbi
// The package enables a simple unified interface to several annotation packages each of which has its 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/OrganismDbi/inst/doc/OrganismDbi.R
// Upstream  : none
// Downstream: Homo.sapiens, Mus.musculus, Rattus.norvegicus
//
// Install: BiocManager::install("OrganismDbi")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ORGANISMDBI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-organismdbi"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-organismdbi:1.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-organismdbi:1.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_organismdbi_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_organismdbi_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_organismdbi_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(OrganismDbi)
    library(jsonlite)

    # --- Transcript annotation retrieval [] ---
    # Key functions: include_graphics, columns, keytypes, transcripts, transcriptsBy, tempfile, makeOrganismPackage
    knitr::include_graphics("relationships-between-annotation-packages.png")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_organismdbi_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_organismdbi_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_organismdbi_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ORGANISMDBI:", paste0("    organismdbi: ", packageVersion("OrganismDbi"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_organismdbi_results.csv
    touch ${prefix}_organismdbi_output.rds
    echo "BIOC_ORGANISMDBI:" > versions.yml
    echo "    organismdbi: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ORGANISMDBI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ORGANISMDBI(ch_input)

    emit:
    results  = BIOC_ORGANISMDBI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ORGANISMDBI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ORGANISMDBI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ORGANISMDBI.out.versions  // channel: path(versions.yml)
}
