#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: bandle
// The Bandle package enables the analysis and visualisation of differential localisation experiments u
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/bandle/inst/doc/v01-getting-started.R
// Upstream  : dplyr, ggplot2, pRolocdata, pheatmap, viridis
// Downstream: none
//
// Install: BiocManager::install("bandle")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BANDLE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bandle"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bandle:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bandle:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bandle_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bandle_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bandle_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(bandle)
    library(jsonlite)

    # --- Gaussian Process Fitting [bandle] ---
    # Key functions: fitGPmaternPC
    K <- length(pRoloc::getMarkerClasses(lopitrep[[1]], fcol = "markers"))
    pc_prior <- matrix(NA, ncol = 3, K)
    pc_prior[seq.int(1:K), ] <- matrix(
        rep(c(10, 60, 250), each = K),
        ncol = 3
    )
    gpParams <- lapply(lopitrep, function(x) {
        fitGPmaternPC(x, hyppar = pc_prior)
    })

    # --- Prior Specification [bandle] ---
    # Key functions: prior_pred_dir
    K <- length(pRoloc::getMarkerClasses(lopitrep[[1]], fcol = "markers"))
    dirPrior <- diag(rep(1, K)) + matrix(0.001, nrow = K, ncol = K)
    predDirPrior <- prior_pred_dir(
        object = lopitrep[[1]],
        dirPrior = dirPrior,
        q = 15
    )

    # --- Differential Localization Analysis [bandle] ---
    # Key functions: bandle
    control <- lopitrep[1:3]
    treatment <- lopitrep[4:6]
    bandleres <- bandle(
        objectCond1 = control,
        objectCond2 = treatment,
        numIter = 20,
        burnin = 5L,
        thin = 1L,
        gpParams = gpParams,
        pcPrior = pc_prior,
        numChains = 1,
        dirPrior = dirPrior
    )

    # --- Posterior Processing and Predictions [bandle] ---
    # Key functions: bandleProcess, summaries, posteriorEstimates, bandlePredict, getPredictions
    bandleres <- bandleProcess(bandleres)
    res <- summaries(bandleres)
    pe1 <- posteriorEstimates(res[[1]])
    xx <- bandlePredict(control, treatment, params = bandleres, fcol = "markers")
    res_control <- getPredictions(
        xx[[1]][[1]],
        fcol = "bandle.allocation",
        scol = "bandle.probability",
        mcol = "markers",
        t = 0.99
    )

    # --- Differential Localisation Assessment [bandle] ---
    # Key functions: binomialDiffLocProb, bootstrapdiffLocprob
    bin_t <- binomialDiffLocProb(
        params = bandleres,
        top = 100,
        nsample = 5000,
        decreasing = TRUE
    )
    boot_t <- bootstrapdiffLocprob(
        params = bandleres,
        top = 100,
        Bootsample = 5000,
        decreasing = TRUE
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bandle_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bandle_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bandle_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BANDLE:", paste0("    bandle: ", packageVersion("bandle"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bandle_results.csv
    touch ${prefix}_bandle_output.rds
    echo "BIOC_BANDLE:" > versions.yml
    echo "    bandle: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BANDLE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BANDLE(ch_input)

    emit:
    results  = BIOC_BANDLE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BANDLE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BANDLE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BANDLE.out.versions  // channel: path(versions.yml)
}
