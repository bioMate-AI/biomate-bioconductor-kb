#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: raer
// Toolkit for identification and statistical testing of RNA editing signals from within R. Provides su
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/raer/inst/doc/raer.R
// Upstream  : AnnotationHub, ComplexHeatmap, SingleCellExperiment, raerdata, scater
// Downstream: none
//
// Install: BiocManager::install("raer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RAER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-raer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-raer:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-raer:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_raer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_raer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_raer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FilterParam)
    library(jsonlite)

    # --- Filter Param [] ---
    # Key functions: FilterParam, pileup_cells, read_sparray, calc_edit_frequency
    outdir <- file.path(tempdir(), "sc_edits")
    cbs <- colnames(sce)
    params <- FilterParam(

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_raer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_raer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_raer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RAER:", paste0("    raer: ", packageVersion("raer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_raer_results.csv
    touch ${prefix}_raer_output.rds
    echo "BIOC_RAER:" > versions.yml
    echo "    raer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RAER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RAER(ch_input)

    emit:
    results  = BIOC_RAER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RAER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RAER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RAER.out.versions  // channel: path(versions.yml)
}
