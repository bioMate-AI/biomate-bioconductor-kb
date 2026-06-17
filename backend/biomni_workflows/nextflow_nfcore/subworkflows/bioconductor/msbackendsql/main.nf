#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MsBackendSql
// Store mass-spectrometry (MS) spectra from an mzML file into a SQL
// (SQLite) backend, then query the data back through a Spectra object.
// This is the on-disk / large-data backend for the Spectra ecosystem.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MsBackendSql/inst/doc/MsBackendSql.R
//
// Input: spectra.mzML
// R packages: MsBackendSql, Spectra, RSQLite
// Document-derived real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2


process BIOC_MSBACKENDSQL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msbackendsql"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

    input:
    tuple val(meta), path(spectra_mzml)

    output:
    tuple val(meta), path("${meta.id}_msbackendsql_spectra_variables.csv"), emit: results
    tuple val(meta), path("${meta.id}_msbackendsql_peaks_summary.csv"),     emit: peaks
    tuple val(meta), path("${meta.id}_msbackendsql.sqlite"),                emit: db
    path "versions.yml",                                                    emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("MsBackendSql", "Spectra", "RSQLite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    suppressPackageStartupMessages({
      library(MsBackendSql)
      library(Spectra)
      library(RSQLite)
    })

    mzml <- "${spectra_mzml}"
    stopifnot(file.exists(mzml))

    # --- Create the SQL database from the mzML file(s) ---
    dbfile <- "${prefix}_msbackendsql.sqlite"
    con <- dbConnect(SQLite(), dbfile)
    createMsBackendSqlDatabase(con, mzml)

    # --- Open a Spectra object backed by the SQL database ---
    sps <- Spectra(dbname = dbfile, source = MsBackendOfflineSql(), drv = SQLite())

    # --- Spectra-variable table (core metadata per spectrum) ---
    core <- c("msLevel", "rtime", "precursorMz", "precursorCharge",
              "polarity", "scanIndex", "totIonCurrent")
    have <- intersect(core, spectraVariables(sps))
    sv <- as.data.frame(spectraData(sps, columns = have))
    sv\$spectrum_id <- seq_len(nrow(sv))
    write.csv(sv, "${prefix}_msbackendsql_spectra_variables.csv", row.names = FALSE)

    # --- Per-spectrum peaks summary (n peaks, base peak, m/z range) ---
    pk <- peaksData(sps)
    summ <- do.call(rbind, lapply(seq_along(pk), function(i) {
        m <- pk[[i]]
        if (is.null(m) || nrow(m) == 0)
            return(data.frame(spectrum_id = i, n_peaks = 0L,
                              mz_min = NA_real_, mz_max = NA_real_,
                              base_peak_mz = NA_real_, max_intensity = NA_real_))
        j <- which.max(m[, "intensity"])
        data.frame(spectrum_id = i, n_peaks = nrow(m),
                   mz_min = min(m[, "mz"]), mz_max = max(m[, "mz"]),
                   base_peak_mz = m[j, "mz"], max_intensity = m[j, "intensity"])
    }))
    write.csv(summ, "${prefix}_msbackendsql_peaks_summary.csv", row.names = FALSE)

    dbDisconnect(con)

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSBACKENDSQL:", paste0("    msbackendsql: ", as.character(packageVersion("MsBackendSql")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msbackendsql_spectra_variables.csv
    touch ${prefix}_msbackendsql_peaks_summary.csv
    touch ${prefix}_msbackendsql.sqlite
    echo "BIOC_MSBACKENDSQL:" > versions.yml
    echo "    msbackendsql: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSBACKENDSQL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(spectra_mzml) ]

    main:
    BIOC_MSBACKENDSQL(ch_input)

    emit:
    results  = BIOC_MSBACKENDSQL.out.results
    peaks    = BIOC_MSBACKENDSQL.out.peaks
    db       = BIOC_MSBACKENDSQL.out.db
    versions = BIOC_MSBACKENDSQL.out.versions
}
