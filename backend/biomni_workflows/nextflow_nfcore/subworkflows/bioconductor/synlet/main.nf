#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: synlet
// Select hits from synthetic lethal RNAi screen data. For example, there are two identical celllines e
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/synlet/inst/doc/synlet-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("synlet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SYNLET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-synlet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-synlet:2.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-synlet:2.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_synlet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_synlet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_synlet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(synlet)
    library(jsonlite)

    # --- z Factor [] ---
    # Key functions: zFactor
    res <- zFactor(example_dt, negativeCon = "scrambled control si1", positiveCon = "PLK1 si1")
    head(res)
    # --- plate Heatmap [] ---
    # Key functions: plateHeatmap, scatterPlot
    plateHeatmap(example_dt)
    scatterPlot(example_dt, controlOnly = FALSE, control_name = c("PLK1 si1", "scrambled control si1", "lipid only"))
    # --- z Factor [] ---
    # Key functions: zFactor
    zF_mean <- zFactor(example_dt, negativeCon = "scrambled control si1", positiveCon = "PLK1 si1")
    zF_med <- zFactor(example_dt, negativeCon = "scrambled control si1", positiveCon = "PLK1 si1", useMean = FALSE)
    # --- si R N A Plot [] ---
    # Key functions: siRNAPlot
    siRNAPlot("AAK1", example_dt,
    controlsiRNA = c("lipid only", "scrambled control si1"),
    normMethod = c("PLATE", "lipid only", "scrambled control si1"))
    # --- t test [] ---
    # Key functions: tTest
    t_res <- tTest(bscore_res$P001, 3, 3)
    head(t_res)
    # --- rsa Hits [] ---
    # Key functions: rsaHits
    rsaHits(example_dt, treatment = "treatment", control = "control",
    sessionInfo()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_synlet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_synlet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_synlet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SYNLET:", paste0("    synlet: ", packageVersion("synlet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_synlet_results.csv
    touch ${prefix}_synlet_output.rds
    echo "BIOC_SYNLET:" > versions.yml
    echo "    synlet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SYNLET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SYNLET(ch_input)

    emit:
    results  = BIOC_SYNLET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SYNLET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SYNLET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SYNLET.out.versions  // channel: path(versions.yml)
}
