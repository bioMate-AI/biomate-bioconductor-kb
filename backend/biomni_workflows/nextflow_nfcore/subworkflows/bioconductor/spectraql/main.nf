#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SpectraQL
// The Mass Spec Query Language (MassQL) is a domain-specific language enabling to express a query and 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SpectraQL/inst/doc/SpectraQL.R
// Upstream  : Spectra, msdata
// Downstream: none
//
// Install: BiocManager::install("SpectraQL")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPECTRAQL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spectraql"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spectraql:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spectraql:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spectraql_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spectraql_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spectraql_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SpectraQL)
    library(jsonlite)

    # --- Table [] ---
    # Key functions: msLevel, rtime
    ---------------------------------------------------------------------
    #' Number of MS1 and MS2 spectra
    table(msLevel(dda))
    #' retention time range
    range(rtime(dda))
    # --- Query [] ---
    # Key functions: query
    ---------------------------------------------------------------------
    dda_rt <- query(dda, "QUERY * WHERE RTMIN = 200 AND RTMAX = 300")
    dda_rt
    # --- Range [] ---
    # Key functions: rtime
    ---------------------------------------------------------------------
    range(rtime(dda_rt))
    # --- Query [] ---
    # Key functions: query
    ---------------------------------------------------------------------
    dda_pmz <- query(
        dda,
        "query * where ms2prec = 278.093:toleancemz=0:toleranceppm=30")
    length(dda_pmz)
    # --- Precursormz [] ---
    # Key functions: precursorMz
    ---------------------------------------------------------------------
    precursorMz(dda_pmz)
    # --- Query [] ---
    # Key functions: query
    ---------------------------------------------------------------------
    dda_rt <- query(dda,
                    paste0("query * where rtmin = 200 and rtmax = 300 and ",
                           "ms2prec = 278.093:toleranceppm = 30"))
    dda_rt
    # --- Query [] ---
    # Key functions: query, scansum
    ---------------------------------------------------------------------
    tic <- query(dda, "query scansum(ms1data)")
    # --- Query [] ---
    # Key functions: query, scaninfo
    ---------------------------------------------------------------------
    si <- query(dda, "query scaninfo(*) where rtmin = 300 and rtmax = 500")
    si
    # --- Query [] ---
    # Key functions: query, scansum
    ---------------------------------------------------------------------
    ic <- query(
        dda, "query scansum(ms1data) filter ms1mz = 219.095:tolerancemz=0.1")
    plot(ic, type = "l", xlab = "scan index")
    # --- Filtermslevel [] ---
    # Key functions: filterMsLevel, filterRt, filterMzValues, ionCount
    ---------------------------------------------------------------------
    res <- dda |>
        filterMsLevel(1L) |>
        filterRt(c(235, 250)) |>
        filterMzValues(219.095, tolerance = 0.1) |>

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spectraql_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spectraql_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spectraql_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPECTRAQL:", paste0("    spectraql: ", packageVersion("SpectraQL"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spectraql_results.csv
    touch ${prefix}_spectraql_output.rds
    echo "BIOC_SPECTRAQL:" > versions.yml
    echo "    spectraql: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPECTRAQL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPECTRAQL(ch_input)

    emit:
    results  = BIOC_SPECTRAQL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPECTRAQL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPECTRAQL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPECTRAQL.out.versions  // channel: path(versions.yml)
}
