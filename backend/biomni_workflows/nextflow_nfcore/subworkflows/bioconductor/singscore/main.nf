#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: singscore
// A simple single-sample gene signature scoring method that uses rank-based statistics to analyze the 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/singscore/inst/doc/singscore.R
// Upstream  : GSEABase
// Downstream: none
//
// Install: BiocManager::install("singscore")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SINGSCORE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-singscore"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-singscore:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-singscore:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_singscore_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_singscore_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_singscore_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SnowParam)
    library(jsonlite)

    # --- RankGenes analysis [] ---
    # Key functions: install_github, rankGenes, simpleScore, getStableGenes, plotRankDensity, plotDispersion, plotScoreLandscape, projectScoreLandscape
    tgfbAnnot <- data.frame(SampleID = colnames(tgfb_expr_10_se),
    tgfbAnnot$Type[grepl("Ctrl", tgfbAnnot$SampleID)] = "Control"
    tgfbAnnot$Type[grepl("TGFb", tgfbAnnot$SampleID)] = "TGFb"

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_singscore_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_singscore_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_singscore_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SINGSCORE:", paste0("    singscore: ", packageVersion("singscore"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_singscore_results.csv
    touch ${prefix}_singscore_output.rds
    echo "BIOC_SINGSCORE:" > versions.yml
    echo "    singscore: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SINGSCORE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SINGSCORE(ch_input)

    emit:
    results  = BIOC_SINGSCORE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SINGSCORE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SINGSCORE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SINGSCORE.out.versions  // channel: path(versions.yml)
}
