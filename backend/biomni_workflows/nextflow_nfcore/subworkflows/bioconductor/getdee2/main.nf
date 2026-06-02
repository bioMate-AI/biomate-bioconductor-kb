#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: getDEE2
// Digital Expression Explorer 2 (or DEE2 for short) is a repository of processed RNA-seq data in the f
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/getDEE2/inst/doc/getDEE2.R
// Upstream  : SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("getDEE2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GETDEE2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-getdee2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-getdee2:1.16.2--r44_0' :
        'quay.io/biocontainers/bioconductor-getdee2:1.16.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_getdee2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_getdee2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_getdee2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(getDEE2)
    library(jsonlite)

    # --- Expression Data Retrieval [] ---
    # Key functions: getDEE2
    se_data <- getDEE2(
        species = "celegans",
        SRRvec = c("SRR363798", "SRR363799"),
        counts = "GeneCounts"
    )


    # --- Legacy Format Retrieval [] ---
    # Key functions: getDEE2
    legacy_data <- getDEE2(
        species = "celegans",
        SRRvec = c("SRR363798", "SRR363799"),
        legacy = TRUE
    )
    gene_counts <- legacy_data$GeneCounts
    tx_counts <- legacy_data$TxCounts


    # --- Bundle Querying and Retrieval [] ---
    # Key functions: list_bundles, query_bundles, getDEE2_bundle
    bundles <- list_bundles("athaliana")
    queried_bundles <- query_bundles(
        species = "athaliana",
        query = "SRP058781",
        col = "SRP_accession",
        bundles = bundles
    )
    bundle_data <- getDEE2_bundle(
        species = "athaliana",
        bundle_id = "SRP058781",
        col = "SRP_accession",
        counts = "GeneCounts"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_getdee2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_getdee2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_getdee2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GETDEE2:", paste0("    getdee2: ", packageVersion("getDEE2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_getdee2_results.csv
    touch ${prefix}_getdee2_output.rds
    echo "BIOC_GETDEE2:" > versions.yml
    echo "    getdee2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GETDEE2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GETDEE2(ch_input)

    emit:
    results  = BIOC_GETDEE2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GETDEE2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GETDEE2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GETDEE2.out.versions  // channel: path(versions.yml)
}
