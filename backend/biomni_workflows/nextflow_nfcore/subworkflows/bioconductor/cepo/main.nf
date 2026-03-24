#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Cepo
// Defining the identity of a cell is fundamental to understand the heterogeneity of cells to various e
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Cepo/inst/doc/cepo.R
// Upstream  : BiocParallel, DelayedArray, HDF5Array, SingleCellExperiment, UpSetR
// Downstream: none
//
// Install: BiocManager::install("Cepo")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CEPO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cepo"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cepo:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cepo:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cepo_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cepo_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cepo_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MulticoreParam)
    library(SnowParam)
    library(jsonlite)

    # --- visualize colData [] ---
    # Key functions: colData
    colData(cellbench)[1:5,]
    # --- upset [] ---
    # Key functions: upset
    library(UpSetR)
    res_name = topGenes(object = ds_res, n = 500)
    upset(fromList(res_name), nsets = 3)
    # --- plot Densities [] ---
    # Key functions: plotDensities
    plotDensities(x = cellbench,
    # --- wrap_plots [] ---
    # Key functions: wrap_plots
    cepo_genes = Cepo::topGenes(ds_res_batches$average, n = 3)
    markersPlot = lapply(cepo_genes, function(x) {
    pp = lapply(x, function(gene) {
    # --- Fast GSEA analysis [] ---
    # Key functions: getGeneSets, fgsea
    library(escape)
    library(fgsea)
    hallmarkList <- getGeneSets(species = "Homo sapiens",
    # --- Snow Param [] ---
    # Key functions: SnowParam, MulticoreParam, setAutoBPPARAM
    library(BiocParallel)
    BPPARAM = if (.Platform$OS.type == "windows") {
    BiocParallel::SnowParam(workers = 2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cepo_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cepo_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cepo_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CEPO:", paste0("    cepo: ", packageVersion("Cepo"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cepo_results.csv
    touch ${prefix}_cepo_output.rds
    echo "BIOC_CEPO:" > versions.yml
    echo "    cepo: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CEPO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CEPO(ch_input)

    emit:
    results  = BIOC_CEPO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CEPO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CEPO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CEPO.out.versions  // channel: path(versions.yml)
}
