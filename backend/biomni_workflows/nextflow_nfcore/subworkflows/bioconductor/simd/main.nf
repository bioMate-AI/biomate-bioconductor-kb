#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SIMD
// This package provides a inferential analysis method for detecting differentially expressed CpG sites
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SIMD/inst/doc/SIMD.R
// Upstream  : edgeR, methylMnM, statmod
// Downstream: none
//
// Install: BiocManager::install("SIMD")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SIMD {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-simd"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-simd:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-simd:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_simd_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_simd_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_simd_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(EMalgorithm)
    library(EMtest)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: EMalgorithm
    ---------------------------------------------------------------------
    data(example_data)
    allcpgfile <- EM_H1ESB1_MeDIP_sigleCpG
    readshort <- paste(filepath, "/H1ESB1_MeDIP_18.extended.txt", sep="")
    writefile <- paste(dirwrite, "EM2_H1ESB1_MeDIP_sigleCpG.bed", sep="")
    # --- Data [] ---
    # Key functions: EMtest
    ---------------------------------------------------------------------
    data(example_data)
    data1 <- EM2_H1ESB1_MeDIP_sigleCpG
    data2 <- EM2_H1ESB2_MeDIP_sigleCpG
    data3 <- H1ESB1_MRE_sigleCpG

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_simd_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_simd_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_simd_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SIMD:", paste0("    simd: ", packageVersion("SIMD"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_simd_results.csv
    touch ${prefix}_simd_output.rds
    echo "BIOC_SIMD:" > versions.yml
    echo "    simd: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SIMD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SIMD(ch_input)

    emit:
    results  = BIOC_SIMD.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SIMD.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SIMD.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SIMD.out.versions  // channel: path(versions.yml)
}
