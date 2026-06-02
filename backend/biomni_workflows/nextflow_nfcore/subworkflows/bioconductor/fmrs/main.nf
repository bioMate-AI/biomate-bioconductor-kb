#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: fmrs
// The package obtains parameter estimation, i.e., maximum likelihood estimators (MLE), via the Expecta
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/fmrs/inst/doc/usingfmrs.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("fmrs")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FMRS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fmrs"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fmrs:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-fmrs:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_fmrs_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fmrs_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fmrs_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(fmrs)
    library(jsonlite)

    # --- Code Block 2 [] ---
    # Key functions: gendata
    dat <- fmrs.gendata(nObs = nObs, nComp = nComp, nCov = nCov,
                         coeff = c(coeff1, coeff2), dispersion = dispersion,
                         mixProp = mixProp, rho = rho, umax = umax,
                         disFamily = "lnorm")
    # --- Code Block 3 [] ---
    # Key functions: mle, rnorm
    res.mle <- fmrs.mle(y = dat$y, x = dat$x, delta = dat$delta,
                       nComp = nComp, disFamily = "lnorm",
                       initCoeff = rnorm(nComp*nCov+nComp),
                       initDispersion = rep(1, nComp),
                       initmixProp = rep(1/nComp, nComp))
    # --- Code Block 5 [] ---
    # Key functions: tunsel, coefficients, dispersion, mixProp
    res.lam <- fmrs.tunsel(y = dat$y, x = dat$x, delta = dat$delta,
                          nComp = nComp, disFamily = "lnorm",
                          initCoeff = c(coefficients(res.mle)),
                          initDispersion = dispersion(res.mle),
                          initmixProp = mixProp(res.mle),
    # --- Code Block 7 [] ---
    # Key functions: varsel, ncomp, coefficients, dispersion, mixProp
    res.var <- fmrs.varsel(y = dat$y, x = dat$x, delta = dat$delta,
                          nComp = ncomp(res.mle), disFamily = "lnorm",
                          initCoeff=c(coefficients(res.mle)),
                          initDispersion = dispersion(res.mle),
                          initmixProp = mixProp(res.mle),
    # --- Code Block 9 [] ---
    # Key functions: 1, namespace
    ## R version 4.4.1 (2024-06-14)
    ## Platform: x86_64-pc-linux-gnu
    ## Running under: Ubuntu 24.04.1 LTS
    ##
    ## Matrix products: default

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fmrs_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fmrs_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fmrs_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FMRS:", paste0("    fmrs: ", packageVersion("fmrs"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fmrs_results.csv
    touch ${prefix}_fmrs_output.rds
    echo "BIOC_FMRS:" > versions.yml
    echo "    fmrs: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FMRS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FMRS(ch_input)

    emit:
    results  = BIOC_FMRS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FMRS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FMRS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FMRS.out.versions  // channel: path(versions.yml)
}
