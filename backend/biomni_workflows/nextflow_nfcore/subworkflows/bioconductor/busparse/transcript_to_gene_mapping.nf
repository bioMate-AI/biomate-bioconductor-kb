#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BUSpaRse — transcript_to_gene_mapping
// Generate transcript-to-gene mapping files and filtered transcriptomes from various sources (Ensembl, FASTA, GTF, TxDb, EnsDb).
// Input: fasta_test.fasta, gtf_test.gtf
// Container: quay.io/biocontainers/bioconductor-busparse:1.24.0--r45ha27e39d_0
// R packages: BSgenome.Hsapiens.UCSC.hg38, BUSpaRse, EnsDb.Hsapiens.v86, TxDb.Hsapiens.UCSC.hg38.knownGene
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg38, BUSpaRse, EnsDb.Hsapiens.v86, TxDb.Hsapiens.UCSC.hg38.knownGene
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Download and filter transcriptome using dl_transcriptome
//  * 2. [Core Analysis] Query Ensembl via biomart using tr2g_ensembl
//  * 3. [Core Analysis] Extract mapping from FASTA using tr2g_fasta
//  * 4. [Core Analysis] Extract mapping and transcriptome from GTF and BSgenome using tr2g_gtf
//  * 5. [Core Analysis] Extract mapping from TxDb using tr2g_TxDb
//  * 6. [Core Analysis] Extract mapping from EnsDb using tr2g_EnsDb

nextflow.enable.dsl = 2

process BIOC_BUSPARSE_TRANSCRIPT_TO_GENE_MAPPING {
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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg38", "BUSpaRse", "EnsDb.Hsapiens.v86", "TxDb.Hsapiens.UCSC.hg38.knownGene")
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
    library(BUSpaRse)
    library(BSgenome.Hsapiens.UCSC.hg38)
    library(TxDb.Hsapiens.UCSC.hg38.knownGene)
    library(EnsDb.Hsapiens.v86)
    
    # Define input files from the working directory
    toy_fasta <- "fasta_test.fasta"
    toy_gtf <- "gtf_test.gtf"
    
    # 1. Download and filter transcriptome using dl_transcriptome
    # Wrapped in tryCatch to handle potential network/Ensembl server issues robustly
    tryCatch({
      dl_transcriptome("Drosophila melanogaster", out_path = "fly", 
                       gene_biotype_use = "cellranger", verbose = FALSE)
    }, error = function(e) {
      message("Warning: dl_transcriptome failed (likely due to network/Ensembl server issues): ", e\$message)
    })
    
    # 2. Query Ensembl via biomart using tr2g_ensembl
    # Wrapped in tryCatch to handle potential network/Ensembl server issues robustly
    tr2g_mm <- NULL
    tryCatch({
      tr2g_mm <- tr2g_ensembl("Mus musculus", ensembl_version = 115, 
                              other_attrs = "description", 
                              gene_biotype_use = "cellranger")
    }, error = function(e) {
      message("Warning: tr2g_ensembl failed (likely due to network/Ensembl server issues): ", e\$message)
    })
    
    # 3. Extract mapping from FASTA using tr2g_fasta
    tr2g_fa <- tr2g_fasta(file = toy_fasta, write_tr2g = FALSE, save_filtered = FALSE)
    
    # 4. Extract mapping and transcriptome from GTF and BSgenome using tr2g_gtf
    tr2g_tg <- tr2g_gtf(toy_gtf, Genome = BSgenome.Hsapiens.UCSC.hg38,
                        gene_biotype_use = "cellranger",
                        out_path = "gtf")
    
    # 5. Extract mapping from TxDb using tr2g_TxDb
    tr2g_hs <- tr2g_TxDb(TxDb.Hsapiens.UCSC.hg38.knownGene, get_transcriptome = FALSE,
                         write_tr2g = FALSE)
    
    # 6. Extract mapping from EnsDb using tr2g_EnsDb
    tr2g_hs86 <- tr2g_EnsDb(EnsDb.Hsapiens.v86, get_transcriptome = FALSE, 
                            write_tr2g = FALSE, gene_biotype_use = "cellranger",
                            use_gene_version = FALSE, use_transcript_version = FALSE)
    
    # Save meaningful results to output files
    if (!is.null(tr2g_mm)) {
      write.csv(tr2g_mm, "tr2g_ensembl_mm.csv", row.names = FALSE)
    }
    write.csv(tr2g_fa, "tr2g_fasta_out.csv", row.names = FALSE)
    write.csv(tr2g_tg, "tr2g_gtf_out.csv", row.names = FALSE)
    write.csv(tr2g_hs, "tr2g_txdb_out.csv", row.names = FALSE)
    write.csv(tr2g_hs86, "tr2g_ensdb_out.csv", row.names = FALSE)
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_BUSPARSE_TRANSCRIPT_TO_GENE_MAPPING":',
        paste0('    BUSpaRse: ', as.character(packageVersion('BUSpaRse')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_transcript_to_gene_mapping.csv versions.yml
    """
}

workflow BIOC_BUSPARSE_TRANSCRIPT_TO_GENE_MAPPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fasta_test.fasta, gtf_test.gtf ] ]

    main:
    BIOC_BUSPARSE_TRANSCRIPT_TO_GENE_MAPPING(ch_input)

    emit:
    tables   = BIOC_BUSPARSE_TRANSCRIPT_TO_GENE_MAPPING.out.tables
    plots    = BIOC_BUSPARSE_TRANSCRIPT_TO_GENE_MAPPING.out.plots
    objects  = BIOC_BUSPARSE_TRANSCRIPT_TO_GENE_MAPPING.out.objects
    versions = BIOC_BUSPARSE_TRANSCRIPT_TO_GENE_MAPPING.out.versions
}
