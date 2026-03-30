#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: switchde
// Inference and detection of switch-like differential expression across single-cell RNA-seq trajectori
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/switchde/inst/doc/switchde_vignette.R
// Upstream  : SingleCellExperiment, dplyr, ggplot2, tidyr
// Downstream: none
//
// Install: BiocManager::install("switchde")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SWITCHDE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-switchde"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-switchde:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-switchde:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(singlecellexperiment)

    output:
    tuple val(meta), path("${meta.id}_switchde_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_switchde_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_switchde_plots.pdf"),    emit: plots, optional: true
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

    # --- Create SingleCellExperiment object [] ---
    # Key functions: SingleCellExperiment, switchde
    sce <- SingleCellExperiment(assays = list(exprs = synth_gex))
    sde <- switchde(sce, ex_pseudotime)
    # --- Custom ggplot2 visualization [] ---
    # Key functions: as_data_frame, gather, ggplot, facet_wrap, theme_bw
    data(synth_gex)
    data(ex_pseudotime)
    gex_cleaned <- as_data_frame(t(synth_gex)) %>%
    # --- Switchde analysis [] ---
    # Key functions: install_github, switchde, arrange, extract_pars, switchplot
    gene <- zde$gene[which.min(zde$lambda)]
    pars <- extract_pars(sde, gene)
    zpars <- extract_pars(zde, gene)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_switchde_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_switchde_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_switchde_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SWITCHDE:", paste0("    switchde: ", packageVersion("switchde"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_switchde_results.csv
    touch ${prefix}_switchde_output.rds
    echo "BIOC_SWITCHDE:" > versions.yml
    echo "    switchde: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SWITCHDE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(singlecellexperiment) ]

    main:
    BIOC_SWITCHDE(ch_input)

    emit:
    results  = BIOC_SWITCHDE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SWITCHDE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SWITCHDE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SWITCHDE.out.versions  // channel: path(versions.yml)
}
