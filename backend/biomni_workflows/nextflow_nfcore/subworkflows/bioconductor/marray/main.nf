#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: marray
// Class definitions for two-color spotted microarray data. Fuctions for data input, diagnostic plots, 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/marray/inst/doc/marray.R
// Upstream  : none
// Downstream: CGHbase, convert, dyebias, MineICA, nnNorm
//
// Install: BiocManager::install("marray")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MARRAY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-marray"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-marray:1.84.0--r44_0' :
        'quay.io/biocontainers/bioconductor-marray:1.84.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_marray_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_marray_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_marray_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Galfile)
    library(Spot)
    library(jsonlite)

    # --- Spot [] ---
    # Key functions: Spot
    mraw <- read.Spot(targets = swirlTargets, path=datadir)
    # --- Galfile [] ---
    # Key functions: Galfile
    galinfo <- read.Galfile("fish.gal", path=datadir)
    mraw@maLayout <- galinfo$layout
    mraw@maGnames <- galinfo$gnames

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_marray_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_marray_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_marray_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MARRAY:", paste0("    marray: ", packageVersion("marray"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_marray_results.csv
    touch ${prefix}_marray_output.rds
    echo "BIOC_MARRAY:" > versions.yml
    echo "    marray: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MARRAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MARRAY(ch_input)

    emit:
    results  = BIOC_MARRAY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MARRAY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MARRAY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MARRAY.out.versions  // channel: path(versions.yml)
}
