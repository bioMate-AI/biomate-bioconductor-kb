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

    # --- Network Inference via ILP [] ---
    # Key functions: doILP, getAdja, getEdgeAnnot
    res1 <- doILP(obs, delta, lambda = 1, b, n, K, T_ = NULL,
                  annot = annot, delta_type)
    adja1 <- getAdja(res1, n)
    res_pos <- doILP(obs, delta, lambda = 1, b, n, K, T_ = NULL,
                     annot = getEdgeAnnot(n, allpos = TRUE), delta_type,
                     all.pos = TRUE)
    adja_pos <- getAdja(res_pos, n)


    # --- Cross Validation and Parameter Tuning [] ---
    # Key functions: calcRangeLambda, loocv, getSampleAdjaMAD
    times <- 5
    annot_node <- seq(1, n)
    active_mu <- 1.1
    inactive_mu <- 0.9
    active_sd <- 0.01
    inactive_sd <- 0.01
    mu_type <- "single"
    lambda_range <- calcRangeLambda(obs, delta, delta_type)
    loocv_res <- loocv(kfold = NULL, times, obs, delta, 
                       lambda = lambda_range[1], b, n, K, T_ = NULL, 
                       annot = annot, annot_node, active_mu, active_sd,
                       inactive_mu, inactive_sd, mu_type, delta_type)
    adja_loocv <- getSampleAdjaMAD(loocv_res$edges_all, n, annot_node)


    # --- Network Inference with Prior Knowledge [] ---
    # Key functions: doILP, getAdja
    prior <- list(c("w+_1_2", 1, ">", 1))
    res_prior <- doILP(obs, delta, lambda = 1, b, n, K, T_ = NULL,
                       annot = annot, delta_type, prior = prior,
                       sourceNode = 1, sinkNode = 5)
    adja_prior <- getAdja(res_prior, n)

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
