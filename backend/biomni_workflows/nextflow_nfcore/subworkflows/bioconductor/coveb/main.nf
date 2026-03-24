#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: covEB
// Using bayesian methods to estimate correlation matrices assuming that they can be written and estima
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/covEB/inst/doc/covEB.R
// Upstream  : curatedBladderData
// Downstream: none
//
// Install: BiocManager::install("covEB")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COVEB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-coveb"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-coveb:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-coveb:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_coveb_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_coveb_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_coveb_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(EBsingle)
    library(jsonlite)

    # --- Matrix [] ---
    # Key functions: rmvnorm, EBsingle
    library(covEB)
     	sigma <- matrix(c(4,2,2,3), ncol=2)
    	x <- rmvnorm(n=500, mean=c(1,2), sigma=sigma)
     	samplecov<-cov(x)
     	test<-EBsingle(samplecov,startlambda=0.4,n=500)
    # --- Data [] ---
    # Key functions: exprs
    library(curatedBladderData)
    data(package="curatedBladderData")
    data(GSE89_eset)
    Edata<-exprs(GSE89_eset)
    # --- Apply [] ---
    # Key functions: cov2cor, EBsingle
    variances<-apply(Edata,1,var)
    edata<-Edata[which(variances>quantile(variances,0.8)),]
    covmat<-cov(t(edata))
    cormat<-cov2cor(covmat)
    #we are now able to use covmat as input into covEB:
    # --- Clusters [] ---
    # Key functions: clusters, adjacency, diag
    clusth<-clusters(graph.adjacency(outmat))
    sel<-which(clusth$membership==6)
    subgraphEB<-outmat[sel,sel]
    subgraph<-cormat[sel,sel]
    subgraph[subgraph<0.5]<-0
    # --- Plot [] ---
    # Key functions: adjacency
    ##
    ## plot(graph.adjacency(subgraph,mode="undirected"))
    ## plot(graph.adjacency(subgraphEB,mode="undirected"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_coveb_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_coveb_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_coveb_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COVEB:", paste0("    coveb: ", packageVersion("covEB"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_coveb_results.csv
    touch ${prefix}_coveb_output.rds
    echo "BIOC_COVEB:" > versions.yml
    echo "    coveb: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COVEB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COVEB(ch_input)

    emit:
    results  = BIOC_COVEB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COVEB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COVEB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COVEB.out.versions  // channel: path(versions.yml)
}
