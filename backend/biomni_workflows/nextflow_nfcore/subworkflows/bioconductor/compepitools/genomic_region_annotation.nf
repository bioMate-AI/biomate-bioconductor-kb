#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: compEpiTools — genomic_region_annotation
// Annotate genomic regions of interest with proximity to nearest Transcription Start Sites (TSS), gene models, and user-defined genomic features like CpG Islands.
// Input: user_regions.RData, user_annotations.RData
// Container: quay.io/biocontainers/bioconductor-compepitools:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: TxDb.Mmusculus.UCSC.mm9.knownGene, compEpiTools, org.Mm.eg.db
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define TSS positions using TSS
//  * 2. [Core Analysis] Find midpoints of genomic regions using GRmidpoint
//  * 3. [Core Analysis] Annotate regions with gene models and custom annotations using GRannotate

nextflow.enable.dsl = 2

process BIOC_COMPEPITOOLS_GENOMIC_REGION_ANNOTATION {
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
    .bm_deps <- c("compEpiTools", "TxDb.Mmusculus.UCSC.mm9.knownGene", "org.Mm.eg.db")
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
    library(compEpiTools)
    library(TxDb.Mmusculus.UCSC.mm9.knownGene)
    library(org.Mm.eg.db)
    
    # Set up TxDb
    txdb <- TxDb.Mmusculus.UCSC.mm9.knownGene
    
    # 1. Load user input files from the working directory
    if (!file.exists("user_regions.RData")) {
      stop("Required input file 'user_regions.RData' not found in the working directory.")
    }
    if (!file.exists("user_annotations.RData")) {
      stop("Required input file 'user_annotations.RData' not found in the working directory.")
    }
    
    # Load genomic regions of interest (GRanges)
    env_regions <- new.env()
    load("user_regions.RData", envir = env_regions)
    gr_names <- names(which(sapply(env_regions, inherits, "GRanges")))
    if (length(gr_names) == 0) {
      stop("No GRanges object found in user_regions.RData")
    }
    gr <- env_regions[[gr_names[1]]]
    
    # Load custom annotations (GRangesList)
    env_ann <- new.env()
    load("user_annotations.RData", envir = env_ann)
    grl_names <- names(which(sapply(env_ann, inherits, "GRangesList")))
    if (length(grl_names) == 0) {
      stop("No GRangesList object found in user_annotations.RData")
    }
    user_ann_list <- env_ann[[grl_names[1]]]
    
    # Stage 1: Define TSS positions using TSS
    TSSpos <- TSS(txdb)
    
    # Stage 2 & 3: Find midpoints of genomic regions using GRmidpoint and annotate them using GRannotate
    # Keeping the exact function calls and argument names as documented
    res <- GRannotate(Object=GRmidpoint(gr), txdb=txdb, EG2GS=org.Mm.eg.db, 
                      upstream=2000, downstream=1000, userAnn=user_ann_list)
    
    # Display the annotated regions
    show(res)
    
    # Write outputs to the working directory
    write.csv(as.data.frame(res), file="annotated_regions.csv", row.names=FALSE)
    saveRDS(res, file="annotated_regions.rds")

    writeLines(c(
        '"BIOC_COMPEPITOOLS_GENOMIC_REGION_ANNOTATION":',
        paste0('    compEpiTools: ', as.character(packageVersion('compEpiTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomic_region_annotation.csv versions.yml
    """
}

workflow BIOC_COMPEPITOOLS_GENOMIC_REGION_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_regions.RData, user_annotations.RData ] ]

    main:
    BIOC_COMPEPITOOLS_GENOMIC_REGION_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_COMPEPITOOLS_GENOMIC_REGION_ANNOTATION.out.tables
    plots    = BIOC_COMPEPITOOLS_GENOMIC_REGION_ANNOTATION.out.plots
    objects  = BIOC_COMPEPITOOLS_GENOMIC_REGION_ANNOTATION.out.objects
    versions = BIOC_COMPEPITOOLS_GENOMIC_REGION_ANNOTATION.out.versions
}
