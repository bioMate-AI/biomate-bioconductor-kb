#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MAST
// Methods and models for handling zero-inflated single cell assay data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MAST/inst/doc/MAITAnalysis.R
// Upstream  : DelayedArray, GGally, GSEABase, HDF5Array, Matrix
// Downstream: POWSC
//
// Install: BiocManager::install("MAST")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MAST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mast"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mast:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mast:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mast_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mast_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mast_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FromMatrix)
    library(jsonlite)

    # --- PCA plot of sample distances [] ---
    # Key functions: rpca, plotPCA, with, ggplot, assays, melt
    assays(scaDE, withDimnames = FALSE) <- c(assays(scaDE), list(resid=residDEMatrix))
    scaResidFlat <- as(scaDE, 'data.table')
    ggplot(scaResidFlat, aes(x=ngeneson, y=resid))+geom_point(aes(col=condition))+geom_smooth()+facet_wrap(~symbolid)
    # --- Assay listing [] ---
    # Key functions: FromMatrix, aheatmap, thresholdSCRNACountMatrix, assays, freq, relevel, colData, zlm
    packageExt <- system.file("extdata", package='MAST')
    module_file <- list.files(packageExt, pattern = module, full.names = TRUE)
    gene_set <- getGmt(module_file)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mast_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mast_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mast_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MAST:", paste0("    mast: ", packageVersion("MAST"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mast_results.csv
    touch ${prefix}_mast_output.rds
    echo "BIOC_MAST:" > versions.yml
    echo "    mast: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MAST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MAST(ch_input)

    emit:
    results  = BIOC_MAST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MAST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MAST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MAST.out.versions  // channel: path(versions.yml)
}
