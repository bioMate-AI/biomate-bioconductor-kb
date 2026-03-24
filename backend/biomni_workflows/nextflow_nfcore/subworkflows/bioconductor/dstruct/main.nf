#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: dStruct
// dStruct identifies differentially reactive regions from RNA structurome profiling data. dStruct is c
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/dStruct/inst/doc/dStruct.R
// Upstream  : BiocStyle, tidyverse
// Downstream: none
//
// Install: BiocManager::install("dStruct")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DSTRUCT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dstruct"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dstruct:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dstruct:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dstruct_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dstruct_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dstruct_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(dStruct)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(lai2019)
    # --- Dstructguided [] ---
    # Key functions: dStructGuided
    ---------------------------------------------------------------------
    dStructGuided(wan2014[[1]],
                   reps_A = 2, reps_B = 1)
    # --- Frame [] ---
    # Key functions: frame, extract
    ---------------------------------------------------------------------
    toPlot <- res@elementMetadata %>%
      data.frame() %$%
      magrittr::extract(t, order(FDR)) %>%
      head(., n = 1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dstruct_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dstruct_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dstruct_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DSTRUCT:", paste0("    dstruct: ", packageVersion("dStruct"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dstruct_results.csv
    touch ${prefix}_dstruct_output.rds
    echo "BIOC_DSTRUCT:" > versions.yml
    echo "    dstruct: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DSTRUCT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DSTRUCT(ch_input)

    emit:
    results  = BIOC_DSTRUCT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DSTRUCT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DSTRUCT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DSTRUCT.out.versions  // channel: path(versions.yml)
}
