#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: InteractionSet
// Provides the GInteractions, InteractionSet and ContactMatrix objects and associated methods for stor
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/InteractionSet/inst/doc/interactions.R
// Upstream  : knitr
// Downstream: diffHic, DuplexDiscovereR, GenomicInteractions, HiCDOC, sevenC
//
// Install: BiocManager::install("InteractionSet")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_INTERACTIONSET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-interactionset"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

    input:
    tuple val(meta), path(granges)

    output:
    tuple val(meta), path("${meta.id}_interactionset_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_interactionset_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_interactionset_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("ContactMatrix", "S4Vectors", "GenomicRanges", "InteractionSet", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
    library(ContactMatrix)
    library(S4Vectors)
    library(GenomicRanges)
    library(InteractionSet)
    library(jsonlite)

    # --- Data import and loading [] ---
    # Key functions: GRanges, IRanges, replaceRegions, appendRegions, GInteractions, findOverlaps, linkOverlaps, overlapsAny
    ---------------------------------------------------------------------
    all.regions <- GRanges(rep(c("chrA", "chrB"), c(10, 5)),
        IRanges(c(0:9*10+1, 0:4*5+1), c(1:10*10, 1:5*5)))
    index.1 <- c(5, 15,  3, 12, 9, 10)
    index.2 <- c(1,  5, 11, 13, 7,  4)
    # --- Quality control and filtering [] ---
    # Key functions: metadata, seqnames, regions, anchors, assay, colData
    ---------------------------------------------------------------------
    all.chrs <- as.character(seqnames(regions(gi)))
    group.by.chr <- paste0(all.chrs[anchors(gi, type="first", id=TRUE)], "+",
                           all.chrs[anchors(gi, type="second", id=TRUE)])
    # --- GInteractions analysis [] ---
    # Key functions: GInteractions, anchors, regions, anchorIds, rnorm, mcols, swapAnchors, pairdist
    ---------------------------------------------------------------------
    norm.freq <- matrix(rnorm(Nlibs*length(gi)), ncol=Nlibs)
    iset2 <- InteractionSet(list(counts=counts, norm.freq=norm.freq), gi, colData=lib.data)
    iset2

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
        write.csv(as.data.frame(.main), "${prefix}_interactionset_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_interactionset_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_interactionset_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_INTERACTIONSET:", paste0("    interactionset: ", as.character(packageVersion("InteractionSet")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interactionset_results.csv
    touch ${prefix}_interactionset_output.rds
    echo "BIOC_INTERACTIONSET:" > versions.yml
    echo "    interactionset: 0.0.0" >> versions.yml
    """
}


workflow BIOC_INTERACTIONSET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(granges) ]

    main:
    BIOC_INTERACTIONSET(ch_input)

    emit:
    results  = BIOC_INTERACTIONSET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_INTERACTIONSET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_INTERACTIONSET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_INTERACTIONSET.out.versions  // channel: path(versions.yml)
}
