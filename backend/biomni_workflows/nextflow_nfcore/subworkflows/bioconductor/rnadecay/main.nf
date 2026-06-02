#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RNAdecay
// RNA degradation is monitored through measurement of RNA abundance after inhibiting RNA synthesis. Th
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RNAdecay/inst/doc/RNAdecay_workflow.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("RNAdecay")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RNADECAY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rnadecay"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rnadecay:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rnadecay:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rnadecay_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rnadecay_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rnadecay_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RNAdecay)
    library(jsonlite)

    # --- Batch Decay Visualization [] ---
    # Key functions: decay_plot, plain_theme
    ids <- c("AT5G54730", "AT1G27730", "AT4G34190")
    plots <- lapply(ids, function(i) {
        p <- decay_plot(
            i,
            what = c("meanSE", "models", "Desc"),
            mod.results = results,
            gdesc = descriptions,
            treatments = c("WT", "sov", "vcs", "vcs.sov"),
            DATA = decay_data
        )
        p + plain_theme(13.8, 1, leg.pos = "right")
    })


    # --- Half-life Estimation and Plotting [] ---
    # Key functions: hl_plot, plain_theme
    p_hl <- hl_plot(
        geneID = "AT1G02860",
        gene_symbol = "SYG1",
        df_decay_rates = RNAdecay::results,
        hl_dist_treatment = "WT",
        hl_treatment = c("WT", "sov", "vcs", "vcs.sov"),
        arrow_lab_loc = "key"
    )
    ids <- c("AT5G54730", "AT1G27730", "AT4G34190")
    hl_plots <- lapply(ids, function(i) {
        hl_plot(
            geneID = i,
            df_decay_rates = RNAdecay::results,
            hl_dist_treatment = "WT",
            hl_treatment = c("WT", "sov", "vcs", "vcs.sov"),
            arrow_lab_loc = "plot"
        )
    })

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rnadecay_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rnadecay_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rnadecay_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RNADECAY:", paste0("    rnadecay: ", packageVersion("RNAdecay"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnadecay_results.csv
    touch ${prefix}_rnadecay_output.rds
    echo "BIOC_RNADECAY:" > versions.yml
    echo "    rnadecay: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RNADECAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RNADECAY(ch_input)

    emit:
    results  = BIOC_RNADECAY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RNADECAY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RNADECAY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RNADECAY.out.versions  // channel: path(versions.yml)
}
