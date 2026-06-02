#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: clusterExperiment
// Provides functionality for running and comparing many different clusterings of single-cell sequencin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/clusterExperiment/inst/doc/clusterExperimentTutorial.R
// Upstream  : igraph, phylobase, scran
// Downstream: netSmooth
//
// Install: BiocManager::install("clusterExperiment")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLUSTEREXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-clusterexperiment"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-clusterexperiment:2.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-clusterexperiment:2.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_clusterexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_clusterexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_clusterexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(clusterExperiment)
    library(RSEC)
    library(jsonlite)

    # --- Consensus Clustering [] ---
    # Key functions: makeConsensus, clusterMatrix
    ceConsensus <- makeConsensus(ce, proportion=0.7,
                                 clusterLabel="makeConsensus,0.7")
    cMat <- clusterMatrix(ceConsensus)


    # --- Robust Clustering Pipeline [] ---
    # Key functions: RSEC, primaryCluster, tableClusters
    rsecFluidigm <- RSEC(se, isCount=TRUE, consensusProportion=0.6,
                         mergeMethod="JC", mergeCutoff=0.05,
                         stopOnErrors=TRUE)
    primClus <- primaryCluster(rsecFluidigm)
    tabClus <- tableClusters(rsecFluidigm)


    # --- Feature Selection and Differential Expression [] ---
    # Key functions: getBestFeatures
    pairsAllRSEC <- getBestFeatures(rsecFluidigm, contrastType="Pairs",
                                    p.value=0.05, DEMethod="edgeR",
                                    number=nrow(rsecFluidigm))


    # --- Cluster Visualization [] ---
    # Key functions: plotClusters, plotCoClustering, plotReducedDims
    plotClusters(rsecFluidigm, whichClusters="workflow",
                 colData=c("Biological_Condition", "Published2"))
    plotCoClustering(rsecFluidigm,
                     whichClusters=c("mergeClusters", "makeConsensus"))
    plotReducedDims(rsecFluidigm, whichDims=1:4)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_clusterexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_clusterexperiment_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_clusterexperiment_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLUSTEREXPERIMENT:", paste0("    clusterexperiment: ", packageVersion("clusterExperiment"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clusterexperiment_results.csv
    touch ${prefix}_clusterexperiment_output.rds
    echo "BIOC_CLUSTEREXPERIMENT:" > versions.yml
    echo "    clusterexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLUSTEREXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLUSTEREXPERIMENT(ch_input)

    emit:
    results  = BIOC_CLUSTEREXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLUSTEREXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLUSTEREXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLUSTEREXPERIMENT.out.versions  // channel: path(versions.yml)
}
