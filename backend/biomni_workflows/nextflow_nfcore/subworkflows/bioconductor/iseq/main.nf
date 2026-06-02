#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iSeq
// Bayesian hidden Ising models are implemented to identify IP-enriched genomic regions from ChIP-seq d
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iSeq/inst/doc/iSeq.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("iSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-iseq:1.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-iseq:1.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_iseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(iSeq)
    library(jsonlite)

    # --- Bayesian Modeling with iSeq1 [] ---
    # Key functions: iSeq1
    res1 <- iSeq1(
        Y = tagct22[, 1:4],
        gap = 200,
        burnin = 200,
        sampling = 1000,
        ctcut = 0.95,
        a0 = 1, b0 = 1, a1 = 5, b1 = 1,
        k0 = 3, mink = 0, maxk = 10,
        normsd = 0.1, verbose = FALSE
    )


    # --- Peak Detection and Region Identification [] ---
    # Key functions: peakreg
    reg1 <- peakreg(
        chrpos = tagct22[, 1:3],
        count = (tagct22[, 5:6] - tagct22[, 7:8]),
        pp = res1$pp,
        cutoff = 0.5,
        method = "ppcut",
        maxgap = 200
    )


    # --- Hidden Markov Modeling with iSeq2 [] ---
    # Key functions: iSeq2
    res2 <- iSeq2(
        Y = tagct22[, 1:4],
        gap = 200,
        burnin = 100,
        sampling = 500,
        winsize = 2,
        ctcut = 0.95,
        a0 = 1, b0 = 1, a1 = 5, b1 = 1,
        k = 1.0, verbose = FALSE
    )


    # --- Visualization of Enriched Regions [] ---
    # Key functions: plotreg
    ID <- (reg1[1, 4]):(reg1[1, 5])
    plotreg(
        tagct22[ID, 2:3],
        tagct22[ID, 5:6],
        tagct22[ID, 7:8],
        peak = reg1[1, 6]
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_iseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_iseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_iseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISEQ:", paste0("    iseq: ", packageVersion("iSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iseq_results.csv
    touch ${prefix}_iseq_output.rds
    echo "BIOC_ISEQ:" > versions.yml
    echo "    iseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ISEQ(ch_input)

    emit:
    results  = BIOC_ISEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISEQ.out.versions  // channel: path(versions.yml)
}
