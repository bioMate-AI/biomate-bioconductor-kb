#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CNORdt
// This add-on to the package CellNOptR handles time-course data, as opposed to steady state data in Ce
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CNORdt/inst/doc/CNORdt-vignette.R
// Upstream  : CellNOptR
// Downstream: none
//
// Install: BiocManager::install("CNORdt")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CNORDT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cnordt"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cnordt:1.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cnordt:1.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cnordt_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cnordt_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cnordt_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CNORdt)
    library(jsonlite)

    # --- Installpackage [] ---
    # Key functions: requireNamespace, packages
    ## if (!requireNamespace("BiocManager", quietly=TRUE))
    ##     install.packages("BiocManager")
    ## BiocManager::install("CNORdt")
    # --- Getdata [] ---
    # Key functions: data
    data(CNOlistPB, package="CNORdt")
    data(modelPB, package="CNORdt")
    # --- Preprocess [] ---
    # Key functions: preprocessing
    # pre-process model
    model = preprocessing(CNOlistPB, modelPB)
    initBstring <- rep(1, length(model$reacID))
    # --- Optimise [] ---
    # Key functions: gaBinaryDT
    opt1 <- gaBinaryDT(CNOlist=CNOlistPB, model=model, initBstring=initBstring,
    verbose=FALSE, boolUpdates=10, maxTime=30, lowerB=0.8, upperB=10)
    # --- Plotdata [] ---
    # Key functions: cutAndPlotResultsDT
    cutAndPlotResultsDT(
    	model=model,
    	CNOlist=CNOlistPB,
    	bString=opt1$bString,
    	plotPDF=FALSE,
    # --- Writeres [] ---
    # Key functions: writeScaffold, writeNetwork
    writeScaffold(
    	modelComprExpanded=model,
    	optimResT1=opt1,
    	optimResT2=NA,
    	modelOriginal=modelPB,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cnordt_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cnordt_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cnordt_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CNORDT:", paste0("    cnordt: ", packageVersion("CNORdt"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnordt_results.csv
    touch ${prefix}_cnordt_output.rds
    echo "BIOC_CNORDT:" > versions.yml
    echo "    cnordt: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CNORDT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CNORDT(ch_input)

    emit:
    results  = BIOC_CNORDT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CNORDT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CNORDT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CNORDT.out.versions  // channel: path(versions.yml)
}
