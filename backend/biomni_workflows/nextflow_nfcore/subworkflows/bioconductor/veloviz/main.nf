#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: veloviz
// VeloViz uses each cell’s current observed and predicted future transcriptional states inferred from 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/veloviz/inst/doc/vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("veloviz")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VELOVIZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-veloviz"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-veloviz:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-veloviz:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_veloviz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_veloviz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_veloviz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(veloviz)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(vel)
    curr <- vel$current #observed current transcriptional state
    proj <- vel$projected #predicted future transcriptional state
    # --- Buildveloviz [] ---
    # Key functions: buildVeloviz
    ---------------------------------------------------------------------
    veloviz <-  veloviz::buildVeloviz(curr = curr, proj = proj,
                             normalize.depth = TRUE,
                             use.ods.genes = FALSE,
                             pca = TRUE, nPCs = 3,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_veloviz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_veloviz_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_veloviz_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VELOVIZ:", paste0("    veloviz: ", packageVersion("veloviz"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_veloviz_results.csv
    touch ${prefix}_veloviz_output.rds
    echo "BIOC_VELOVIZ:" > versions.yml
    echo "    veloviz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VELOVIZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VELOVIZ(ch_input)

    emit:
    results  = BIOC_VELOVIZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VELOVIZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VELOVIZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VELOVIZ.out.versions  // channel: path(versions.yml)
}
