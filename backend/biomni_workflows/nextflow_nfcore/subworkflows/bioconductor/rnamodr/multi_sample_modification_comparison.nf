#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rnamodr — multi_sample_modification_comparison
// Compare post-transcriptional RNA modification profiles across multiple sample sets with replicates.
// Input: annotation.gff3, sequences.fasta, sample1_rep1.bam, sample1_rep2.bam, sample2_rep1.bam, sample2_rep2.bam
// Container: quay.io/biocontainers/bioconductor-rnamodr:1.24.0--r45hdfd78af_0
// R packages: GenomicFeatures, RNAmodR, Rsamtools, rtracklayer, txdbmaker
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: ROC curve

nextflow.enable.dsl = 2

process BIOC_RNAMODR_MULTI_SAMPLE_MODIFICATION_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rnamodr:1.24.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicFeatures", "RNAmodR", "Rsamtools", "rtracklayer", "txdbmaker")
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
    library(rtracklayer)
    library(Rsamtools)
    library(GenomicFeatures)
    library(txdbmaker)
    library(RNAmodR)
    
    # --- Load annotation and sequence files from the working ---
    sequences <- "sequences.fasta"
    annotation <- GFF3File("annotation.gff3")
    
    # --- Define a named list of named character vectors ---
    # We map the 4 user-provided BAM files into 3 sample sets to match the documented workflow structure.
    files <- list("SampleSet1" = c(treated = "sample1_rep1.bam",
                                   treated = "sample1_rep2.bam"),
                  "SampleSet2" = c(treated = "sample2_rep1.bam",
                                   treated = "sample2_rep2.bam"),
                  "SampleSet3" = c(treated = "sample2_rep1.bam",
                                   treated = "sample2_rep2.bam"))
    
    # --- Create a ModifierSet object (ModSetInosine) to process ---
    msi <- ModSetInosine(files, annotation = annotation, sequences = sequences)
    
    # --- Retrieve identified modifications using modifications() ---
    mod <- modifications(msi)
    saveRDS(mod, "modifications_genomic.rds")
    
    mod <- modifications(msi, perTranscript = TRUE)
    saveRDS(mod, "modifications_transcript.rds")
    
    mod <- modifications(msi)
    
    # --- Compare modification scores across samples at specific ---
    coord <- unique(unlist(mod))
    if (length(coord) > 0) {
      coord\$score <- NULL
      coord\$sd <- NULL
      comparison_results <- compareByCoord(msi, coord)
      write.csv(as.data.frame(comparison_results), "comparison_by_coordinate.csv", row.names = FALSE)
    } else {
      warning("No modifications found to compare.")
    }
    
    # --- Generate a TxDb object and alias data frame for ---
    txdb <- makeTxDbFromGFF(annotation)
    alias <- data.frame(tx_id = names(id2name(txdb)),
                        name = id2name(txdb))
    write.csv(alias, "transcript_alias_map.csv", row.names = FALSE)
    
    # --- Visualize comparisons and evaluate performance ---
    pdf("rnamodr_visualization_plots.pdf", width = 10, height = 8)
    
    if (length(coord) > 0) {
      tryCatch({
        plotCompareByCoord(msi, coord, alias = alias)
      }, error = function(e) {
        message("Skipping plotCompareByCoord: ", e\$message)
      })
      
      tryCatch({
        plotCompareByCoord(msi[c(3,1,2)], coord, alias = alias, normalize = "SampleSet3",
                           perTranscript = TRUE)
      }, error = function(e) {
        message("Skipping normalized plotCompareByCoord: ", e\$message)
      })
    }
    
    # Transcript-level plots (using transcript "2" as documented)
    tryCatch({
      plotData(msi, "2", from = 10L, to = 45L, alias = alias)
    }, error = function(e) {
      message("Skipping plotData for transcript '2': ", e\$message)
    })
    
    tryCatch({
      plotData(msi[1:2], "2", from = 10L, to = 45L, showSequenceData = TRUE, alias = alias)
    }, error = function(e) {
      message("Skipping plotData with sequence data for transcript '2': ", e\$message)
    })
    
    # --- Evaluate performance using ROC curves ---
    if (length(coord) > 0) {
      tryCatch({
        plotROC(msi, coord)
      }, error = function(e) {
        message("Skipping plotROC: ", e\$message)
      })
    }
    
    dev.off()
    
    # Retrieve read metadata statistics
    stats <- stats(msi)
    saveRDS(stats, "sample_stats.rds")

    writeLines(c(
        '"BIOC_RNAMODR_MULTI_SAMPLE_MODIFICATION_COMPARISON":',
        paste0('        rnamodr: ', as.character(packageVersion("rnamodr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_sample_modification_comparison.csv versions.yml
    """
}

workflow BIOC_RNAMODR_MULTI_SAMPLE_MODIFICATION_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ annotation.gff3, sequences.fasta, sample1_rep1.bam, sample1_rep2.bam, sample2_rep1.bam, sample2_rep2.bam ] ]

    main:
    BIOC_RNAMODR_MULTI_SAMPLE_MODIFICATION_COMPARISON(ch_input)

    emit:
    tables   = BIOC_RNAMODR_MULTI_SAMPLE_MODIFICATION_COMPARISON.out.tables
    plots    = BIOC_RNAMODR_MULTI_SAMPLE_MODIFICATION_COMPARISON.out.plots
    objects  = BIOC_RNAMODR_MULTI_SAMPLE_MODIFICATION_COMPARISON.out.objects
    versions = BIOC_RNAMODR_MULTI_SAMPLE_MODIFICATION_COMPARISON.out.versions
}
