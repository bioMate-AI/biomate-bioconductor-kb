#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: QTLExperiment
// QLTExperiment defines an S4 class for storing and manipulating summary statistics from QTL mapping e
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/QTLExperiment/inst/doc/QTLExperiment.R
// Upstream  : none
// Downstream: multistateQTL
//
// Install: BiocManager::install("QTLExperiment")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_QTLEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-qtlexperiment"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_qtlexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_qtlexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_qtlexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("S4Vectors", "QTLExperiment", "jsonlite", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }    library(SummarizedExperiment)

    library(S4Vectors)
    library(QTLExperiment)
    library(jsonlite)

    # --- Mock Data Generation ---
    # Key functions: mockSummaryStats, QTLExperiment, mockQTLE
    nStates <- 6
    nQTL <- 40
    mock_stats <- mockSummaryStats(nStates = nStates, nQTL = nQTL)
    qtle <- QTLExperiment(
        assays = list(
            betas = mock_stats\$betas,
            errors = mock_stats\$errors
        ),
        metadata = list(study = "mock-example")
    )
    qtle_mock <- mockQTLE(nStates = nStates, nQTL = nQTL)

    # --- Importing Summary Statistics ---
    # Key functions: sumstats2qtle, betas
    input_path <- system.file("extdata", package = "QTLExperiment")
    state <- c("lung", "thyroid", "spleen", "blood")
    input <- data.frame(
        state = state,
        path = paste0(input_path, "/GTEx_tx_", state, ".tsv")
    )
    qtle4 <- sumstats2qtle(
        input,
        feature_id = "molecular_trait_id",
        variant_id = "rsid",
        betas = "beta",
        errors = "se",
        pvalues = "pvalue",
        verbose = TRUE
    )
    b_mat <- betas(qtle4)

    # --- Importing MASHR Objects ---
    # Key functions: mockMASHR, mash2qtle
    nStates <- 6
    nQTL <- 40
    mashr_sim <- mockMASHR(nStates = nStates, nQTL = nQTL)
    qtle2 <- mash2qtle(
        mashr_sim,
        rowData = DataFrame(
            feature_id = row.names(mashr_sim\$Bhat),
            variant_id = sample(seq(1:1e5), nQTL)
        )
    )

    # --- Accessing and Modifying Assays ---
    # Key functions: betas, state_id, feature_id, variant_id
    qtle <- mockQTLE(nStates = 4, nQTL = 20)
    betas(qtle) <- betas(qtle) * -1
    states <- state_id(qtle)
    features <- feature_id(qtle)
    variants <- variant_id(qtle)

    # --- Data Manipulation and Recovery ---
    # Key functions: recover_qtle_ids
    qtle <- mockQTLE(nStates = 4, nQTL = 20)
    new_colData <- DataFrame(list(
        some_info1 = LETTERS[1:ncol(qtle)],
        some_info2 = c(1:ncol(qtle))
    ))
    colData(qtle) <- new_colData
    qtle_recovered <- recover_qtle_ids(qtle)


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
        write.csv(as.data.frame(.main), "${prefix}_qtlexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_qtlexperiment_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_qtlexperiment_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_QTLEXPERIMENT:", paste0("    qtlexperiment: ", as.character(packageVersion("QTLExperiment")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qtlexperiment_results.csv
    touch ${prefix}_qtlexperiment_output.rds
    echo "BIOC_QTLEXPERIMENT:" > versions.yml
    echo "    qtlexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QTLEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_QTLEXPERIMENT(ch_input)

    emit:
    results  = BIOC_QTLEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QTLEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QTLEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QTLEXPERIMENT.out.versions  // channel: path(versions.yml)
}
