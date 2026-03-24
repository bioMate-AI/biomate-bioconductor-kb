#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: vbmp
// Variational Bayesian Multinomial Probit Regression with Gaussian Process Priors. It estimates class 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/vbmp/inst/doc/vbmp.R
// Upstream  : Biobase
// Downstream: none
//
// Install: BiocManager::install("vbmp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VBMP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-vbmp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-vbmp:1.74.0--r44_0' :
        'quay.io/biocontainers/bioconductor-vbmp:1.74.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_vbmp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_vbmp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_vbmp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(U)
    library(jsonlite)

    # --- Example11 [] ---
    # Key functions: 2, U, runif
    genSample <- function(n, noiseVar=0) {
        KF <- 10; # magnify factor
        nt <- round(n/3,0)#
        ## class 1 and 2 (x ~ U(0,1))
        u <- 4. * matrix(runif(2*KF*n), nrow=KF*n, ncol=2) - 2.;
    # --- Example14 [] ---
    # Key functions: genSample
    dataXtTrain <- genSample(Ntrain, nNoisyInputs);
    dataXtTest  <- genSample(Ntest,  nNoisyInputs);
    # --- Example15 [] ---
    # Key functions: rep
    theta <- rep(1., ncol(dataXtTrain$X));
    max.train.iter <- 12;
    # --- Example16 [] ---
    # Key functions: vbmp
    library(vbmp);
    res <- vbmp( dataXtTrain$X, dataXtTrain$t.class,
                 dataXtTest$X, dataXtTest$t.class, theta,
                 control=list(bThetaEstimate=T, bMonitor=T, maxIts=max.train.iter));
    # --- Diagnostics [] ---
    # Key functions: diagnostics, plotDiagnostics
    ## plot convergence diagnostics (same as setting bPlotFitting=T)
    plotDiagnostics(res);
    # --- Example2 [] ---
    # Key functions: exprs
    library("Biobase");
      data("BRCA12");
      brca.y <- BRCA12$Target.class;
      brca.x <- t(exprs(BRCA12));
    # --- Example21 [] ---
    # Key functions: vbmp, predClass
    predictVBMP <- function(x) {
          sKernelType <- "iprod";
          Thresh      <- 1e-8;
          theta       <- rep(1.0, ncol(brca.x));
          max.train.iter <- 24;
    # --- Example212 [] ---
    # Key functions: rep
    # fake predictVBMP to speed-up the RCMD TEST
      predictVBMP <- function(x) {
          rep(0,sum(x));
      }
    # --- Example22 [] ---
    # Key functions: sample, ifelse
    n     <- nrow(brca.x);
      Kfold <- n; # number of folds , if equal to n then LOO
      samps <- sample(rep(1:Kfold, length=n), n, replace=FALSE);
      res   <- rep(NA, n);
      print(paste("Crossvalidation started...... (",n,"steps )"));

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_vbmp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_vbmp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_vbmp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VBMP:", paste0("    vbmp: ", packageVersion("vbmp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vbmp_results.csv
    touch ${prefix}_vbmp_output.rds
    echo "BIOC_VBMP:" > versions.yml
    echo "    vbmp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VBMP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VBMP(ch_input)

    emit:
    results  = BIOC_VBMP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VBMP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VBMP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VBMP.out.versions  // channel: path(versions.yml)
}
