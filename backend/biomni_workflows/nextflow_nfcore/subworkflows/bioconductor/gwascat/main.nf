#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gwascat — query_and_subset_gwas_catalog
// Retrieve the latest GWAS catalog, convert it to a GRanges object, and subset it by specific traits or overlap with a SNP chip.
// Input: locon6
// Container: quay.io/biocontainers/bioconductor-gwascat:2.42.0--r45hdfd78af_0
// R packages: S4Vectors, dplyr, GenomeInfoDb, ggbio, Gviz, gwascat, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomeInfoDb, S4Vectors, gwascat
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Load genotype data from the working directory
//  * 2. [Core Analysis] Filter standard chromosomes and query traits
//  * 3. [Core Analysis] Find overlaps with a SNP chip

nextflow.enable.dsl = 2

process BIOC_GWASCAT_QUERY_AND_SUBSET_GWAS_CATALOG {
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
    .bm_deps <- c("S4Vectors", "dplyr", "GenomeInfoDb", "ggbio", "Gviz", "gwascat", "rtracklayer")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load required libraries
        library(gwascat)
        library(S4Vectors)
        library(GenomeInfoDb)
        
        # --- Load genotype data from the working directory ---
        if (file.exists("locon6.rds")) {
          locon6 <- readRDS("locon6.rds")
        } else if (file.exists("locon6.csv")) {
          locon6 <- read.csv("locon6.csv", check.names = FALSE)
        } else if (file.exists("locon6")) {
          locon6 <- readRDS("locon6")
        } else {
          stop("Required input file 'locon6' (RDS or CSV format) not found in the working directory.")
        }
        
        # Load GWAS catalog dynamically to avoid forbidden data() or bundled datasets
        gwcat <- get_cached_gwascat()
        gwtrunc <- as_GRanges(gwcat)
        
        # --- Filter standard chromosomes and query traits ---
        gwtrunc <- keepStandardChromosomes(gwtrunc, pruning="coarse")
        tt <- topTraits(gwtrunc)
        result_subset <- subsetByTraits(gwtrunc, tr=names(tt)[1])
        
        # --- Find overlaps with a SNP chip ---
        gr6.0 <- GRanges(seqnames=ifelse(is.na(locon6[[2]]), 0, locon6[[2]]),
                         IRanges(ifelse(is.na(locon6[[3]]), 1, locon6[[3]]), width=1))
        S4Vectors::mcols(gr6.0)\$rsid <- as.character(locon6[[1]])
        
        ag <- function(x) as(x, "GRanges")
        overlaps <- suppressWarnings(subsetByOverlaps(ag(gwtrunc), gr6.0))
        
        # Write named output files
        saveRDS(gwtrunc, "gwtrunc.rds")
        write.csv(as.data.frame(S4Vectors::mcols(result_subset)), "result_subset.csv", row.names = TRUE)
        write.csv(as.data.frame(overlaps), "overlaps.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_GWASCAT_QUERY_AND_SUBSET_GWAS_CATALOG":',
        paste0('    gwascat: ', as.character(packageVersion('gwascat')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_query_and_subset_gwas_catalog.csv versions.yml
    """
}

workflow BIOC_GWASCAT_QUERY_AND_SUBSET_GWAS_CATALOG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ locon6 ] ]

    main:
    BIOC_GWASCAT_QUERY_AND_SUBSET_GWAS_CATALOG(ch_input)

    emit:
    tables   = BIOC_GWASCAT_QUERY_AND_SUBSET_GWAS_CATALOG.out.tables
    plots    = BIOC_GWASCAT_QUERY_AND_SUBSET_GWAS_CATALOG.out.plots
    objects  = BIOC_GWASCAT_QUERY_AND_SUBSET_GWAS_CATALOG.out.objects
    versions = BIOC_GWASCAT_QUERY_AND_SUBSET_GWAS_CATALOG.out.versions
}
