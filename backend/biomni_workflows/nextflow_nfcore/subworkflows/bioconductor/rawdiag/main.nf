#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rawDiag
// Optimizing methods for liquid chromatography coupled to mass spectrometry (LC-MS) poses a nontrivial
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rawDiag/inst/doc/rawDiag.R
// Upstream  : ExperimentHub
// Downstream: none
//
// Install: BiocManager::install("rawDiag")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RAWDIAG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rawdiag"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rawdiag:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rawdiag:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rawdiag_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rawdiag_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rawdiag_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExperimentHub)
    library(jsonlite)

    # --- system2 [] ---
    # Key functions: system2
    if (Sys.info()["sysname"] %in% c("Darwin", "Linux")) {
    system2("mono", args = '--version', stdout = TRUE)
    # --- check Rawrr [] ---
    # Key functions: checkRawrr, installRawFileReaderDLLs, installRawrrExe
    rawDiag::checkRawrr()
    if (isFALSE(rawrr::.checkDllInMonoPath())){
    rawrr::installRawFileReaderDLLs()
    # --- rawrr Assembly Path [] ---
    # Key functions: rawrrAssemblyPath
    rawrr::rawrrAssemblyPath()
    rawrr::rawrrAssemblyPath() |> list.files()
    # --- Access ExperimentHub data [] ---
    # Key functions: ExperimentHub, normalizePath
    library(ExperimentHub)
    ExperimentHub::ExperimentHub() -> eh
    normalizePath(eh[["EH3222"]]) -> EH3222
    # --- build Raw Diag Shiny App [] ---
    # Key functions: buildRawDiagShinyApp
    dirname() |>
    rawDiag::buildRawDiagShinyApp() -> app

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rawdiag_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rawdiag_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rawdiag_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RAWDIAG:", paste0("    rawdiag: ", packageVersion("rawDiag"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rawdiag_results.csv
    touch ${prefix}_rawdiag_output.rds
    echo "BIOC_RAWDIAG:" > versions.yml
    echo "    rawdiag: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RAWDIAG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RAWDIAG(ch_input)

    emit:
    results  = BIOC_RAWDIAG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RAWDIAG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RAWDIAG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RAWDIAG.out.versions  // channel: path(versions.yml)
}
