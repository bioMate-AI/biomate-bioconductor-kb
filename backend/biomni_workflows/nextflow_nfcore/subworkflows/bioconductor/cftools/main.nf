#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cfTools
// The cfTools R package provides methods for cell-free DNA (cfDNA) methylation data analysis to facili
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cfTools/inst/doc/cfTools-vignette.R
// Upstream  : GenomicRanges
// Downstream: none
//
// Install: BiocManager::install("cfTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CFTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cftools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cftools:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cftools:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cftools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cftools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cftools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cfTools)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>"
    )

    # --- Demo [] ---
    # Key functions: read.table, MergePEReads, cfTools, demo.sorted.bed.txt.gz, CpG_OT_demo.txt.gz, CpG_OB_demo.txt.gz
    library(cfTools)
    library(utils)
    demo.dir <- system.file("data", package="cfTools")

    ## -----------------------------------------------------------------------------
    PEReads <- file.path(demo.dir, "demo.sorted.bed.txt.gz")
    head(read.table(PEReads, header=FALSE), 2)

    ## -----------------------------------------------------------------------------
    fragInfo <- MergePEReads(PEReads)
    head(fragInfo, 2)

    ## -----------------------------------------------------------------------------
    CpG_OT <- file.path(demo.dir, "CpG_OT_demo.txt.gz")
    CpG_OB <- file.path(demo.dir, "CpG_OB_demo.txt.gz")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cftools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cftools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cftools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CFTOOLS:", paste0("    cftools: ", packageVersion("cfTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cftools_results.csv
    touch ${prefix}_cftools_output.rds
    echo "BIOC_CFTOOLS:" > versions.yml
    echo "    cftools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CFTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CFTOOLS(ch_input)

    emit:
    results  = BIOC_CFTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CFTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CFTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CFTOOLS.out.versions  // channel: path(versions.yml)
}
