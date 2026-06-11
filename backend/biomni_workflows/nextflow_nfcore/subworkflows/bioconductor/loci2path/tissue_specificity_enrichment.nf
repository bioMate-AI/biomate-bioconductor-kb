#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: loci2path — tissue_specificity_enrichment
// Query tissue specificity of genomic intervals directly using eQTL sets without pathway/gene set collections.
// Input: query/Psoriasis.BED, eqtl/brain.gtex.txt, eqtl/skin.gtex.txt, eqtl/blood.gtex.txt
// Container: quay.io/biocontainers/bioconductor-loci2path:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, loci2path
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load query regions as GenomicRanges
//  * 2. [Input & Preparation] Construct eQTL sets and list
//  * 3. [Core Analysis] Perform tissue specificity query using query() with only query.gr and loci arguments

nextflow.enable.dsl = 2

process BIOC_LOCI2PATH_TISSUE_SPECIFICITY_ENRICHMENT {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(GenomicRanges)
    library(loci2path)
    
    # Define input file paths as specified by the user
    bed.file <- "query/Psoriasis.BED"
    brain.file <- "eqtl/brain.gtex.txt"
    skin.file <- "eqtl/skin.gtex.txt"
    blood.file <- "eqtl/blood.gtex.txt"
    
    # 1. Load query regions as GenomicRanges
    query.bed <- read.table(bed.file, header=FALSE)
    colnames(query.bed) <- c("chr","start","end")
    query.gr <- makeGRangesFromDataFrame(query.bed)
    
    # 2. Construct eQTL sets and list
    # Brain eQTL set
    tab <- read.table(brain.file, stringsAsFactors=FALSE, header=TRUE)
    snp.gr <- GRanges(seqnames=Rle(tab\$snp.chr), ranges=IRanges(start=tab\$snp.pos, width=1))
    brain.eset <- eqtlSet(tissue="brain", eqtlId=tab\$snp.id, eqtlRange=snp.gr, gene=as.character(tab\$gene.entrez.id))
    
    # Skin eQTL set
    tab <- read.table(skin.file, stringsAsFactors=FALSE, header=TRUE)
    snp.gr <- GRanges(seqnames=Rle(tab\$snp.chr), ranges=IRanges(start=tab\$snp.pos, width=1))
    skin.eset <- eqtlSet(tissue="skin", eqtlId=tab\$snp.id, eqtlRange=snp.gr, gene=as.character(tab\$gene.entrez.id))
    
    # Blood eQTL set
    tab <- read.table(blood.file, stringsAsFactors=FALSE, header=TRUE)
    snp.gr <- GRanges(seqnames=Rle(tab\$snp.chr), ranges=IRanges(start=tab\$snp.pos, width=1))
    blood.eset <- eqtlSet(tissue="blood", eqtlId=tab\$snp.id, eqtlRange=snp.gr, gene=as.character(tab\$gene.entrez.id))
    
    # Combine into an eQTL set list
    eset.list <- list(Brain=brain.eset, Skin=skin.eset, Blood=blood.eset)
    
    # 3. Perform tissue specificity query
    gr.tissue <- query(query.gr, loci=eset.list)
    
    # Save the results to the working directory
    write.csv(as.data.frame(gr.tissue), "tissue_enrichment_results.csv", row.names=TRUE)
    saveRDS(gr.tissue, "tissue_enrichment_results.rds")

    writeLines(c(
        '"BIOC_LOCI2PATH_TISSUE_SPECIFICITY_ENRICHMENT":',
        paste0('    loci2path: ', as.character(packageVersion('loci2path')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tissue_specificity_enrichment.csv versions.yml
    """
}

workflow BIOC_LOCI2PATH_TISSUE_SPECIFICITY_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ query/Psoriasis.BED, eqtl/brain.gtex.txt, eqtl/skin.gtex.txt, eqtl/blood.gtex.txt ] ]

    main:
    BIOC_LOCI2PATH_TISSUE_SPECIFICITY_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_LOCI2PATH_TISSUE_SPECIFICITY_ENRICHMENT.out.tables
    plots    = BIOC_LOCI2PATH_TISSUE_SPECIFICITY_ENRICHMENT.out.plots
    objects  = BIOC_LOCI2PATH_TISSUE_SPECIFICITY_ENRICHMENT.out.objects
    versions = BIOC_LOCI2PATH_TISSUE_SPECIFICITY_ENRICHMENT.out.versions
}
