#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: transmogr — genome_modification_and_coordinate_shifting
// Modify a reference genome and shift exon coordinates to extract modified transcript sequences efficiently.
// Input: reference_genome.fa, variants.vcf.gz, annotations.gtf.gz
// Container: quay.io/biocontainers/bioconductor-transmogr:1.6.0--r45h01b2380_0
// R packages: Biostrings, GenomicFeatures, VariantAnnotation, extraChIPs, magrittr, rtracklayer, transmogR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRANSMOGR_GENOME_MODIFICATION_AND_COORDINATE_SHIFTING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-transmogr:1.6.0--r45h01b2380_0"

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
    .bm_deps <- c("Biostrings", "GenomicFeatures", "VariantAnnotation", "extraChIPs", "magrittr", "rtracklayer", "transmogR")
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
    library(VariantAnnotation)
    library(rtracklayer)
    library(extraChIPs)
    library(transmogR)
    library(GenomicFeatures)
    library(Biostrings)
    library(magrittr)
    
    # --- Load Reference Genome ---
    chr1 <- readDNAStringSet("reference_genome.fa")
    sq <- seqinfo(chr1)
    genome(sq) <- "GRCh38"
    
    # --- Load and Clean Variants ---
    vcf <- VcfFile("variants.vcf.gz")
    var <- cleanVariants(vcf)
    seqinfo(var) <- sq
    
    # --- Load Annotations ---
    gtf <- import.gff("annotations.gtf.gz", which = GRanges(sq))
    seqinfo(gtf) <- sq
    gtf <- splitAsList(gtf, gtf\$type)
    
    # --- Modify Reference Genome ---
    chr1_mod <- genomogrify(chr1, var)
    
    # --- Shift Exon Coordinates ---
    ref_exons_by_trans <- gtf\$exon %>% splitAsList(.\$transcript_id) 
    new_exons <- shiftByVar(gtf\$exon, var)
    new_exon_by_trans <- splitAsList(new_exons, new_exons\$transcript_id)
    
    # --- Generate Variant Tags ---
    tags <- varTags(ref_exons_by_trans, var, tag = "1000GP")
    names(new_exon_by_trans) <- paste0(names(new_exon_by_trans), tags)
    
    # --- Extract Modified Transcript Sequences ---
    new_trans_mod <- extractTranscriptSeqs(chr1_mod, new_exon_by_trans)
    
    # --- Save Outputs ---
    writeXStringSet(chr1_mod, "modified_genome.fa.gz", compress = TRUE)
    writeXStringSet(new_trans_mod, "modified_transcripts.fa.gz", compress = TRUE)
    saveRDS(new_exons, "shifted_exons.rds")
    saveRDS(new_exon_by_trans, "shifted_exons_by_transcript.rds")

    writeLines(c(
        '"BIOC_TRANSMOGR_GENOME_MODIFICATION_AND_COORDINATE_SHIFTING":',
        paste0('        transmogr: ', as.character(packageVersion("transmogr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genome_modification_and_coordinate_shifting.csv versions.yml
    """
}

workflow BIOC_TRANSMOGR_GENOME_MODIFICATION_AND_COORDINATE_SHIFTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ reference_genome.fa, variants.vcf.gz, annotations.gtf.gz ] ]

    main:
    BIOC_TRANSMOGR_GENOME_MODIFICATION_AND_COORDINATE_SHIFTING(ch_input)

    emit:
    tables   = BIOC_TRANSMOGR_GENOME_MODIFICATION_AND_COORDINATE_SHIFTING.out.tables
    plots    = BIOC_TRANSMOGR_GENOME_MODIFICATION_AND_COORDINATE_SHIFTING.out.plots
    objects  = BIOC_TRANSMOGR_GENOME_MODIFICATION_AND_COORDINATE_SHIFTING.out.objects
    versions = BIOC_TRANSMOGR_GENOME_MODIFICATION_AND_COORDINATE_SHIFTING.out.versions
}
