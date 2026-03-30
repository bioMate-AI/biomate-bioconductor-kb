#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MPAC
// Multi-omic Pathway Analysis of Cancer (MPAC), integrates multi-omic data for understanding cancer me
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MPAC/inst/doc/MPAC.R
// Upstream  : SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("MPAC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MPAC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mpac"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mpac:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mpac:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mpac_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mpac_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mpac_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MPAC)
    library(jsonlite)

    # --- Data import and preprocessing [] ---
    # Key functions: tempdir, runPrd, runPermPrd, subNtw, ovrGMT, conMtf, pltNeiStt
    a list of igraph objects from `subNtw()`
    subntwl <- system.file('extdata/conMtf/subntwl.rds', package='MPAC') |>readRDS()
    (optional) genes that have CN and RNA data in the input files for PARADIGM
    # --- Object metadata inspection [] ---
    # Key functions: include_graphics, install_github, ppCnInp, ppRnaInp, ppRealInp, ppPermInp, metadata, assays
    collected real IPLs. It is the output from `colRealIPL()`
    realdt <- system.file('extdata/fltByPerm/real.rds', package='MPAC') |> readRDS()
    collected permutation IPLs. It is the output from `colPermIPL()`

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mpac_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mpac_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mpac_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MPAC:", paste0("    mpac: ", packageVersion("MPAC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mpac_results.csv
    touch ${prefix}_mpac_output.rds
    echo "BIOC_MPAC:" > versions.yml
    echo "    mpac: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MPAC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MPAC(ch_input)

    emit:
    results  = BIOC_MPAC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MPAC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MPAC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MPAC.out.versions  // channel: path(versions.yml)
}
