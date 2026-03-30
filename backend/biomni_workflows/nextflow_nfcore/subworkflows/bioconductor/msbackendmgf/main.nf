#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MsBackendMgf
// Mass spectrometry (MS) data backend supporting import and export of MS/MS spectra data from Mascot G
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MsBackendMgf/inst/doc/MsBackendMgf.R
// Upstream  : BiocStyle, Spectra
// Downstream: none
//
// Install: BiocManager::install("MsBackendMgf")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSBACKENDMGF {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msbackendmgf"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msbackendmgf:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-msbackendmgf:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msbackendmgf_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msbackendmgf_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msbackendmgf_plots.pdf"),    emit: plots, optional: true
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
    library(MsBackendMgf)
    fls <- dir(system.file("extdata", package = "MsBackendMgf"),
    # --- Spectra [] ---
    # Key functions: Spectra
    sps <- Spectra(fls, source = MsBackendMgf())
    # --- spectra Variables [] ---
    # Key functions: spectraVariables
    spectraVariables(sps)
    # --- spectra Variable Mapping [] ---
    # Key functions: spectraVariableMapping
    spectraVariableMapping(MsBackendMgf())
    # --- Spectra [] ---
    # Key functions: Spectra
    sps <- Spectra(fls, source = MsBackendMgf(), mapping = map)
    # --- intensity [] ---
    # Key functions: intensity
    mz(sps)
    intensity(sps)
    # --- tempfile [] ---
    # Key functions: tempfile, export
    fl <- tempfile()
    export(sps, backend = MsBackendMgf(), file = fl, mapping = map)
    # --- export [] ---
    # Key functions: export, selectSpectraVariables
    readLines(fl)[1:12]
    export(sps, backend = MsBackendMgf(), file = fl)
    readLines(fl)[1:12]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msbackendmgf_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msbackendmgf_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msbackendmgf_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSBACKENDMGF:", paste0("    msbackendmgf: ", packageVersion("MsBackendMgf"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msbackendmgf_results.csv
    touch ${prefix}_msbackendmgf_output.rds
    echo "BIOC_MSBACKENDMGF:" > versions.yml
    echo "    msbackendmgf: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSBACKENDMGF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSBACKENDMGF(ch_input)

    emit:
    results  = BIOC_MSBACKENDMGF.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSBACKENDMGF.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSBACKENDMGF.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSBACKENDMGF.out.versions  // channel: path(versions.yml)
}
