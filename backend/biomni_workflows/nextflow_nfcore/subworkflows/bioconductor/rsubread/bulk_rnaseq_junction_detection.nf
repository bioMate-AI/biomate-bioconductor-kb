#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Rsubread — bulk_rnaseq_junction_detection
// Align RNA-seq reads globally and detect exon-exon junctions.
// Input: genome.fa, rnaseq-reads.txt.gz
// Container: quay.io/biocontainers/bioconductor-rsubread:2.24.0--r45h01b2380_0
// Requires: Rsubread
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build reference index using buildindex
//  * 2. [Core Analysis] Align reads and detect junctions using subjunc

nextflow.enable.dsl = 2

process BIOC_RSUBREAD_BULK_RNASEQ_JUNCTION_DETECTION {
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
    
    # Load the required Bioconductor library
    library(Rsubread)
    
    # Define input files (must exist in the working directory)
    genome_file <- "genome.fa"
    reads_file <- "rnaseq-reads.txt.gz"
    
    # Verify that the required user input files exist before proceeding
    if (!file.exists(genome_file)) {
      stop(paste("Error: Required input reference genome file '", genome_file, "' not found in the working directory.", sep=""))
    }
    
    if (!file.exists(reads_file)) {
      stop(paste("Error: Required input RNA-seq reads file '", reads_file, "' not found in the working directory.", sep=""))
    }
    
    # Stage 1: Build reference index using buildindex
    message("Stage 1: Building reference genome index...")
    buildindex(basename="my_index", reference="genome.fa")
    
    # Stage 2: Align reads and detect junctions using subjunc
    message("Stage 2: Aligning RNA-seq reads and detecting exon-exon junctions...")
    align_stats <- subjunc(index="my_index", readfile1="rnaseq-reads.txt.gz", output_file="subjunc_results.bam")
    
    # Stage 3: Export and save meaningful results
    message("Stage 3: Saving alignment statistics and outputs...")
    
    # Save the alignment statistics dataframe to a CSV file
    write.csv(align_stats, file="subjunc_alignment_statistics.csv", row.names=TRUE)
    
    # Save the alignment statistics as an RDS object for downstream R analyses
    saveRDS(align_stats, file="subjunc_alignment_statistics.rds")
    
    # Subjunc automatically generates a junction BED file named <output_file>.junction.bed
    expected_junction_file <- "subjunc_results.bam.junction.bed"
    if (file.exists(expected_junction_file)) {
      message(paste("Junction detection completed. Junctions written to: ", expected_junction_file, sep=""))
    } else {
      warning("Junction BED file was not generated. This can happen if no splice junctions were supported by the input reads.")
    }
    
    message("Pipeline completed successfully. Outputs generated: 'subjunc_results.bam', 'subjunc_alignment_statistics.csv', 'subjunc_alignment_statistics.rds'.")

    writeLines(c(
        '"BIOC_RSUBREAD_BULK_RNASEQ_JUNCTION_DETECTION":',
        paste0('    Rsubread: ', as.character(packageVersion('Rsubread')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bulk_rnaseq_junction_detection.csv versions.yml
    """
}

workflow BIOC_RSUBREAD_BULK_RNASEQ_JUNCTION_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genome.fa, rnaseq-reads.txt.gz ] ]

    main:
    BIOC_RSUBREAD_BULK_RNASEQ_JUNCTION_DETECTION(ch_input)

    emit:
    tables   = BIOC_RSUBREAD_BULK_RNASEQ_JUNCTION_DETECTION.out.tables
    plots    = BIOC_RSUBREAD_BULK_RNASEQ_JUNCTION_DETECTION.out.plots
    objects  = BIOC_RSUBREAD_BULK_RNASEQ_JUNCTION_DETECTION.out.objects
    versions = BIOC_RSUBREAD_BULK_RNASEQ_JUNCTION_DETECTION.out.versions
}
