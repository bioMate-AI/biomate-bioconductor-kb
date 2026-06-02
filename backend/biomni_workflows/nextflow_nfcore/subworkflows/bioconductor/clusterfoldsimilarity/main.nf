#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ClusterFoldSimilarity
// This package calculates a similarity coefficient using the fold changes of shared features (e.g. gen
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ClusterFoldSimilarity/inst/doc/ClusterFoldSimilarity.R
// Upstream  : Seurat, dplyr, scRNAseq
// Downstream: none
//
// Install: BiocManager::install("ClusterFoldSimilarity")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLUSTERFOLDSIMILARITY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-clusterfoldsimilarity"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-clusterfoldsimilarity:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-clusterfoldsimilarity:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_clusterfoldsimilarity_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_clusterfoldsimilarity_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_clusterfoldsimilarity_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ClusterFoldSimilarity)
    library(jsonlite)


    # --- Construct [] ---
    # Key functions: MuraroPancreasData, colData, make.names, unlist, function, CreateSeuratObject, counts
    library(Seurat)
    library(scRNAseq)
    library(dplyr)
    # Human pancreatic single cell data 1
    pancreasMuraro <- scRNAseq::MuraroPancreasData(ensembl=FALSE)
    pancreasMuraro <- pancreasMuraro[,rownames(colData(pancreasMuraro)[!is.na(colData(pancreasMuraro)$label),])]
    colData(pancreasMuraro)$cell.type <- colData(pancreasMuraro)$label
    rownames(pancreasMuraro) <- make.names(unlist(lapply(strsplit(rownames(pancreasMuraro), split="__"), function(x)x[[1]])), unique = TRUE)
    singlecell1Seurat <- CreateSeuratObject(counts=counts(pancreasMuraro), meta.data=as.data.frame(colData(pancreasMuraro)))

    # --- Results='hide' [] ---
    # Key functions: function, NormalizeData, FindVariableFeatures, ScaleData, VariableFeatures, RunPCA, FindNeighbors, FindClusters
    # Create a list with the unprocessed single-cell datasets
    singlecellObjectList <- list(singlecell1Seurat, singlecell2Seurat)
    # Apply the same processing to each dataset and return a list of single-cell analysis
    singlecellObjectList <- lapply(X=singlecellObjectList, FUN=function(scObject){
    scObject <- NormalizeData(scObject)
    scObject <- FindVariableFeatures(scObject, selection.method="vst", nfeatures=2000)
    scObject <- ScaleData(scObject, features=VariableFeatures(scObject))
    scObject <- RunPCA(scObject, features=VariableFeatures(object=scObject))
    scObject <- FindNeighbors(scObject, dims=seq(16))
    scObject <- FindClusters(scObject, resolution=0.4)
    })

    # --- Results='hide' [] ---
    # Key functions: NormalizeData, FindVariableFeatures, ScaleData, VariableFeatures, RunPCA, FindNeighbors, FindClusters, vst
    scObject <- singlecellObjectList[[3]]
    scObject <- NormalizeData(scObject)
    scObject <- FindVariableFeatures(scObject, selection.method="vst", nfeatures=2000)
    scObject <- ScaleData(scObject, features=VariableFeatures(scObject))
    scObject <- RunPCA(scObject, features=VariableFeatures(object=scObject))
    scObject <- FindNeighbors(scObject, dims=seq(16))
    scObject <- FindClusters(scObject, resolution=0.4)
    singlecellObjectList[[3]] <- scObject

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_clusterfoldsimilarity_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_clusterfoldsimilarity_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_clusterfoldsimilarity_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLUSTERFOLDSIMILARITY:", paste0("    clusterfoldsimilarity: ", packageVersion("ClusterFoldSimilarity"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clusterfoldsimilarity_results.csv
    touch ${prefix}_clusterfoldsimilarity_output.rds
    echo "BIOC_CLUSTERFOLDSIMILARITY:" > versions.yml
    echo "    clusterfoldsimilarity: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLUSTERFOLDSIMILARITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLUSTERFOLDSIMILARITY(ch_input)

    emit:
    results  = BIOC_CLUSTERFOLDSIMILARITY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLUSTERFOLDSIMILARITY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLUSTERFOLDSIMILARITY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLUSTERFOLDSIMILARITY.out.versions  // channel: path(versions.yml)
}
