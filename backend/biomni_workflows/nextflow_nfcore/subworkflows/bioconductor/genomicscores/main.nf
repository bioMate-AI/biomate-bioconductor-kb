#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GenomicScores
// Provide infrastructure to store and access genomewide position-specific scores within R and Biocondu
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GenomicScores/inst/doc/GenomicScores.R
// Upstream  : RColorBrewer, VariantAnnotation, gwascat
// Downstream: AlphaMissense.v2023.hg19, AlphaMissense.v2023.hg38, cadd.v1.6.hg19, cadd.v1.6.hg38, fitCons.UCSC.hg19
//
// Install: BiocManager::install("GenomicScores")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_GENOMICSCORES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomicscores"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomicscores_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomicscores_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomicscores_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("GenomicScores", "GenomicRanges", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(GenomicScores)
    library(GenomicRanges)
    library(jsonlite)

    # --- Querying Available Scores [] ---
    # Key functions: availableGScores
    avgs <- availableGScores()
    ah_scores <- rownames(avgs)[avgs\$AnnotationHub]
    head(ah_scores)

    # --- Retrieving Genomic Scores [] ---
    # Key functions: getGScores, gscores, score
    gsco <- getGScores("phastCons100way.UCSC.hg38")
    gr <- GRanges(
        seqnames = "chr22",
        IRanges(start = 50528591:50528596, width = 1)
    )
    res_gscores <- gscores(gsco, gr)
    res_scores <- score(gsco, gr)

    # --- Annotating Genomic Variants [] ---
    # Key functions: score, populations, defaultPopulation
    gsco <- getGScores("phastCons100way.UCSC.hg38")
    pops <- populations(gsco)
    def_pop <- defaultPopulation(gsco)
    gwcgr <- GRanges(
        seqnames = "chr22",
        IRanges(start = c(50528591, 50528593, 50528595), width = 1)
    )
    pcsco <- score(gsco, gwcgr, pop = "DP2")

    # --- Comparing Multiple Score Providers [] ---
    # Key functions: getGScores, score
    phast <- getGScores("phastCons100way.UCSC.hg38")
    phylop <- getGScores("phyloP100way.UCSC.hg38")
    gwcgr <- GRanges(
        seqnames = "chr22",
        IRanges(start = c(50528591, 50528593, 50528595), width = 1)
    )
    pcsco <- score(phast, gwcgr)
    ppsco <- score(phylop, gwcgr)
    plot(pcsco, ppsco, xlab = "phastCons", ylab = "phyloP")


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
        write.csv(as.data.frame(.main), "${prefix}_genomicscores_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_genomicscores_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_genomicscores_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMICSCORES:", paste0("    genomicscores: ", as.character(packageVersion("GenomicScores")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomicscores_results.csv
    touch ${prefix}_genomicscores_output.rds
    echo "BIOC_GENOMICSCORES:" > versions.yml
    echo "    genomicscores: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMICSCORES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMICSCORES(ch_input)

    emit:
    results  = BIOC_GENOMICSCORES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMICSCORES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMICSCORES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMICSCORES.out.versions  // channel: path(versions.yml)
}
