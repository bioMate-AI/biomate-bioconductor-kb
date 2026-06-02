#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: celda
// Celda is a suite of Bayesian hierarchical models for clustering single-cell RNA-sequencing (scRNA-se
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/celda/inst/doc/celda.R
// Upstream  : Seurat, SingleCellExperiment, TENxPBMCData, scater, singleCellTK
// Downstream: none
//
// Install: BiocManager::install("celda")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CELDA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-celda"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-celda:1.22.1--r44_0' :
        'quay.io/biocontainers/bioconductor-celda:1.22.1--r44_0'}"

    input:
    tuple val(meta), path(singlecellexperiment)

    output:
    tuple val(meta), path("${meta.id}_celda_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_celda_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_celda_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(celda)
    library(jsonlite)


    # --- Simulate [] ---
    # Key functions: simulateCells, celda_CG, counts, colData
    simsce <- simulateCells("celda_CG",
        S = 5, K = 5, L = 10, G = 200, CRange = c(30, 50))
    library(SingleCellExperiment)
    dim(counts(simsce))
    table(colData(simsce)$celda_cell_cluster)
    table(colData(simsce)$celda_sample_label)

    # --- Module Numbers [] ---
    # Key functions: rowData, selectFeatures, celda_CG
    table(rowData(simsce)$celda_feature_module)
    simsce <- selectFeatures(simsce)
    sce <- celda_CG(x = simsce, K = 5, L = 10, verbose = FALSE, nchains = 1)

    # --- Accuracy [] ---
    # Key functions: celdaClusters, celdaModules, celdaUmap, plotDimReduceCluster, plotDimReduceModule, plotDimReduceFeature, celda_UMAP, Gene_1
    table(celdaClusters(sce), celdaClusters(simsce))
    table(celdaModules(sce), celdaModules(simsce))
    sce <- celdaUmap(sce)
    plotDimReduceCluster(x = sce, reducedDimName = "celda_UMAP")

    plotDimReduceModule(x = sce, reducedDimName = "celda_UMAP", rescale = TRUE)

    plotDimReduceFeature(x = sce, reducedDimName = "celda_UMAP",
        normalize = TRUE, features = "Gene_1")

    # --- Celda Heatmap [] ---
    # Key functions: celdaHeatmap, celdaProbabilityMap, moduleHeatmap
    plot(celdaHeatmap(sce = sce, nfeatures = 10))
    celdaProbabilityMap(sce)
    moduleHeatmap(sce, featureModule = c(1,2), topCells = 100)

    # --- Module Split Rpc [] ---
    # Key functions: plotRPC, subsetCeldaList, recursiveSplitCell, celdaModules, plotGridSearchPerplexity
    plotRPC(moduleSplit)
    moduleSplitSelect <- subsetCeldaList(moduleSplit, params = list(L = 10))

    cellSplit <- recursiveSplitCell(moduleSplitSelect,
        initialK = 3,
        maxK = 12,
        yInit = celdaModules(moduleSplitSelect))
    plotGridSearchPerplexity(cellSplit)
    plotRPC(cellSplit)

    # --- Subset Celda [] ---
    # Key functions: subsetCeldaList, celdaGridSearch, celda_CG, plotGridSearchPerplexity
    sce <- subsetCeldaList(cellSplit, params = list(K = 5, L = 10))
    cgs <- celdaGridSearch(simsce,
        paramsTest = list(K = seq(4, 6), L = seq(9, 11)),
        cores = 1,
        model = "celda_CG",
        nchains = 2,
        maxIter = 100,
        verbose = FALSE,
        bestOnly = TRUE)
    plotGridSearchPerplexity(cgs)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_celda_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_celda_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_celda_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CELDA:", paste0("    celda: ", packageVersion("celda"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_celda_results.csv
    touch ${prefix}_celda_output.rds
    echo "BIOC_CELDA:" > versions.yml
    echo "    celda: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CELDA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(singlecellexperiment) ]

    main:
    BIOC_CELDA(ch_input)

    emit:
    results  = BIOC_CELDA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CELDA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CELDA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CELDA.out.versions  // channel: path(versions.yml)
}
