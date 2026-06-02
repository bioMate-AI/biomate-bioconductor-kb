#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CARNIVAL
// An upgraded causal reasoning tool from Melas et al in R with updated assignments of TFs' weights fro
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/CARNIVAL/inst/doc/CARNIVAL.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CARNIVAL")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CARNIVAL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-carnival"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-carnival:2.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-carnival:2.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_carnival_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_carnival_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_carnival_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CARNIVAL)
    library(jsonlite)

    # --- Code Block 3 [] ---
    # Key functions: defaultLpSolveCarnivalOptions, create, runVanillaCarnival
    library(CARNIVAL)
    load(file = system.file("toy_perturbations_ex1.RData",
                            package = "CARNIVAL"))
    load(file = system.file("toy_measurements_ex1.RData",
                            package = "CARNIVAL"))
    # --- Code Block 5 [] ---
    # Key functions: defaultLpSolveCarnivalOptions, create, frame
    load(file = system.file("toy_measurements_ex2.RData",
                            package="CARNIVAL"))
    load(file = system.file("toy_network_ex2.RData",
                            package="CARNIVAL"))
    carnivalOptions <- defaultLpSolveCarnivalOptions()
    # --- Code Block 7 [] ---
    # Key functions: defaultLpSolveCarnivalOptions, create, generateLpFileCarnival
    load(file = system.file("toy_perturbations_ex1.RData",
                            package = "CARNIVAL"))
    load(file = system.file("toy_measurements_ex1.RData",
                            package = "CARNIVAL"))
    load(file = system.file("toy_network_ex1.RData",
    # --- Code Block 8 [] ---
    # Key functions: runFromLpCarnival, defaultLpSolveCarnivalOptions
    lpFilename <- "toy_files_vignettes/lpFile_t18_01_53d28_04_2021n4.lp"
    parsedDataFile <- "toy_files_vignettes/parsedData_t18_01_53d28_04_2021n4.RData"
    resultsFromLp <- runFromLpCarnival(lpFile = lpFilename,
                                       parsedDataFile = parsedDataFile,
                                       carnivalOptions = defaultLpSolveCarnivalOptions())
    # --- Code Block 11 [] ---
    # Key functions: 1, namespace
    ## R version 4.4.1 (2024-06-14)
    ## Platform: x86_64-pc-linux-gnu
    ## Running under: Ubuntu 24.04.1 LTS
    ##
    ## Matrix products: default

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_carnival_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_carnival_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_carnival_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CARNIVAL:", paste0("    carnival: ", packageVersion("CARNIVAL"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_carnival_results.csv
    touch ${prefix}_carnival_output.rds
    echo "BIOC_CARNIVAL:" > versions.yml
    echo "    carnival: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CARNIVAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CARNIVAL(ch_input)

    emit:
    results  = BIOC_CARNIVAL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CARNIVAL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CARNIVAL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CARNIVAL.out.versions  // channel: path(versions.yml)
}
