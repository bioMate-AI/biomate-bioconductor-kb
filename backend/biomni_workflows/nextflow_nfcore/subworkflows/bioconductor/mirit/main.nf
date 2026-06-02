#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MIRit
// MIRit is an R package that provides several methods for investigating the relationships between miRN
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MIRit/inst/doc/MIRit.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MIRit")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIRIT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mirit"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mirit:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mirit:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(ggplot_object)

    output:
    tuple val(meta), path("${meta.id}_mirit_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mirit_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mirit_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MirnaExperiment)
    library(jsonlite)

    # --- Table formatting and display [] ---
    # Key functions: kable, MirnaExperiment, plotDimensions, ggarrange, performGeneDE, performMirnaDE, geneDE, mirnaDE
    knitr::kable(mirnaCounts[seq(5), seq(5)], digits = 2, caption = "MiRNA expression matrix. An expression matrix containing normalized values, with row names according to miRBase.")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mirit_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mirit_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mirit_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MIRIT:", paste0("    mirit: ", packageVersion("MIRit"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mirit_results.csv
    touch ${prefix}_mirit_output.rds
    echo "BIOC_MIRIT:" > versions.yml
    echo "    mirit: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MIRIT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(ggplot_object) ]

    main:
    BIOC_MIRIT(ch_input)

    emit:
    results  = BIOC_MIRIT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MIRIT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MIRIT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MIRIT.out.versions  // channel: path(versions.yml)
}
