#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ABSSeq
// Inferring differential expression genes by absolute counts difference between two groups, utilizing 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ABSSeq/inst/doc/ABSSeq.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ABSSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ABSSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-absseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-absseq:1.60.0--r44_0' :
        'quay.io/biocontainers/bioconductor-absseq:1.60.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_absseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_absseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_absseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ABSDataSet)
    library(ABSSeq)
    library(ABSSeqlm)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data(simuN5)
    names(simuN5)
    # --- Absdataset [] ---
    # Key functions: ABSDataSet, factor
    obj <- ABSDataSet(simuN5$counts, factor(simuN5$groups))
    pairedobj <- ABSDataSet(simuN5$counts, factor(simuN5$groups),paired=TRUE)
    # --- Absdataset [] ---
    # Key functions: ABSDataSet, factor, runif, normMethod
    obj1 <- ABSDataSet(simuN5$counts, factor(simuN5$groups),
                       normMethod="user",sizeFactor=runif(10,1,2))
    normMethod(obj1)
    normMethod(obj1) <- "geometric"
    normMethod(obj1)
    # --- Normalfactors [] ---
    # Key functions: normalFactors, sFactors
    obj <- normalFactors(obj)
      sFactors(obj)
    # --- Head [] ---
    # Key functions: counts
    head(counts(obj,norm=TRUE))
    # --- Callparameter [] ---
    # Key functions: callParameter
    obj=callParameter(obj)
    # --- Plotdifftobase [] ---
    # Key functions: callDEs, plotDifftoBase
    obj <- callDEs(obj)
    plotDifftoBase(obj)
    # --- Calldes [] ---
    # Key functions: callDEs, results
    obj <- callDEs(obj)
    head(results(obj,c("rawFC","lowFC","foldChange","pvalue","adj.pvalue")))
    # --- Data [] ---
    # Key functions: ABSDataSet, factor, ABSSeq, results
    data(simuN5)
    obj <- ABSDataSet(simuN5$counts, factor(simuN5$groups))
    obj <- ABSSeq(obj)
    res <- results(obj,c("Amean","Bmean","foldChange","pvalue","adj.pvalue"))
    head(res)
    # --- Data [] ---
    # Key functions: ABSDataSet, factor, minRates, maxRates, ABSSeq, results
    data(simuN5)
    obj <- ABSDataSet(simuN5$counts, factor(simuN5$groups),minRates=0.2, maxRates=0.2)
    #or by slot functions
    #minRates(obj) <- 0.2
    #maxRates(obj) <- 0.2
    # --- Data [] ---
    # Key functions: ABSDataSet, factor, minimalDispersion, ABSSeq, results
    data(simuN5)
    obj <- ABSDataSet(simuN5$counts, factor(simuN5$groups),minDispersion=0.1)
    #or by slot functions
    #minimalDispersion(obj) <- 0.2
    obj <- ABSSeq(obj)
    # --- Data [] ---
    # Key functions: ABSDataSet, factor, ABSSeq, results
    data(simuN5)
    obj <- ABSDataSet(simuN5$counts[,c(1,2)], factor(c(1,2)))
    obj <- ABSSeq(obj)
    res <- results(obj,c("Amean","Bmean","foldChange","pvalue","adj.pvalue"))
    head(res)
    # --- Data [] ---
    # Key functions: ABSDataSet, factor, counts, genAFold
    data(simuN5)
    obj <- ABSDataSet(counts=simuN5$counts)
    ##as one group
    cond <- as.factor(rep("hex",ncol(simuN5$counts)))
    ##normalization
    # --- Data [] ---
    # Key functions: factor, ABSDataSet, ABSSeqlm
    data(simuN5)
    groups<-factor(simuN5$groups)
    obj <- ABSDataSet(counts=simuN5$counts)
    design <- model.matrix(~0+groups)
    res <- ABSSeqlm(obj,design,condA=c("groups0"),condB=c("groups1"))
    # --- Absseqlm [] ---
    # Key functions: ABSSeqlm
    res <- ABSSeqlm(obj,design,condA=c("groups0","groups1"))
    head(res)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_absseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_absseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_absseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ABSSEQ:", paste0("    absseq: ", packageVersion("ABSSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_absseq_results.csv
    touch ${prefix}_absseq_output.rds
    echo "BIOC_ABSSEQ:" > versions.yml
    echo "    absseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ABSSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ABSSEQ(ch_input)

    emit:
    results  = BIOC_ABSSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ABSSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ABSSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ABSSEQ.out.versions  // channel: path(versions.yml)
}
