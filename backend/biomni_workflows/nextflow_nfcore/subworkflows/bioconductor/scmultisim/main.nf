#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scMultiSim
// scMultiSim simulates paired single cell RNA-seq, single cell ATAC-seq and RNA velocity data, while i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scMultiSim/inst/doc/spatialCCI.R
// Upstream  : ggplot2, knitr
// Downstream: none
//
// Install: BiocManager::install("scMultiSim")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCMULTISIM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scmultisim"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scmultisim:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scmultisim:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scmultisim_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scmultisim_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scmultisim_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scMultiSim)
    library(jsonlite)

    # --- Load all analysis [] ---
    # Key functions: load_all, scmultisim_help, sim_true_counts, plot_cell_loc, gen_clutter, colSums
    plot_cell_loc(results_1, show.arrows = T, .cell.pop = as.character(results$grid$final_types))
    plot_cell_loc(results_3, show.arrows = T, .cell.pop = as.character(results$grid$final_types))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scmultisim_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scmultisim_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scmultisim_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCMULTISIM:", paste0("    scmultisim: ", packageVersion("scMultiSim"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scmultisim_results.csv
    touch ${prefix}_scmultisim_output.rds
    echo "BIOC_SCMULTISIM:" > versions.yml
    echo "    scmultisim: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCMULTISIM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCMULTISIM(ch_input)

    emit:
    results  = BIOC_SCMULTISIM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCMULTISIM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCMULTISIM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCMULTISIM.out.versions  // channel: path(versions.yml)
}
