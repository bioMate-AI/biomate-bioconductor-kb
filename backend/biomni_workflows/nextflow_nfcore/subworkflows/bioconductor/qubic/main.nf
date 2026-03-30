#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: QUBIC
// The core function of this R package is to provide the implementation of the well-cited and well-revi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/QUBIC/inst/doc/qubic_vignette.R
// Upstream  : QUBICdata, RColorBrewer
// Downstream: none
//
// Install: BiocManager::install("QUBIC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QUBIC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-qubic"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-qubic:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-qubic:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(deseqresults)

    output:
    tuple val(meta), path("${meta.id}_qubic_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_qubic_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_qubic_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(QUBIC)
    library(jsonlite)

    # --- Qudiscretize analysis [] ---
    # Key functions: qudiscretize, runif, biclust, colorRampPalette, quheatmap, qunetwork, qgraph, showinfo
    net <- qunetwork(ecoli, res, number = c(4, 8), group = c(4, 8), method = "spearman")
    if (requireNamespace("qgraph", quietly = TRUE))
    qgraph::qgraph(net[[1]], groups = net[[2]], legend.cex = 0.5, layout = "spring",

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_qubic_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_qubic_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_qubic_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QUBIC:", paste0("    qubic: ", packageVersion("QUBIC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qubic_results.csv
    touch ${prefix}_qubic_output.rds
    echo "BIOC_QUBIC:" > versions.yml
    echo "    qubic: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QUBIC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(deseqresults) ]

    main:
    BIOC_QUBIC(ch_input)

    emit:
    results  = BIOC_QUBIC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QUBIC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QUBIC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QUBIC.out.versions  // channel: path(versions.yml)
}
