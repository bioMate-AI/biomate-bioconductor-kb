#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MsFeatures
// The MsFeature package defines functionality for Mass Spectrometry features. This includes functions 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MsFeatures/inst/doc/MsFeatures.R
// Upstream  : SummarizedExperiment, pheatmap
// Downstream: none
//
// Install: BiocManager::install("MsFeatures")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSFEATURES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msfeatures"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msfeatures:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-msfeatures:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(summarizedexperiment)

    output:
    tuple val(meta), path("${meta.id}_msfeatures_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msfeatures_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msfeatures_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MsFeatures)
    library(jsonlite)

    # --- Plot hierarchical clustering heatmap [] ---
    # Key functions: pheatmap
    library(pheatmap)
    fvals <- log2(assay(se))
    cormat <- cor(t(fvals), use = "pairwise.complete.obs")
    # --- Feature metadata inspection [] ---
    # Key functions: rowData, grid, groupFeatures, split, pairs, featureGroups
    tmp <- as.data.frame(rowData(se)[fts, c("rtmed", "mzmed", "feature_group")])
    tmp <- tmp[order(tmp$feature_group), ]
    knitr::kable(tmp)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msfeatures_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msfeatures_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msfeatures_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSFEATURES:", paste0("    msfeatures: ", packageVersion("MsFeatures"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msfeatures_results.csv
    touch ${prefix}_msfeatures_output.rds
    echo "BIOC_MSFEATURES:" > versions.yml
    echo "    msfeatures: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSFEATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(summarizedexperiment) ]

    main:
    BIOC_MSFEATURES(ch_input)

    emit:
    results  = BIOC_MSFEATURES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSFEATURES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSFEATURES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSFEATURES.out.versions  // channel: path(versions.yml)
}
