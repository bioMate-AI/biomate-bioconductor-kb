#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: transmogr — direct_transcriptome_modification
// Create a variant-modified reference transcriptome directly from a reference genome, a set of variants, and exon coordinates.
// Input: reference_genome.fa, variants.vcf.gz, annotations.gtf.gz
// Container: quay.io/biocontainers/bioconductor-transmogr:1.6.0--r45h01b2380_0
// R packages: Biostrings, GenomicFeatures, extraChIPs, rtracklayer, transmogR, VariantAnnotation
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRANSMOGR_DIRECT_TRANSCRIPTOME_MODIFICATION {
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
    .bm_deps <- c("Biostrings", "GenomicFeatures", "extraChIPs", "rtracklayer", "transmogR", "VariantAnnotation")
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
    
    # 1. Load Reference Genome and Setup Seqinfo
    chr1 <- readDNAStringSet("reference_genome.fa")
    sq <- seqinfo(chr1)
    genome(sq) <- "GRCh38"
    
    # 2. Load and Clean Variants
    vcf <- VcfFile("variants.vcf.gz")
    var <- cleanVariants(vcf)
    seqinfo(var) <- sq
    
    # 3. Import and Split GTF Annotations
    f <- "annotations.gtf.gz"
    gtf <- import.gff(f, which = GRanges(sq))
    seqinfo(gtf) <- sq
    gtf <- splitAsList(gtf, gtf\$type)
    
    # 4. Run transmogrify to Generate Modified Transcript Sequences
    trans_mod <- transmogrify(chr1, var, gtf\$exon, tag = "1000GP", var_tags = TRUE)
    
    # 5. Save Outputs
    writeXStringSet(trans_mod, "modified_transcriptome.fa.gz", compress = TRUE)
    saveRDS(trans_mod, "modified_transcripts.rds")
    saveRDS(var, "cleaned_variants.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_TRANSMOGR_DIRECT_TRANSCRIPTOME_MODIFICATION":
        transmogr: \$(Rscript -e 'cat(as.character(packageVersion("transmogr")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_direct_transcriptome_modification.csv versions.yml
    """
}

workflow BIOC_TRANSMOGR_DIRECT_TRANSCRIPTOME_MODIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ reference_genome.fa, variants.vcf.gz, annotations.gtf.gz ] ]

    main:
    BIOC_TRANSMOGR_DIRECT_TRANSCRIPTOME_MODIFICATION(ch_input)

    emit:
    tables   = BIOC_TRANSMOGR_DIRECT_TRANSCRIPTOME_MODIFICATION.out.tables
    plots    = BIOC_TRANSMOGR_DIRECT_TRANSCRIPTOME_MODIFICATION.out.plots
    objects  = BIOC_TRANSMOGR_DIRECT_TRANSCRIPTOME_MODIFICATION.out.objects
    versions = BIOC_TRANSMOGR_DIRECT_TRANSCRIPTOME_MODIFICATION.out.versions
}
