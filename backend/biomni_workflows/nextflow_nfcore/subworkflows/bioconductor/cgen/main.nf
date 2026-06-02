#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CGEN
// This is a package for analysis of case-control data in genetic epidemiology. It provides a set of st
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CGEN/inst/doc/vignette.R
// Upstream  : cluster
// Downstream: none
//
// Install: BiocManager::install("CGEN")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CGEN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cgen"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cgen:3.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cgen:3.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cgen_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cgen_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cgen_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CGEN)
    library(jsonlite)

    # --- Hardy-Weinberg Equilibrium Testing [snphwe] ---
    # Key functions: snphwe
    n_AA <- c(120, 150, 90)
    n_AB <- c(50, 40, 60)
    n_BB <- c(10, 5, 15)
    hwe_pvals <- snphwe(n_AA, n_AB, n_BB)
    valid_snps <- hwe_pvals >= 0.001

    # --- Case-Control Matching [getMatchedSets] ---
    # Key functions: getMatchedSets
    Xdata <- data.frame(
        case.control = rbinom(100, 1, 0.5),
        ethnic.group = sample(1:3, 100, replace = TRUE),
        age.group_1 = sample(1:4, 100, replace = TRUE),
        gynSurgery.history = rbinom(100, 1, 0.2),
        BRCA.history = rbinom(100, 1, 0.1)
    )
    size <- ifelse(Xdata$ethnic.group == 3, 3, 4)
    d <- cluster::daisy(Xdata[, c("age.group_1", "gynSurgery.history", "BRCA.history")])
    mx <- getMatchedSets(d, CC = TRUE, NN = TRUE, ccs.var = Xdata$case.control,
                         strata.var = Xdata$ethnic.group, size = size, fixed = TRUE)
    Xdata$CCStrat <- mx$CC
    Xdata$NNStrat <- mx$NN

    # --- Gene-Environment Interaction Analysis [logistic.nci] ---
    # Key functions: logistic.nci
    study_data <- data.frame(
        case_control = rbinom(500, 1, 0.5),
        exposure = rbinom(500, 1, 0.4),
        snp_allele = rbinom(500, 2, 0.3),
        age = rnorm(500, mean = 45, sd = 12)
    )
    fit_res <- logistic.nci(study_data, response.var = "case_control",
                            exposure.var = "exposure", genetic.var = "snp_allele",
                            extra.var = "age")

    # --- Additive Interaction Testing [additive.test] ---
    # Key functions: additive.test
    add_test <- additive.test(study_data, response.var = "case_control",
                              exposure.var = "exposure", genetic.var = "snp_allele")


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cgen_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cgen_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cgen_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CGEN:", paste0("    cgen: ", packageVersion("CGEN"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cgen_results.csv
    touch ${prefix}_cgen_output.rds
    echo "BIOC_CGEN:" > versions.yml
    echo "    cgen: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CGEN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CGEN(ch_input)

    emit:
    results  = BIOC_CGEN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CGEN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CGEN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CGEN.out.versions  // channel: path(versions.yml)
}
