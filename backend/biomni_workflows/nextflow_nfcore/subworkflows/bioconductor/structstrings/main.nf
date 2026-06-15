#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Structstrings
// The Structstrings package implements the widely used dot bracket annotation for storing base pairing
//
// Input: structures.txt (dot-bracket annotations, one per line), sequences.fasta (matching RNA sequences in FASTA, same order)
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Structstrings/inst/doc/Structstrings.R
// Upstream  : none
// Downstream: tRNA, tRNAdbImport
//
// Install: BiocManager::install("Structstrings")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_STRUCTSTRINGS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-structstrings"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_structstrings_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_structstrings_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_structstrings_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Structstrings", "Biostrings", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(Structstrings)
    library(Biostrings)
    library(jsonlite)

    # --- Load user-provided inputs ---
    # structures.txt : dot-bracket secondary-structure annotations, one structure
    #                  per line (e.g. "(((((.(..(((.........)))...)))))").
    # sequences.fasta: matching RNA sequences in FASTA format (one record per
    #                  structure, in the same order).
    dbs  <- DotBracketStringSet(readLines("structures.txt"))
    nseq <- readRNAStringSet("sequences.fasta")

    # --- get Base Pairing [] ---
    # Key functions: getBasePairing
    dbdfl <- getBasePairing(dbs)
    # --- get Loop Indices [] ---
    # Key functions: getLoopIndices, all
    loopids <- getLoopIndices(dbs, bracket.type = 1L)
    loopids2 <- getLoopIndices(dbdfl, bracket.type = 1L)
    all(loopids == loopids2)
    # --- get Dot Bracket [] ---
    # Key functions: getDotBracket, unlist, relist
    rec_dbs <- getDotBracket(dbdfl)
    dbdf <- unlist(dbdfl)
    dbdfl2 <- relist(dbdf,dbdfl)
    # --- Dot Bracket String [] ---
    # Key functions: DotBracketString, getDotBracket
    db <- DotBracketString("((((....[[[))))....((((....<<<<...))))]]]....>>>>...")
    getDotBracket(getBasePairing(db), force = TRUE)
    # --- structured rna string [] ---
    # Key functions: StructuredRNAStringSet, dotbracket
    sdbs <- StructuredRNAStringSet(nseq,dbs)
    # --- structured rna string base pairing [] ---
    # Key functions: getBasePairing
    dbdfl <- getBasePairing(sdbs)
    dbdfl <- getBasePairing(sdbs, return.sequence = TRUE)
    sessionInfo()

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
        write.csv(as.data.frame(.main), "${prefix}_structstrings_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_structstrings_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_structstrings_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_STRUCTSTRINGS:", paste0("    structstrings: ", as.character(packageVersion("Structstrings")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_structstrings_results.csv
    touch ${prefix}_structstrings_output.rds
    echo "BIOC_STRUCTSTRINGS:" > versions.yml
    echo "    structstrings: 0.0.0" >> versions.yml
    """
}


workflow BIOC_STRUCTSTRINGS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_STRUCTSTRINGS(ch_input)

    emit:
    results  = BIOC_STRUCTSTRINGS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_STRUCTSTRINGS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_STRUCTSTRINGS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_STRUCTSTRINGS.out.versions  // channel: path(versions.yml)
}
