#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Harman
// Harman is a PCA and constrained optimisation based technique that maximises the removal of batch eff
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Harman/inst/doc/IntroductionToHarman.R
// Upstream  : HarmanData, RColorBrewer, bladderbatch, limma, msmsEDA
// Downstream: none
//
// Install: BiocManager::install("Harman")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HARMAN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-harman"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-harman:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-harman:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_harman_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_harman_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_harman_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Harman)
    library(jsonlite)

    # --- intensity [] ---
    # Key functions: intensity
    library(affydata, quietly = TRUE, warn.conflicts = FALSE)
    data(Dilution)
    intensity(Dilution.log) <- log(intensity(Dilution))
    # --- Principal component analysis [] ---
    # Key functions: prcomp, rainbow
    Dilution.loess <- normalize(Dilution.log, method="loess")
    Dilution.qnt <- normalize(Dilution.log, method="quantiles")
    pca <- function(exprs, pc_x=1, pc_y=2, cols, ...) {
    # --- affydata reconstruct [] ---
    # Key functions: exprs, detach
    exprs(Dilution.loess.hm) <- reconstructData(loess.hm)
    exprs(Dilution.qnt.hm) <- reconstructData(qnt.hm)
    detach('package:affydata')
    # --- Filter by row sum threshold [] ---
    # Key functions: preprocessSWAN, preprocessIllumina, detectionP, rowSums
    rgSet <- read.metharray.exp(targets=targets)
    mSetSw <- preprocessSWAN(rgSet)
    mSet <- preprocessIllumina(rgSet, bg.correct=TRUE, normalize="controls",
    # --- p Data [] ---
    # Key functions: pData, mdsPlot
    par(mfrow=c(1, 1))
    cancer_by_gender_factor <- as.factor(paste(pData(mSetSw)$sex,
    pData(mSetSw)$status)
    # --- shift Betas [] ---
    # Key functions: shiftBetas, beta2m
    par(mfrow=c(2,2))
    library(lumi, quietly = TRUE)
    shifted_betas <- shiftBetas(betas=getBeta(mSetIl), shiftBy=1e-7)
    # --- myplot [] ---
    # Key functions: myplot
    slide_cols <- rep(brewer.pal(9, "Set1"), times=5)[as.factor(episcope$pd$array_num)]
    myplot <- function(probe) {
    plot(episcope$original[probe, ],
    # --- Linear model fit (limma) [] ---
    # Key functions: lmFit, eBayes
    fit_hm <- lmFit(ms_hm, design)
    fit_hm <- eBayes(fit_hm)
    fit <- lmFit(getM(mSetSw), design)
    # --- harman [] ---
    # Key functions: harman
    log_ms_exprs <- log(exprs(msms_pp) + 1, 2)
    hm <- harman(log_ms_exprs, expt=expt, batch=batch)
    summary(hm)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_harman_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_harman_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_harman_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HARMAN:", paste0("    harman: ", packageVersion("Harman"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_harman_results.csv
    touch ${prefix}_harman_output.rds
    echo "BIOC_HARMAN:" > versions.yml
    echo "    harman: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HARMAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HARMAN(ch_input)

    emit:
    results  = BIOC_HARMAN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HARMAN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HARMAN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HARMAN.out.versions  // channel: path(versions.yml)
}
