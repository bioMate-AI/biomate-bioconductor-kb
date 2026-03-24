#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Pviz
// Pviz adapts the Gviz package for protein sequences and data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Pviz/inst/doc/Pviz.R
// Upstream  : pepDat
// Downstream: none
//
// Install: BiocManager::install("Pviz")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PVIZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pviz"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pviz:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pviz:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pviz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pviz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pviz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ATrack)
    library(CladeTrack)
    library(DTrack)
    library(ProbeTrack)
    library(ProteinAxisTrack)
    library(ProteinSequenceTrack)
    library(jsonlite)

    # --- Object metadata inspection [] ---
    # Key functions: ATrack, plotTracks, DTrack, ProteinAxisTrack, metadata, ProteinSequenceTrack, ProbeTrack, CladeTrack
    ctA <- CladeTrack(restab, clade = "A", type = "l")
    ctM <- CladeTrack(restab, clade = "M", type = "l", legend = TRUE)
    plotTracks(c(ctA, ctM), main = "Clades comparison", cex.main = 1.5)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pviz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pviz_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pviz_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PVIZ:", paste0("    pviz: ", packageVersion("Pviz"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pviz_results.csv
    touch ${prefix}_pviz_output.rds
    echo "BIOC_PVIZ:" > versions.yml
    echo "    pviz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PVIZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PVIZ(ch_input)

    emit:
    results  = BIOC_PVIZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PVIZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PVIZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PVIZ.out.versions  // channel: path(versions.yml)
}
