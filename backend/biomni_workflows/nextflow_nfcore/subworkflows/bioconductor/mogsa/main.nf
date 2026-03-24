#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mogsa
// This package provide a method for doing gene set analysis based on multiple omics data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mogsa/inst/doc/mogsa-knitr.R
// Upstream  : gplots, graphite
// Downstream: none
//
// Install: BiocManager::install("mogsa")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOGSA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mogsa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mogsa:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mogsa:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mogsa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mogsa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mogsa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GIS)
    library(jsonlite)

    # --- Visualization and reporting [] ---
    # Key functions: getmgsa
    eigs <- getmgsa(mgsa1, "partial.eig") # get partial "eigenvalue" for separate data
    barplot(as.matrix(eigs), legend.text = rownames(eigs))
    # --- Mogsa analysis [] ---
    # Key functions: mogsa, getmgsa, GIS, moa, slot, prepGraphite, prepMsigDB, prepSupMoa
    fs <- getmgsa(mgsa1, "fac.scr") # extract the factor scores for cell lines (cell line space)
    layout(matrix(1:2, 1, 2))
    plot(fs[, 1:2], pch=20, col=colcode, axes = FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mogsa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mogsa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mogsa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOGSA:", paste0("    mogsa: ", packageVersion("mogsa"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mogsa_results.csv
    touch ${prefix}_mogsa_output.rds
    echo "BIOC_MOGSA:" > versions.yml
    echo "    mogsa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOGSA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOGSA(ch_input)

    emit:
    results  = BIOC_MOGSA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOGSA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOGSA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOGSA.out.versions  // channel: path(versions.yml)
}
