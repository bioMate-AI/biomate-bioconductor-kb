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
    library(IrlbaParam)
    library(jsonlite)

    # --- Loading Data [] ---
    # Key functions: data
    ## Subsetted mouse ESC data
    data("example_sce", package = "scMerge")
    # --- Checking Raw Data [] ---
    # Key functions: runPCA, plotPCA
    example_sce = runPCA(example_sce, exprs_values = "logcounts")
    scater::plotPCA(
      example_sce,
      colour_by = "cellTypes",
      shape_by = "batch")
    # --- Load Seg [] ---
    # Key functions: data
    ## single-cell stably expressed gene list
    data("segList_ensemblGeneID", package = "scMerge")
    head(segList_ensemblGeneID$mouse$mouse_scSEG)
    # --- Unsupervised Default [] ---
    # Key functions: scMerge
    scMerge_unsupervised <- scMerge(
      sce_combine = example_sce,
      ctl = segList_ensemblGeneID$mouse$mouse_scSEG,
      kmeansK = c(3, 3),
      assay_name = "scMerge_unsupervised")
    # --- Unsupervised Default Plotting [] ---
    # Key functions: runPCA, plotPCA
    scMerge_unsupervised = runPCA(scMerge_unsupervised, exprs_values = "scMerge_unsupervised")
    scater::plotPCA(
      scMerge_unsupervised,
      colour_by = "cellTypes",
      shape_by = "batch")
    # --- Unsupervised Prop1 [] ---
    # Key functions: scMerge

    # --- Unsupervised Prop1 Plotting [] ---
    # Key functions: runPCA, plotPCA
    scMerge_unsupervised_all = runPCA(scMerge_unsupervised_all,
                                      exprs_values = "scMerge_unsupervised_all")
    # --- Supervised [] ---
    # Key functions: scMerge

    # --- Supervised Plotting [] ---
    # Key functions: runPCA, plotPCA
    scMerge_supervised = runPCA(scMerge_supervised,
                                exprs_values = "scMerge_supervised")
    # --- Semi Supervised1 [] ---
    # Key functions: scMerge

    # --- Semi Supervised1 Plotting [] ---
    # Key functions: runPCA, plotPCA
    scMerge_semisupervised1 = runPCA(scMerge_semisupervised1,
                                     exprs_values = "scMerge_semisupervised1")
    # --- Semi Supervised2 [] ---
    # Key functions: scMerge

    # --- Semi Supervised2 Plotting [] ---
    # Key functions: runPCA, plotPCA
    scMerge_semisupervised2 = runPCA(scMerge_semisupervised2,
                                     exprs_values = "scMerge_semisupervised2")
    # --- Segindex2 [] ---
    # Key functions: data
    ## SEG list in ensemblGene ID
    data("segList_ensemblGeneID", package = "scMerge")
    ## SEG list in official gene symbols
    data("segList", package = "scMerge")
    ## SEG list for human scRNA-Seq data
    # --- Computation Fast [] ---
    # Key functions: scMerge, IrlbaParam
    library(BiocSingular)

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
