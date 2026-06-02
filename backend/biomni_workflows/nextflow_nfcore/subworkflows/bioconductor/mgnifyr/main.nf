#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MGnifyR
// Utility package to facilitate integration and analysis of EBI MGnify data in R. The package can be u
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MGnifyR/inst/doc/MGnifyR.R
// Upstream  : Biostrings, ggplot2, knitr, mia, miaViz
// Downstream: none
//
// Install: BiocManager::install("MGnifyR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MGNIFYR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mgnifyr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mgnifyr:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mgnifyr:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mgnifyr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mgnifyr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mgnifyr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MGnifyR)
    library(MgnifyClient)
    library(jsonlite)

    # --- Metadata Retrieval [] ---
    # Key functions: getMetadata
    mg <- MgnifyClient(useCache = TRUE)
    analyses_metadata <- getMetadata(
        client = mg,
        accession = analyses_accessions
    )


    # --- Fetching Microbiome Data [] ---
    # Key functions: getMicrobiomeData
    mg <- MgnifyClient(useCache = TRUE)
    mae <- getMicrobiomeData(
        client = mg,
        accession = analyses_accessions
    )


    # --- Download URL Retrieval and File Download [] ---
    # Key functions: searchFile, getFile
    mg <- MgnifyClient(useCache = TRUE)
    dl_urls <- searchFile(
        client = mg,
        accession = "MGYS00005058"
    )
    target_urls <- dl_urls[
        dl_urls$attributes.description.label == "Predicted alpha tmRNA",
    ]
    cached_location <- getFile(
        client = mg,
        url = target_urls$links.self[1]
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mgnifyr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mgnifyr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mgnifyr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MGNIFYR:", paste0("    mgnifyr: ", packageVersion("MGnifyR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mgnifyr_results.csv
    touch ${prefix}_mgnifyr_output.rds
    echo "BIOC_MGNIFYR:" > versions.yml
    echo "    mgnifyr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MGNIFYR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MGNIFYR(ch_input)

    emit:
    results  = BIOC_MGNIFYR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MGNIFYR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MGNIFYR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MGNIFYR.out.versions  // channel: path(versions.yml)
}
