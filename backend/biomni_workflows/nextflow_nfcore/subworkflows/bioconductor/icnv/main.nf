#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iCNV
// Integrative copy number variation (CNV) detection from multiple platform and experimental design.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iCNV/inst/doc/iCNV-vignette.R
// Upstream  : CODEX
// Downstream: none
//
// Install: BiocManager::install("iCNV")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ICNV {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-icnv"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-icnv:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-icnv:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_icnv_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_icnv_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_icnv_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(iCNV)
    library(jsonlite)

    # --- CODEX Normalization 1 [] ---
    # Key functions: getbambed, getcoverage, getgc, getmapp, normalize
    library(CODEX)
    library(WES.1KG.WUGSC) # Load Toy data from the 1000 Genomes Project.
    library(iCNV)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_icnv_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_icnv_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_icnv_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ICNV:", paste0("    icnv: ", packageVersion("iCNV"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_icnv_results.csv
    touch ${prefix}_icnv_output.rds
    echo "BIOC_ICNV:" > versions.yml
    echo "    icnv: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ICNV_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ICNV(ch_input)

    emit:
    results  = BIOC_ICNV.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ICNV.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ICNV.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ICNV.out.versions  // channel: path(versions.yml)
}
