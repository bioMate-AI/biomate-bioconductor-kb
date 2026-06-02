#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gypsum
// Client for the gypsum REST API (https://gypsum.artifactdb.com), a cloud-based file store in the Arti
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gypsum/inst/doc/userguide.R
// Upstream  : BiocStyle
// Downstream: none
//
// Install: BiocManager::install("gypsum")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GYPSUM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gypsum"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gypsum:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gypsum:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gypsum_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gypsum_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gypsum_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(gypsum)
    library(jsonlite)

    # --- Listassets [] ---
    # Key functions: listAssets, listVersions, listFiles, saveFile, saveVersion, files
    ---------------------------------------------------------------------
    library(gypsum)
    listAssets("test-R")
    listVersions("test-R", "basic")
    listFiles("test-R", "basic", "v1")
    # --- Fetchmanifest [] ---
    # Key functions: fetchManifest, fetchSummary
    ---------------------------------------------------------------------
    fetchManifest("test-R", "basic", "v1")
    fetchSummary("test-R", "basic", "v1")
    # --- Fetchlatest [] ---
    # Key functions: fetchLatest
    ---------------------------------------------------------------------
    fetchLatest("test-R", "basic")
    # --- Fetchpermissions [] ---
    # Key functions: fetchPermissions
    ---------------------------------------------------------------------
    fetchPermissions("test-R")
    # --- Fetchquota [] ---
    # Key functions: fetchQuota
    ---------------------------------------------------------------------
    fetchQuota("test-R")
    # --- Fetchusage [] ---
    # Key functions: fetchUsage
    ---------------------------------------------------------------------
    fetchUsage("test-R")
    # --- Fetchmetadataschema [] ---
    # Key functions: fetchMetadataSchema
    ---------------------------------------------------------------------
    schema <- fetchMetadataSchema()
    cat(head(readLines(schema)), sep="\n")
    # --- List [] ---
    # Key functions: validateMetadata
    ---------------------------------------------------------------------
    metadata <- list(
        title="Fatherhood",
        description="Luke ich bin dein Vater.",
        sources=list(

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gypsum_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gypsum_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gypsum_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GYPSUM:", paste0("    gypsum: ", packageVersion("gypsum"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gypsum_results.csv
    touch ${prefix}_gypsum_output.rds
    echo "BIOC_GYPSUM:" > versions.yml
    echo "    gypsum: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GYPSUM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GYPSUM(ch_input)

    emit:
    results  = BIOC_GYPSUM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GYPSUM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GYPSUM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GYPSUM.out.versions  // channel: path(versions.yml)
}
