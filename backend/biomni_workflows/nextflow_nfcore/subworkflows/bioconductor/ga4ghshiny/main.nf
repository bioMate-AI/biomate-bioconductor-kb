#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GA4GHshiny
// GA4GHshiny package provides an easy way to interact with data servers based on Global Alliance for G
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/GA4GHshiny/inst/doc/GA4GHshiny.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GA4GHshiny")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GA4GHSHINY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ga4ghshiny"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ga4ghshiny:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ga4ghshiny:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ga4ghshiny_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ga4ghshiny_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ga4ghshiny_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GA4GHshiny)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: app
    library(org.Hs.eg.db)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    library(GA4GHshiny)
    app(host = "http://1kgenomes.ga4gh.org/",
        serverName = "Hosting Thousand Genomes Project",
    # --- Code Block 3 [] ---
    # Key functions: app
    library(org.Hs.eg.db)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    library(GA4GHshiny)
    app(host = "http://1kgenomes.ga4gh.org/",
        serverName = "Hosting Thousand Genomes Project",
    # --- Code Block 4 [] ---
    # Key functions: 1, namespace
    ## R version 4.4.1 (2024-06-14)
    ## Platform: x86_64-pc-linux-gnu
    ## Running under: Ubuntu 24.04.1 LTS
    ##
    ## Matrix products: default

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ga4ghshiny_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ga4ghshiny_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ga4ghshiny_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GA4GHSHINY:", paste0("    ga4ghshiny: ", packageVersion("GA4GHshiny"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ga4ghshiny_results.csv
    touch ${prefix}_ga4ghshiny_output.rds
    echo "BIOC_GA4GHSHINY:" > versions.yml
    echo "    ga4ghshiny: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GA4GHSHINY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GA4GHSHINY(ch_input)

    emit:
    results  = BIOC_GA4GHSHINY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GA4GHSHINY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GA4GHSHINY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GA4GHSHINY.out.versions  // channel: path(versions.yml)
}
