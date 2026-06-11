#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: orfhunter — predict_and_annotate_orfs
// Predict true ORFs in transcripts of interest, extract their sequences, detect premature termination codons, translate them, and perform basic annotation.
// Input: trans_sequences.fasta, classRFmodel_1.rds, trans_sequences.gtf
// Container: quay.io/biocontainers/bioconductor-orfhunter:1.18.0--r45ha27e39d_0
// R packages: Biostrings, ORFhunteR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ORFHUNTER_PREDICT_AND_ANNOTATE_ORFS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-orfhunter:1.18.0--r45ha27e39d_0"

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
    
    # Define input file paths (exactly as declared in USER INPUT)
    trans_fasta <- "trans_sequences.fasta"
    model_rds   <- "classRFmodel_1.rds"
    trans_gtf   <- "trans_sequences.gtf"
    
    # Define intermediate and output file paths
    orfs_coords_file <- "predicted_orfs_coordinates.txt"
    orfs_seqs_fasta  <- "predicted_orfs_sequences.fasta"
    proteins_fasta   <- "predicted_proteins_sequences.fasta"
    ptcs_output_csv  <- "detected_ptcs.csv"
    anno_output_csv  <- "annotated_orfs.csv"
    
    # 1. Predict true ORFs using predictORF
    message("Predicting ORFs...")
    ORFs <- predictORF(
      tr = trans_fasta,
      model = model_rds,
      prThr = 0
    )
    
    # Save predicted ORF coordinates to a tab-delimited file (required for subsequent steps)
    write.table(ORFs, file = orfs_coords_file, sep = "\t", quote = FALSE, row.names = FALSE)
    
    # 2. Extract ORF sequences using getSeqORFs
    message("Extracting ORF sequences...")
    seq_orfs <- getSeqORFs(
      orfs = orfs_coords_file,
      tr = trans_fasta,
      genome = "BSgenome.Hsapiens.UCSC.hg38",
      workDir = NULL
    )
    
    # Save extracted ORF sequences to FASTA (required for translation)
    writeXStringSet(seq_orfs, filepath = orfs_seqs_fasta)
    
    # 3. Detect premature termination codons (PTCs) using findPTCs
    message("Detecting premature termination codons (PTCs)...")
    ptcs <- findPTCs(
      orfs = orfs_coords_file,
      gtf = trans_gtf,
      workDir = NULL
    )
    
    # Save PTC results
    write.csv(ptcs, file = ptcs_output_csv, row.names = FALSE)
    
    # 4. Translate ORFs in silico using translateORFs
    message("Translating ORFs...")
    prot_seqs <- translateORFs(
      seqORFs = orfs_seqs_fasta
    )
    
    # Save translated protein sequences to FASTA (required for annotation)
    writeXStringSet(prot_seqs, filepath = proteins_fasta)
    
    # 5. Annotate identified ORFs using annotateORFs
    message("Annotating identified ORFs...")
    anno_orfs <- annotateORFs(
      orfs = orfs_coords_file,
      tr = trans_fasta,
      gtf = trans_gtf,
      prts = proteins_fasta,
      workDir = NULL
    )
    
    # Save final annotation results
    write.csv(anno_orfs, file = anno_output_csv, row.names = FALSE)
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_ORFHUNTER_PREDICT_AND_ANNOTATE_ORFS":',
        paste0('        orfhunter: ', as.character(packageVersion("orfhunter")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_predict_and_annotate_orfs.csv versions.yml
    """
}

workflow BIOC_ORFHUNTER_PREDICT_AND_ANNOTATE_ORFS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ trans_sequences.fasta, classRFmodel_1.rds, trans_sequences.gtf ] ]

    main:
    BIOC_ORFHUNTER_PREDICT_AND_ANNOTATE_ORFS(ch_input)

    emit:
    tables   = BIOC_ORFHUNTER_PREDICT_AND_ANNOTATE_ORFS.out.tables
    plots    = BIOC_ORFHUNTER_PREDICT_AND_ANNOTATE_ORFS.out.plots
    objects  = BIOC_ORFHUNTER_PREDICT_AND_ANNOTATE_ORFS.out.objects
    versions = BIOC_ORFHUNTER_PREDICT_AND_ANNOTATE_ORFS.out.versions
}
