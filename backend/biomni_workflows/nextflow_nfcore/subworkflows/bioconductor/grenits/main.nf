#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GRENITS
// The package offers four network inference statistical models using Dynamic Bayesian Networks and Gib
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GRENITS/inst/doc/GRENITS_package.R
// Upstream  : network
// Downstream: none
//
// Install: BiocManager::install("GRENITS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GRENITS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-grenits"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-grenits:1.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-grenits:1.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_grenits_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_grenits_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_grenits_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRENITS)
    library(Time)
    library(jsonlite)

    # --- Network Inference [Network Inference] ---
    # Key functions: LinearNet
    data(Athaliana_ODE)
    output.folder <- file.path(tempdir(), "Example_LinearNet")
    LinearNet(
        output.folder = output.folder,
        data = Athaliana_ODE
    )

    # --- Statistical Analysis [Statistical Analysis] ---
    # Key functions: analyse.output
    output.folder <- file.path(tempdir(), "Example_LinearNet")
    analyse.output(output.folder)

    # --- Convergence Diagnostics [Convergence Diagnostics] ---
    # Key functions: read.chain
    output.folder <- file.path(tempdir(), "Example_LinearNet")
    chain1 <- read.chain(output.folder, 1)
    chain2 <- read.chain(output.folder, 2)
    gamma1 <- colMeans(chain1$gamma)
    gamma2 <- colMeans(chain2$gamma)
    plot(
        x = gamma1, y = gamma2,
        xlab = "chain1", ylab = "chain2",
        main = "Convergence plot for link probabilities",
        xlim = c(0, 1), ylim = c(0, 1)
    )

    # --- Network Probability Extraction [Network Probability Extraction] ---
    # Key functions: analyse.output
    output.folder <- file.path(tempdir(), "Example_LinearNet")
    prob.file <- file.path(output.folder, "NetworkProbability_Matrix.txt")
    prob.mat <- read.table(prob.file)
    inferred.net <- 1 * (prob.mat > 0.8)
    prob.list.file <- file.path(output.folder, "NetworkProbability_List.txt")
    prob.list <- read.table(prob.list.file, header = TRUE)
    above.threshold <- prob.list[prob.list[, 3] > 0.8, ]


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_grenits_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_grenits_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_grenits_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GRENITS:", paste0("    grenits: ", packageVersion("GRENITS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_grenits_results.csv
    touch ${prefix}_grenits_output.rds
    echo "BIOC_GRENITS:" > versions.yml
    echo "    grenits: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GRENITS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GRENITS(ch_input)

    emit:
    results  = BIOC_GRENITS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GRENITS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GRENITS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GRENITS.out.versions  // channel: path(versions.yml)
}
