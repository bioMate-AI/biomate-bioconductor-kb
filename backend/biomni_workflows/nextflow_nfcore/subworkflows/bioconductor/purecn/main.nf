#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PureCN
// This package estimates tumor purity, copy number, and loss of heterozygosity (LOH), and classifies s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PureCN/inst/doc/PureCN.R
// Upstream  : rtracklayer
// Downstream: none
//
// Install: BiocManager::install("PureCN")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PURECN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-purecn"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-purecn:2.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-purecn:2.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_purecn_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_purecn_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_purecn_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PureCN)
    library(jsonlite)

    # --- Import genomic data file [] ---
    # Key functions: import, preprocessIntervals, calculateTangentNormal, callMutationBurden

    # --- UlateBamCoverageByInterval analysis [] ---
    # Key functions: calculateBamCoverageByInterval, correctCoverageBias, createNormalDatabase, calculateMappingBiasVcf, browserSession, genome, track, export


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_purecn_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_purecn_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_purecn_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PURECN:", paste0("    purecn: ", packageVersion("PureCN"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_purecn_results.csv
    touch ${prefix}_purecn_output.rds
    echo "BIOC_PURECN:" > versions.yml
    echo "    purecn: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PURECN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PURECN(ch_input)

    emit:
    results  = BIOC_PURECN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PURECN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PURECN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PURECN.out.versions  // channel: path(versions.yml)
}
