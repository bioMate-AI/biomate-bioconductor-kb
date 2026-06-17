#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SRAdb
// The Sequence Read Archive (SRA) is the largest public repository of sequencing data from the next ge
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SRAdb/inst/doc/SRAdb.R
// Upstream  : Rgraphviz
// Downstream: none
//
// Install: BiocManager::install("SRAdb")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_SRADB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sradb"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sradb_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sradb_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sradb_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("SRAdb", "SQLite", "TABLE_INFO", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(SRAdb)
    library(SQLite)
    library(TABLE_INFO)
    library(jsonlite)

    # --- Database Connection ---
    # Key functions: getSRAdbFile, dbConnect
    sra_db <- getSRAdbFile(
        destdir = tempdir(),
        method = "curl"
    )
    con <- dbConnect(
        RSQLite::SQLite(),
        sra_db
    )

    # --- Metadata Querying ---
    # Key functions: dbGetQuery
    study_query <- paste(
        "SELECT study_accession, study_title",
        "FROM study WHERE study_description LIKE '%Transcriptome%'",
        "LIMIT 10"
    )
    study_meta <- dbGetQuery(
        con,
        study_query
    )

    # --- Accession Conversion ---
    # Key functions: sraConvert
    sra_ids <- c("SRX014819", "SRX014820")
    converted_ids <- sraConvert(
        in_acc = sra_ids,
        out_type = c("run", "study"),
        sra_con = con
    )

    # --- Retrieve FASTQ Information ---
    # Key functions: getFASTQinfo
    run_ids <- c("SRR034311", "SRR034312")
    fastq_info <- getFASTQinfo(
        in_acc = run_ids,
        sra_con = con,
        srcType = "ftp"
    )

    # --- SRA File Search and Download ---
    # Key functions: listSRAfile, getSRA
    sra_files <- listSRAfile(
        in_acc = c("SRR034311"),
        sra_con = con,
        fileType = "sra"
    )
    getSRA(
        search_str = "SRR034311",
        sra_con = con,
        destDir = tempdir()
    )


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
        write.csv(as.data.frame(.main), "${prefix}_sradb_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_sradb_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_sradb_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_SRADB:", paste0("    sradb: ", as.character(packageVersion("SRAdb")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sradb_results.csv
    touch ${prefix}_sradb_output.rds
    echo "BIOC_SRADB:" > versions.yml
    echo "    sradb: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SRADB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SRADB(ch_input)

    emit:
    results  = BIOC_SRADB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SRADB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SRADB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SRADB.out.versions  // channel: path(versions.yml)
}
