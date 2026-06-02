#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: multistateQTL
// A collection of tools for doing various analyses of multi-state QTL data, with a focus on visualizat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/multistateQTL/inst/doc/multiStateQTL.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("multistateQTL")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MULTISTATEQTL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-multistateqtl"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-multistateqtl:1.2.2--r44_0' :
        'quay.io/biocontainers/bioconductor-multistateqtl:1.2.2--r44_0'}"

    input:
    tuple val(meta), path(ggplot_object)

    output:
    tuple val(meta), path("${meta.id}_multistateqtl_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_multistateqtl_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_multistateqtl_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(multistateQTL)
    library(jsonlite)

    # --- Assay data access [] ---
    # Key functions: sumstats2qtle, qtleEstimate, plotSimulationParams, qtleSimulate, sample, assay, getComplete, replaceNAs
    sim <- callSignificance(sim, assay="lfsrs", thresh=0.05)
    message("Median number of significant tests per state: ",
    median(colData(sim)$nSignificant))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_multistateqtl_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_multistateqtl_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_multistateqtl_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MULTISTATEQTL:", paste0("    multistateqtl: ", packageVersion("multistateQTL"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multistateqtl_results.csv
    touch ${prefix}_multistateqtl_output.rds
    echo "BIOC_MULTISTATEQTL:" > versions.yml
    echo "    multistateqtl: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MULTISTATEQTL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(ggplot_object) ]

    main:
    BIOC_MULTISTATEQTL(ch_input)

    emit:
    results  = BIOC_MULTISTATEQTL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MULTISTATEQTL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MULTISTATEQTL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MULTISTATEQTL.out.versions  // channel: path(versions.yml)
}
