#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: bacon
// Bacon can be used to remove inflation and bias often observed in epigenome- and transcriptome-wide a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/bacon/inst/doc/bacon.R
// Upstream  : BiocParallel
// Downstream: none
//
// Install: BiocManager::install("bacon")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BACON {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bacon"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bacon:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bacon:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(summarizedexperiment)

    output:
    tuple val(meta), path("${meta.id}_bacon_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bacon_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bacon_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(bacon)
    library(jsonlite)


    # --- Generatedata1 [] ---
    # Key functions: rnormmix, bacon, estimates, inflation, bias, traces
    y <- rnormmix(5000, c(0.9, 0.2, 1.3, 1, 4, 1))
    bc <- bacon(y)
    bc
    estimates(bc)
    inflation(bc)
    bias(bc)
    traces(bc, burnin=FALSE)

    # --- Gsoutput2 [] ---
    # Key functions: posteriors, fit
    posteriors(bc)
    fit(bc, n=100)
    plot(bc, type="hist")

    # --- Plotqq1 [] ---
    # Key functions: runif, for, rnormmix, replicate, rchisq, register, MulticoreParam, bacon
    plot(bc, type="qq")
    set.seed(12345)
    biases <- runif(6, -0.2, 0.2)
    inflations <- runif(6, 1, 1.3)
    es <- matrix(nrow=5000, ncol=6)
    for(i in 1:6)
        es[,i] <- rnormmix(5000, c(0.9, biases[i], inflations[i], 0, 4, 1), shuffle=FALSE)
    se <- replicate(6, 0.8*sqrt(4/rchisq(5000,df=4)))
    colnames(es) <- colnames(se) <- LETTERS[1:ncol(se)]
    rownames(es) <- rownames(se) <- 1:5000
    head(rownames(es))
    library(BiocParallel)
    register(MulticoreParam(1, log=TRUE))
    bc <- bacon(NULL, es, se)
    bc
    knitr::kable(estimates(bc))
    inflation(bc)
    bias(bc)
    knitr::kable(tstat(bc)[1:5,])
    knitr::kable(pval(bc)[1:5,])

    # --- Gsoutput4 [] ---
    # Key functions: traces, posteriors, fit
    traces(bc, burnin=FALSE, index=3)
    posteriors(bc, index=3)
    fit(bc, n=100, index=3)

    # --- Plothist2 [] ---
    # Key functions: meta, pval, topTable
    plot(bc, type="hist")
    plot(bc, type="qq")
    bcm <- meta(bc)
    head(pval(bcm))
    print(topTable(bcm))

    # --- Plotqq3 [] ---
    # Key functions: rnormmix
    plot(bcm, type="qq")
    zs <- rnormmix(5000, c(0.9, 0.2, 1.3, 1, 4, 1))
    zs <- cbind(zs, matrix(zs, nrow=5000, ncol=9))
    colnames(zs) <- c(paste0("A", 1:10))
    rownames(zs) <- 1:5000
    head(rownames(zs))
    head(colnames(zs))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bacon_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bacon_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bacon_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BACON:", paste0("    bacon: ", packageVersion("bacon"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bacon_results.csv
    touch ${prefix}_bacon_output.rds
    echo "BIOC_BACON:" > versions.yml
    echo "    bacon: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BACON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(summarizedexperiment) ]

    main:
    BIOC_BACON(ch_input)

    emit:
    results  = BIOC_BACON.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BACON.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BACON.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BACON.out.versions  // channel: path(versions.yml)
}
