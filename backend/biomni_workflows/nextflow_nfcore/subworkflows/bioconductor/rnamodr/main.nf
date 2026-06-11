#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rnamodr — single_sample_modification_detection
// Detect post-transcriptional RNA modifications (such as Inosine) in a single sample set with replicates.
// Input: annotation.gff3, sequences.fasta, treated_rep1.bam, treated_rep2.bam, treated_rep3.bam
// Container: quay.io/biocontainers/bioconductor-rnamodr:1.24.0--r45hdfd78af_0
// R packages: GenomicFeatures, RNAmodR, Rsamtools, rtracklayer, txdbmaker
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RNAMODR_SINGLE_SAMPLE_MODIFICATION_DETECTION {
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
    library(rtracklayer)
    library(Rsamtools)
    library(GenomicFeatures)
    library(txdbmaker)
    library(RNAmodR)
    
    # Define input files from the working directory
    annotation_file <- "annotation.gff3"
    sequence_file <- "sequences.fasta"
    bam_files <- c(
      Treated = "treated_rep1.bam",
      Treated = "treated_rep2.bam",
      Treated = "treated_rep3.bam"
    )
    
    # Ensure BAM files are indexed (required by Rsamtools/RNAmodR)
    for (f in bam_files) {
      if (!file.exists(paste0(f, ".bai"))) {
        try(Rsamtools::indexBam(f), silent = TRUE)
      }
    }
    
    # 1. Load annotation and sequence files
    annotation <- GFF3File(annotation_file)
    sequences <- sequence_file
    
    # 2. Define named BAM file vector with "Treated" or "Control" conditions
    files <- bam_files
    
    # 3. Create a SequenceData object (End5SequenceData) to load and parse BAM files
    seqdata <- End5SequenceData(files, annotation = annotation, 
                                sequences = sequences)
    
    # 4. Create a Modifier object (ModInosine) to automatically aggregate data and search for modifications
    mi <- ModInosine(files, annotation = annotation, sequences = sequences)
    
    # 5. Retrieve and adjust settings (e.g., minScore) of the Modifier object
    settings(mi)
    settings(mi, "minScore")
    settings(mi) <- list(minScore = 0.5)
    settings(mi, "minScore")
    
    # Save meaningful results to the working directory
    saveRDS(seqdata, file = "seqdata.rds")
    saveRDS(mi, file = "mod_inosine.rds")
    
    # Extract detected modifications and save as a CSV table
    mods <- modifications(mi)
    mods_df <- as.data.frame(mods)
    write.csv(mods_df, file = "detected_modifications.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_RNAMODR_SINGLE_SAMPLE_MODIFICATION_DETECTION":',
        paste0('        rnamodr: ', as.character(packageVersion("rnamodr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_sample_modification_detection.csv versions.yml
    """
}

workflow BIOC_RNAMODR_SINGLE_SAMPLE_MODIFICATION_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ annotation.gff3, sequences.fasta, treated_rep1.bam, treated_rep2.bam, treated_rep3.bam ] ]

    main:
    BIOC_RNAMODR_SINGLE_SAMPLE_MODIFICATION_DETECTION(ch_input)

    emit:
    tables   = BIOC_RNAMODR_SINGLE_SAMPLE_MODIFICATION_DETECTION.out.tables
    plots    = BIOC_RNAMODR_SINGLE_SAMPLE_MODIFICATION_DETECTION.out.plots
    objects  = BIOC_RNAMODR_SINGLE_SAMPLE_MODIFICATION_DETECTION.out.objects
    versions = BIOC_RNAMODR_SINGLE_SAMPLE_MODIFICATION_DETECTION.out.versions
}
