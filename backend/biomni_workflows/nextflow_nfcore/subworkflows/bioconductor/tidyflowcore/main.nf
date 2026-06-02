#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tidyFlowCore
// tidyFlowCore bridges the gap between flow cytometry analysis using the flowCore Bioconductor package
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tidyFlowCore/inst/doc/tidyFlowCore.R
// Upstream  : RefManageR, flowCore, knitr, rmarkdown, sessioninfo
// Downstream: none
//
// Install: BiocManager::install("tidyFlowCore")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TIDYFLOWCORE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tidyflowcore"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tidyflowcore:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tidyflowcore:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tidyflowcore_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tidyflowcore_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tidyflowcore_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tidyFlowCore)
    library(jsonlite)


    # --- Vignette Setup [] ---
    # Key functions: Sys.time, citation, rmarkdown, sessioninfo, testthat, dplyr, tidyFlowCore
    ## Track vignette build time
    startTime <- Sys.time()

    ## Bib setup
    library(RefManageR)

    ## Write bibliography information
    # --- "citation" [] ---
    # Key functions: citation, tidyFlowCore
    citation("tidyFlowCore")

    # --- Example [] ---
    # Key functions: Bodenmiller_BCR_XL_flowSet
    # read data from the HDCytoData package
    bcr_flowset <- HDCytoData::Bodenmiller_BCR_XL_flowSet()

    # --- Eval = False [] ---
    # Key functions: arcsinhTransform, transformList, transform, mutate, across, ends_with, asinh, fsApply
    #  ?HDCytoData::Bodenmiller_BCR_XL_flowSet

    ## -----------------------------------------------------------------------------
    asinh_transformation <- flowCore::arcsinhTransform(a = 0, b = 1/5, c = 0)
    transformation_list <- 
      flowCore::transformList(
        colnames(bcr_flowset), 
        asinh_transformation
      )

    # --- Reproduce1 [] ---
    # Key functions: Sys.time
    ## Date the vignette was generated
    Sys.time()

    # --- Reproduce2 [] ---
    # Key functions: diff, Sys.time
    ## Processing time in seconds
    totalTime <- diff(c(startTime, Sys.time()))
    round(totalTime, digits = 3)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tidyflowcore_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tidyflowcore_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tidyflowcore_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TIDYFLOWCORE:", paste0("    tidyflowcore: ", packageVersion("tidyFlowCore"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tidyflowcore_results.csv
    touch ${prefix}_tidyflowcore_output.rds
    echo "BIOC_TIDYFLOWCORE:" > versions.yml
    echo "    tidyflowcore: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TIDYFLOWCORE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TIDYFLOWCORE(ch_input)

    emit:
    results  = BIOC_TIDYFLOWCORE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TIDYFLOWCORE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TIDYFLOWCORE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TIDYFLOWCORE.out.versions  // channel: path(versions.yml)
}
