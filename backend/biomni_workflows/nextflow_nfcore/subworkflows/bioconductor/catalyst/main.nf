#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CATALYST
// CATALYST provides tools for preprocessing of and differential discovery in cytometry data such as FA
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CATALYST/inst/doc/differential.R
// Upstream  : SingleCellExperiment, cowplot, diffcyt, flowCore, flowWorkspace
// Downstream: spillR, cytofWorkflow
//
// Install: BiocManager::install("CATALYST")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CATALYST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-catalyst"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-catalyst:1.30.2--r44_0' :
        'quay.io/biocontainers/bioconductor-catalyst:1.30.2--r44_0'}"

    input:
    tuple val(meta), path(singlecellexperiment)

    output:
    tuple val(meta), path("${meta.id}_catalyst_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_catalyst_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_catalyst_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CATALYST)
    library(jsonlite)

    # --- Run UMAP embedding [] ---
    # Key functions: runUMAP, reducedDimNames
    sce <- runUMAP(sce, exprs_values = "exprs")
    reducedDimNames(sce)
    head(reducedDim(sce, "UMAP"))
    # --- Cluster analysis [] ---
    # Key functions: cluster, mergeClusters, delta_area, pbMDS, clrDR, plotExprHeatmap, raw, plotPbExprs
    p <- plotPbExprs(sce, k = "meta4", facet_by = "cluster_id")
    p <- p + scale_color_manual(values = c("royalblue", "orange"))
    (p + labs(x = NULL) + theme(axis.text.x = element_text(angle = 90, size = 8, vjust = 0.5)))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_catalyst_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_catalyst_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_catalyst_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CATALYST:", paste0("    catalyst: ", packageVersion("CATALYST"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_catalyst_results.csv
    touch ${prefix}_catalyst_output.rds
    echo "BIOC_CATALYST:" > versions.yml
    echo "    catalyst: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CATALYST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(singlecellexperiment) ]

    main:
    BIOC_CATALYST(ch_input)

    emit:
    results  = BIOC_CATALYST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CATALYST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CATALYST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CATALYST.out.versions  // channel: path(versions.yml)
}
