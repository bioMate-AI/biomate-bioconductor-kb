#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: wiggleplotr — transcript_annotation_plotting
// Plot transcript structures (exons, introns, and coding sequences) from manual GRanges or database objects.
// Input: exons_list, cds_list, metadata_df, EnsDb_object, TxDb_object
// Container: quay.io/biocontainers/bioconductor-wiggleplotr:1.34.0--r45hdfd78af_0
// R packages: biomaRt, dplyr, ensembldb, GenomicFeatures, GenomicRanges, ggplot2, wiggleplotr
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicFeatures, GenomicRanges, dplyr, ensembldb, ggplot2, wiggleplotr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load transcript annotations (exons, CDS, and metadata) or database objects
//  * 2. [Visualization & Output] Plot transcript structures using plotTranscripts, plotTranscriptsFromEnsembldb, or plotTranscriptsFromUCSC, optionally setting res

nextflow.enable.dsl = 2

process BIOC_WIGGLEPLOTR_TRANSCRIPT_ANNOTATION_PLOTTING {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("biomaRt", "dplyr", "ensembldb", "GenomicFeatures", "GenomicRanges", "ggplot2", "wiggleplotr")
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
    library("wiggleplotr")
    library("GenomicRanges")
    library("dplyr")
    library("GenomicFeatures")
    library("ggplot2")
    
    # 1. Load transcript annotations (exons, CDS, and metadata) or database objects
    # Read user input files from the working directory
    exons_list_path <- "exons_list.rds"
    if (!file.exists(exons_list_path)) {
      stop("Required input file 'exons_list.rds' not found in the working directory.")
    }
    exons_list <- readRDS(exons_list_path)
    
    cds_list <- NULL
    if (file.exists("cds_list.rds")) {
      cds_list <- readRDS("cds_list.rds")
    }
    
    metadata_df <- NULL
    if (file.exists("metadata_df.csv")) {
      metadata_df <- read.csv("metadata_df.csv", stringsAsFactors = FALSE)
    } else if (file.exists("metadata_df.rds")) {
      metadata_df <- readRDS("metadata_df.rds")
    }
    
    EnsDb_object <- NULL
    if (file.exists("EnsDb_object.rds")) {
      library("ensembldb")
      EnsDb_object <- readRDS("EnsDb_object.rds")
    }
    
    TxDb_object <- NULL
    if (file.exists("TxDb_object.rds")) {
      TxDb_object <- readRDS("TxDb_object.rds")
    }
    
    # 2. Plot transcript structures using plotTranscripts, plotTranscriptsFromEnsembldb, or plotTranscriptsFromUCSC
    
    # Plot 1: Without rescaling introns
    p1 <- plotTranscripts(exons_list, cds_list, metadata_df, rescale_introns = FALSE)
    ggsave("plot_transcripts_rescale_false.pdf", plot = p1, width = 10, height = 6)
    
    # Plot 2: With rescaling introns
    p2 <- plotTranscripts(exons_list, cds_list, metadata_df, rescale_introns = TRUE)
    ggsave("plot_transcripts_rescale_true.pdf", plot = p2, width = 10, height = 6)
    
    # Plot 3: Exons only, with rescaling introns
    p3 <- plotTranscripts(exons_list, rescale_introns = TRUE)
    ggsave("plot_transcripts_exons_only.pdf", plot = p3, width = 10, height = 6)
    
    # Plot 4: From Ensembldb (if database object is provided)
    if (!is.null(EnsDb_object)) {
      tryCatch({
        p4 <- plotTranscriptsFromEnsembldb(EnsDb_object, transcript_ids = names(exons_list))
        ggsave("plot_transcripts_ensembldb.pdf", plot = p4, width = 10, height = 6)
      }, error = function(e) {
        message("Could not plot from Ensembldb: ", e\$message)
      })
    }
    
    # Plot 5: From UCSC (if database object is provided)
    if (!is.null(TxDb_object)) {
      tryCatch({
        p5 <- plotTranscriptsFromUCSC(txdb = TxDb_object, transcript_ids = names(exons_list))
        ggsave("plot_transcripts_ucsc.pdf", plot = p5, width = 10, height = 6)
      }, error = function(e) {
        message("Could not plot from UCSC: ", e\$message)
      })
    }

    writeLines(c(
        '"BIOC_WIGGLEPLOTR_TRANSCRIPT_ANNOTATION_PLOTTING":',
        paste0('    wiggleplotr: ', as.character(packageVersion('wiggleplotr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_transcript_annotation_plotting.csv versions.yml
    """
}

workflow BIOC_WIGGLEPLOTR_TRANSCRIPT_ANNOTATION_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exons_list, cds_list, metadata_df, EnsDb_object, TxDb_object ] ]

    main:
    BIOC_WIGGLEPLOTR_TRANSCRIPT_ANNOTATION_PLOTTING(ch_input)

    emit:
    tables   = BIOC_WIGGLEPLOTR_TRANSCRIPT_ANNOTATION_PLOTTING.out.tables
    plots    = BIOC_WIGGLEPLOTR_TRANSCRIPT_ANNOTATION_PLOTTING.out.plots
    objects  = BIOC_WIGGLEPLOTR_TRANSCRIPT_ANNOTATION_PLOTTING.out.objects
    versions = BIOC_WIGGLEPLOTR_TRANSCRIPT_ANNOTATION_PLOTTING.out.versions
}
