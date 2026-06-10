#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: txcutr — transcriptome_truncation_and_export
// Truncate a transcriptome annotation from the 3' end and export the resulting GTF, FASTA, and merge table for downstream alignment and quantification.
// Input: txdb, sacCer3
// Container: quay.io/biocontainers/bioconductor-txcutr:1.16.0--r45hdfd78af_0
// R packages: GenomicFeatures, knitr, refmanager, rmarkdown, sessioninfo, txcutr
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationDbi, GenomicFeatures, txcutr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the TxDb object and optionally restrict to specific chromosomes
//  * 2. [Core Analysis] Truncate the transcriptome using truncateTxome
//  * 3. [Visualization & Output] Export the truncated annotation to a GTF file using exportGTF
//  * 4. [Visualization & Output] Export the truncated transcript sequences to a FASTA file using exportFASTA
//  * 5. [Visualization & Output] Generate a merge table using generateMergeTable to map input transcripts to output transcripts or genes

nextflow.enable.dsl = 2

process BIOC_TXCUTR_TRANSCRIPTOME_TRUNCATION_AND_EXPORT {
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
    .bm_deps <- c("GenomicFeatures", "knitr", "refmanager", "rmarkdown", "sessioninfo", "txcutr")
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
    library(GenomicFeatures)
    library(txcutr)
    
    # 1. Load the TxDb object and BSgenome object from the working directory
    message("Loading input files...")
    
    txdb_path <- if (file.exists("txdb.rds")) {
      "txdb.rds"
    } else if (file.exists("txdb")) {
      "txdb"
    } else if (file.exists("txdb.sqlite")) {
      "txdb.sqlite"
    } else {
      stop("Error: 'txdb' file (RDS or SQLite) not found in the working directory.")
    }
    
    txdb <- tryCatch({
      AnnotationDbi::loadDb(txdb_path)
    }, error = function(e) {
      readRDS(txdb_path)
    })
    
    sacCer3_path <- if (file.exists("sacCer3.rds")) {
      "sacCer3.rds"
    } else if (file.exists("sacCer3")) {
      "sacCer3"
    } else {
      stop("Error: 'sacCer3' file (RDS) not found in the working directory.")
    }
    
    sacCer3 <- readRDS(sacCer3_path)
    
    ## constrain to "chrI"
    seqlevels(txdb) <- "chrI"
    
    ## view the lengths of first ten transcripts
    print("Transcript lengths before truncation:")
    print(transcriptLengths(txdb)[1:10,])
    
    # 2. Truncate the transcriptome using truncateTxome
    message("Truncating transcriptome...")
    txdb_w500 <- truncateTxome(txdb, maxTxLength=500)
    
    print("Transcript lengths after truncation:")
    print(transcriptLengths(txdb_w500)[1:10,])
    
    # 3. Export the truncated annotation to a GTF file using exportGTF
    message("Exporting GTF...")
    gtf_file <- "sacCer3_chrI.sgd.txcutr_w500.gtf.gz"
    exportGTF(txdb_w500, file=gtf_file)
    
    # 4. Export the truncated transcript sequences to a FASTA file using exportFASTA
    message("Exporting FASTA...")
    fasta_file <- "sacCer3_chrI.sgd.txcutr_w500.fa.gz"
    exportFASTA(txdb_w500, genome=sacCer3, file=fasta_file)
    
    # 5. Generate a merge table using generateMergeTable
    message("Generating merge table...")
    df_merge <- generateMergeTable(txdb_w500, minDistance=500)
    
    print("First 10 rows of merge table:")
    print(head(df_merge, 10))
    
    print("Merged transcripts (where input != output):")
    print(df_merge[df_merge\$tx_in != df_merge\$tx_out,])
    
    # Query transcripts for YAL026C
    print("Transcripts for gene YAL026C:")
    print(transcripts(txdb_w500, columns=c("tx_name", "gene_id"),
                filter=list(gene_id=c("YAL026C"))))
    
    # Save outputs
    write.csv(df_merge, "merge_table.csv", row.names = FALSE)
    message("Pipeline completed successfully. Outputs written to:")
    message("- ", gtf_file)
    message("- ", fasta_file)
    message("- merge_table.csv")

    writeLines(c(
        '"BIOC_TXCUTR_TRANSCRIPTOME_TRUNCATION_AND_EXPORT":',
        paste0('    txcutr: ', as.character(packageVersion('txcutr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_transcriptome_truncation_and_export.csv versions.yml
    """
}

workflow BIOC_TXCUTR_TRANSCRIPTOME_TRUNCATION_AND_EXPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ txdb, sacCer3 ] ]

    main:
    BIOC_TXCUTR_TRANSCRIPTOME_TRUNCATION_AND_EXPORT(ch_input)

    emit:
    tables   = BIOC_TXCUTR_TRANSCRIPTOME_TRUNCATION_AND_EXPORT.out.tables
    plots    = BIOC_TXCUTR_TRANSCRIPTOME_TRUNCATION_AND_EXPORT.out.plots
    objects  = BIOC_TXCUTR_TRANSCRIPTOME_TRUNCATION_AND_EXPORT.out.objects
    versions = BIOC_TXCUTR_TRANSCRIPTOME_TRUNCATION_AND_EXPORT.out.versions
}
