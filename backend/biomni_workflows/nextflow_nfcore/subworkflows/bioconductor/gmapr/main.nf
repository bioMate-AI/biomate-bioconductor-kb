#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gmapR — short_read_alignment_gsnap
// Build a genome index (with optional splice sites) and align paired-end short reads (FASTQ) using GSNAP.
// Input: p53Seq, fastqs["H1993.first"], fastqs["H1993.last"]
// Container: quay.io/biocontainers/bioconductor-gmapr:1.48.0--r44h15a9599_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, GenomicFeatures, TxDb.Hsapiens.UCSC.hg19.knownGene, gmapR, org.Hs.eg.db
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a GmapGenome index
//  * 2. [Core Analysis] Extract and assign known splice sites
//  * 3. [Core Analysis] Configure alignment parameters using GsnapParam
//  * 4. [Core Analysis] Align reads using gsnap

nextflow.enable.dsl = 2

process BIOC_GMAPR_SHORT_READ_ALIGNMENT_GSNAP {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(gmapR)
    library(Biostrings)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    library(org.Hs.eg.db)
    library(GenomicFeatures)
    
    # 1. Read User Inputs from the working directory
    # p53Seq is expected to be a DNAStringSet saved as an RDS file
    p53Seq <- readRDS("p53Seq.rds")
    
    # Construct the fastqs named vector pointing to the local FASTQ files
    fastqs <- c(
      "H1993.first" = "H1993.first.fastq",
      "H1993.last" = "H1993.last.fastq"
    )
    
    # 2. Setup Region of Interest (roi) and TxDb for splice site extraction
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
    eg <- org.Hs.eg.db::org.Hs.egSYMBOL2EG[["TP53"]]
    tx <- transcripts(txdb, filter = list(gene_id = eg))
    roi <- range(tx) + 1e6
    strand(roi) <- "*"
    
    # 3. Create GmapGenome index
    gmapGenome <- GmapGenome(genome = p53Seq, 
                             name = paste0("TP53_demo_", 
                               packageVersion("TxDb.Hsapiens.UCSC.hg19.knownGene")), 
                             create = TRUE, 
                             k = 12L)
    
    # 4. Extract and assign known splice sites
    exons <- gmapR:::subsetRegion(exonsBy(txdb), roi, "TP53")
    spliceSites(gmapGenome, "knownGene") <- exons
    
    # 5. Configure alignment parameters using GsnapParam
    gsnapParam <- GsnapParam(genome=gmapGenome,
                             unique_only=FALSE,
                             suboptimal_levels=2L, 
                             npaths=10L,
                             novelsplicing=TRUE,
                             splicing="knownGene",
                             indel_penalty=1L,
                             distant_splice_penalty=1L,
                             clip_overlap=TRUE)
    
    # 6. Align reads using gsnap
    gsnapOutput <- gsnap(input_a=fastqs["H1993.first"],
                         input_b=fastqs["H1993.last"],
                         params=gsnapParam)
    
    # 7. Save meaningful results
    # Save the GsnapOutput object
    saveRDS(gsnapOutput, file = "gsnapOutput.rds")
    
    # Retrieve and save the paths to the generated BAM files
    bam_files <- dir(path(gsnapOutput), full.names = TRUE, pattern = "\\\\.bam\$")
    writeLines(bam_files, con = "aligned_bam_files.txt")

    writeLines(c(
        '"BIOC_GMAPR_SHORT_READ_ALIGNMENT_GSNAP":',
        paste0('    gmapR: ', as.character(packageVersion('gmapR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_short_read_alignment_gsnap.csv versions.yml
    """
}

workflow BIOC_GMAPR_SHORT_READ_ALIGNMENT_GSNAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ p53Seq, fastqs["H1993.first"], fastqs["H1993.last"] ] ]

    main:
    BIOC_GMAPR_SHORT_READ_ALIGNMENT_GSNAP(ch_input)

    emit:
    tables   = BIOC_GMAPR_SHORT_READ_ALIGNMENT_GSNAP.out.tables
    plots    = BIOC_GMAPR_SHORT_READ_ALIGNMENT_GSNAP.out.plots
    objects  = BIOC_GMAPR_SHORT_READ_ALIGNMENT_GSNAP.out.objects
    versions = BIOC_GMAPR_SHORT_READ_ALIGNMENT_GSNAP.out.versions
}
