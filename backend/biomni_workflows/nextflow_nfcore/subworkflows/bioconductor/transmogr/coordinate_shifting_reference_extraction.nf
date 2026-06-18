#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: transmogR — coordinate_shifting_reference_extraction
// Efficiently extract a variant-modified reference transcriptome by shifting exon coordinates to account for indels and extracting sequences from a modified genom
// Input: 1000GP_subset.vcf.gz, gencode.v44.subset.gtf.gz
// Container: quay.io/biocontainers/bioconductor-transmogr:1.6.0--r45h01b2380_0
// R packages: BSgenome.Hsapiens.UCSC.hg38, Biostrings, GenomicFeatures, VariantAnnotation, extraChIPs, magrittr, rtracklayer, transmogR
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg38, Biostrings, GenomicFeatures, VariantAnnotation, extraChIPs, magrittr, rtracklayer, transmogR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and clean genomic variants
//  * 2. [Core Analysis] Modify the reference genome sequence
//  * 3. [Core Analysis] Shift exon coordinates to account for length-modifying variants
//  * 4. [Core Analysis] Generate variant tags for transcripts before coordinate shifting
//  * 5. [Core Analysis] Extract modified transcript sequences from the modified genome

nextflow.enable.dsl = 2

process BIOC_TRANSMOGR_COORDINATE_SHIFTING_REFERENCE_EXTRACTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg38", "Biostrings", "GenomicFeatures", "VariantAnnotation", "extraChIPs", "magrittr", "rtracklayer", "transmogR")
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
    library(VariantAnnotation)
    library(rtracklayer)
    library(extraChIPs)
    library(transmogR)
    library(GenomicFeatures)
    library(BSgenome.Hsapiens.UCSC.hg38)
    library(Biostrings)
    library(magrittr)
    
    # ==========================================
    # 1. Setup Reference Genome and Seqinfo
    # ==========================================
    message("Setting up reference genome sequence (chr1)...")
    chr1 <- getSeq(BSgenome.Hsapiens.UCSC.hg38, "chr1")
    chr1 <- as(chr1, "DNAStringSet")
    names(chr1) <- "chr1"
    
    sq <- seqinfo(chr1)
    genome(sq) <- "GRCh38"
    
    # ==========================================
    # 2. Load and Clean Genomic Variants
    # ==========================================
    message("Loading and cleaning genomic variants...")
    # Read the declared user input file from the working directory
    vcf_file <- "1000GP_subset.vcf.gz"
    vcf <- VcfFile(vcf_file)
    var <- cleanVariants(vcf)
    seqinfo(var) <- sq
    
    # ==========================================
    # 3. Load Transcript Annotations
    # ==========================================
    message("Loading transcript annotations...")
    # Read the declared user input file from the working directory
    f <- "gencode.v44.subset.gtf.gz"
    gtf <- import.gff(f, which = GRanges(sq))
    seqinfo(gtf) <- sq
    gtf <- splitAsList(gtf, gtf\$type)
    
    # ==========================================
    # 4. Modify Reference Genome Sequence
    # ==========================================
    message("Modifying reference genome sequence...")
    chr1_mod <- genomogrify(chr1, var)
    
    # ==========================================
    # 5. Shift Exon Coordinates
    # ==========================================
    message("Shifting exon coordinates to account for indels...")
    ref_exons_by_trans <- gtf\$exon %>% splitAsList(.\$transcript_id) 
    new_exons <- shiftByVar(gtf\$exon, var)
    new_exon_by_trans <- splitAsList(new_exons, new_exons\$transcript_id)
    
    # ==========================================
    # 6. Generate Variant Tags and Extract Sequences
    # ==========================================
    message("Generating variant tags and extracting modified transcript sequences...")
    tags <- varTags(ref_exons_by_trans, var, tag = "1000GP")
    names(new_exon_by_trans) <- paste0(names(new_exon_by_trans), tags)
    new_trans_mod <- extractTranscriptSeqs(chr1_mod, new_exon_by_trans)
    
    # ==========================================
    # 7. Save Outputs
    # ==========================================
    message("Saving output files...")
    
    # Save the modified transcript sequences as a compressed FASTA file
    writeXStringSet(new_trans_mod, "new_trans_mod.fa.gz", compress = TRUE)
    
    # Save the modified genome sequence as a compressed FASTA file
    writeXStringSet(chr1_mod, "chr1_mod.fa.gz", compress = TRUE)
    
    # Save the shifted exons as an RDS object for downstream analysis
    saveRDS(new_exons, "new_exons.rds")
    
    # Save a summary of the modified transcripts
    summary_df <- data.frame(
      transcript_id = names(new_trans_mod),
      width = width(new_trans_mod),
      stringsAsFactors = FALSE
    )
    write.csv(summary_df, "modified_transcripts_summary.csv", row.names = FALSE)
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_TRANSMOGR_COORDINATE_SHIFTING_REFERENCE_EXTRACTION":',
        paste0('    transmogR: ', as.character(packageVersion('transmogR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_coordinate_shifting_reference_extraction.csv versions.yml
    """
}

workflow BIOC_TRANSMOGR_COORDINATE_SHIFTING_REFERENCE_EXTRACTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ 1000GP_subset.vcf.gz, gencode.v44.subset.gtf.gz ] ]

    main:
    BIOC_TRANSMOGR_COORDINATE_SHIFTING_REFERENCE_EXTRACTION(ch_input)

    emit:
    tables   = BIOC_TRANSMOGR_COORDINATE_SHIFTING_REFERENCE_EXTRACTION.out.tables
    plots    = BIOC_TRANSMOGR_COORDINATE_SHIFTING_REFERENCE_EXTRACTION.out.plots
    objects  = BIOC_TRANSMOGR_COORDINATE_SHIFTING_REFERENCE_EXTRACTION.out.objects
    versions = BIOC_TRANSMOGR_COORDINATE_SHIFTING_REFERENCE_EXTRACTION.out.versions
}
