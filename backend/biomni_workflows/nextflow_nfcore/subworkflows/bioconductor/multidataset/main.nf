#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MultiDataSet
// Implementation of the BRGE's (Bioinformatic Research Group in Epidemiology from Center for Research 
//
// Input: expression.csv (gene-expression matrix, genes x samples), methylation.csv (optional DNA-methylation beta-value matrix, probes x samples)
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MultiDataSet/inst/doc/MultiDataSet.R
// Upstream  : Biobase, GenomicRanges, brgedata
// Downstream: MEAL
//
// Install: BiocManager::install("MultiDataSet")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_MULTIDATASET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-multidataset"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_multidataset_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_multidataset_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_multidataset_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("MultiDataSet", "Biobase", "GenomicRanges", "SummarizedExperiment", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(MultiDataSet)
    library(Biobase)
    library(GenomicRanges)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Load user-provided inputs ---
    # expression.csv : gene-expression matrix (genes in rows, samples in columns;
    #                  first column = feature/gene IDs used as row names)
    # methylation.csv: DNA-methylation beta-value matrix (CpG/probe IDs in rows,
    #                  samples in columns; first column = probe IDs as row names).
    #                  Optional - only loaded if present.
    expr_mat <- as.matrix(read.csv("expression.csv", row.names = 1, check.names = FALSE))
    brge_gexp <- ExpressionSet(assayData = expr_mat)
    # Second expression set used by the overwrite / multi-add demonstrations below.
    brge_gexp2 <- brge_gexp

    # --- New Multi [] ---
    # Key functions: createMultiDataSet
    multi <- createMultiDataSet()
    # --- add eset 10 [] ---
    # Key functions: add_eset
    multi2 <- add_eset(multi, brge_gexp, dataset.type = "expression")
    # --- add eset 2 [] ---
    # Key functions: add_eset
    multi2 <- add_eset(multi2, brge_gexp, dataset.type = "expression", dataset.name = "new")
    # --- add eset add id to eset [] ---
    # Key functions: add_eset
    multi2 <- add_eset(multi, brge_gexp2, dataset.type = "expression")
    # --- add eset overwrite [] ---
    # Key functions: add_eset
    multi2 <- add_eset(multi, brge_gexp, dataset.type = "expression", warnings = FALSE)
    multi2 <- add_eset(multi2, brge_gexp2, dataset.type = "expression", warnings = FALSE, overwrite = FALSE)
    multi2 <- add_eset(multi2, brge_gexp2, dataset.type = "expression", warnings = FALSE, overwrite = TRUE)
    # --- add eset GRanges [] ---
    # Key functions: add_eset
    multi2 <- add_eset(multi, brge_gexp, dataset.type = "expression", warnings = FALSE, GRanges = NA)
    # --- add rse overwrite [] ---
    # Key functions: createMultiDataSet, add_rse
    if (file.exists("methylation.csv")) {
        methy_mat <- as.matrix(read.csv("methylation.csv", row.names = 1, check.names = FALSE))
        brge_methy <- SummarizedExperiment(assays = list(meth = methy_mat))
    } else {
        brge_methy <- SummarizedExperiment(assays = list(meth = expr_mat))
    }
    multi <- createMultiDataSet()
    multi2 <- add_rse(multi, brge_methy, dataset.type = "methylation", warnings = FALSE)
    # --- create Multi Data Set [] ---
    # Key functions: createMultiDataSet, add_genexp
    multi <- createMultiDataSet()
    multi2 <- add_genexp(multi, brge_gexp)
    # --- add_genexp [] ---
    # Key functions: add_genexp
    multi2 <- add_genexp(multi2, brge_gexp, dataset.name = "2")
    # --- Subsetting intro [] ---
    # Key functions: createMultiDataSet, add_methy, add_genexp, add_eset
    multi <- createMultiDataSet()
    multi <- add_methy(multi, brge_methy)
    multi <- add_genexp(multi, brge_gexp)
    # --- sample Names [] ---
    # Key functions: sampleNames
    samples <- sampleNames(brge_gexp)[76:100]
    # --- subset common samples [] ---
    # Key functions: commonSamples
    commonSamples(multi)
    length(intersect(sampleNames(brge_gexp), sampleNames(brge_methy)))
    # --- Genomic Ranges [] ---
    # Key functions: GRanges
    range <- GRanges("chr17:1-100000")
    # --- Genomic Ranges 2 [] ---
    # Key functions: GRanges
    range2 <- GRanges(c("chr17:1-100000", "chr17:1000000-2000000"))

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
        write.csv(as.data.frame(.main), "${prefix}_multidataset_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_multidataset_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_multidataset_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_MULTIDATASET:", paste0("    multidataset: ", as.character(packageVersion("MultiDataSet")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multidataset_results.csv
    touch ${prefix}_multidataset_output.rds
    echo "BIOC_MULTIDATASET:" > versions.yml
    echo "    multidataset: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MULTIDATASET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MULTIDATASET(ch_input)

    emit:
    results  = BIOC_MULTIDATASET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MULTIDATASET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MULTIDATASET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MULTIDATASET.out.versions  // channel: path(versions.yml)
}
