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
    library(MgnifyClient)
    library(jsonlite)

    # --- Mgnify Client [] ---
    # Key functions: MgnifyClient
    mg <- MgnifyClient(useCache = TRUE)
    # --- convert to analyses1 [] ---
    # Key functions: searchAnalysis
    analyses_accessions <- searchAnalysis(mg, "samples", samples$accession)
    # --- get metadata1 [] ---
    # Key functions: getMetadata
    analyses_metadata <- getMetadata(mg, analyses_accessions)
    # --- get mae1 [] ---
    # Key functions: getResult
    mae <- getResult(mg, accession = analyses_accessions)
    # --- calculate diversity [] ---
    # Key functions: plotColData
    library(mia)
    mae[[1]] <- estimateDiversity(mae[[1]], index = "shannon")
    library(scater)
    # --- plot abundance [] ---
    # Key functions: altExps, getTopFeatures, plotAbundance
    altExps(mae[[1]]) <- splitByRanks(mae[[1]])
    library(miaViz)
    top_taxa <- getTopFeatures(altExp(mae[[1]], "Phylum"), 10)
    # --- plot Reduced Dim [] ---
    # Key functions: plotReducedDim
    mae[[1]] <- transformAssay(mae[[1]], method = "relabundance")
    # --- fetch data1 [] ---
    # Key functions: getData
    publications <- getData(mg, type = "publications")
    # --- get download urls1 [] ---
    # Key functions: searchFile
    dl_urls <- searchFile(mg, analyses_accessions, type = "analyses")
    # --- download file1 [] ---
    # Key functions: getFile
    cached_location <- getFile(mg, file_url)

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
