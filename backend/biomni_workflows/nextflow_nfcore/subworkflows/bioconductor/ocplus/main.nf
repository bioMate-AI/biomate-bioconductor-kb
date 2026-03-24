#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: OCplus
// This package allows to characterize the operating characteristics of a microarray experiment, i.e. t
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/OCplus/inst/doc/OCplus.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("OCplus")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OCPLUS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ocplus"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ocplus:1.80.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ocplus:1.80.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ocplus_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ocplus_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ocplus_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(EOC)
    library(OCshow)
    library(TOC)
    library(jsonlite)

    # --- Samplesize [] ---
    # Key functions: samplesize
    ss1 = samplesize(p0=0.95, D=1, crit=0.01)
    # --- Toc [] ---
    # Key functions: TOC
    TOC(n=20, p0=0.95, D=1, alpha=FALSE, legend=TRUE)
    # --- Eoc [] ---
    # Key functions: EOC
    sim1 = EOC(simdat, colnames(simdat))
    sim1[1:5,]
    # --- fdr1d [] ---
    # Key functions: fdr1d
    sim2 = fdr1d(simdat, colnames(simdat), verb=FALSE)
    sim2[1:5,]
    # --- fdr2d [] ---
    # Key functions: fdr2d, p0
    sim3 = fdr2d(simdat, colnames(simdat), p0=p0(sim2), verb=FALSE)
    sim3[1:5,]
    # --- Plot [] ---
    # Key functions: fdr
    plot(sim2)
    lines(average.fdr(sim3), lty=2)
    # --- Summary [] ---
    # Key functions: topDE
    summary(sim3)
    topDE(sim3, co=0.1)
    # --- Ocshow [] ---
    # Key functions: OCshow
    OCshow(sim1, sim2, sim3, legend=c("FDR","fdr1d","fdr2d"))
    # --- Tstatistics [] ---
    # Key functions: tstatistics, tMixture
    tt = tstatistics(simdat, colnames(simdat))
    tt[1:10,]
    tm = tMixture(tt, nq=3)
    # --- Tmixture [] ---
    # Key functions: tMixture
    tMixture(tt, nq=3, p0=0.80)$p0.est
    tMixture(tt, nq=3, p0=0.60)$p0.est

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ocplus_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ocplus_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ocplus_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OCPLUS:", paste0("    ocplus: ", packageVersion("OCplus"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ocplus_results.csv
    touch ${prefix}_ocplus_output.rds
    echo "BIOC_OCPLUS:" > versions.yml
    echo "    ocplus: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OCPLUS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OCPLUS(ch_input)

    emit:
    results  = BIOC_OCPLUS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OCPLUS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OCPLUS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OCPLUS.out.versions  // channel: path(versions.yml)
}
