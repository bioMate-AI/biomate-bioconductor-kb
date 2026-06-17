#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ORFhunteR — orf_prediction_and_annotation
// Predict true ORFs in a set of transcripts, extract their sequences, detect premature termination codons (PTCs), translate them in silico, and generate a basic a
// Input: transcripts.fasta, transcripts.gtf, classRFmodel.rds
// Container: quay.io/biocontainers/bioconductor-orfhunter:1.18.0--r45ha27e39d_0
// R packages: Biostrings, ORFhunteR
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, ORFhunteR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Predict true ORFs using predictORF
//  * 2. [Core Analysis] Extract nucleotide sequences of predicted ORFs using getSeqORFs
//  * 3. [Core Analysis] Detect premature termination codons (PTCs) using findPTCs
//  * 4. [Core Analysis] Translate predicted ORFs into amino acid sequences using translateORFs
//  * 5. [Core Analysis] Generate a comprehensive annotation table using annotateORFs

nextflow.enable.dsl = 2

process BIOC_ORFHUNTER_ORF_PREDICTION_AND_ANNOTATION {
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
    .bm_deps <- c("Biostrings", "ORFhunteR")
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
    library(ORFhunteR)
    library(Biostrings)
    
    # Define input file paths based on user requirements
    tr_path <- "transcripts.fasta"
    gtf_path <- "transcripts.gtf"
    model_path <- "classRFmodel.rds"
    
    # Verify that input files exist before proceeding
    if (!file.exists(tr_path)) {
      stop(paste("Required input file missing:", tr_path))
    }
    if (!file.exists(gtf_path)) {
      stop(paste("Required input file missing:", gtf_path))
    }
    if (!file.exists(model_path)) {
      stop(paste("Required input file missing:", model_path))
    }
    
    # 1. Predict true ORFs using predictORF
    message("Predicting ORFs...")
    ORFs <- predictORF(tr = tr_path,
                       model = model_path,
                       prThr = 0)
    
    # Save predicted ORF coordinates to a tab-delimited file
    # This file is required as input for subsequent steps
    orfs_path <- "predicted_orfs_coordinates.txt"
    write.table(ORFs, file = orfs_path, sep = "\t", row.names = FALSE, col.names = TRUE, quote = FALSE)
    message("Predicted ORF coordinates saved to: ", orfs_path)
    
    # 2. Extract nucleotide sequences of predicted ORFs using getSeqORFs
    message("Extracting ORF sequences...")
    seq_orfs <- getSeqORFs(orfs = orfs_path,
                           tr = tr_path,
                           genome = "BSgenome.Hsapiens.UCSC.hg38",
                           workDir = NULL)
    
    # Save extracted nucleotide sequences to a FASTA file
    seq_orf_path <- "predicted_orfs_sequences.fasta"
    writeXStringSet(seq_orfs, filepath = seq_orf_path)
    message("Extracted ORF sequences saved to: ", seq_orf_path)
    
    # 3. Detect premature termination codons (PTCs) using findPTCs
    message("Detecting premature termination codons (PTCs)...")
    ptcs <- findPTCs(orfs = orfs_path,
                     gtf = gtf_path, 
                     workDir = NULL)
    
    # Save PTC analysis results
    ptcs_output_path <- "ptc_results.csv"
    write.csv(ptcs, file = ptcs_output_path, row.names = FALSE)
    message("PTC results saved to: ", ptcs_output_path)
    
    # 4. Translate predicted ORFs into amino acid sequences using translateORFs
    message("Translating ORFs in silico...")
    prot_seqs <- translateORFs(seqORFs = seq_orf_path)
    
    # Save translated protein sequences to a FASTA file
    prts_path <- "predicted_proteins_sequences.fasta"
    writeXStringSet(prot_seqs, filepath = prts_path)
    message("Translated protein sequences saved to: ", prts_path)
    
    # 5. Generate a comprehensive annotation table using annotateORFs
    message("Generating basic annotation table...")
    anno_orfs <- annotateORFs(orfs = orfs_path,
                              tr = tr_path,
                              gtf = gtf_path,
                              prts = prts_path,
                              workDir = NULL)
    
    # Save final annotation table
    annotation_output_path <- "annotated_orfs.csv"
    write.csv(anno_orfs, file = annotation_output_path, row.names = FALSE)
    message("Final ORF annotations saved to: ", annotation_output_path)
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_ORFHUNTER_ORF_PREDICTION_AND_ANNOTATION":',
        paste0('    ORFhunteR: ', as.character(packageVersion('ORFhunteR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_orf_prediction_and_annotation.csv versions.yml
    """
}

workflow BIOC_ORFHUNTER_ORF_PREDICTION_AND_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ transcripts.fasta, transcripts.gtf, classRFmodel.rds ] ]

    main:
    BIOC_ORFHUNTER_ORF_PREDICTION_AND_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_ORFHUNTER_ORF_PREDICTION_AND_ANNOTATION.out.tables
    plots    = BIOC_ORFHUNTER_ORF_PREDICTION_AND_ANNOTATION.out.plots
    objects  = BIOC_ORFHUNTER_ORF_PREDICTION_AND_ANNOTATION.out.objects
    versions = BIOC_ORFHUNTER_ORF_PREDICTION_AND_ANNOTATION.out.versions
}
