#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Mergeomics
// The Mergeomics pipeline serves as a flexible framework for integrating multidimensional omics-diseas
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Mergeomics/inst/doc/Mergeomics.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Mergeomics")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MERGEOMICS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mergeomics"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mergeomics:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mergeomics:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mergeomics_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mergeomics_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mergeomics_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MSEA)
    library(jsonlite)

    # --- Packages [] ---
    # Key functions: packages, requireNamespace
    ## install.packages("Mergeomics.tar.gz", repos = NULL,
    ## type="source")
    ## ## or from bioconductor3.3 release, use following lines:
    ## if (!requireNamespace("BiocManager", quietly=TRUE))
    ##     install.packages("BiocManager")
    # --- List [] ---
    # Key functions: parameters, onestep, 2, 33
    ## ###########################################################
    ## #######    One-step analysis for Mergeomics - 1st way    ##
    ## ###########################################################
    ## ## Import library scripts.
    ## library(Mergeomics)
    # --- Msea [] ---
    # Key functions: MSEA, 20000, start, prepare, control
    ###########################################################
    #######    One-step analysis for Mergeomics - 2nd way    ##
    ###########################################################
    ## Import library scripts.
    library(Mergeomics)
    # --- List [] ---
    # Key functions: 20000, databases, sets, start, prepare
    ## ###########################################################
    ## ## Import Mergeomics library.
    ## library("Mergeomics")
    ## ## create an empty list for setting parameters
    ## job.msea <- list()
    # --- List [] ---
    # Key functions: read, translate, coalesce
    ## ###########################################################
    ## job <-list()
    ## job$folder <- c("module_merge")
    ## ## The moddata and modinfo either come from the significant pathways found in
    ## ## any previous MSEA run or these files can be manually curated by the user.
    # --- Finish [] ---
    # Key functions: finish, meta
    ## ###########################################################
    ## ## Assume there are three MSEA objects passed down by
    ## ## ssea.finish()
    ## # job.metamsea = list()
    ## # job.metamsea$job1 = job.msea1
    # --- List [] ---
    # Key functions: configure, start, prepare, analyze, finish
    ## ###########################################################
    ## job.kda <- list()
    ## job.kda$label<-"HDLC"
    ## ## parent folder for results
    ## job.kda$folder<-"./Results"
    # --- Finish [] ---
    # Key functions: finish, kda2cytoscape
    ## ###########################################################
    ## ## run following line after finishing the KDA process
    ## ## i.e., after the kda.finish() function concluded
    ## job.kda <- kda2cytoscape (job.kda, node.list=NULL,
    ## modules=NULL, ndrivers=5, depth=1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mergeomics_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mergeomics_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mergeomics_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MERGEOMICS:", paste0("    mergeomics: ", packageVersion("Mergeomics"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mergeomics_results.csv
    touch ${prefix}_mergeomics_output.rds
    echo "BIOC_MERGEOMICS:" > versions.yml
    echo "    mergeomics: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MERGEOMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MERGEOMICS(ch_input)

    emit:
    results  = BIOC_MERGEOMICS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MERGEOMICS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MERGEOMICS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MERGEOMICS.out.versions  // channel: path(versions.yml)
}
