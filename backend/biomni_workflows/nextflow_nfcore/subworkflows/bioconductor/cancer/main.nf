#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: canceR
// The package is user friendly interface based on the cgdsr and other modeling packages to explore, co
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/canceR/inst/doc/canceR.html
// Upstream  : biocManager, devtools
// Downstream: none
//
// Install: BiocManager::install("canceR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CANCER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cancer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cancer:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cancer:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cancer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cancer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cancer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(canceR)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: insall
    sudo apt-get insall ("r-cran-tcltk2","r-cran-tkrplot")
    sudo apt-get install(Tk-table, BWidget)
    sudo apt-get install libcurl4-openssl-dev
    sudo apt-get install r-cran-xml
    # --- Code Block 3 [] ---
    # Key functions: install_git
    library(devtools)
    devtools::install_git("kmezhoud/canceR")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cancer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cancer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cancer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CANCER:", paste0("    cancer: ", packageVersion("canceR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cancer_results.csv
    touch ${prefix}_cancer_output.rds
    echo "BIOC_CANCER:" > versions.yml
    echo "    cancer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CANCER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CANCER(ch_input)

    emit:
    results  = BIOC_CANCER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CANCER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CANCER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CANCER.out.versions  // channel: path(versions.yml)
}
