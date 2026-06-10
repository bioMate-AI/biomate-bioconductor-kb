#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: transmogr — splice_junction_extraction
// Extract and format splice junctions from exon coordinates as GRanges or GInteractions.
// Input: annotations.gtf.gz
// Container: quay.io/biocontainers/bioconductor-transmogr:1.6.0--r45h01b2380_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRANSMOGR_SPLICE_JUNCTION_EXTRACTION {
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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg38", "GenomicFeatures", "VariantAnnotation", "extraChIPs", "rtracklayer", "transmogR")
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
    library(BSgenome.Hsapiens.UCSC.hg38)
    
    # Setup genome and seqinfo
    chr1 <- getSeq(BSgenome.Hsapiens.UCSC.hg38, "chr1")
    chr1 <- as(chr1, "DNAStringSet")
    names(chr1) <- "chr1"
    sq <- seqinfo(chr1)
    genome(sq) <- "GRCh38"
    
    # 1. Import GTF annotations from user input file
    f <- "annotations.gtf.gz"
    gtf <- import.gff(f, which = GRanges(sq))
    seqinfo(gtf) <- sq
    gtf <- splitAsList(gtf, gtf\$type)
    
    # 2. Extract splice junctions using sjFromExons()
    ec <- c("transcript_id", "transcript_name", "gene_id", "gene_name")
    sj <- sjFromExons(gtf\$exon, extra_cols = ec)
    
    # Save GRanges splice junctions
    saveRDS(sj, "sj_granges.rds")
    
    # 3. Simplify shared junctions using chopMC()
    sj_chopped <- chopMC(sj)
    saveRDS(sj_chopped, "sj_chopped.rds")
    
    # Extract splice junctions as GInteractions
    sj <- sjFromExons(gtf\$exon, extra_cols = ec, as = "GInteractions")
    saveRDS(sj, "sj_ginteractions.rds")
    
    # Subset for specific transcript
    sj_sub <- subset(sj, transcript_name == "DDX11L17-201")
    saveRDS(sj_sub, "sj_subset.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_TRANSMOGR_SPLICE_JUNCTION_EXTRACTION":
        transmogr: \$(Rscript -e 'cat(as.character(packageVersion("transmogr")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_splice_junction_extraction.csv versions.yml
    """
}

workflow BIOC_TRANSMOGR_SPLICE_JUNCTION_EXTRACTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ annotations.gtf.gz ] ]

    main:
    BIOC_TRANSMOGR_SPLICE_JUNCTION_EXTRACTION(ch_input)

    emit:
    tables   = BIOC_TRANSMOGR_SPLICE_JUNCTION_EXTRACTION.out.tables
    plots    = BIOC_TRANSMOGR_SPLICE_JUNCTION_EXTRACTION.out.plots
    objects  = BIOC_TRANSMOGR_SPLICE_JUNCTION_EXTRACTION.out.objects
    versions = BIOC_TRANSMOGR_SPLICE_JUNCTION_EXTRACTION.out.versions
}
