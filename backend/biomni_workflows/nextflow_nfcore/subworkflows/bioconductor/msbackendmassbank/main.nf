#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MsBackendMassbank
// Mass spectrometry (MS) data backend supporting import and export of MS/MS library spectra from MassB
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MsBackendMassbank/inst/doc/MsBackendMassbank.R
// Upstream  : BiocStyle, MsCoreUtils, RMariaDB, RSQLite, Spectra
// Downstream: none
//
// Install: BiocManager::install("MsBackendMassbank")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSBACKENDMASSBANK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msbackendmassbank"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msbackendmassbank:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-msbackendmassbank:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msbackendmassbank_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msbackendmassbank_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msbackendmassbank_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Spectra)
    library(jsonlite)

    # --- dir [] ---
    # Key functions: dir
    library(Spectra)
    library(MsBackendMassbank)
    fls <- dir(system.file("extdata", package = "MsBackendMassbank"),
    # --- Spectra [] ---
    # Key functions: Spectra
    sps <- Spectra(fls[1],
    source = MsBackendMassbank(),
    backend = MsBackendDataFrame())
    # --- spectra Variables [] ---
    # Key functions: spectraVariables
    spectraVariables(sps)
    # --- Spectra [] ---
    # Key functions: Spectra, spectraVariables
    sps <- Spectra(fls[-1],
    source = MsBackendMassbank(),
    backend = MsBackendDataFrame())
    # --- intensity [] ---
    # Key functions: intensity
    mz(sps)
    intensity(sps)
    # --- Spectra [] ---
    # Key functions: Spectra
    sps <- Spectra(fls, source = MsBackendMassbank(), nonStop = TRUE)
    # --- db Connect [] ---
    # Key functions: dbConnect
    library(RMariaDB)
    con <- dbConnect(MariaDB(), host = "localhost", user = "massbank",
    # --- db Connect [] ---
    # Key functions: dbConnect, Spectra, spectraVariables, compareSpectra
    library(RSQLite)
    con <- dbConnect(SQLite(), system.file("sql", "minimassbank.sqlite",
    mb <- Spectra(con, source = MsBackendMassbankSql())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msbackendmassbank_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msbackendmassbank_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msbackendmassbank_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSBACKENDMASSBANK:", paste0("    msbackendmassbank: ", packageVersion("MsBackendMassbank"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msbackendmassbank_results.csv
    touch ${prefix}_msbackendmassbank_output.rds
    echo "BIOC_MSBACKENDMASSBANK:" > versions.yml
    echo "    msbackendmassbank: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSBACKENDMASSBANK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSBACKENDMASSBANK(ch_input)

    emit:
    results  = BIOC_MSBACKENDMASSBANK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSBACKENDMASSBANK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSBACKENDMASSBANK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSBACKENDMASSBANK.out.versions  // channel: path(versions.yml)
}
