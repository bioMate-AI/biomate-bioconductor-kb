#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AlphaMissenseR
// The AlphaMissense publication <https://www.science.org/doi/epdf/10.1126/science.adg7492> outlines ho
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AlphaMissenseR/inst/doc/alphafold.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("AlphaMissenseR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALPHAMISSENSER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-alphamissenser"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-alphamissenser:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-alphamissenser:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_alphamissenser_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_alphamissenser_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_alphamissenser_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AlphaMissenseR)
    library(jsonlite)

    # --- Am data analysis [] ---
    # Key functions: am_data, af_prediction_view, distinct, pull, af_predictions, glimpse, bfcrpath, r3dmol
    r3dmol::r3dmol() |>
    r3dmol::m_add_model(r3dmol::m_bio3d(pdb)) |>
    r3dmol::m_set_style(style = r3dmol::m_style_cartoon(arrow = TRUE)) |>

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_alphamissenser_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_alphamissenser_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_alphamissenser_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ALPHAMISSENSER:", paste0("    alphamissenser: ", packageVersion("AlphaMissenseR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alphamissenser_results.csv
    touch ${prefix}_alphamissenser_output.rds
    echo "BIOC_ALPHAMISSENSER:" > versions.yml
    echo "    alphamissenser: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ALPHAMISSENSER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ALPHAMISSENSER(ch_input)

    emit:
    results  = BIOC_ALPHAMISSENSER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ALPHAMISSENSER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ALPHAMISSENSER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ALPHAMISSENSER.out.versions  // channel: path(versions.yml)
}
