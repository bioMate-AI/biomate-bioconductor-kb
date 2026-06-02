#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sparsenetgls
// The package provides methods of combining the graph structure learning and generalized least squares
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sparsenetgls/inst/doc/vignettes_sparsenetgls.R
// Upstream  : MASS, Matrix
// Downstream: none
//
// Install: BiocManager::install("sparsenetgls")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPARSENETGLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sparsenetgls"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sparsenetgls:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sparsenetgls:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sparsenetgls_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sparsenetgls_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sparsenetgls_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(sparsenetgls)
    library(jsonlite)

    # --- Coefficient Conversion and Selection [] ---
    # Key functions: convertbeta
    q <- dim(databand_X)[2]
    nlambda <- 10
    betagls <- matrix(nrow = nlambda, ncol = q + 1)
    for (i in seq_len(nlambda)) {
        betagls[i, ] <- convertbeta(
            Y = databand_Y,
            X = databand_X,
            q = q + 1,
            beta0 = fitgls$beta[, i]
        )$betaconv
    }
    ndist <- max(fitgls$power) - 1
    tr_gamma <- matrix(nrow = 10, ncol = ndist - 1)
    for (j in seq_len(ndist - 1)) {
        for (i in seq_len(nlambda)) {
            tr_gamma[i, j] <- sum(diag(fitgls$covBeta[, , j, i]))
        }
    }
    select_lambda_dist <- which(tr_gamma == min(tr_gamma), arr.ind = TRUE)
    betagls_select <- betagls[select_lambda_dist[1], ]


    # --- Model Selection via Information Criteria [] ---
    # Key functions: sparsenetgls
    select_lambda_dist2 <- which(
        fitgls$bic == min(fitgls$bic, na.rm = TRUE),
        arr.ind = TRUE
    )
    select_lambda_dist3 <- which(
        fitgls$aic == min(fitgls$aic, na.rm = TRUE),
        arr.ind = TRUE
    )
    ndist <- max(fitgls$power) - 1
    varbeta_bic <- diag(fitgls$covBeta[, , ndist, select_lambda_dist2[1]])
    varbeta_aic <- diag(fitgls$covBeta[, , ndist, select_lambda_dist3[1]])


    # --- Performance Assessment and ROC Analysis [] ---
    # Key functions: path_result_for_roc, plot_roc
    omega <- fitgls$PREC_seq
    omega_est <- array(dim = c(50, 50, 10))
    for (i in seq_len(10)) {
        omega_est[, , i] <- as.matrix(omega[[i]])
    }
    roc_path_result <- path_result_for_roc(
        PREC_for_graph = prec,
        OMEGA_path = omega_est,
        pathnumber = 10
    )
    plot_roc(
        result_assessment = roc_path_result,
        group = FALSE,
        ngroup = 0,
        est_names = "glasso estimation"
    )


    # --- Visualization of Network Estimates [] ---
    # Key functions: plotsngls, sparsenetgls
    plotsngls(
        fitgls,
        ith_lambda = 5
    )
    fitgls_elastic <- sparsenetgls(
        responsedata = databand_Y,
        predictdata = databand_X,
        nlambda = 10,
        ndist = 5,
        method = "elastic"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sparsenetgls_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sparsenetgls_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sparsenetgls_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPARSENETGLS:", paste0("    sparsenetgls: ", packageVersion("sparsenetgls"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sparsenetgls_results.csv
    touch ${prefix}_sparsenetgls_output.rds
    echo "BIOC_SPARSENETGLS:" > versions.yml
    echo "    sparsenetgls: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPARSENETGLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPARSENETGLS(ch_input)

    emit:
    results  = BIOC_SPARSENETGLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPARSENETGLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPARSENETGLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPARSENETGLS.out.versions  // channel: path(versions.yml)
}
