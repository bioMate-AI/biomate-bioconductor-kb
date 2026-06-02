#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PLSDAbatch
// A novel framework to correct for batch effects prior to any downstream analysis in microbiome data b
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PLSDAbatch/inst/doc/brief_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("PLSDAbatch")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PLSDABATCH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-plsdabatch"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-plsdabatch:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-plsdabatch:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_plsdabatch_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_plsdabatch_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_plsdabatch_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Scatter_Density)
    library(jsonlite)

    # --- Plot hierarchical clustering heatmap [] ---
    # Key functions: pheatmap, ggplot, geom_boxplot, theme_bw, theme, geom_bar, alignment_score, geom_text
    ad.clr.s <- scale(ad.clr, center = TRUE, scale = TRUE)
    ad.clr.ss <- scale(t(ad.clr.s), center = TRUE, scale = TRUE)
    ad.anno_col <- data.frame(Batch = ad.batch, Treatment = ad.trt)
    # --- Scatter Density analysis [] ---
    # Key functions: Scatter_Density, box_plot, density_plot, partVar_plot
    ad.OTU.name <- selectVar(ad.pca.before, comp = 1)$name[1]
    ad.OTU_batch <- data.frame(value = ad.clr[,ad.OTU.name], batch = ad.batch)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_plsdabatch_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_plsdabatch_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_plsdabatch_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PLSDABATCH:", paste0("    plsdabatch: ", packageVersion("PLSDAbatch"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_plsdabatch_results.csv
    touch ${prefix}_plsdabatch_output.rds
    echo "BIOC_PLSDABATCH:" > versions.yml
    echo "    plsdabatch: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PLSDABATCH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PLSDABATCH(ch_input)

    emit:
    results  = BIOC_PLSDABATCH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PLSDABATCH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PLSDABATCH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PLSDABATCH.out.versions  // channel: path(versions.yml)
}
