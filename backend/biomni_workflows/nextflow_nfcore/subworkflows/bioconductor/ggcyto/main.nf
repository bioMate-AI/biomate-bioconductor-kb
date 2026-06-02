#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ggcyto
// With the dedicated fortify method implemented for flowSet, ncdfFlowSet and GatingSet classes, both r
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ggcyto/inst/doc/Top_features_of_ggcyto.R
// Upstream  : knitr
// Downstream: flowGate
//
// Install: BiocManager::install("ggcyto")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GGCYTO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ggcyto"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ggcyto:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ggcyto:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ggcyto_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ggcyto_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ggcyto_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ggcyto)
    library(jsonlite)

    # --- Automated Flow Cytometry Plotting [Visualization] ---
    # Key functions: autoplot
    p_1d <- autoplot(fs, "CD4")
    p_2d <- autoplot(fs, "CD4", "CD8", bins = 64)
    p_gs <- autoplot(gs, c("CD4", "CD8"), bins = 64)

    # --- Custom Gating and Statistics Visualization [Visualization] ---
    # Key functions: ggcyto, geom_gate, geom_stats
    p <- ggcyto(gs, aes(x = "CD4", y = "CD8"), subset = "CD3+") +
        geom_hex(bins = 128)
    p_gate <- p + geom_gate("CD4") + geom_stats(type = "count")
    p_gate_percent <- p + geom_gate("CD4") + geom_stats()

    # --- Scale and Axis Transformations [Visualization] ---
    # Key functions: scale_x_logicle, scale_x_flowJo_fasinh, scale_x_flowJo_biexp, axis_x_inverse_trans
    p_raw <- autoplot(fr, "FL1-H")
    p_logicle <- p_raw + scale_x_logicle()
    p_fasinh <- p_raw + scale_x_flowJo_fasinh()
    p_biexp <- p_raw + scale_x_flowJo_biexp()
    p_inv <- p_logicle + axis_x_inverse_trans()

    # --- Plot Customization and Theme Settings [Visualization] ---
    # Key functions: ggcyto_par_set, labs_cyto
    mySettings <- ggcyto_par_set(
        limits = "instrument",
        facet = facet_wrap("name"),
        lab = labs_cyto("marker")
    )
    p_custom <- ggcyto(gs, aes(x = CD4, y = CD8)) +
        geom_hex(bins = 128) +
        mySettings

    # --- Layout Arrangement and Conversion [Visualization] ---
    # Key functions: as.ggplot, ggcyto_arrange
    p_gg <- as.ggplot(p_custom)
    p_multi <- autoplot(gh, nodes, bins = 64)
    gt <- ggcyto_arrange(p_multi, nrow = 1)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ggcyto_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ggcyto_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ggcyto_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GGCYTO:", paste0("    ggcyto: ", packageVersion("ggcyto"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ggcyto_results.csv
    touch ${prefix}_ggcyto_output.rds
    echo "BIOC_GGCYTO:" > versions.yml
    echo "    ggcyto: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GGCYTO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GGCYTO(ch_input)

    emit:
    results  = BIOC_GGCYTO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GGCYTO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GGCYTO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GGCYTO.out.versions  // channel: path(versions.yml)
}
