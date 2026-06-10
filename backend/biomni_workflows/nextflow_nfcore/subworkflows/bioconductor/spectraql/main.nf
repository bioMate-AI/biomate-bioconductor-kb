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
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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

    # --- Spectra Filtering by Properties [] ---
    # Key functions: query
    dda_rt <- query(dda, "QUERY * WHERE RTMIN = 200 AND RTMAX = 300")
    dda_pmz <- query(
        dda,
        "query * where ms2prec = 278.093:tolerancemz=0:toleranceppm=30"
    )
    dda_combined <- query(
        dda,
        paste0("query * where rtmin = 200 and rtmax = 300 and ",
               "ms2prec = 278.093:toleranceppm = 30")
    )

    # --- Peak Data Extraction [] ---
    # Key functions: query
    pks <- query(dda, "query ms2data where rtmin = 200 and rtmax = 300")
    first_peak_matrix <- pks[[1L]]

    # --- Total Ion Chromatogram Generation [] ---
    # Key functions: query
    tic <- query(dda, "query scansum(ms1data)")

    # --- Extracted Ion Chromatogram Generation [] ---
    # Key functions: query
    ic <- query(
        dda,
        "query scansum(ms1data) filter ms1mz = 219.095:tolerancemz=0.1"
    )
    ic_rt_filtered <- query(
        dda,
        paste0("query scansum(ms1data) where rtmin = 235 and rtmax = 250",
               " filter ms1mz = 219.095:tolerancemz=0.1")
    )

    # --- Scan Information Retrieval [] ---
    # Key functions: query
    si <- query(dda, "query scaninfo(*) where rtmin = 300 and rtmax = 500")


    # --- Save outputs ---
    .objs <- setdiff(ls(), c("args", "prefix", ".objs"))
    .cells <- function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                            if (is.data.frame(x) || is.matrix(x)) prod(dim(x)) else -1 }
    .dfs  <- Filter(function(v) is.data.frame(tryCatch(get(v), error = function(e) NULL)), .objs)
    .tabs <- Filter(function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                                  is.data.frame(x) || is.matrix(x) }, .objs)
    .cand <- if (length(.dfs) > 0) .dfs else .tabs
    if (length(.cand) > 0) {
        .main <- get(.cand[[ which.max(sapply(.cand, .cells)) ]])
        write.csv(as.data.frame(.main), "${prefix}_spectraql_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_spectraql_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_spectraql_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPECTRAQL:", paste0("    spectraql: ", as.character(packageVersion("SpectraQL")))),
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
