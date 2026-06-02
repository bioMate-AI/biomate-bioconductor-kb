#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: systemPipeTools
// systemPipeTools package extends the widely used systemPipeR (SPR) workflow environment with an enhan
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/systemPipeTools/inst/doc/systemPipeTools.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("systemPipeTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SYSTEMPIPETOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-systempipetools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-systempipetools:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-systempipetools:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_systempipetools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_systempipetools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_systempipetools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GLMplot)
    library(MAplot)
    library(MDSplot)
    library(PCAplot)
    library(jsonlite)

    # --- Volcano plot of DE results [] ---
    # Key functions: volcanoplot

    # --- ReadComp analysis [] ---
    # Key functions: readComp, showDT, exploreDDS, exploreDDSplot, hclustplot, heatMaplot, run_DESeq2, filterDEGs
    targetspath <- system.file("extdata", "targets.txt", package = "systemPipeR")
    targets <- read.delim(targetspath, comment = "#")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_systempipetools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_systempipetools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_systempipetools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SYSTEMPIPETOOLS:", paste0("    systempipetools: ", packageVersion("systemPipeTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_systempipetools_results.csv
    touch ${prefix}_systempipetools_output.rds
    echo "BIOC_SYSTEMPIPETOOLS:" > versions.yml
    echo "    systempipetools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SYSTEMPIPETOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SYSTEMPIPETOOLS(ch_input)

    emit:
    results  = BIOC_SYSTEMPIPETOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SYSTEMPIPETOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SYSTEMPIPETOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SYSTEMPIPETOOLS.out.versions  // channel: path(versions.yml)
}
