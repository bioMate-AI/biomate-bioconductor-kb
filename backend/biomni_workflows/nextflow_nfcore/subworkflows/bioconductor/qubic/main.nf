#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: QUBIC
// The core function of this R package is to provide the implementation of the well-cited and well-revi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/QUBIC/inst/doc/qubic_vignette.R
// Upstream  : QUBICdata, RColorBrewer
// Downstream: none
//
// Install: BiocManager::install("QUBIC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QUBIC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-qubic"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-qubic:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-qubic:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(deseqresults)

    output:
    tuple val(meta), path("${meta.id}_qubic_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_qubic_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_qubic_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(QUBIC)
    library(jsonlite)


    # --- Comment=na [] ---
    # Key functions: citation
    citation("QUBIC")

    # --- Random [] ---
    # Key functions: rnorm, qudiscretize, cond, gene
    library(QUBIC)
    set.seed(1)
    # Create a random matrix
    test <- matrix(rnorm(10000), 100, 100)
    colnames(test) <- paste("cond", 1:100, sep = "_")
    rownames(test) <- paste("gene", 1:100, sep = "_")

    # Discretization
    matrix1 <- test[1:7, 1:4]
    matrix1

    matrix2 <- qudiscretize(matrix1)
    matrix2

    # Fill bicluster blocks

    # --- Yeast [] ---
    # Key functions: qudiscretize, system.time, biclust, BCQU, summary
    library(QUBIC)
    data(BicatYeast)

    # Discretization
    matrix1 <- BicatYeast[1:7, 1:4]
    matrix1

    matrix2 <- qudiscretize(matrix1)
    matrix2

    # QUBIC
    x <- BicatYeast
    system.time(res <- biclust::biclust(x, method = BCQU()))

    summary(res)

    # --- Ecoli [] ---
    # Key functions: qudiscretize, biclust, BCQU, system.time, ecoli
    library(QUBIC)
    library(QUBICdata)
    data("ecoli", package = "QUBICdata")

    # Discretization
    matrix1 <- ecoli[1:7, 1:4]
    matrix1

    matrix2 <- qudiscretize(matrix1)
    matrix2

    # QUBIC
    res <- biclust::biclust(ecoli, method = BCQU(), r = 1, q = 0.06, c = 0.95, o = 100, 
        f = 0.25, k = max(ncol(ecoli)%/%20, 2))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_qubic_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_qubic_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_qubic_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QUBIC:", paste0("    qubic: ", packageVersion("QUBIC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qubic_results.csv
    touch ${prefix}_qubic_output.rds
    echo "BIOC_QUBIC:" > versions.yml
    echo "    qubic: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QUBIC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(deseqresults) ]

    main:
    BIOC_QUBIC(ch_input)

    emit:
    results  = BIOC_QUBIC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QUBIC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QUBIC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QUBIC.out.versions  // channel: path(versions.yml)
}
