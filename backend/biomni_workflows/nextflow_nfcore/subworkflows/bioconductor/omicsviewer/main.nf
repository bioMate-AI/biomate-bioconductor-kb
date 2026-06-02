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
    library(NS)
    library(jsonlite)

    # --- Simple Pipeline [] ---
    # Key functions: delim, path
    library(omicsViewer)
    library(Biobase)
    packdir <- system.file("extdata", package = "omicsViewer")
    # reading expression
    expr <- read.delim(file.path(packdir, "expressionMatrix.tsv"), stringsAsFactors = FALSE)
    # --- Dend [] ---
    # Key functions: hclust, dist, dendrogram, attr
    # euclidean distance + complete linkage
    hcl <- hclust(dist(expr))
    dend <- as.dendrogram(hcl)
    # correlation distance + ward.D linkage
    hcl2 <- hclust(as.dist(1-cor(t(expr), use= "pair")), method = "ward.D")
    # --- Simple Pipeline Continue [] ---
    # Key functions: delim, path, read_gmt, gsAnnotIdList
    # reading feature data
    fd <- read.delim(file.path(packdir, "featureGeneral.tsv"), stringsAsFactors = FALSE)
    # reading phenotype data
    pd <- read.delim(file.path(packdir, "sampleGeneral.tsv"), stringsAsFactors = FALSE)
    #  reading other datasets
    # --- Add More Cols [] ---
    # Key functions: exprs, correlationAnalysis, extendMetaData, omicsViewer
    expr <- exprs(d)
    drugcor <- correlationAnalysis(expr, pheno = drugData[, 1:2])
    d <- extendMetaData(d, drugcor, where = "fData")
    # saveRDS(d, file = "dtest.RDS")
    ##  to open the viewer
    # --- Write Extension 1 [] ---
    # Key functions: NS, tagList, verbatimTextOutput
    library(omicsViewer)
    ctxt <- function(x) paste(
      x[1:min(10, length(x))], collapse = ";"
    )
    ### extra tab 1 -- feature selected ###
    # --- Write Extension 2 [] ---
    # Key functions: NS, tagList, verbatimTextOutput, ns, renderText, ctxt
    ### continue from above : extra tab 2 -- sample selected ###
    # --- Write Extension 3 [] ---
    # Key functions: NS, tagList, triselector_ui, ns, reactive, fdata


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
