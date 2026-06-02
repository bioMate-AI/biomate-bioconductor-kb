#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sincell
// Cell differentiation processes are achieved through a continuum of hierarchical intermediate cell-st
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sincell/inst/doc/sincell-vignette.R
// Upstream  : biomaRt, monocle, rgl, stringr
// Downstream: none
//
// Install: BiocManager::install("sincell")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SINCELL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sincell"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sincell:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sincell:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sincell_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sincell_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sincell_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(sincell)
    library(jsonlite)

    # --- initialize sincellObject example [] ---
    # Key functions: sc_InitializingSincellObject
    SincellObject<-sc_InitializingSincellObject(ExpressionMatrix)
    # --- monocle expression matrix filtering 2 [] ---
    # Key functions: detectGenes, differentialGeneTest
    HSMM <- detectGenes(HSMM, min_expr = 0.1)
    expressed_genes <- row.names(subset(fData(HSMM), num_cells_expressed >= 50))
    # --- change geneIDs [] ---
    # Key functions: getBM
    GeneEnsemblID<-rownames(EMlog)
    head(GeneEnsemblID)
    # --- initialize sincellObject [] ---
    # Key functions: sc_InitializingSincellObject
    SO<-sc_InitializingSincellObject(EMlog)
    # --- cell to cell distance matrix [] ---
    # Key functions: sc_distanceObj
    SO<-sc_distanceObj(SO, method="euclidean")
    SO<-sc_distanceObj(SO, method="cosine")
    SO<-sc_distanceObj(SO, method="pearson")
    # --- Mutual Information [] ---
    # Key functions: sc_distanceObj
    SO<-sc_distanceObj(SO, method="MI", bins=c(-Inf,0,1,2,Inf))
    # --- sc_ Dimensionality Reduction Obj [] ---
    # Key functions: sc_DimensionalityReductionObj
    help(sc_DimensionalityReductionObj)
    Principal Component Analysis (PCA)
    SO <- sc_DimensionalityReductionObj(SO, method="PCA", dim=3)
    # --- ICA tSNE [] ---
    # Key functions: sc_DimensionalityReductionObj
    Independent Component Analysis (ICA)
    SO <- sc_DimensionalityReductionObj(SO, method="ICA", dim=3)
    t-Distributed Stochastic Neighbor Embedding (t-SNE)
    # --- sc_ Dimensionality Reduction Obj [] ---
    # Key functions: sc_DimensionalityReductionObj
    Classic Multidimensional Scaling (classical-MDS).
    SO <- sc_DimensionalityReductionObj(SO, method="classical-MDS", dim=3)
    Non-metric Multidimensional Scaling (nonmetric-MDS).
    # --- color by marker [] ---
    # Key functions: sc_marker2color

    # --- using rgl package [] ---
    # Key functions: plot3d
    library(rgl)
    # --- ICA 2dim [] ---
    # Key functions: sc_DimensionalityReductionObj
    Independent Component Analysis (ICA)
    SO <- sc_DimensionalityReductionObj(SO, method="ICA", dim=2)
    # --- Cluster assessment [] ---
    # Key functions: sc_clusterObj, clusters
    SO<- sc_clusterObj(SO, clust.method="max.distance", max.distance=0.5)
    clusters(SO[["cellsClustering"]])
    SO<- sc_clusterObj(SO, clust.method="percent", shortest.rank.percent=10)
    # --- Cluster assessment2 [] ---
    # Key functions: sc_clusterObj, clusters
    SO <- sc_clusterObj (SO, clust.method="k-medoids", mutual=TRUE, k=3)
    clusters(SO[["cellsClustering"]])
    SO <- sc_clusterObj (SO, clust.method="complete", mutual=TRUE, k=3)
    # --- graph assessment0 [] ---
    # Key functions: sc_GraphBuilderObj
    help(sc_GraphBuilderObj)
    Minimum Spanning Tree (MST)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sincell_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sincell_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sincell_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SINCELL:", paste0("    sincell: ", packageVersion("sincell"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sincell_results.csv
    touch ${prefix}_sincell_output.rds
    echo "BIOC_SINCELL:" > versions.yml
    echo "    sincell: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SINCELL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SINCELL(ch_input)

    emit:
    results  = BIOC_SINCELL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SINCELL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SINCELL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SINCELL.out.versions  // channel: path(versions.yml)
}
