#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tomoseqr — detect_axial_peak_genes
// Detect genes with significant differences in expression levels between sections along a specific axis.
// Input: testx
// Container: quay.io/biocontainers/bioconductor-tomoseqr:1.14.0--r45hdfd78af_0
// R packages: tomoseqr
// Bioconductor: 3.20 | R: 4.4
// Requires: tomoseqr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and input data
//  * 2. [Core Analysis] Identify axial peak genes across all genes or a subset of candidate genes using findAxialGenes

nextflow.enable.dsl = 2

process BIOC_TOMOSEQR_DETECT_AXIAL_PEAK_GENES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("tomoseqr")
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
    
    # Stage 1: Load the package and input data
    library(tomoseqr)
    
    # Read the user input file 'testx' from the working directory
    if (file.exists("testx")) {
      testx <- tryCatch({
        readRDS("testx")
      }, error = function(e) {
        tryCatch({
          read.csv("testx", check.names = FALSE, stringsAsFactors = FALSE)
        }, error = function(e2) {
          read.table("testx", header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
        })
      })
    } else if (file.exists("testx.csv")) {
      testx <- read.csv("testx.csv", check.names = FALSE, stringsAsFactors = FALSE)
    } else if (file.exists("testx.tsv")) {
      testx <- read.delim("testx.tsv", check.names = FALSE, stringsAsFactors = FALSE)
    } else if (file.exists("testx.rds")) {
      testx <- readRDS("testx.rds")
    } else {
      stop("Required input file 'testx' (CSV, TSV, or RDS format) not found in the working directory.")
    }
    
    # Stage 2: Identify axial peak genes across all genes or a subset of candidate genes using findAxialGenes
    axialGeneTable <- findAxialGenes(testx)
    print(axialGeneTable)
    write.csv(axialGeneTable, "axial_gene_table_all.csv", row.names = FALSE)
    
    tryCatch({
      axialGeneTable <- findAxialGenes(testx, genes = c("gene1", "gene3"))
      print(axialGeneTable)
      write.csv(axialGeneTable, "axial_gene_table_subset.csv", row.names = FALSE)
    }, error = function(e) {
      message("Note: findAxialGenes with genes = c('gene1', 'gene3') skipped or failed. Error: ", e\$message)
    })

    writeLines(c(
        '"BIOC_TOMOSEQR_DETECT_AXIAL_PEAK_GENES":',
        paste0('    tomoseqr: ', as.character(packageVersion('tomoseqr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_detect_axial_peak_genes.csv versions.yml
    """
}

workflow BIOC_TOMOSEQR_DETECT_AXIAL_PEAK_GENES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ testx ] ]

    main:
    BIOC_TOMOSEQR_DETECT_AXIAL_PEAK_GENES(ch_input)

    emit:
    tables   = BIOC_TOMOSEQR_DETECT_AXIAL_PEAK_GENES.out.tables
    plots    = BIOC_TOMOSEQR_DETECT_AXIAL_PEAK_GENES.out.plots
    objects  = BIOC_TOMOSEQR_DETECT_AXIAL_PEAK_GENES.out.objects
    versions = BIOC_TOMOSEQR_DETECT_AXIAL_PEAK_GENES.out.versions
}
