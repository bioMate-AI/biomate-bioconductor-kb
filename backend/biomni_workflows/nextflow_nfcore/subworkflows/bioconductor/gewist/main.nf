#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GEWIST
// This 'GEWIST' package provides statistical tools to efficiently optimize SNP prioritization for gene
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GEWIST/inst/doc/GEWIST.R
// Upstream  : car
// Downstream: none
//
// Install: BiocManager::install("GEWIST")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GEWIST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gewist"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gewist:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gewist:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gewist_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gewist_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gewist_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GEWIST)
    library(jsonlite)

    # --- Effect Size Distribution Analysis [] ---
    # Key functions: effectPDF
    weibull_exp <- effectPDF(
        distribution = "weibull",
        parameter1 = 0.8,
        parameter2 = 0.3,
        parameter3 = NULL,
        p = 0.1,
        N = 10000,
        theta_c = 0.1,
        M = 350000,
        K = 10000,
        nb_incr = 50,
        range = c(0.00025, 0.003),
        verbose = FALSE
    )


    # --- Optimal Threshold Estimation for SNP Set [] ---
    # Key functions: gewistLevene
    nb_snps <- 50
    maf <- seq(0.05, 0.5, length.out = nb_snps)
    optimal_pvals <- numeric(nb_snps)
    for (i in seq_len(nb_snps)) {
        res <- gewistLevene(
            p = maf[i],
            N = 10000,
            theta_gc = 0.002,
            theta_c = 0.15,
            M = 100000,
            verbose = FALSE
        )
        optimal_pvals[i] <- res$Optimal_pval
    }

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gewist_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gewist_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gewist_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GEWIST:", paste0("    gewist: ", packageVersion("GEWIST"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gewist_results.csv
    touch ${prefix}_gewist_output.rds
    echo "BIOC_GEWIST:" > versions.yml
    echo "    gewist: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GEWIST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GEWIST(ch_input)

    emit:
    results  = BIOC_GEWIST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GEWIST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GEWIST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GEWIST.out.versions  // channel: path(versions.yml)
}
