#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RUVcorr
// RUVcorr allows to apply global removal of unwanted variation (ridged version of RUV) to real and sim
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RUVcorr/inst/doc/Vignette.R
// Upstream  : bladderbatch, snowfall
// Downstream: none
//
// Install: BiocManager::install("RUVcorr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RUVCORR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ruvcorr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ruvcorr:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ruvcorr:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ruvcorr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ruvcorr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ruvcorr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RUVcorr)
    library(jsonlite)


    # --- Warning=false [] ---
    # Key functions: function, histogramPlot
    cor_AllRUV_na <- lapply(expr_AllRUV, function(x) cor(x[,na_index]))
    cor_Raw_na <- cor(expr[,na_index])

    lapply(1:4, function(i) histogramPlot(cor_AllRUV_na[seq(0,15,4)+i], cor_Raw_na,
      title=paste("nu=", nu[i]), legend=c(paste("k=", k), "Raw")))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ruvcorr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ruvcorr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ruvcorr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RUVCORR:", paste0("    ruvcorr: ", packageVersion("RUVcorr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ruvcorr_results.csv
    touch ${prefix}_ruvcorr_output.rds
    echo "BIOC_RUVCORR:" > versions.yml
    echo "    ruvcorr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RUVCORR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RUVCORR(ch_input)

    emit:
    results  = BIOC_RUVCORR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RUVCORR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RUVCORR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RUVCORR.out.versions  // channel: path(versions.yml)
}
