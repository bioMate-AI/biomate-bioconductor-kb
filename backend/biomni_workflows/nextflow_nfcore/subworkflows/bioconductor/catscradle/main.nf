#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CatsCradle
// This package addresses two broad areas.  It allows for in-depth analysis of spatial transcriptomic d
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CatsCradle/inst/doc/CatsCradle.R
// Upstream  : pheatmap, tictoc
// Downstream: none
//
// Install: BiocManager::install("CatsCradle")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CATSCRADLE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-catscradle"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-catscradle:1.0.1--r44_0' :
        'quay.io/biocontainers/bioconductor-catscradle:1.0.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_catscradle_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_catscradle_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_catscradle_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DimPlot)
    library(jsonlite)

    # --- [CC2] [] ---
    # Key functions: DimPlot
    library(Seurat,quietly=TRUE)
    library(ggplot2,quietly=TRUE)
    DimPlot(exSeuratObj,cols='polychrome') + ggtitle('Cell clusters on UMAP')
    # --- [CC3] [] ---
    # Key functions: DimPlot
    DimPlot(STranspose,cols='polychrome') + ggtitle('Gene clusters on UMAP')
    # --- [CC4] [] ---
    # Key functions: geom_point, saveWidget
    library(plotly,quietly=TRUE)
    umap = FetchData(STranspose,c('UMAP_1','UMAP_2','seurat_clusters'))
    umap$gene = colnames(STranspose)
    # --- [CC5] [] ---
    # Key functions: pheatmap
    library(pheatmap,quietly=TRUE)
    averageExpMatrix = getAverageExpressionMatrix(exSeuratObj,STranspose,layer='data')
    # --- [CC7] [] ---
    # Key functions: geom_point, ggtitle
    hallmark = getExample('hallmark')
    umap = FetchData(STranspose,c('umap_1','umap_2'))
    idx = colnames(STranspose) %in% hallmark[[h]]
    # --- [CC9] [] ---
    # Key functions: aes, geom_histogram, geom_vline, ggtitle
    statsPlot = ggplot(data.frame(medianComplementDistance=stats$randomSubsetDistance),
    aes(x=medianComplementDistance)) +
    geom_histogram(bins=50) +
    # --- [CC10] [] ---
    # Key functions: geom_histogram, geom_vline, ggtitle
    df = read.table('hallmarkPValues.txt',header=TRUE,sep='\t')
    g = ggplot(df,aes(x=logPValue)) +
    geom_histogram() +
    # --- [CC11] [] ---
    # Key functions: geom_point, scale_color_gradient, ggtitle

    # --- [CC12] [] ---
    # Key functions: geom_point, scale_color_gradient, ggtitle
    k = ggplot(TDiff,aes(x=umap_1,y=umap_2,color=TDiff)) +
    geom_point() +
    scale_color_gradient(low='green',high='red') +
    # --- [CC13] [] ---
    # Key functions: geom_point, ggtitle


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_catscradle_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_catscradle_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_catscradle_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CATSCRADLE:", paste0("    catscradle: ", packageVersion("CatsCradle"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_catscradle_results.csv
    touch ${prefix}_catscradle_output.rds
    echo "BIOC_CATSCRADLE:" > versions.yml
    echo "    catscradle: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CATSCRADLE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CATSCRADLE(ch_input)

    emit:
    results  = BIOC_CATSCRADLE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CATSCRADLE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CATSCRADLE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CATSCRADLE.out.versions  // channel: path(versions.yml)
}
