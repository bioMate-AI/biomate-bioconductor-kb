#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CrispRVariants
// CrispRVariants provides tools for analysing the results of a CRISPR-Cas9 mutagenesis sequencing expe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CrispRVariants/inst/doc/user_guide.R
// Upstream  : Biostrings, GenomicFeatures, IRanges, Rsamtools, gridExtra
// Downstream: none
//
// Install: BiocManager::install("CrispRVariants")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CRISPRVARIANTS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-crisprvariants"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_crisprvariants_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_crisprvariants_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_crisprvariants_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("CrispRVariants", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(CrispRVariants)
    library(jsonlite)

    # --- Reference Sequence Reconstruction [] ---
    # Key functions: refFromAlns
    bam_dir <- system.file(package = "CrispRVariants", "extdata/bam")
    bam_fnames <- dir(bam_dir, "bam\$", full.names = TRUE)
    gd_fname <- system.file(package = "CrispRVariants", "extdata/bed/guide.bed")
    gd <- rtracklayer::import(gd_fname)
    gdl <- GenomicRanges::resize(gd, GenomicRanges::width(gd) + 10, fix = "center")
    alns <- GenomicAlignments::readGAlignments(
        bam_fnames[[1]],
        param = Rsamtools::ScanBamParam(tag = "MD", what = c("seq", "flag")),
        use.names = TRUE
    )
    rfa <- refFromAlns(alns, gdl)


    # --- Alignment to Target and Variant Counting [] ---
    # Key functions: readsToTarget, variantCounts
    ref_fname <- system.file(
        package = "CrispRVariants",
        "extdata/ptena_GRCHz10_ref.rda"
    )
    load(ref_fname)
    crispr_set <- readsToTarget(
        bam_fnames,
        target = gdl,
        reference = reference,
        target.loc = 22
    )
    vc <- variantCounts(crispr_set)


    # --- Mutation Efficiency and Consensus Sequences [] ---
    # Key functions: mutationEfficiency, consensusSeqs
    eff <- mutationEfficiency(
        crispr_set,
        filter.cols = "control",
        exclude.cols = "control"
    )
    sqs <- consensusSeqs(crispr_set)


    # --- Visualisation of Variants [] ---
    # Key functions: plotVariants
    txdb_fname <- system.file(
        "extdata/GRCz10_81_ptena_txdb.sqlite",
        package = "CrispRVariants"
    )
    txdb <- AnnotationDbi::loadDb(txdb_fname)
    p <- plotVariants(
        crispr_set,
        txdb = txdb,
        gene.text.size = 8,
        row.ht.ratio = c(1, 8),
        col.wdth.ratio = c(4, 2)
    )


    # --- Chimeric Alignment Analysis [] ---
    # Key functions: getChimeras, plotChimeras
    ch <- getChimeras(crispr_set, sample = "ptena 4")
    annotations <- c(
        GenomicRanges::resize(gd, 1, fix = "start"),
        GenomicRanges::resize(gd, 1, fix = "end")
    )
    annotations\$name <- c("ptena_start", "ptena_end")
    plotChimeras(ch, annotations = annotations)

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
        write.csv(as.data.frame(.main), "${prefix}_crisprvariants_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_crisprvariants_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_crisprvariants_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_CRISPRVARIANTS:", paste0("    crisprvariants: ", as.character(packageVersion("CrispRVariants")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_crisprvariants_results.csv
    touch ${prefix}_crisprvariants_output.rds
    echo "BIOC_CRISPRVARIANTS:" > versions.yml
    echo "    crisprvariants: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CRISPRVARIANTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CRISPRVARIANTS(ch_input)

    emit:
    results  = BIOC_CRISPRVARIANTS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CRISPRVARIANTS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CRISPRVARIANTS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CRISPRVARIANTS.out.versions  // channel: path(versions.yml)
}
