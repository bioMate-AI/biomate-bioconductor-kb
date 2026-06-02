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
    library(MsBackendMassbank)
    library(Spectra)
    library(jsonlite)

    # --- Metadata Extraction and Cleaning [] ---
    # Key functions: Spectra, spectraVariables, dropNaSpectraVariables
    metaDataBlocks <- data.frame(
        metadata = c("ac", "ch", "sp", "ms", "record", "pk", "comment"),
        read = rep(TRUE, 7)
    )
    sps_meta <- Spectra(
        fls,
        source = MsBackendMassbank(),
        backend = MsBackendDataFrame(),
        metaBlock = metaDataBlocks
    )
    all_vars <- spectraVariables(sps_meta)
    sps_clean <- dropNaSpectraVariables(sps_meta)


    # --- Database Backend Connection [] ---
    # Key functions: MsBackendMassbankSql, Spectra, spectraVariables
    con <- dbConnect(
        SQLite(),
        system.file("sql", "minimassbank.sqlite", package = "MsBackendMassbank")
    )
    mb <- Spectra(con, source = MsBackendMassbankSql())
    db_vars <- spectraVariables(mb)


    # --- Spectra Filtering and Querying [] ---
    # Key functions: msLevel, mz, intensity
    levels <- msLevel(mb)
    mzs <- mz(mb)
    ints <- intensity(mb)
    mb_esi <- mb[mb$ionization == "ESI"]


    # --- Spectra Comparison and Matching [] ---
    # Key functions: compareSpectra, compounds
    sims <- compareSpectra(mb[11], mb[-11], FUN = ndotproduct, ppm = 40)
    best_match_idx <- which.max(sims) + 1
    mb_match <- mb[c(11, best_match_idx)]
    cmp_info <- compounds(mb_match)

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
