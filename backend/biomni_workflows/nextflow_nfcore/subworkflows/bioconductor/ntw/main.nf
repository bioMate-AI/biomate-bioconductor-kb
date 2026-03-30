#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: NTW
// This package predicts the gene-gene interaction network and identifies the direct transcriptional ta
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/NTW/inst/doc/NTW.R
// Upstream  : mvtnorm
// Downstream: none
//
// Install: BiocManager::install("NTW")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NTW {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ntw"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ntw:1.56.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ntw:1.56.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ntw_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ntw_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ntw_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(NTW)
    library(Srow)
    library(jsonlite)

    # --- Loaddata [] ---
    # Key functions: data
    data(sos.data)
    X<-sos.data
    X<-as.matrix(X)
    X
    # --- Setpara [] ---
    # Key functions: rep
    restK=rep(ncol(X)-1, nrow(X))
    topD = round(0.6*nrow(X))
    topK = round(0.5*nrow(X))
    numP = round(0.25*nrow(X))
    # --- Genprior [] ---
    # Key functions: runif
    pred.net<-matrix(round(runif(nrow(X)*nrow(X), min=0, max=1)), nrow(X), nrow(X))
    pred.net
    # --- Calresult1 [] ---
    # Key functions: NTW
    result<-NTW(X, restK, topD, topK, P.known=NULL, cFlag="sse", pred.net = NULL, sup.drop = -1,numP, noiseLevel=0.1)
    result
    # --- Calresult2 [] ---
    # Key functions: NTW
    result<-NTW(X, restK, topD, topK, P.known=NULL, cFlag="sse", pred.net =pred.net, sup.drop = 1,numP, noiseLevel=0.1)
    result
    # --- Calresults [] ---
    # Key functions: preestimation, Srow
    IX<-P.preestimation(X, topK= round(2*nrow(X)))
    result.Srow<-AP.estimation.Srow(r=1,cMM.corrected = 1, pred.net,X, IX,topD, restK, cFlag="sse",sup.drop = -1, numP, noiseLevel=0.1)
    result.Srow
    # --- Calresultspknown [] ---
    # Key functions: runif, Srow
    P.known<-matrix(round(runif(nrow(X)*ncol(X), min=0, max=1)), nrow(X), ncol(X))
    result.Srow<-A.estimation.Srow(r=1,cMM.corrected = 1, pred.net, X, P.known, topD, restK, cFlag="ml",sup.drop = -1, noiseLevel=0.1)
    result.Srow

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ntw_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ntw_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ntw_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NTW:", paste0("    ntw: ", packageVersion("NTW"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ntw_results.csv
    touch ${prefix}_ntw_output.rds
    echo "BIOC_NTW:" > versions.yml
    echo "    ntw: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NTW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NTW(ch_input)

    emit:
    results  = BIOC_NTW.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NTW.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NTW.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NTW.out.versions  // channel: path(versions.yml)
}
