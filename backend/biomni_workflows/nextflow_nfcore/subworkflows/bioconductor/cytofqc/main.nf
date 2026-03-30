#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cytofQC
// cytofQC is a package for initial cleaning of CyTOF data. It uses a semi-supervised approach for labe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cytofQC/inst/doc/cytofQC.R
// Upstream  : RColorBrewer, uwot
// Downstream: none
//
// Install: BiocManager::install("cytofQC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYTOFQC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cytofqc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cytofqc:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cytofqc:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cytofqc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cytofqc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cytofqc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cytofQC)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_point, scale_color_manual, guides, labs
    library(RColorBrewer)
    ggplot(lab.umapD, aes(x = x, y = y)) +
    geom_point(aes(color = labs), size = 0.5, alpha = 0.5) +
    # --- PrepData analysis [] ---
    # Key functions: prepData, readCytof, labelQC, cytofHist, initialBead, svmLabel, initialDebris, initialDoublet
    bead <- cytofHist(scores(x, type = 'bead'), label(x), type = "density", title = "Bead score")
    debris <- cytofHist(scores(x, type = 'debris'), label(x), type = "density", title = "Debris score")
    doublet <- cytofHist(scores(x, type = 'doublet'), label(x), type = "density", title = "Doublet score")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cytofqc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cytofqc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cytofqc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CYTOFQC:", paste0("    cytofqc: ", packageVersion("cytofQC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cytofqc_results.csv
    touch ${prefix}_cytofqc_output.rds
    echo "BIOC_CYTOFQC:" > versions.yml
    echo "    cytofqc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CYTOFQC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CYTOFQC(ch_input)

    emit:
    results  = BIOC_CYTOFQC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CYTOFQC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CYTOFQC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CYTOFQC.out.versions  // channel: path(versions.yml)
}
