#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: KCsmart — comparative_kc_smart
// Identify genomic regions with significant copy number differences between two distinct groups of samples.
// Input: hsSampleData, hsMirrorLocs
// Container: quay.io/biocontainers/bioconductor-kcsmart:2.68.0--r45hdfd78af_0
// R packages: KCsmart
// Bioconductor: 3.20 | R: 4.4
// Requires: KCsmart
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate a sample point matrix collection using calcSpmCollection with a class vector defining the groups
//  * 2. [Core Analysis] Determine significance of the differences between groups using compareSpmCollection
//  * 3. [Core Analysis] Extract the significantly different genomic regions using getSigRegionsCompKC
//  * 4. [Visualization & Output] Plot the comparative analysis results using plot

nextflow.enable.dsl = 2

process BIOC_KCSMART_COMPARATIVE_KC_SMART {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("KCsmart")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    library(KCsmart)
    
    if (file.exists("hsSampleData.rds")) {
      hsSampleData <- readRDS("hsSampleData.rds")
    } else if (file.exists("hsSampleData.RData")) {
      env <- new.env()
      load("hsSampleData.RData", envir = env)
      if ("hsSampleData" %in% names(env)) {
        hsSampleData <- env\$hsSampleData
      } else {
        hsSampleData <- env[[names(env)[1]]]
      }
    } else if (file.exists("hsSampleData.csv")) {
      hsSampleData <- read.csv("hsSampleData.csv", check.names = FALSE)
    } else if (file.exists("hsSampleData.txt")) {
      hsSampleData <- read.delim("hsSampleData.txt", check.names = FALSE)
    } else {
      stop("Required input file for 'hsSampleData' (RDS, RData, CSV, or TXT) not found in the working directory.")
    }
    
    if (file.exists("hsMirrorLocs.rds")) {
      hsMirrorLocs <- readRDS("hsMirrorLocs.rds")
    } else if (file.exists("hsMirrorLocs.RData")) {
      env <- new.env()
      load("hsMirrorLocs.RData", envir = env)
      if ("hsMirrorLocs" %in% names(env)) {
        hsMirrorLocs <- env\$hsMirrorLocs
      } else {
        hsMirrorLocs <- env[[names(env)[1]]]
      }
    } else {
      stop("Required input file for 'hsMirrorLocs' (RDS or RData) not found in the working directory.")
    }
    
    if (inherits(hsSampleData, "data.frame")) {
      num_samples <- length(setdiff(tolower(colnames(hsSampleData)), c("chrom", "maploc")))
    } else if (inherits(hsSampleData, "DNAcopy")) {
      num_samples <- length(setdiff(tolower(colnames(hsSampleData\$data)), c("chrom", "maploc")))
    } else {
      num_samples <- ncol(hsSampleData)
    }
    
    cl_vec <- c(rep(0, floor(num_samples / 2)), rep(1, num_samples - floor(num_samples / 2)))
    
    spmc1mb <- calcSpmCollection(hsSampleData, hsMirrorLocs, cl=cl_vec, sigma=1000000)
    spmc1mb.sig <- compareSpmCollection(spmc1mb, nperms=3, method=c("siggenes"))
    spmc1mb.sig.regions <- getSigRegionsCompKC(spmc1mb.sig)
    
    pdf("comparative_kc_plot.pdf", width = 10, height = 6)
    plot(spmc1mb.sig, sigRegions=spmc1mb.sig.regions)
    dev.off()
    
    saveRDS(spmc1mb, file = "spmc1mb.rds")
    saveRDS(spmc1mb.sig, file = "spmc1mb.sig.rds")
    saveRDS(spmc1mb.sig.regions, file = "spmc1mb.sig.regions.rds")
    
    write.table(spmc1mb.sig.regions, file = "spmc1mb_sig_regions.txt", sep = "\t", quote = FALSE, row.names = FALSE)

    writeLines(c(
        '"BIOC_KCSMART_COMPARATIVE_KC_SMART":',
        paste0('    KCsmart: ', as.character(packageVersion('KCsmart')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_comparative_kc_smart.csv versions.yml
    """
}

workflow BIOC_KCSMART_COMPARATIVE_KC_SMART_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hsSampleData, hsMirrorLocs ] ]

    main:
    BIOC_KCSMART_COMPARATIVE_KC_SMART(ch_input)

    emit:
    tables   = BIOC_KCSMART_COMPARATIVE_KC_SMART.out.tables
    plots    = BIOC_KCSMART_COMPARATIVE_KC_SMART.out.plots
    objects  = BIOC_KCSMART_COMPARATIVE_KC_SMART.out.objects
    versions = BIOC_KCSMART_COMPARATIVE_KC_SMART.out.versions
}
