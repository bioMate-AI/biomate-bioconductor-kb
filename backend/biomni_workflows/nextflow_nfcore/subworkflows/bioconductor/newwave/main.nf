#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: NewWave
// A model designed for dimensionality reduction and batch effect removal for scRNA-seq data. It is des
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/NewWave/inst/doc/vignette.R
// Upstream  : Rtsne, SingleCellExperiment, ggplot2, irlba, mclust
// Downstream: none
//
// Install: BiocManager::install("NewWave")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NEWWAVE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-newwave"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-newwave:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-newwave:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_newwave_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_newwave_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_newwave_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Rtsne)
    library(jsonlite)

    # --- Newsplatparams [] ---
    # Key functions: newSplatParams, splatSimulateGroups
    ---------------------------------------------------------------------
    params <- newSplatParams()
    N=500
    set.seed(1234)
    data <- splatSimulateGroups(params,batchCells=c(N/2,N/2),
    # --- Coldata [] ---
    # Key functions: colData
    ---------------------------------------------------------------------
    colData(data)
    # --- Factor [] ---
    # Key functions: factor
    ---------------------------------------------------------------------
    data$Batch <- as.factor(data$Batch)
    # --- Prcomp Irlba [] ---
    # Key functions: prcomp_irlba, counts, frame, Rtsne
    ---------------------------------------------------------------------
    pca <- prcomp_irlba(t(counts(data)),n=10)
    plot_data <-data.frame(Rtsne(pca$x)$Y)
    # --- Ggplot [] ---
    # Key functions: ggplot, aes, geom_point
    ---------------------------------------------------------------------
    ggplot(plot_data, aes(x=X1,y=X2,col=group, shape=batch))+ geom_point()
    # --- Newwave [] ---
    # Key functions: newWave
    ---------------------------------------------------------------------
    res <- newWave(data,X = "~Batch", K=10, verbose = TRUE)
    # --- Reduceddim [] ---
    # Key functions: reducedDim, frame, Rtsne
    ---------------------------------------------------------------------
    latent <- reducedDim(res)
    tsne_latent <- data.frame(Rtsne(latent)$Y)
    tsne_latent$batch <- data$Batch
    tsne_latent$group <- data$Group
    # --- Ggplot [] ---
    # Key functions: ggplot, aes, geom_point
    ---------------------------------------------------------------------
    ggplot(tsne_latent, aes(x=X1,y=X2,col=group, shape=batch))+ geom_point()
    # --- Kmeans [] ---
    # Key functions: kmeans, adjustedRandIndex
    ---------------------------------------------------------------------
    cluster <- kmeans(latent, 10)
    adjustedRandIndex(cluster$cluster, data$Group)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_newwave_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_newwave_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_newwave_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NEWWAVE:", paste0("    newwave: ", packageVersion("NewWave"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_newwave_results.csv
    touch ${prefix}_newwave_output.rds
    echo "BIOC_NEWWAVE:" > versions.yml
    echo "    newwave: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NEWWAVE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NEWWAVE(ch_input)

    emit:
    results  = BIOC_NEWWAVE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NEWWAVE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NEWWAVE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NEWWAVE.out.versions  // channel: path(versions.yml)
}
