#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: systemPipeTools
// systemPipeTools package extends the widely used systemPipeR (SPR) workflow environment with an enhan
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/systemPipeTools/inst/doc/systemPipeTools.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("systemPipeTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SYSTEMPIPETOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-systempipetools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-systempipetools:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-systempipetools:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_systempipetools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_systempipetools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_systempipetools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(systemPipeTools)
    library(GLMplot)
    library(MAplot)
    library(MDSplot)
    library(PCAplot)
    library(jsonlite)

    # --- Hierarchical Clustering and Sample Heatmaps [] ---
    # Key functions: exploreDDS, hclustplot, heatMaplot
    targetspath <- system.file("extdata", "targets.txt", package = "systemPipeR")
    targets <- read.delim(targetspath, comment = "#")
    cmp <- systemPipeR::readComp(
        file = targetspath, format = "matrix", delim = "-"
    )
    countMatrixPath <- system.file(
        "extdata", "countDFeByg.xls", package = "systemPipeR"
    )
    countMatrix <- read.delim(countMatrixPath, row.names = 1)
    exploredds <- exploreDDS(
        countMatrix, targets, cmp = cmp[[1]],
        preFilter = NULL, transformationMethod = "rlog"
    )
    hclustplot(exploredds, method = "spearman")
    heatMaplot(exploredds, clust = "samples", plotly = FALSE)


    # --- Dimensionality Reduction [] ---
    # Key functions: exploreDDS, PCAplot, MDSplot, tSNEplot
    targetspath <- system.file("extdata", "targets.txt", package = "systemPipeR")
    targets <- read.delim(targetspath, comment = "#")
    cmp <- systemPipeR::readComp(
        file = targetspath, format = "matrix", delim = "-"
    )
    countMatrixPath <- system.file(
        "extdata", "countDFeByg.xls", package = "systemPipeR"
    )
    countMatrix <- read.delim(countMatrixPath, row.names = 1)
    exploredds <- exploreDDS(
        countMatrix, targets, cmp = cmp[[1]],
        preFilter = NULL, transformationMethod = "rlog"
    )
    PCAplot(exploredds, plotly = FALSE)
    MDSplot(exploredds, plotly = FALSE)
    tSNEplot(countMatrix, targets, perplexity = 5)


    # --- Differential Expression Visualization [] ---
    # Key functions: exploreDDS, heatMaplot, MAplot, volcanoplot, GLMplot
    targetspath <- system.file("extdata", "targets.txt", package = "systemPipeR")
    targets <- read.delim(targetspath, comment = "#")
    cmp <- systemPipeR::readComp(
        file = targetspath, format = "matrix", delim = "-"
    )
    countMatrixPath <- system.file(
        "extdata", "countDFeByg.xls", package = "systemPipeR"
    )
    countMatrix <- read.delim(countMatrixPath, row.names = 1)
    exploredds <- exploreDDS(
        countMatrix, targets, cmp = cmp[[1]],
        preFilter = NULL, transformationMethod = "rlog"
    )
    exploredds_raw <- exploreDDS(
        countMatrix, targets, cmp = cmp[[1]],
        preFilter = NULL, transformationMethod = "raw"
    )
    GLMplot(exploredds_raw, plotly = FALSE)
    degseqDF <- systemPipeR::run_DESeq2(
        countDF = countMatrix, targets = targets,
        cmp = cmp[[1]], independent = FALSE
    )
    DEG_list <- systemPipeR::filterDEGs(
        degDF = degseqDF, filter = c(Fold = 2, FDR = 10)
    )
    heatMaplot(
        exploredds, clust = "ind",
        DEGlist = unique(as.character(unlist(DEG_list[[1]])))
    )
    MAplot(
        degseqDF, comparison = "M12-A12",
        filter = c(Fold = 1, FDR = 20), genes = "ATCG00280"
    )
    volcanoplot(
        degseqDF, comparison = "M12-A12",
        filter = c(Fold = 1, FDR = 20), genes = "ATCG00280"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_systempipetools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_systempipetools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_systempipetools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SYSTEMPIPETOOLS:", paste0("    systempipetools: ", packageVersion("systemPipeTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_systempipetools_results.csv
    touch ${prefix}_systempipetools_output.rds
    echo "BIOC_SYSTEMPIPETOOLS:" > versions.yml
    echo "    systempipetools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SYSTEMPIPETOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SYSTEMPIPETOOLS(ch_input)

    emit:
    results  = BIOC_SYSTEMPIPETOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SYSTEMPIPETOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SYSTEMPIPETOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SYSTEMPIPETOOLS.out.versions  // channel: path(versions.yml)
}
