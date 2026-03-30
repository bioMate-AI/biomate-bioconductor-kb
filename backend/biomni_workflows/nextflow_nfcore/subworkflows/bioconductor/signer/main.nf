#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: signeR
// The signeR package provides an empirical Bayesian approach to mutational signature discovery. It is 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/signeR/inst/doc/signeR-vignette.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("signeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SIGNER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-signer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-signer:2.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-signer:2.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_signer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_signer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_signer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExposureBarplot)
    library(ExposureBoxplot)
    library(ExposureHeat)
    library(Paths)
    library(SignHeat)
    library(SignPlot)
    library(jsonlite)

    # --- Table [] ---
    # Key functions: file
    ---------------------------------------------------------------------
    mut <- read.table(system.file("extdata","21_breast_cancers.mutations.txt",
        package="signeR"), header=TRUE, check.names=FALSE)
    opp <- read.table(system.file("extdata","21_breast_cancers.opportunity.txt",
        package="signeR"))
    # --- Matrix [] ---
    # Key functions: file
    ---------------------------------------------------------------------
    Pmatrix <- as.matrix(read.table(system.file("extdata","Cosmic_signatures_BRC.txt",
        package="signeR"), sep="\t", check.names=FALSE))
    # --- Paths [] ---
    # Key functions: Paths
    ---------------------------------------------------------------------
    Paths(signatures$SignExposures)
    # --- Signplot [] ---
    # Key functions: SignPlot
    ---------------------------------------------------------------------
    SignPlot(signatures$SignExposures)
    # --- Signheat [] ---
    # Key functions: SignHeat
    ---------------------------------------------------------------------
    SignHeat(signatures$SignExposures)
    # --- Exposureboxplot [] ---
    # Key functions: ExposureBoxplot
    ---------------------------------------------------------------------
    ExposureBoxplot(signatures$SignExposures)
    # --- Exposurebarplot [] ---
    # Key functions: ExposureBarplot
    ---------------------------------------------------------------------
    ExposureBarplot(signatures$SignExposures)
    # --- Exposureheat [] ---
    # Key functions: ExposureHeat
    ---------------------------------------------------------------------
    ExposureHeat(signatures$SignExposures)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_signer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_signer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_signer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SIGNER:", paste0("    signer: ", packageVersion("signeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_signer_results.csv
    touch ${prefix}_signer_output.rds
    echo "BIOC_SIGNER:" > versions.yml
    echo "    signer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SIGNER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SIGNER(ch_input)

    emit:
    results  = BIOC_SIGNER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SIGNER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SIGNER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SIGNER.out.versions  // channel: path(versions.yml)
}
