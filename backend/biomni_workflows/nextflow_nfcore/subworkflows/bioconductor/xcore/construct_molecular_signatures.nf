#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: xcore — construct_molecular_signatures
// Construct a custom molecular signature matrix by intersecting promoter annotations with transcription factor binding sites (TFBS).
// Input: promoters.gr, tfbs.gr
// Container: quay.io/biocontainers/bioconductor-xcore:1.14.0--r45hdfd78af_0
// R packages: GenomicRanges, xcore
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, xcore
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load promoter annotations and ensure names are in the 'name' metadata column
//  * 2. [Input & Preparation] Load TFBS/motif annotations and ensure names are in the 'name' metadata column
//  * 3. [Core Analysis] Intersect promoters and TFBS with a specified extension window using getInteractionMatrix

nextflow.enable.dsl = 2

process BIOC_XCORE_CONSTRUCT_MOLECULAR_SIGNATURES {
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
    .bm_deps <- c("GenomicRanges", "xcore")
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
    
    # Load required libraries
    library(xcore)
    library(GenomicRanges)
    
    # 1. Load promoter annotations and ensure names are in the 'name' metadata column
    if (!file.exists("promoters.gr")) {
      stop("Required input file 'promoters.gr' not found in the working directory.")
    }
    promoters_f5 <- readRDS("promoters.gr")
    if (!"name" %in% colnames(mcols(promoters_f5))) {
      stop("The promoters GRanges object must contain a 'name' metadata column.")
    }
    
    # 2. Load TFBS/motif annotations and ensure names are in the 'name' metadata column
    if (!file.exists("tfbs.gr")) {
      stop("Required input file 'tfbs.gr' not found in the working directory.")
    }
    CTCF_hg38 <- readRDS("tfbs.gr")
    if (!"name" %in% colnames(mcols(CTCF_hg38))) {
      stop("The TFBS GRanges object must contain a 'name' metadata column.")
    }
    
    # 3. Intersect promoters and TFBS with a specified extension window using getInteractionMatrix
    molecular_signature <- getInteractionMatrix(
      a = promoters_f5,
      b = CTCF_hg38,
      ext = 500
    )
    
    # Save the resulting molecular signature matrix
    saveRDS(molecular_signature, file = "molecular_signature.rds")

    writeLines(c(
        '"BIOC_XCORE_CONSTRUCT_MOLECULAR_SIGNATURES":',
        paste0('    xcore: ', as.character(packageVersion('xcore')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_construct_molecular_signatures.csv versions.yml
    """
}

workflow BIOC_XCORE_CONSTRUCT_MOLECULAR_SIGNATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ promoters.gr, tfbs.gr ] ]

    main:
    BIOC_XCORE_CONSTRUCT_MOLECULAR_SIGNATURES(ch_input)

    emit:
    tables   = BIOC_XCORE_CONSTRUCT_MOLECULAR_SIGNATURES.out.tables
    plots    = BIOC_XCORE_CONSTRUCT_MOLECULAR_SIGNATURES.out.plots
    objects  = BIOC_XCORE_CONSTRUCT_MOLECULAR_SIGNATURES.out.objects
    versions = BIOC_XCORE_CONSTRUCT_MOLECULAR_SIGNATURES.out.versions
}
