#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Rcollectl
// Provide functions to obtain instrumentation data on processes in a unix environment.  Parse output o
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Rcollectl/inst/doc/Rcollectl.R
// Upstream  : knitcitations, knitr, rmarkdown, sessioninfo
// Downstream: none
//
// Install: BiocManager::install("Rcollectl")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RCOLLECTL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rcollectl"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rcollectl:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rcollectl:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rcollectl_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rcollectl_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rcollectl_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Rcollectl)
    library(jsonlite)


    # --- Vignette Setup [] ---
    # Key functions: Sys.time, cleanbib, cite_options, citation, write.bibtex, knitcitations, to.doc, text
    ## Track time spent on making the vignette
    startTime <- Sys.time()

    ## Bib setup
    library("knitcitations")

    ## Load knitcitations with a clean bibliography
    cleanbib()
    cite_options(hyperlink = "to.doc", citation_format = "text", style = "html")

    # --- Lkdemo [] ---
    # Key functions: cl_parse, attr, meta
    lk = cl_parse(system.file("demotab/demo_1123.tab.gz", package="Rcollectl"))
    dim(lk)
    attr(lk, "meta")
    lk[1:5,1:5]

    # --- Lkviz [] ---
    # Key functions: plot_usage
    plot_usage(lk)

    # --- Lkts [] ---
    # Key functions: cl_start, Sys.sleep, cl_timestamp, cl_stop, cl_result_path, plot_usage, cl_parse, cl_timestamp_layer
    id <- cl_start() 
         Sys.sleep(2)
         #code
         cl_timestamp(id, "step1")
         Sys.sleep(2)
         # code
         Sys.sleep(2)
         cl_timestamp(id, "step2")
         Sys.sleep(2)
         # code

    # --- Create Vignette2 [] ---
    # Key functions: file.remove
    ## Clean up
    file.remove("Rcollectl.bib")

    # --- Reproduce1 [] ---
    # Key functions: Sys.time
    ## Date the vignette was generated
    Sys.time()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rcollectl_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rcollectl_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rcollectl_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RCOLLECTL:", paste0("    rcollectl: ", packageVersion("Rcollectl"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rcollectl_results.csv
    touch ${prefix}_rcollectl_output.rds
    echo "BIOC_RCOLLECTL:" > versions.yml
    echo "    rcollectl: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RCOLLECTL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RCOLLECTL(ch_input)

    emit:
    results  = BIOC_RCOLLECTL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RCOLLECTL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RCOLLECTL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RCOLLECTL.out.versions  // channel: path(versions.yml)
}
