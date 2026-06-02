#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MsBackendMetaboLights
// MetaboLights is one of the main public repositories for storage of metabolomics experiments, which i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MsBackendMetaboLights/inst/doc/MsBackendMetaboLights.R
// Upstream  : BiocStyle, Spectra
// Downstream: none
//
// Install: BiocManager::install("MsBackendMetaboLights")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSBACKENDMETABOLIGHTS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msbackendmetabolights"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msbackendmetabolights:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-msbackendmetabolights:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msbackendmetabolights_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msbackendmetabolights_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msbackendmetabolights_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MsBackendMetaboLights)
    library(Spectra)
    library(jsonlite)

    # --- Initialize Spectra Backend [] ---
    # Key functions: MsBackendMetaboLights, Spectra
    be <- MsBackendMetaboLights()
    s <- Spectra(
        "MTBLS39",
        filePattern = "63A.cdf",
        source = be
    )


    # --- Extract Spectra Metadata [] ---
    # Key functions: spectraVariables, spectraData
    vars <- spectraVariables(s)
    meta <- spectraData(
        s,
        columns = c(
            "mtbls_id", 
            "mtbls_assay_name", 
            "derived_spectral_data_file"
        )
    )


    # --- Synchronize and Cache Data [] ---
    # Key functions: mtbls_sync, mtbls_sync_data_files, mtbls_cached_data_files
    synced_be <- mtbls_sync(s@backend)
    res <- mtbls_sync_data_files("MTBLS39", fileName = "AM063A.cdf")
    cached_files <- mtbls_cached_data_files()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msbackendmetabolights_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msbackendmetabolights_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msbackendmetabolights_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSBACKENDMETABOLIGHTS:", paste0("    msbackendmetabolights: ", packageVersion("MsBackendMetaboLights"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msbackendmetabolights_results.csv
    touch ${prefix}_msbackendmetabolights_output.rds
    echo "BIOC_MSBACKENDMETABOLIGHTS:" > versions.yml
    echo "    msbackendmetabolights: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSBACKENDMETABOLIGHTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSBACKENDMETABOLIGHTS(ch_input)

    emit:
    results  = BIOC_MSBACKENDMETABOLIGHTS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSBACKENDMETABOLIGHTS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSBACKENDMETABOLIGHTS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSBACKENDMETABOLIGHTS.out.versions  // channel: path(versions.yml)
}
