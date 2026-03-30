#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tomoda
// This package provides many easy-to-use methods to analyze and visualize tomo-seq data. The tomo-seq 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tomoda/inst/doc/tomoda.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("tomoda")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TOMODA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tomoda"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tomoda:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tomoda:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tomoda_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tomoda_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tomoda_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tomoda)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(zh.data)
    head(zh.data)
    # --- Createtomo [] ---
    # Key functions: createTomo
    ---------------------------------------------------------------------
    zh <- createTomo(zh.data)
    zh
    # --- Head [] ---
    # Key functions: assay
    ---------------------------------------------------------------------
    head(assay(zh, 'scaled'), 2)
    # --- Corheatmap [] ---
    # Key functions: corHeatmap
    ---------------------------------------------------------------------
    corHeatmap(zh, max.cor=0.3)
    # --- Runpca [] ---
    # Key functions: runPCA, embedPlot, colData
    ---------------------------------------------------------------------
    zh <- runPCA(zh)
    embedPlot(zh, method="PCA")
    head(colData(zh))
    # --- Hierarchclust [] ---
    # Key functions: hierarchClust
    ---------------------------------------------------------------------
    hc_zh <- hierarchClust(zh)
    plot(hc_zh)
    # --- Kmeansclust [] ---
    # Key functions: kmeansClust, colData, embedPlot
    ---------------------------------------------------------------------
    zh <- kmeansClust(zh, centers=3)
    head(colData(zh))
    embedPlot(zh, group='kmeans_cluster')
    # --- Findpeakgene [] ---
    # Key functions: findPeakGene
    ---------------------------------------------------------------------
    peak_genes <- findPeakGene(zh, threshold = 1, length = 4, nperm = 1e5)
    head(peak_genes)
    # --- Expheatmap [] ---
    # Key functions: expHeatmap
    ---------------------------------------------------------------------
    expHeatmap(zh, peak_genes$gene, size=0)
    # --- Genecorheatmap [] ---
    # Key functions: geneCorHeatmap
    ---------------------------------------------------------------------
    geneCorHeatmap(zh, peak_genes, size=0)
    # Use variable 'start' to group genes
    geneCorHeatmap(zh, peak_genes, group='start', size=0)
    # --- Runtsne [] ---
    # Key functions: runTSNE, geneEmbedPlot, runUMAP
    ---------------------------------------------------------------------
    zh <- runTSNE(zh, peak_genes$gene)
    geneEmbedPlot(zh, peak_genes)
    zh <- runUMAP(zh, peak_genes$gene)
    geneEmbedPlot(zh, peak_genes, method="UMAP")
    # --- Lineplot [] ---
    # Key functions: linePlot
    ---------------------------------------------------------------------
    linePlot(zh, peak_genes$gene[1:3])
    # --- Expheatmap [] ---
    # Key functions: expHeatmap, scale_fill_gradient2
    ---------------------------------------------------------------------
    library(ggplot2)
    exp_heat <- expHeatmap(zh, peak_genes$gene, size=0)
    exp_heat + scale_fill_gradient2(low='magenta', mid='black', high='yellow')
    # --- Lineplot [] ---
    # Key functions: linePlot, theme_classic, scale_x_discrete
    ---------------------------------------------------------------------
    line <- linePlot(zh, peak_genes$gene[1:3])
    line +
      theme_classic() +
      scale_x_discrete(breaks=paste('X', seq(5,40,5), sep=''), labels=seq(5,40,5))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tomoda_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tomoda_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tomoda_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TOMODA:", paste0("    tomoda: ", packageVersion("tomoda"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tomoda_results.csv
    touch ${prefix}_tomoda_output.rds
    echo "BIOC_TOMODA:" > versions.yml
    echo "    tomoda: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TOMODA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TOMODA(ch_input)

    emit:
    results  = BIOC_TOMODA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TOMODA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TOMODA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TOMODA.out.versions  // channel: path(versions.yml)
}
