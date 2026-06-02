#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scMerge
// Like all gene expression data, single-cell data suffers from batch effects and other unwanted variat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scMerge/inst/doc/scMerge.R
// Upstream  : BiocSingular, SingleCellExperiment, scater
// Downstream: none
//
// Install: BiocManager::install("scMerge")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCMERGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scmerge"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scmerge:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scmerge:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scmerge_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scmerge_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scmerge_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scMerge)
    library(IrlbaParam)
    library(jsonlite)

    # --- Unsupervised Batch Correction [scMerge] ---
    # Key functions: scMerge
    data("example_sce", package = "scMerge")
    data("segList_ensemblGeneID", package = "scMerge")
    scMerge_unsupervised <- scMerge(
        sce_combine = example_sce,
        ctl = segList_ensemblGeneID$mouse$mouse_scSEG,
        kmeansK = c(3, 3),
        assay_name = "scMerge_unsupervised"
    )

    # --- Supervised Batch Correction [scMerge] ---
    # Key functions: scMerge
    data("example_sce", package = "scMerge")
    data("segList_ensemblGeneID", package = "scMerge")
    scMerge_supervised <- scMerge(
        sce_combine = example_sce,
        ctl = segList_ensemblGeneID$mouse$mouse_scSEG,
        kmeansK = c(3, 3),
        assay_name = "scMerge_supervised",
        cell_type = example_sce$cellTypes
    )

    # --- Semi-Supervised Batch Correction [scMerge] ---
    # Key functions: scMerge
    data("example_sce", package = "scMerge")
    data("segList_ensemblGeneID", package = "scMerge")
    scMerge_semisupervised <- scMerge(
        sce_combine = example_sce,
        ctl = segList_ensemblGeneID$mouse$mouse_scSEG,
        kmeansK = c(3, 3),
        assay_name = "scMerge_semisupervised",
        cell_type = example_sce$cellTypes,
        cell_type_inc = which(example_sce$cellTypes == "2i"),
        cell_type_match = FALSE
    )

    # --- Fast Batch Correction [scMerge] ---
    # Key functions: scMerge
    data("example_sce", package = "scMerge")
    data("segList_ensemblGeneID", package = "scMerge")
    scMerge_fast <- scMerge(
        sce_combine = example_sce,
        ctl = segList_ensemblGeneID$mouse$mouse_scSEG,
        kmeansK = c(3, 3),
        assay_name = "scMerge_fast",
        BSPARAM = BiocSingular::IrlbaParam(),
        svd_k = 20
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scmerge_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scmerge_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scmerge_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCMERGE:", paste0("    scmerge: ", packageVersion("scMerge"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scmerge_results.csv
    touch ${prefix}_scmerge_output.rds
    echo "BIOC_SCMERGE:" > versions.yml
    echo "    scmerge: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCMERGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCMERGE(ch_input)

    emit:
    results  = BIOC_SCMERGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCMERGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCMERGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCMERGE.out.versions  // channel: path(versions.yml)
}
