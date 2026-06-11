#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TFutils
// This package helps users to work with TF metadata from various sources. Significant catalogs of TFs 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TFutils/inst/doc/TFutils.R
// Upstream  : AnnotationDbi, BiocParallel, GenomicFiles, GenomicRanges, UpSetR
// Downstream: none
//
// Install: BiocManager::install("TFutils")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TFUTILS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tfutils"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tfutils_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tfutils_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tfutils_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("TFutils", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(TFutils)
    library(jsonlite)

    # --- TF Catalog Construction [TFCatalog, HGNCmap] ---
    # Key functions: TFCatalog, HGNCmap
    data(cisbpTFcat, package = "TFutils")
    data(hocomoco.mono.sep2018, package = "TFutils")
    TFs_CISBP <- TFCatalog(
        name = "CISBP.info",
        nativeIds = cisbpTFcat[, 1],
        HGNCmap = cisbpTFcat
    )
    TFs_HOCO <- TFCatalog(
        name = "hocomoco11",
        nativeIds = hocomoco.mono.sep2018[, 1],
        HGNCmap = hocomoco.mono.sep2018
    )
    cis_map <- HGNCmap(TFs_CISBP)
    hoco_map <- HGNCmap(TFs_HOCO)

    # --- Catalog Intersection Analysis [TFCatalog, HGNCmap] ---
    # Key functions: TFCatalog, HGNCmap
    data(tftCollMap, package = "TFutils")
    data(tftColl, package = "TFutils")
    TFs_MSIG <- TFCatalog(
        name = "MsigDb.TFT",
        nativeIds = names(tftColl),
        HGNCmap = data.frame(tftCollMap, stringsAsFactors = FALSE)
    )
    msig_syms <- HGNCmap(TFs_MSIG)[, 2]
    cis_syms <- HGNCmap(TFs_CISBP)[, 2]
    common_symbols <- intersect(msig_syms, cis_syms)
    overlap_ratio <- length(common_symbols) / length(cis_syms)

    # --- TF Family Classification [HGNCmap] ---
    # Key functions: HGNCmap
    cismap <- HGNCmap(TFs_CISBP)
    scis <- split(cismap, cismap\$HGNC)
    uf <- vapply(scis, function(x) x\$Family_Name[1], "character")
    CISTOP <- sort(table(uf), decreasing = TRUE)[1:10]
    hoc <- HGNCmap(TFs_HOCO)
    shoc <- split(hoc, hoc\$HGNC)
    sfam <- vapply(shoc, function(x) x\$`TF family`[1], "character")
    HOTOP <- sort(table(sfam), decreasing = TRUE)[1:10]

    # --- Genomic Motif Scan Processing [reduceByFile] ---
    # Key functions: reduceByFile
    data(fimo16, package = "TFutils")
    if (.Platform\$OS.type != "windows") {
        BiocParallel::register(BiocParallel::SerialParam())
        GenomicRanges::rowRanges(fimo16) <- GenomicRanges::GRanges(
            "chr17",
            BiocGenerics::IRanges(38.077e6, 38.084e6)
        )
        rr <- GenomicFiles::reduceByFile(
            fimo16,
            MAP = function(r, f) Rsamtools::scanTabix(f, param = r)
        )
    } else {
        f_path <- system.file("fimoser/fimo16rr.rds", package = "TFutils")
        rr <- readRDS(f_path)
    }

    # --- GWAS Trait Association [directHitsInCISBP, topTraitsOfTargets] ---
    # Key functions: directHitsInCISBP, topTraitsOfTargets
    gwas_file <- system.file("legacy/ebicat37.rda", package = "gwascat")
    load(gwas_file)
    hits <- directHitsInCISBP("Rheumatoid arthritis", ebicat37)
    tt <- topTraitsOfTargets("MTF1", TFutils::tftColl, ebicat37)
    top_traits <- head(tt)
    trait_counts <- table(tt[, 1])


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
        write.csv(as.data.frame(.main), "${prefix}_tfutils_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_tfutils_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_tfutils_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_TFUTILS:", paste0("    tfutils: ", as.character(packageVersion("TFutils")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tfutils_results.csv
    touch ${prefix}_tfutils_output.rds
    echo "BIOC_TFUTILS:" > versions.yml
    echo "    tfutils: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TFUTILS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TFUTILS(ch_input)

    emit:
    results  = BIOC_TFUTILS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TFUTILS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TFUTILS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TFUTILS.out.versions  // channel: path(versions.yml)
}
