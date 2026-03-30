#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BioNet
// This package provides functions for the integrated analysis of protein-protein interaction networks 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BioNet/inst/doc/Tutorial.R
// Upstream  : ALL, DLBCL, genefilter, impute, limma
// Downstream: none
//
// Install: BiocManager::install("BioNet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIONET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bionet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bionet:1.66.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bionet:1.66.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bionet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bionet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bionet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BioNet)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(BioNet)
    library(DLBCL)
    data(dataLym)
    data(interactome)
    # --- Subnetwork [] ---
    # Key functions: subNetwork, rmSelfLoops
    subnet <- subNetwork(dataLym$label, interactome)
    subnet <- rmSelfLoops(subnet)
    subnet
    # --- Fitbummodel [] ---
    # Key functions: fitBumModel, scoreNodes
    fb <- fitBumModel(pval, plot=FALSE)
    scores <- scoreNodes(subnet, fb, fdr=0.001)
    # --- Runfastheinz [] ---
    # Key functions: runFastHeinz
    module <- runFastHeinz(subnet, scores)
    logFC <- dataLym$diff
    names(logFC) <- dataLym$label
    # --- Plotmodule [] ---
    # Key functions: plotModule
    plotModule(module, scores=scores, diff.expr=logFC)
    # --- Data [] ---
    # Key functions: data
    library(BioNet)
    library(DLBCL)
    data(exprLym)
    data(interactome)
    # --- Subnetwork [] ---
    # Key functions: subNetwork, featureNames
    network <- subNetwork(featureNames(exprLym), interactome)
    network
    # --- Largestcomp [] ---
    # Key functions: largestComp
    network <- largestComp(network)
    network
    # --- Knn [] ---
    # Key functions: knn, exprs, rowttests
    library(genefilter)
    library(impute)
    expressions <- impute.knn(exprs(exprLym))$data
    t.test <- rowttests(expressions, fac=exprLym$Subgroup)
    # --- Xtable [] ---
    # Key functions: xtable
    library(xtable)
    top.table <- xtable(t.test[1:10,], display=c("s", "f", "f", "f"))
    print(top.table, floating=FALSE)
    # --- Data [] ---
    # Key functions: data, cbind
    data(dataLym)
    ttest.pval <- t.test[, "p.value"]
    surv.pval <- dataLym$s.pval
    names(surv.pval) <- dataLym$label
    pvals <- cbind(ttest.pval, surv.pval)
    # --- Aggrpvals [] ---
    # Key functions: aggrPvals
    pval <- aggrPvals(pvals, order=2, plot=FALSE)
    # --- Fitbummodel [] ---
    # Key functions: fitBumModel
    fb <- fitBumModel(pval, plot=FALSE)
    fb
    # --- Plotllsurface [] ---
    # Key functions: plotLLSurface
    plotLLSurface(pval, fb)
    # --- Scorenodes [] ---
    # Key functions: scoreNodes
    scores <- scoreNodes(network=network, fb=fb, fdr=0.001)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bionet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bionet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bionet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIONET:", paste0("    bionet: ", packageVersion("BioNet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bionet_results.csv
    touch ${prefix}_bionet_output.rds
    echo "BIOC_BIONET:" > versions.yml
    echo "    bionet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIONET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIONET(ch_input)

    emit:
    results  = BIOC_BIONET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIONET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIONET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIONET.out.versions  // channel: path(versions.yml)
}
