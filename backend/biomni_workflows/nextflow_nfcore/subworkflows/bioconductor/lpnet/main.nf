#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: lpNet
// lpNet aims at infering biological networks, in particular signaling and gene networks. For that it t
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/lpNet/inst/doc/vignette_lpNet.R
// Upstream  : KEGGgraph
// Downstream: none
//
// Install: BiocManager::install("lpNet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LPNET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-lpnet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-lpnet:2.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-lpnet:2.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_lpnet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_lpnet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_lpnet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(lpNet)
    library(jsonlite)

    # --- Data1 [] ---
    # Key functions: rnorm
    n <- 5 # number of genes
    K <- 7 # number of perturbation experiments
    obs <- matrix(rnorm(n*K), nrow=n, ncol=K)
    delta <- apply(obs, 1, mean)
    delta_type <- "perGene"
    # --- Lp [] ---
    # Key functions: doILP, getEdgeAnnot, getAdja
    res1 <- doILP(obs, delta, lambda=1, b, n, K, T_=NULL,
                  annot=getEdgeAnnot(n), delta_type)
    adja1 <- getAdja(res1, n)
    # --- Lp Pos [] ---
    # Key functions: doILP, getEdgeAnnot, getAdja
    res2 <- doILP(obs, delta, lambda=1, b, n, K, T_=NULL,
                  annot=getEdgeAnnot(n,allpos=TRUE), delta_type,
                  all.pos=TRUE)
    adja2 <- getAdja(res2,n)
    # --- Data Ts [] ---
    # Key functions: array, rnorm
    T_ <- 4 # number of time points
    obs_ts <- array(rnorm(n*K*T_), c(n,K,T_))
    # --- Lp Ts [] ---
    # Key functions: doILP, getEdgeAnnot, getAdja
    res1 <- doILP(obs_ts, delta, lambda=1, b, n, K, T_,
                  annot=getEdgeAnnot(n), delta_type,
                  flag_time_series=TRUE)
    adja1 <- getAdja(res1, n)
    # --- Loocv [] ---
    # Key functions: loocv, getEdgeAnnot
    times <- 5 # number of times the removed observation is sampled
    annot_node <- seq(1,n) # annotation of the nodes
    # --- Loocv [] ---
    # Key functions: getSampleAdjaMAD
    adja_loocv <- getSampleAdjaMAD(loocv_res$edges_all, n,
                                   annot_node)
    # --- Rangelambda [] ---
    # Key functions: calcRangeLambda, loocv, getEdgeAnnot, getSampleAdjaMAD
    lambda <- calcRangeLambda(obs, delta, delta_type)
    MSE <- Inf
    # --- Foldcv [] ---
    # Key functions: kfoldCV, getEdgeAnnot, getSampleAdjaMAD
    kfold <- 5
    MSE <- Inf
    # --- Prior1 [] ---
    # Key functions: doILP, getEdgeAnnot, getAdja
    res3 <- doILP(obs, delta, lambda=1, b, n, K, T_=NULL,
                  annot=getEdgeAnnot(n), delta_type,
                  sourceNode=1, sinkNode=5)
    adja3 <- getAdja(res3,n)
    # --- Prior2 [] ---
    # Key functions: doILP, getEdgeAnnot, getAdja
    prior <- list(c("w+_1_2", 1, ">", 1))
    res4 <- doILP(obs,delta, lambda=1, b, n, K, T_=NULL,
                  annot=getEdgeAnnot(n), delta_type,
                  prior=prior)
    adja4 <- getAdja(res4, n)
    # --- Prior3 [] ---
    # Key functions: doILP, getEdgeAnnot, getAdja
    prior <- list(c("w+_1_2", 1/0.9, ">", 1))
    res5 <- doILP(obs, delta, lambda=1, b, n, K, T_=NULL,
                  annot=getEdgeAnnot(n), delta_type,
                  prior=prior)
    adja5 <- getAdja(res5, n)
    # --- Prior4 [] ---
    # Key functions: parseKGML2Graph
    library("KEGGgraph")
    toyKGML <- system.file("extdata/kgml-ed-toy.xml", package="KEGGgraph")
    toyGraph <- parseKGML2Graph(toyKGML, genesOnly=FALSE)
    adja <- as(toyGraph,"matrix")
    entries <- which(adja!=0, arr.ind=TRUE)
    # --- Sahindata [] ---
    # Key functions: summarizeRepl
    data("SahinRNAi2008")
    dataStim <- dat.normalized[dat.normalized[ ,17] == 1,-17]
    dataUnstim <- dat.normalized[dat.normalized[ ,17] == 0,-17]
    # summarize replicates; transpose: rows=genes, cols=experiments
    dataSt <- t(summarizeRepl(dataStim, type=mean))
    # --- Sahindata Parameter [] ---
    # Key functions: getEdgeAnnot
    n <- 16 # number of genes
    K <- 16 # number of experiments
    annot <- getEdgeAnnot(n)
    # perturbation vector;       kd of:

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_lpnet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_lpnet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_lpnet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LPNET:", paste0("    lpnet: ", packageVersion("lpNet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lpnet_results.csv
    touch ${prefix}_lpnet_output.rds
    echo "BIOC_LPNET:" > versions.yml
    echo "    lpnet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LPNET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LPNET(ch_input)

    emit:
    results  = BIOC_LPNET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LPNET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LPNET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LPNET.out.versions  // channel: path(versions.yml)
}
