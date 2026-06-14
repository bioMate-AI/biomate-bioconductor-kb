#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: txdbmaker
// A set of tools for making TxDb objects from genomic annotations from various sources (e.g. UCSC, Ens
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/txdbmaker/inst/doc/txdbmaker.R
// Upstream  : none
// Downstream: mygene
//
// Install: BiocManager::install("txdbmaker")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_TXDBMAKER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-txdbmaker"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_txdbmaker_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_txdbmaker_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_txdbmaker_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("txdbmaker", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(txdbmaker)
    library(jsonlite)

    # --- supported U C S Ctables [] ---
    # Key functions: supportedUCSCtables, makeTxDbFromUCSC
    supportedUCSCtables(genome="mm9")
    mm9KG_txdb <- makeTxDbFromUCSC(genome="mm9", tablename="knownGene")
    # --- make Tx Db From Biomart [] ---
    # Key functions: makeTxDbFromBiomart
    mmusculusEnsembl <- makeTxDbFromBiomart(dataset="mmusculus_gene_ensembl")
    # --- save Db [] ---
    # Key functions: saveDb
    saveDb(mm9KG_txdb, file="mm9KG_txdb.sqlite")
    # --- load Db [] ---
    # Key functions: loadDb
    mm9KG_txdb <- loadDb("mm9KG_txdb.sqlite")

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
        write.csv(as.data.frame(.main), "${prefix}_txdbmaker_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_txdbmaker_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_txdbmaker_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_TXDBMAKER:", paste0("    txdbmaker: ", as.character(packageVersion("txdbmaker")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_txdbmaker_results.csv
    touch ${prefix}_txdbmaker_output.rds
    echo "BIOC_TXDBMAKER:" > versions.yml
    echo "    txdbmaker: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TXDBMAKER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TXDBMAKER(ch_input)

    emit:
    results  = BIOC_TXDBMAKER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TXDBMAKER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TXDBMAKER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TXDBMAKER.out.versions  // channel: path(versions.yml)
}
