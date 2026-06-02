#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: qvalue
// This package takes a list of p-values resulting from the simultaneous testing of many hypotheses and
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/qvalue/inst/doc/qvalue.R
// Upstream  : none
// Downstream: anota, DEGseq, DrugVsDisease, r3Cseq, webbioc
//
// Install: BiocManager::install("qvalue")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QVALUE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-qvalue"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-qvalue:2.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-qvalue:2.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_qvalue_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_qvalue_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_qvalue_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(qvalue)
    library(jsonlite)


    # --- Foo [] ---
    # Key functions: packageDescription, qvalue, help
    library(qvalue)
    options(keep.source = TRUE, width = 48)
    foo <- packageDescription("qvalue")
    help(package="qvalue")
    library(qvalue)
    data(hedenfalk)
    pvalues <- hedenfalk$p
    qobj <- qvalue(p = pvalues)

    # --- Quick Stat [] ---
    # Key functions: empPvals, qvalue
    library(qvalue)
    data(hedenfalk)
    obs_stats <- hedenfalk$stat
    null_stats <- hedenfalk$stat0
    pvalues <- empPvals(stat = obs_stats, stat0 = null_stats)
    qobj <- qvalue(p = pvalues)
    qvalues <- qobj$qvalues
    pi0 <- qobj$pi0
    lfdr <- qobj$lfdr
    data(hedenfalk)
    names(hedenfalk)

    # --- Obsnullstat [] ---
    # Key functions: empPvals, runif
    null_stats <- hedenfalk$stat0
    obs_stats <- hedenfalk$stat
    pvalues <- empPvals(stat = obs_stats, stat0 = null_stats, pool = FALSE)
    hist(hedenfalk$p, nclass = 20)
    set.seed(478)
    p2 = c(hedenfalk$p, (runif(450, min=0.7, max=1))^(0.33))
    somethingsWrong = list(p=p2)
    hist(somethingsWrong$p, nclass=20, main="Problematic p-values", xlab="intentionally bad, simulated p-values")

    # --- Run Qvalue [] ---
    # Key functions: qvalue, summary
    qobj <- qvalue(p = hedenfalk$p)
    names(qobj)
    summary(qobj)

    # --- Pi0 [] ---
    # Key functions: pi0est, smoother
    pi0 <- qobj$pi0
    pi0 <- pi0est(p = hedenfalk$p, lambda = seq(0.1, 0.9, 0.1), pi0.method = "smoother" )
    names(pi0)
    qvalues <- qobj$qvalues

    # --- Tmp [] ---
    # Key functions: lfdr
    max(qvalues[qobj$pvalues <= 0.01])
    localFDR <- qobj$lfdr
    localFDR <- lfdr(p = hedenfalk$p)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_qvalue_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_qvalue_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_qvalue_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QVALUE:", paste0("    qvalue: ", packageVersion("qvalue"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qvalue_results.csv
    touch ${prefix}_qvalue_output.rds
    echo "BIOC_QVALUE:" > versions.yml
    echo "    qvalue: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QVALUE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_QVALUE(ch_input)

    emit:
    results  = BIOC_QVALUE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QVALUE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QVALUE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QVALUE.out.versions  // channel: path(versions.yml)
}
