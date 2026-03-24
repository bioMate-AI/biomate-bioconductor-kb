#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SICtools
// This package is to find SNV/Indel differences between two bam files with near relationship in a way 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SICtools/inst/doc/SICtools.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SICtools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SICTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sictools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sictools:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sictools:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sictools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sictools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sictools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SICtools)
    library(jsonlite)

    # --- Indeldiff [] ---
    # Key functions: indelDiff
    ---------------------------------------------------------------------
    indelDiffDf <- indelDiff(bam1,bam2,refFsa,'chr07',828514,828914,pValueCutOff=1,gtDistCutOff=0)
    indelDiffDfSort <- indelDiffDf[order(indelDiffDf$p.value,indelDiffDf$d.value),]
    indelDiffDfSort

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sictools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sictools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sictools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SICTOOLS:", paste0("    sictools: ", packageVersion("SICtools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sictools_results.csv
    touch ${prefix}_sictools_output.rds
    echo "BIOC_SICTOOLS:" > versions.yml
    echo "    sictools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SICTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SICTOOLS(ch_input)

    emit:
    results  = BIOC_SICTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SICTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SICTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SICTOOLS.out.versions  // channel: path(versions.yml)
}
