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
    library(Time)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data(Athaliana_ODE)
    dim(Athaliana_ODE)
    # --- Ts [] ---
    # Key functions: ts, Time
    # Load A. thaliana circadian clock ODE generated data
    plot.ts( t(Athaliana_ODE), plot.type = "single", col = 1:5,  xlim = c(0,65),
    	main = "Circadian Clock Network \n ODE simulated data",
    	 xlab = "Time (h)",  ylab = "Expression")
    legend("topright", rownames(Athaliana_ODE), lty = 1, col = 1:5)
    # --- Output [] ---
    # Key functions: output
    # Analyse raw results, place analysis plots and files in output.folder
    analyse.output(output.folder)
    # --- Chain [] ---
    # Key functions: chain, colMeans
    chain1 <- read.chain(output.folder,1)
    chain2 <- read.chain(output.folder,2)
    gamma1 <- colMeans(chain1$gamma)
    gamma2 <- colMeans(chain2$gamma)
    # --- Network [] ---
    # Key functions: network, interaction
    library(network)
    inferred.net <- network(inferred.net)
    par(mfrow = c(1,2), cex = 1.76, cex.lab = 1.3, cex.main = 1.4)
    # Plot cut off
    prob.vec <- sort(as.vector(as.matrix(prob.mat)), T)

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
