#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: xcms
// Framework for processing and visualization of chromatographically separated and single-spectra mass 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/xcms/inst/doc/LC-MS-feature-grouping.R
// Upstream  : BiocStyle, MSnbase, MassSpecWavelet, MetaboCoreUtils, MsBackendMgf
// Downstream: CAMERA, flagme, IPO, LOBSTAHS, metaMS
//
// Install: BiocManager::install("xcms")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_XCMS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-xcms"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-xcms:4.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-xcms:4.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_xcms_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_xcms_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_xcms_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(xcms)
    library(jsonlite)

    # --- Plot hierarchical clustering heatmap [] ---
    # Key functions: pheatmap
    library(pheatmap)
    fvals <- log2(featureValues(xmse, filled = TRUE))
    cormat <- cor(t(fvals), use = "pairwise.complete.obs")
    # --- Markdown analysis [] ---
    # Key functions: markdown, register, loadXcmsData, featureDefinitions, grid, groupFeatures, plotFeatureGroups, ifelse
    xmse <- groupFeatures(xmse, SimilarRtimeParam(diffRt = 20))
    xmse <- groupFeatures(xmse, AbundanceSimilarityParam(threshold = 0.7))
    table(featureGroups(xmse))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_xcms_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_xcms_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_xcms_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_XCMS:", paste0("    xcms: ", packageVersion("xcms"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_xcms_results.csv
    touch ${prefix}_xcms_output.rds
    echo "BIOC_XCMS:" > versions.yml
    echo "    xcms: 0.0.0" >> versions.yml
    """
}


workflow BIOC_XCMS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_XCMS(ch_input)

    emit:
    results  = BIOC_XCMS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_XCMS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_XCMS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_XCMS.out.versions  // channel: path(versions.yml)
}
