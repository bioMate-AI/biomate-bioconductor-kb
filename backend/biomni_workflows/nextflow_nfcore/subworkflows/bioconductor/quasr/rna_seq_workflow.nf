#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: quasr — rna_seq_workflow
// Perform spliced alignment of RNA-seq reads and quantify expression at gene, exon, and junction levels.
// Input: samples_rna_paired.txt, hg19sub.fa, hg19sub_annotation.gtf
// Container: quay.io/biocontainers/bioconductor-quasr:1.50.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QUASR_RNA_SEQ_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-quasr:1.50.0--r45ha27e39d_0"

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
    .bm_deps <- c("GenomicFeatures", "QuasR", "Rsamtools", "txdbmaker")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(QuasR)
    library(Rsamtools)
    if (!requireNamespace("txdbmaker", quietly = TRUE)) {
        library(GenomicFeatures)
    } else {
        library(txdbmaker)
        library(GenomicFeatures)
    }
    
    # Define input files from the working directory
    sampleFile <- "samples_rna_paired.txt"
    genomeFile <- "hg19sub.fa"
    annotFile <- "hg19sub_annotation.gtf"
    
    # Create TxDb object from the GTF and genome FASTA
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
    
    # 1. Align paired-end reads with spliced alignment enabled using qAlign
    proj2 <- qAlign(sampleFile, genome = genomeFile,
                    splicedAlignment = TRUE, aligner = "Rhisat2")
    proj2
    
    # 2. Quantify gene and exon expression levels using qCount
    geneLevels <- qCount(proj2, txdb, reportLevel = "gene")
    exonLevels <- qCount(proj2, txdb, reportLevel = "exon")
    
    # Calculate RPKM expression values
    geneRPKM <- t(t(geneLevels[,-1] / geneLevels[,1] * 1000)
                  / colSums(geneLevels[,-1]) * 1e6)
    
    # 3. Quantify exon-exon junctions using qCount with reportLevel="junction"
    exonJunctions <- qCount(proj2, NULL, reportLevel = "junction")
    
    # 4. Quantify exon body levels excluding spliced alignments using qCount with includeSpliced=FALSE
    exonBodyLevels <- qCount(proj2, txdb, reportLevel = "exon",
                             includeSpliced = FALSE)
    
    # Write outputs to the working directory
    write.csv(geneLevels, "gene_levels.csv", row.names = TRUE)
    write.csv(exonLevels, "exon_levels.csv", row.names = TRUE)
    write.csv(geneRPKM, "gene_rpkm.csv", row.names = TRUE)
    write.csv(as.data.frame(exonJunctions), "exon_junctions.csv", row.names = FALSE)
    write.csv(exonBodyLevels, "exon_body_levels.csv", row.names = TRUE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_QUASR_RNA_SEQ_WORKFLOW":
        quasr: \$(Rscript -e 'cat(as.character(packageVersion("quasr")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_seq_workflow.csv versions.yml
    """
}

workflow BIOC_QUASR_RNA_SEQ_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ samples_rna_paired.txt, hg19sub.fa, hg19sub_annotation.gtf ] ]

    main:
    BIOC_QUASR_RNA_SEQ_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_QUASR_RNA_SEQ_WORKFLOW.out.tables
    plots    = BIOC_QUASR_RNA_SEQ_WORKFLOW.out.plots
    objects  = BIOC_QUASR_RNA_SEQ_WORKFLOW.out.objects
    versions = BIOC_QUASR_RNA_SEQ_WORKFLOW.out.versions
}
