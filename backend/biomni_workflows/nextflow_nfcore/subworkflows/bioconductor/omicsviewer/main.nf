#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: omicsViewer
// omicsViewer visualizes ExpressionSet (or SummarizedExperiment) in an interactive way. The omicsViewe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/omicsViewer/inst/doc/quickStart.R
// Upstream  : Biobase
// Downstream: none
//
// Install: BiocManager::install("omicsViewer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OMICSVIEWER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-omicsviewer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-omicsviewer:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-omicsviewer:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_omicsviewer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_omicsviewer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_omicsviewer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(omicsViewer)
    library(NS)
    library(jsonlite)

    # --- Data Preparation [] ---
    # Key functions: prepOmicsViewer
    expr <- matrix(runif(100), 10, 10)
    rownames(expr) <- paste0("G", 1:10)
    colnames(expr) <- paste0("S", 1:10)
    pd <- data.frame(Origin = rep(c("RE", "ME"), each = 5),
                     row.names = colnames(expr))
    fd <- data.frame(Protein.ID = paste0("P", 1:10),
                     row.names = rownames(expr))
    tests <- rbind(c("Origin", "RE", "ME"))
    d <- prepOmicsViewer(expr = expr, pData = pd, fData = fd,
                         PCA = TRUE, pca.fillNA = TRUE,
                         t.test = tests, ttest.fillNA = FALSE,
                         SummarizedExperiment = FALSE)


    # --- Correlation Analysis [] ---
    # Key functions: correlationAnalysis, extendMetaData
    expr <- matrix(runif(100), 10, 10)
    rownames(expr) <- paste0("G", 1:10)
    colnames(expr) <- paste0("S", 1:10)
    pd <- data.frame(Origin = rep(c("RE", "ME"), each = 5),
                     row.names = colnames(expr))
    fd <- data.frame(Protein.ID = paste0("P", 1:10),
                     row.names = rownames(expr))
    d <- prepOmicsViewer(expr = expr, pData = pd, fData = fd,
                         PCA = TRUE, SummarizedExperiment = FALSE)
    drugData <- data.frame(DrugA = runif(10), DrugB = runif(10),
                           row.names = colnames(expr))
    drugcor <- correlationAnalysis(expr, pheno = drugData[, 1:2])
    d <- extendMetaData(d, drugcor, where = "fData")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_omicsviewer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_omicsviewer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_omicsviewer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OMICSVIEWER:", paste0("    omicsviewer: ", packageVersion("omicsViewer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_omicsviewer_results.csv
    touch ${prefix}_omicsviewer_output.rds
    echo "BIOC_OMICSVIEWER:" > versions.yml
    echo "    omicsviewer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OMICSVIEWER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OMICSVIEWER(ch_input)

    emit:
    results  = BIOC_OMICSVIEWER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OMICSVIEWER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OMICSVIEWER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OMICSVIEWER.out.versions  // channel: path(versions.yml)
}
