#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GenVisR — sequence_coverage_gencov
// View sequence coverage information aligned to genomic features and gene tracks.
// Input: cov_input_A, cov_input_B
// Container: quay.io/biocontainers/bioconductor-genvisr:1.42.2--r45hdfd78af_0
// R packages: BSgenome.Hsapiens.UCSC.hg19, GenVisR, GenomicRanges, TxDb.Hsapiens.UCSC.hg19.knownGene
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg19, GenVisR, GenomicRanges, TxDb.Hsapiens.UCSC.hg19.knownGene
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load transcript metadata and reference genome packages
//  * 2. [Input & Preparation] Define the genomic region of interest as a GRanges object
//  * 3. [Core Analysis] Format coverage data into a named list of data frames
//  * 4. [Visualization & Output] Generate the coverage plot aligned to the gene track, optionally compressing introns/UTRs

nextflow.enable.dsl = 2

process BIOC_GENVISR_SEQUENCE_COVERAGE_GENCOV {
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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "GenVisR", "GenomicRanges", "TxDb.Hsapiens.UCSC.hg19.knownGene")
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
    
    # 1. Load transcript metadata, reference genome, and GenVisR packages
    library(GenVisR)
    library(GenomicRanges)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    library(BSgenome.Hsapiens.UCSC.hg19)
    
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
    genome <- BSgenome.Hsapiens.UCSC.hg19
    
    # 2. Define the genomic region of interest as a GRanges object
    gr <- GRanges(seqnames = c("chr10"), ranges = IRanges(start = c(89622195), end = c(89729532)), strand = strand(c("+")))
    
    # Verify that the required user input files exist in the working directory
    if (!file.exists("cov_input_A.csv") || !file.exists("cov_input_B.csv")) {
      stop("Required input files 'cov_input_A.csv' and/or 'cov_input_B.csv' are missing from the working directory.")
    }
    
    # 3. Format coverage data into a named list of data frames
    cov_input_A <- read.csv("cov_input_A.csv", header = TRUE)
    cov_input_B <- read.csv("cov_input_B.csv", header = TRUE)
    
    data <- list(`Sample A` = cov_input_A, `Sample B` = cov_input_B)
    
    # Save the formatted data list as an RDS object
    saveRDS(data, file = "formatted_coverage_data.rds")
    
    # 4. Generate the coverage plots aligned to the gene track and save to PDF
    # Plot 1: Uncompressed coverage plot
    pdf(file = "coverage_plot_uncompressed.pdf", width = 12, height = 8)
    plot_uncompressed <- genCov(data, txdb, gr, genome, gene_labelTranscriptSize = 2, transform = NULL, base = NULL)
    if (!is.null(plot_uncompressed)) {
      print(plot_uncompressed)
    }
    dev.off()
    
    # Plot 2: Compressed coverage plot (compressing introns/UTRs)
    pdf(file = "coverage_plot_compressed.pdf", width = 12, height = 8)
    plot_compressed <- genCov(data, txdb, gr, genome, transform = c("Intron", "CDS", "UTR"), base = c(10, 2, 2), reduce = TRUE)
    if (!is.null(plot_compressed)) {
      print(plot_compressed)
    }
    dev.off()

    writeLines(c(
        '"BIOC_GENVISR_SEQUENCE_COVERAGE_GENCOV":',
        paste0('    GenVisR: ', as.character(packageVersion('GenVisR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sequence_coverage_gencov.csv versions.yml
    """
}

workflow BIOC_GENVISR_SEQUENCE_COVERAGE_GENCOV_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cov_input_A, cov_input_B ] ]

    main:
    BIOC_GENVISR_SEQUENCE_COVERAGE_GENCOV(ch_input)

    emit:
    tables   = BIOC_GENVISR_SEQUENCE_COVERAGE_GENCOV.out.tables
    plots    = BIOC_GENVISR_SEQUENCE_COVERAGE_GENCOV.out.plots
    objects  = BIOC_GENVISR_SEQUENCE_COVERAGE_GENCOV.out.objects
    versions = BIOC_GENVISR_SEQUENCE_COVERAGE_GENCOV.out.versions
}
