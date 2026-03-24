#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sevenbridges
// R client and utilities for Seven Bridges platform API, from Cancer Genomics Cloud to other Seven Bri
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sevenbridges/inst/doc/api.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("sevenbridges")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEVENBRIDGES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sevenbridges"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sevenbridges:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sevenbridges:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sevenbridges_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sevenbridges_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sevenbridges_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Auth)
    library(Date)
    library(Metadata)
    library(Tool)
    library(jsonlite)

    # --- Create Auth Object [] ---
    # Key functions: Auth, api
    ---------------------------------------------------------------------
    #  library("sevenbridges")
    #  a <- Auth(token = "your_token", platform = "aws-us")
    #  a$api(path = "projects", method = "GET")
    # --- Get Project Details [] ---
    # Key functions: project
    ---------------------------------------------------------------------
    #  a$project()
    # --- Packages [] ---
    # Key functions: packages
    ---------------------------------------------------------------------
    #  install.packages("BiocManager")
    #  BiocManager::install("sevenbridges")
    # --- Packages [] ---
    # Key functions: packages, install_github, repositories
    ---------------------------------------------------------------------
    #  install.packages("BiocManager")
    #  install.packages("readr")
    #
    #  devtools::install_github(
    # --- Create Auth Object [] ---
    # Key functions: Auth
    ---------------------------------------------------------------------
    #  (a <- Auth(platform = "cgc", token = "your_token"))
    # --- Set Environment Variables [] ---
    # Key functions: sbg_set_env
    ---------------------------------------------------------------------
    #  sbg_set_env("https://cgc-api.sbgenomics.com/v2", "your_token")
    # --- Create Auth Object [] ---
    # Key functions: Auth
    ---------------------------------------------------------------------
    #  a <- Auth(from = "env")
    # --- Get User Information [] ---
    # Key functions: user
    ---------------------------------------------------------------------
    #  a$user()
    # --- Check Rate Limit [] ---
    # Key functions: rate_limit
    ---------------------------------------------------------------------
    #  a$rate_limit()
    # --- Show Billing Information [] ---
    # Key functions: billing, invoice
    ---------------------------------------------------------------------
    #  # check your billing info
    #  a$billing()
    #  a$invoice()
    # --- Show Billing Information [] ---
    # Key functions: billing
    ---------------------------------------------------------------------
    #  a$billing(id = "your_billing_id", breakdown = TRUE)
    # --- Show Billing Information [] ---
    # Key functions: billing, project_new
    ---------------------------------------------------------------------
    #  # get billing group id
    #  bid <- a$billing()$id
    #  # create new project
    #  (p <- a$project_new(name = "api testing", bid, description = "Just a test"))
    # --- Get Project Details [] ---
    # Key functions: project
    ---------------------------------------------------------------------
    #  # list first 100
    #  a$project()
    #  # list all
    #  a$project(complete = TRUE)
    # --- List Public Apps [] ---
    # Key functions: public_app
    ---------------------------------------------------------------------
    #  # search by name matching, complete = TRUE search all apps,
    #  # not limited by offset or limit.
    #  a$public_app(name = "STAR", complete = TRUE)
    #  # search by id is accurate
    # --- Copy Public App [] ---
    # Key functions: copy_app, project, app
    ---------------------------------------------------------------------
    #  # copy
    #  a$copy_app(
    #    id = "admin/sbg-public-data/rna-seq-alignment-star/5",
    #    project = "RFranklin/api-testing", name = "new copy of star"

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sevenbridges_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sevenbridges_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sevenbridges_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEVENBRIDGES:", paste0("    sevenbridges: ", packageVersion("sevenbridges"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sevenbridges_results.csv
    touch ${prefix}_sevenbridges_output.rds
    echo "BIOC_SEVENBRIDGES:" > versions.yml
    echo "    sevenbridges: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEVENBRIDGES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEVENBRIDGES(ch_input)

    emit:
    results  = BIOC_SEVENBRIDGES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEVENBRIDGES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEVENBRIDGES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEVENBRIDGES.out.versions  // channel: path(versions.yml)
}
