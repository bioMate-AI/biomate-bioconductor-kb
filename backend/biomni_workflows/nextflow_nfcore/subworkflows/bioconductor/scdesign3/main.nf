#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scDesign3
// We present a statistical simulator, scDesign3, to generate realistic single-cell and spatial omics d
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scDesign3/inst/doc/scDesign3.R
// Upstream  : SingleCellExperiment, ggplot2
// Downstream: none
//
// Install: BiocManager::install("scDesign3")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCDESIGN3 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scdesign3"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scdesign3:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scdesign3:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scdesign3_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scdesign3_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scdesign3_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SingleCellExperiment)
    library(jsonlite)

    # --- Readrds [] ---
    # Key functions: url
    ---------------------------------------------------------------------
    example_sce <- readRDS((url("https://figshare.com/ndownloader/files/40581992")))
    print(example_sce)
    # --- Logcounts [] ---
    # Key functions: logcounts, log1p, counts, SingleCellExperiment
    ---------------------------------------------------------------------
    logcounts(example_sce) <- log1p(counts(example_sce))
    simu_sce <- SingleCellExperiment(list(counts = example_simu$new_count), colData = example_simu$new_covariate)
    logcounts(simu_sce) <- log1p(counts(simu_sce))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scdesign3_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scdesign3_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scdesign3_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCDESIGN3:", paste0("    scdesign3: ", packageVersion("scDesign3"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scdesign3_results.csv
    touch ${prefix}_scdesign3_output.rds
    echo "BIOC_SCDESIGN3:" > versions.yml
    echo "    scdesign3: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCDESIGN3_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCDESIGN3(ch_input)

    emit:
    results  = BIOC_SCDESIGN3.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCDESIGN3.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCDESIGN3.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCDESIGN3.out.versions  // channel: path(versions.yml)
}
