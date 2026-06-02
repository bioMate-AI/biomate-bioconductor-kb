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
    library(ComBat)
    library(jsonlite)

    # --- Initbatchrandrot [] ---
    # Key functions: initBatchRandrot
    ---------------------------------------------------------------------
    rr <- initBatchRandrot(Y = edata, X = mod1, coef.h = 2, batch = pdata$batch)
    # --- Function [] ---
    # Key functions: ComBat, lmFit, eBayes
    ---------------------------------------------------------------------
    statistic <- function(Y, batch, mod){
      # (I) Batch effect correction with "Combat" from the "sva" package
      Y <- sva::ComBat(dat = Y, batch = batch, mod = mod)
      # (II) Linear model fit
    # --- Pfdr [] ---
    # Key functions: pFdr, qqunif
    ---------------------------------------------------------------------
    p.vals <- pFdr(rs1)
    hist(p.vals, col = "lightgreen");abline(h = 100, col = "blue", lty = 2)
    qqunif(p.vals)
    # --- Combat [] ---
    # Key functions: ComBat, lmFit, eBayes, topTable, qqunif
    ---------------------------------------------------------------------
    library(limma)
    library(sva)
    edata.combat <- ComBat(dat = edata, batch = pdata$batch, mod = mod1)
    fit1 <- lmFit(edata.combat, mod1)
    # --- Matrix [] ---
    # Key functions: initRandrot, coef, fit, coefs, randrot
    ---------------------------------------------------------------------
    # Specification of the full model
    mod1 <- model.matrix(~1+phenotype, pdata)
    # We select "phenotype" as the coefficient associated with H0
    # All other coefficients are considered as "determined" coefficients
    # --- Coefs [] ---
    # Key functions: coefs, randrot
    ---------------------------------------------------------------------
    coef11 <- coefs(edata, mod1)
    coef12 <- coefs(randrot(rr), mod1)
    head(cbind(coef11, coef12))
    # --- Lmfit [] ---
    # Key functions: lmFit, eBayes, topTable, qqunif
    ---------------------------------------------------------------------
    # Linear model fit
    fit0 <- lmFit(edata, mod1)
    fit0 <- eBayes(fit0)
    # P values for phenotype coefficient
    # --- Combat [] ---
    # Key functions: ComBat
    ---------------------------------------------------------------------
    library(sva)
    edata.combat = ComBat(edata, batch = pdata$batch, mod = mod1)
    # --- Lmfit [] ---
    # Key functions: lmFit, eBayes, topTable, qqunif
    ---------------------------------------------------------------------
    # Linear model fit
    fit1 <- lmFit(edata.combat, mod1)
    fit1 <- eBayes(fit1)
    # P value for phenotype coefficient
    # --- Initbatchrandrot [] ---
    # Key functions: initBatchRandrot
    ---------------------------------------------------------------------
    init1 <- initBatchRandrot(edata, mod1, coef.h = 2, batch = pdata$batch)
    # --- Function [] ---
    # Key functions: ComBat, lmFit, eBayes
    ---------------------------------------------------------------------
    statistic <- function(Y, batch, mod, coef){
      Y.tmp <- sva::ComBat(dat = Y, batch = batch, mod = mod)
      fit1 <- limma::lmFit(Y.tmp, mod)
      fit1 <- limma::eBayes(fit1)
    # --- Pfdr [] ---
    # Key functions: pFdr, qqunif
    ---------------------------------------------------------------------
    p.rot <- pFdr(res1)
    head(p.rot)
    hist(p.rot, freq = FALSE, col = "lightgreen", breaks = seq(0,1,0.1))
    abline(1,0, col = "blue", lty = 2)
    # --- Plot [] ---
    # Key functions: density
    ---------------------------------------------------------------------
    plot(density(log(p.rot/p0)), col = "salmon", "Log p ratios",
         panel.first = abline(v=0, col = "grey"),
         xlim = range(log(c(p.rot/p0, p.combat/p0))))
    lines(density(log(p.combat/p0)), col = "blue")
    # --- Pfdr [] ---
    # Key functions: pFdr, matplot
    ---------------------------------------------------------------------
    fdr.q  <- pFdr(res1, "fdr.q")
    fdr.qu <- pFdr(res1, "fdr.qu")
    fdr.BH <- pFdr(res1, "BH")
    FDRs <- cbind(fdr.q, fdr.qu, fdr.BH)
    # --- Contrastmodel [] ---
    # Key functions: contrastModel
    ---------------------------------------------------------------------
    mod.cont <- contrastModel(X = mod.groups, C = contrasts1)

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
