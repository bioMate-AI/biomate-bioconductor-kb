#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: randRotation
// A collection of methods for performing random rotations on high-dimensional, normally distributed da
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/randRotation/inst/doc/randRotationIntro.R
// Upstream  : limma, nlme, sva
// Downstream: none
//
// Install: BiocManager::install("randRotation")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RANDROTATION {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-randrotation"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-randrotation:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-randrotation:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_randrotation_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_randrotation_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_randrotation_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(randRotation)
    library(ComBat)
    library(jsonlite)

    # --- Random Rotation and Statistical Testing [] ---
    # Key functions: rotateStat, pFdr
    statistic <- function(Y, batch, mod) {
        Y <- sva::ComBat(dat = Y, batch = batch, mod = mod)
        fit1 <- limma::lmFit(Y, design = mod)
        fit1 <- limma::eBayes(fit1)
        abs(fit1$t[, 2])
    }
    rs1 <- rotateStat(
        initialised.obj = rr, R = 10, statistic = statistic,
        batch = pdata$batch, mod = mod1
    )
    p.vals <- pFdr(rs1)


    # --- Null Hypothesis Model Rotation [] ---
    # Key functions: initRandrot, randrot
    mod1 <- model.matrix(~1 + phenotype, pdata)
    rr <- initRandrot(Y = edata, X = mod1, coef.h = 2)
    coefs <- function(Y, mod) {
        t(coef(lm.fit(x = mod, y = t(Y))))
    }
    mod0 <- model.matrix(~1, pdata)
    coef01 <- coefs(edata, mod0)
    coef02 <- coefs(randrot(rr), mod0)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_randrotation_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_randrotation_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_randrotation_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RANDROTATION:", paste0("    randrotation: ", packageVersion("randRotation"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_randrotation_results.csv
    touch ${prefix}_randrotation_output.rds
    echo "BIOC_RANDROTATION:" > versions.yml
    echo "    randrotation: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RANDROTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RANDROTATION(ch_input)

    emit:
    results  = BIOC_RANDROTATION.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RANDROTATION.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RANDROTATION.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RANDROTATION.out.versions  // channel: path(versions.yml)
}
