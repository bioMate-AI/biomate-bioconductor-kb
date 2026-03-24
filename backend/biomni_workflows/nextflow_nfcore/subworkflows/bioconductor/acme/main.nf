#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ACME
// ACME (Algorithms for Calculating Microarray Enrichment) is a set of tools for analysing tiling array
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ACME/inst/doc/ACME.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ACME")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ACME {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-acme"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-acme:2.62.0--r44_0' :
        'quay.io/biocontainers/bioconductor-acme:2.62.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_acme_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_acme_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_acme_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ACME)
    library(jsonlite)

    # --- Calc [] ---
    # Key functions: calc
    calc <- do.aGFF.calc(example.agff,window=1000,thresh=0.95)
    # --- Findregions [] ---
    # Key functions: findRegions
    regs <- findRegions(calc)
    regs[1:5,]
    # --- Sgr [] ---
    # Key functions: sgr
    # write both calculated values and raw data
    write.sgr(calc)
    # OR write only calculated data
    write.sgr(calc,raw=FALSE)
    # --- Bedgraph [] ---
    # Key functions: bedGraph
    # or for the UCSC genome browser
    write.bedGraph(calc)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_acme_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_acme_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_acme_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ACME:", paste0("    acme: ", packageVersion("ACME"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_acme_results.csv
    touch ${prefix}_acme_output.rds
    echo "BIOC_ACME:" > versions.yml
    echo "    acme: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ACME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ACME(ch_input)

    emit:
    results  = BIOC_ACME.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ACME.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ACME.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ACME.out.versions  // channel: path(versions.yml)
}
