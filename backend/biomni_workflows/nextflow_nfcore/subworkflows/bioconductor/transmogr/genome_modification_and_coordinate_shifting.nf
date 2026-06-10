#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: transmogr — genome_modification_and_coordinate_shifting
// Modify a reference genome and shift exon coordinates to extract modified transcript sequences efficiently.
// Input: reference_genome.fa, variants.vcf.gz, annotations.gtf.gz
// Container: quay.io/biocontainers/bioconductor-transmogr:1.6.0--r45h01b2380_0
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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(VariantAnnotation)
    library(rtracklayer)
    library(extraChIPs)
    library(transmogR)
    library(GenomicFeatures)
    library(Biostrings)
    library(magrittr)
    
    # 1. Load Reference Genome
    chr1 <- readDNAStringSet("reference_genome.fa")
    sq <- seqinfo(chr1)
    genome(sq) <- "GRCh38"
    
    # 2. Load and Clean Variants
    vcf <- VcfFile("variants.vcf.gz")
    var <- cleanVariants(vcf)
    seqinfo(var) <- sq
    
    # 3. Load Annotations
    gtf <- import.gff("annotations.gtf.gz", which = GRanges(sq))
    seqinfo(gtf) <- sq
    gtf <- splitAsList(gtf, gtf\$type)
    
    # 4. Modify Reference Genome
    chr1_mod <- genomogrify(chr1, var)
    
    # 5. Shift Exon Coordinates
    ref_exons_by_trans <- gtf\$exon %>% splitAsList(.\$transcript_id) 
    new_exons <- shiftByVar(gtf\$exon, var)
    new_exon_by_trans <- splitAsList(new_exons, new_exons\$transcript_id)
    
    # 6. Generate Variant Tags
    tags <- varTags(ref_exons_by_trans, var, tag = "1000GP")
    names(new_exon_by_trans) <- paste0(names(new_exon_by_trans), tags)
    
    # 7. Extract Modified Transcript Sequences
    new_trans_mod <- extractTranscriptSeqs(chr1_mod, new_exon_by_trans)
    
    # 8. Save Outputs
    writeXStringSet(chr1_mod, "modified_genome.fa.gz", compress = TRUE)
    writeXStringSet(new_trans_mod, "modified_transcripts.fa.gz", compress = TRUE)
    saveRDS(new_exons, "shifted_exons.rds")
    saveRDS(new_exon_by_trans, "shifted_exons_by_transcript.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_TRANSMOGR_GENOME_MODIFICATION_AND_COORDINATE_SHIFTING":
        transmogr: \$(Rscript -e 'cat(as.character(packageVersion("transmogr")))')
    END_VERSIONS
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
