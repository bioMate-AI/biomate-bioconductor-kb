#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tomoseqr — detect_axial_peak_genes
// Detect genes with significant differences in expression levels between sections along a specific axis.
// Input: testx
// Container: quay.io/biocontainers/bioconductor-tomoseqr:1.14.0--r45hdfd78af_0
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

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
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
