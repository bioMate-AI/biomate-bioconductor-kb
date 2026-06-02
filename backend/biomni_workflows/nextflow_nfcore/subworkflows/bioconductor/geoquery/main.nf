#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GEOquery
// The NCBI Gene Expression Omnibus (GEO) is a public repository of microarray data.  Given the rich an
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GEOquery/inst/doc/GEOquery.R
// Upstream  : knitr, Biobase
// Downstream: DrugVsDisease, SCAN.UPC, dyebiasexamples, GSE103322, GSE13015
//
// Install: BiocManager::install("GEOquery")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GEOQUERY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-geoquery"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-geoquery:2.74.0--r44_0' :
        'quay.io/biocontainers/bioconductor-geoquery:2.74.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_geoquery_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_geoquery_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_geoquery_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Columns)
    library(GSMList)
    library(Table)
    library(GEOquery)
    library(jsonlite)


    # --- Pre [] ---
    # Key functions: set
    library(knitr)
    opts_chunk$set(warning=FALSE,message=FALSE,cache=FALSE)

    # --- Load Library [] ---
    # Key functions: getGEO
    library(GEOquery)

    ## -----------------------------------------------------------------------------
    # If you have network access, the more typical way to do this
    # would be to use this:
    # gds <- getGEO("GDS507")
    gds <- getGEO(filename=system.file("extdata/GDS507.soft.gz",package="GEOquery"))

    ## -----------------------------------------------------------------------------
    # If you have network access, the more typical way to do this
    # would be to use this:
    # gds <- getGEO("GSM11805")
    gsm <- getGEO(filename=system.file("extdata/GSM11805.txt.gz",package="GEOquery"))

    ## -----------------------------------------------------------------------------

    # --- Citation [] ---
    # Key functions: citation
    citation("GEOquery")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_geoquery_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_geoquery_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_geoquery_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GEOQUERY:", paste0("    geoquery: ", packageVersion("GEOquery"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_geoquery_results.csv
    touch ${prefix}_geoquery_output.rds
    echo "BIOC_GEOQUERY:" > versions.yml
    echo "    geoquery: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GEOQUERY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GEOQUERY(ch_input)

    emit:
    results  = BIOC_GEOQUERY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GEOQUERY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GEOQUERY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GEOQUERY.out.versions  // channel: path(versions.yml)
}
