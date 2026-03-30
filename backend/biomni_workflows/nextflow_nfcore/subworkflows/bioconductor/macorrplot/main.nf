#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: maCorrPlot
// Graphically displays correlation in microarray data that is due to insufficient normalization
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/maCorrPlot/inst/doc/maCorrPlot.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("maCorrPlot")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MACORRPLOT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-macorrplot"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-macorrplot:1.76.0--r44_0' :
        'quay.io/biocontainers/bioconductor-macorrplot:1.76.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_macorrplot_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_macorrplot_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_macorrplot_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CorrSample)
    library(jsonlite)

    # --- Corrsample [] ---
    # Key functions: CorrSample
    corrA.rma = CorrSample(datA.rma, np=1000, seed=213)
    # --- Rowsums [] ---
    # Key functions: rowSums
    pcntA = rowSums(datA.amp=="P")
    # --- Cut [] ---
    # Key functions: cut
    pgrpA.pairs = cut(pcntA.pairs, c(0, 10, 20, 30), include.lowest=TRUE)
    table(pgrpA.pairs)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_macorrplot_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_macorrplot_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_macorrplot_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MACORRPLOT:", paste0("    macorrplot: ", packageVersion("maCorrPlot"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_macorrplot_results.csv
    touch ${prefix}_macorrplot_output.rds
    echo "BIOC_MACORRPLOT:" > versions.yml
    echo "    macorrplot: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MACORRPLOT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MACORRPLOT(ch_input)

    emit:
    results  = BIOC_MACORRPLOT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MACORRPLOT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MACORRPLOT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MACORRPLOT.out.versions  // channel: path(versions.yml)
}
