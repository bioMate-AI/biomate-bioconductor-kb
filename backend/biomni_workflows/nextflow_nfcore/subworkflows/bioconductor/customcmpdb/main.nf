#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: customCMPdb
// This package serves as a query interface for important community collections of small molecules, whi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/customCMPdb/inst/doc/customCMPdb.R
// Upstream  : AnnotationHub, RSQLite
// Downstream: none
//
// Install: BiocManager::install("customCMPdb")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CUSTOMCMPDB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-customcmpdb"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-customcmpdb:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-customcmpdb:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_customcmpdb_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_customcmpdb_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_customcmpdb_plots.pdf"),    emit: plots, optional: true
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
    # Key functions: AnnotationHub
    library(AnnotationHub)
    ah <- AnnotationHub()
    # --- LoadAnnot analysis [] ---
    # Key functions: install_github, loadAnnot, dbListTables, dbReadTable, dbDisconnect, loadSDFwithName, cid, addCustomAnnot
    query_id <- c("CHEMBL1064", "CHEMBL10", "CHEMBL113", "CHEMBL1004", "CHEMBL31574")
    listAnnot()
    qres <- queryAnnotDB(query_id, annot=c("drugAgeAnnot", "lincsAnnot"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_customcmpdb_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_customcmpdb_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_customcmpdb_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CUSTOMCMPDB:", paste0("    customcmpdb: ", packageVersion("customCMPdb"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_customcmpdb_results.csv
    touch ${prefix}_customcmpdb_output.rds
    echo "BIOC_CUSTOMCMPDB:" > versions.yml
    echo "    customcmpdb: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CUSTOMCMPDB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CUSTOMCMPDB(ch_input)

    emit:
    results  = BIOC_CUSTOMCMPDB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CUSTOMCMPDB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CUSTOMCMPDB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CUSTOMCMPDB.out.versions  // channel: path(versions.yml)
}
