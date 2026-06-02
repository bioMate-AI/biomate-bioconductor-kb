#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: basilisk
// Installs a self-contained conda instance that is managed by the R/Bioconductor installation machiner
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/basilisk/inst/doc/motivation.R
// Upstream  : BiocStyle, reticulate
// Downstream: scviR
//
// Install: BiocManager::install("basilisk")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BASILISK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-basilisk"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-basilisk:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-basilisk:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_basilisk_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_basilisk_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_basilisk_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BasiliskEnvironment)
    library(basilisk)
    library(jsonlite)


    # --- Eval=false [] ---
    # Key functions: setDefaultClusterOptions, createLocalBasiliskEnv, sequential, windows
    #  parallel:::setDefaultClusterOptions(setup_strategy = "sequential")

    ## -----------------------------------------------------------------------------
    if (.Platform$OS.type != "windows") {
    tmp <- createLocalBasiliskEnv("basilisk-vignette-test",
        packages=c("scikit-learn=1.1.1", "numpy=1.22.1"))
    }

    # --- Error=false [] ---
    # Key functions: rnorm, basiliskRun, function, import, TruncatedSVD, fit, windows, sklearn.decomposition
    if (.Platform$OS.type != "windows") {
    x <- matrix(rnorm(1000), ncol=10)
    basiliskRun(env=tmp, fun=function(mat) {
        module <- reticulate::import("sklearn.decomposition")
        runner <- module$TruncatedSVD()
        output <- runner$fit(mat) 
        output$singular_values_
    }, mat = x, testload="scipy.optimize")
    }

    # --- Error=false [] ---
    # Key functions: getwd, file.exists, getCondaDir, getCondaBinary, conda_install, windows
    if (.Platform$OS.type != "windows") {
    library(reticulate)

    # In this case, we'll use reticulate directly to construct our conda
    # environment; though we'll cheat a little and use basilisk's conda
    # installation, otherwise reticulate will try to install its own miniconda.
    tmp2 <- file.path(getwd(), "basilisk-vignette-test2")
    if (!file.exists(tmp2)) {
        conda.bin <- file.path(
            basilisk.utils::getCondaDir(), 
            basilisk.utils::getCondaBinary()
        )
        conda_install(tmp2, 
            packages=c("scipy==1.9.1"), 
            python_version="3.10", 

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_basilisk_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_basilisk_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_basilisk_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BASILISK:", paste0("    basilisk: ", packageVersion("basilisk"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_basilisk_results.csv
    touch ${prefix}_basilisk_output.rds
    echo "BIOC_BASILISK:" > versions.yml
    echo "    basilisk: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BASILISK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BASILISK(ch_input)

    emit:
    results  = BIOC_BASILISK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BASILISK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BASILISK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BASILISK.out.versions  // channel: path(versions.yml)
}
