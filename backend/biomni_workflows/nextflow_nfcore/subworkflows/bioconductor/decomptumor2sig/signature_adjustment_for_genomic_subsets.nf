#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: decomptumor2sig — signature_adjustment_for_genomic_subsets
// Adjust and normalize mutational signatures derived from one genomic context (e.g., whole genome) to match the nucleotide frequencies of a target genomic region 
// Input: COSMIC mutational signatures, TxDb.Hsapiens.UCSC.hg19.knownGene
// Container: quay.io/biocontainers/bioconductor-decomptumor2sig:2.26.0--r45hdfd78af_0
// R packages: BSgenome.Hsapiens.UCSC.hg19, GenomicRanges, TxDb.Hsapiens.UCSC.hg19.knownGene, decompTumor2Sig
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DECOMPTUMOR2SIG_SIGNATURE_ADJUSTMENT_FOR_GENOMIC_SUBSETS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-decomptumor2sig:2.26.0--r45hdfd78af_0"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "GenomicRanges", "TxDb.Hsapiens.UCSC.hg19.knownGene", "decompTumor2Sig")
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
    library(decompTumor2Sig)
    library(GenomicRanges)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    library(BSgenome.Hsapiens.UCSC.hg19)
    
    # --- Read the original mutational signatures ---
    # Check if a local COSMIC signatures file exists in the working directory,
    # otherwise read/download using the package's default behavior.
    cosmic_file <- "cosmic_signatures.txt"
    if (file.exists(cosmic_file)) {
      message("Reading COSMIC signatures from local file: ", cosmic_file)
      signatures <- readAlexandrovSignatures(file = cosmic_file)
    } else {
      message("Local COSMIC signatures file not found. Reading signatures using readAlexandrovSignatures().")
      signatures <- readAlexandrovSignatures()
    }
    
    # --- Define the target genomic regions (promoters) as a ---
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene
    regionsTarget <- promoters(txdb, upstream = 2000, downstream = 200)
    
    # --- Adjust the signatures to the target regions using the ---
    sign_adj <- adjustSignaturesForRegionSet(
      signatures,
      regionsTarget,
      regionsOriginal = NULL,
      refGenome = BSgenome.Hsapiens.UCSC.hg19::BSgenome.Hsapiens.UCSC.hg19
    )
    
    # --- Write named output files for the meaningful results ---
    # Save the adjusted signatures object as an RDS file
    saveRDS(sign_adj, file = "adjusted_signatures.rds")
    
    # Convert the adjusted signatures list to a data frame and save as a CSV file
    sign_adj_df <- as.data.frame(sign_adj)
    write.csv(sign_adj_df, file = "adjusted_signatures.csv", row.names = TRUE)
    
    # Plot the mutation distribution of the first adjusted signature and save as a PDF
    pdf("adjusted_signature_1_distribution.pdf", width = 12, height = 6)
    plotMutationDistribution(sign_adj[[1]])
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to 'adjusted_signatures.rds', 'adjusted_signatures.csv', and 'adjusted_signature_1_distribution.pdf'.")

    writeLines(c(
        '"BIOC_DECOMPTUMOR2SIG_SIGNATURE_ADJUSTMENT_FOR_GENOMIC_SUBSETS":',
        paste0('        decomptumor2sig: ', as.character(packageVersion("decomptumor2sig")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_signature_adjustment_for_genomic_subsets.csv versions.yml
    """
}

workflow BIOC_DECOMPTUMOR2SIG_SIGNATURE_ADJUSTMENT_FOR_GENOMIC_SUBSETS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ COSMIC mutational signatures, TxDb.Hsapiens.UCSC.hg19.knownGene ] ]

    main:
    BIOC_DECOMPTUMOR2SIG_SIGNATURE_ADJUSTMENT_FOR_GENOMIC_SUBSETS(ch_input)

    emit:
    tables   = BIOC_DECOMPTUMOR2SIG_SIGNATURE_ADJUSTMENT_FOR_GENOMIC_SUBSETS.out.tables
    plots    = BIOC_DECOMPTUMOR2SIG_SIGNATURE_ADJUSTMENT_FOR_GENOMIC_SUBSETS.out.plots
    objects  = BIOC_DECOMPTUMOR2SIG_SIGNATURE_ADJUSTMENT_FOR_GENOMIC_SUBSETS.out.objects
    versions = BIOC_DECOMPTUMOR2SIG_SIGNATURE_ADJUSTMENT_FOR_GENOMIC_SUBSETS.out.versions
}
