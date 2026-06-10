#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: QuasR — rna_seq_analysis
// Align paired-end RNA-seq reads using spliced alignment and quantify gene, exon, and junction expression levels.
// Input: samples_rna_paired.txt, hg19sub.fa, hg19sub_annotation.gtf
// Container: quay.io/biocontainers/bioconductor-quasr:1.50.0--r45ha27e39d_0
// Requires: GenomicFeatures, QuasR, Rsamtools, rtracklayer, txdbmaker
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Align reads with spliced alignment using qAlign with Rhisat2
//  * 2. [Core Analysis] Get alignment statistics using alignmentStats
//  * 3. [Core Analysis] Quantify gene and exon expression levels using qCount
//  * 4. [Visualization & Output] Quantify exon-exon junctions using qCount with reportLevel="junction"

nextflow.enable.dsl = 2

process BIOC_QUASR_RNA_SEQ_ANALYSIS {
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
    .bm_deps <- c("GenomicFeatures", "QuasR", "Rsamtools", "rtracklayer", "txdbmaker")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(QuasR)
    library(Rsamtools)
    library(rtracklayer)
    library(GenomicFeatures)
    if (requireNamespace("txdbmaker", quietly = TRUE)) {
        library(txdbmaker)
    }
    
    # Define input files from the working directory
    sampleFile <- "samples_rna_paired.txt"
    genomeFile <- "hg19sub.fa"
    annotFile <- "hg19sub_annotation.gtf"
    
    # Create TxDb object from the GTF annotation and reference genome
    chrLen <- scanFaIndex(genomeFile)
    chrominfo <- data.frame(
        chrom = as.character(seqnames(chrLen)),
        length = width(chrLen),
        is_circular = rep(FALSE, length(chrLen))
    )
    txdb <- makeTxDbFromGFF(
        file = annotFile,
        format = "gtf",
        chrominfo = chrominfo,
        dataSource = "Ensembl",
        organism = "Homo sapiens"
    )
    
    # 1. Align reads with spliced alignment using qAlign with Rhisat2
    proj2 <- qAlign(sampleFile, genome = genomeFile,
                    splicedAlignment = TRUE, aligner = "Rhisat2")
    proj2
    
    # Align reads without spliced alignment for comparison
    proj2unspl <- qAlign(sampleFile, genome = genomeFile,
                         splicedAlignment = FALSE)
    
    # 2. Get alignment statistics using alignmentStats
    stats_spliced <- alignmentStats(proj2)
    stats_unspliced <- alignmentStats(proj2unspl)
    
    # Save alignment statistics
    write.csv(stats_spliced, "alignment_stats_spliced.csv", row.names = TRUE)
    write.csv(stats_unspliced, "alignment_stats_unspliced.csv", row.names = TRUE)
    
    # 3. Quantify gene and exon expression levels using qCount
    geneLevels <- qCount(proj2, txdb, reportLevel = "gene")
    exonLevels <- qCount(proj2, txdb, reportLevel = "exon")
    
    head(geneLevels)
    head(exonLevels)
    
    # Save raw counts
    write.csv(geneLevels, "gene_expression_counts.csv", row.names = TRUE)
    write.csv(exonLevels, "exon_expression_counts.csv", row.names = TRUE)
    
    # Calculate RPKM expression values
    geneRPKM <- t(t(geneLevels[,-1] / geneLevels[,1] * 1000)
                  / colSums(geneLevels[,-1]) * 1e6)
    geneRPKM
    
    # Save RPKM values
    write.csv(geneRPKM, "gene_expression_rpkm.csv", row.names = TRUE)
    
    # 4. Quantify exon-exon junctions using qCount with reportLevel="junction"
    exonJunctions <- qCount(proj2, NULL, reportLevel = "junction")
    exonJunctions
    
    # Save exon junctions as RDS
    saveRDS(exonJunctions, "exon_junctions.rds")
    
    # Overlap with known introns
    knownIntrons <- unlist(intronsByTranscript(txdb))
    isKnown <- overlapsAny(exonJunctions, knownIntrons, type = "equal")
    table(isKnown)
    
    # Save known junctions table
    write.csv(as.data.frame(table(isKnown)), "known_junctions_table.csv", row.names = FALSE)
    
    # Summarize junction counts
    junction_summary <- tapply(rowSums(as.matrix(mcols(exonJunctions))),
                               isKnown, summary)
    saveRDS(junction_summary, "junction_summary.rds")
    
    # Quantify exon body levels (excluding spliced alignments)
    exonBodyLevels <- qCount(proj2, txdb, reportLevel = "exon",
                             includeSpliced = FALSE)
    write.csv(exonBodyLevels, "exon_body_expression_counts.csv", row.names = TRUE)
    
    # Compare exon levels with and without spliced alignments
    diff_summary <- summary(exonLevels - exonBodyLevels)
    saveRDS(diff_summary, "exon_spliced_vs_unspliced_diff_summary.rds")

    writeLines(c(
        '"BIOC_QUASR_RNA_SEQ_ANALYSIS":',
        paste0('    QuasR: ', as.character(packageVersion('QuasR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_seq_analysis.csv versions.yml
    """
}

workflow BIOC_QUASR_RNA_SEQ_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ samples_rna_paired.txt, hg19sub.fa, hg19sub_annotation.gtf ] ]

    main:
    BIOC_QUASR_RNA_SEQ_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_QUASR_RNA_SEQ_ANALYSIS.out.tables
    plots    = BIOC_QUASR_RNA_SEQ_ANALYSIS.out.plots
    objects  = BIOC_QUASR_RNA_SEQ_ANALYSIS.out.objects
    versions = BIOC_QUASR_RNA_SEQ_ANALYSIS.out.versions
}
