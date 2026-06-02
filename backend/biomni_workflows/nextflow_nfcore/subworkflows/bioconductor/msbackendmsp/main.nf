#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MsBackendMsp
// Mass spectrometry (MS) data backend supporting import and handling of MS/MS spectra from NIST MSP Fo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MsBackendMsp/inst/doc/MsBackendMsp.R
// Upstream  : BiocParallel, BiocStyle, Spectra
// Downstream: none
//
// Install: BiocManager::install("MsBackendMsp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSBACKENDMSP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msbackendmsp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msbackendmsp:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-msbackendmsp:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msbackendmsp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msbackendmsp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msbackendmsp_plots.pdf"),    emit: plots, optional: true
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

    # --- spectra Variables [] ---
    # Key functions: spectraVariables, spectraVariableMapping, Spectra, tempfile, export
    spectraVariables(sp)
    spectraVariableMapping(MsBackendMsp())
    mona <- system.file("extdata", "minimona.msp", package = "MsBackendMsp")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msbackendmsp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msbackendmsp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msbackendmsp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSBACKENDMSP:", paste0("    msbackendmsp: ", packageVersion("MsBackendMsp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msbackendmsp_results.csv
    touch ${prefix}_msbackendmsp_output.rds
    echo "BIOC_MSBACKENDMSP:" > versions.yml
    echo "    msbackendmsp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSBACKENDMSP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSBACKENDMSP(ch_input)

    emit:
    results  = BIOC_MSBACKENDMSP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSBACKENDMSP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSBACKENDMSP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSBACKENDMSP.out.versions  // channel: path(versions.yml)
}
