#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dexseq — r_based_bam_workflow
// Perform differential exon usage analysis starting from BAM files and a GTF annotation entirely within R.
// Input: annotation.gtf, sample1.bam, sample2.bam
// Container: quay.io/biocontainers/bioconductor-dexseq:1.56.0--r45hdfd78af_0
// R packages: GenomeInfoDb, GenomicAlignments, GenomicFeatures, Rsamtools, DEXSeq, txdbmaker
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEXSEQ_R_BASED_BAM_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-dexseq:1.56.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomeInfoDb", "GenomicAlignments", "GenomicFeatures", "Rsamtools", "DEXSeq", "txdbmaker", "SummarizedExperiment")
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
    l    library(SummarizedExperiment)
ibrary(GenomicFeatures)
    library(txdbmaker)
    library(Rsamtools)
    library(GenomicAlignments)
    library(GenomeInfoDb)
    library(DEXSeq)
    
    # --- Prepare annotation using makeTxDbFromGFF() and ---
    txdb = makeTxDbFromGFF("annotation.gtf")
    flattenedAnnotation = exonicParts( txdb, linked.to.single.gene.only=TRUE )
    names(flattenedAnnotation) =
        sprintf("%s:E%0.3d", flattenedAnnotation\$gene_id, flattenedAnnotation\$exonic_part)
    
    # --- Count reads overlapping exonic parts using BamFileList() ---
    bamFiles = c( "sample1.bam", "sample2.bam" )
    bamFiles = BamFileList( bamFiles )
    
    # Safely attempt to set seqlevelsStyle to UCSC as in the documented code
    tryCatch({
        seqlevelsStyle(flattenedAnnotation) = "UCSC"
    }, error = function(e) {
        message("Warning: Could not set seqlevelsStyle to UCSC. Proceeding with default style.")
    })
    
    se = summarizeOverlaps(
        flattenedAnnotation, BamFileList(bamFiles), singleEnd=FALSE,
        fragments=TRUE, ignore.strand=TRUE )
    
    # --- Build a DEXSeqDataSet using DEXSeqDataSetFromSE() ---
    colData(se)\$condition = factor(c("untreated1", "untreated3"))
    colData(se)\$libType = factor(c("single-end", "paired-end"))
    dxd = DEXSeqDataSetFromSE( se, design= ~ sample + exon + condition:exon )
    
    # --- Estimate size factors using estimateSizeFactors() ---
    dxd = estimateSizeFactors( dxd )
    
    # --- Estimate dispersions using estimateDispersions() ---
    dxd = estimateDispersions( dxd )
    
    # --- Test for differential exon usage using testForDEU() ---
    dxd = testForDEU( dxd )
    
    # --- Estimate exon fold changes using estimateExonFoldChanges() ---
    dxd = estimateExonFoldChanges( dxd, fitExpToVar="condition")
    
    # --- Extract results using DEXSeqResults() ---
    dxr1 = DEXSeqResults( dxd )
    
    # Write meaningful output files
    write.csv(as.data.frame(dxr1), file="dexseq_results.csv", row.names=TRUE)
    saveRDS(dxd, file="dexseq_dxd.rds")
    saveRDS(dxr1, file="dexseq_results.rds")
    
    # Generate diagnostic and results plots
    pdf("dispersion_plots.pdf")
    plotDispEsts( dxd )
    dev.off()
    
    pdf("ma_plot.pdf")
    plotMA( dxr1, cex=0.8 )
    dev.off()
    
    # Plot the first gene in the results if available
    if (nrow(dxr1) > 0) {
        first_gene = dxr1\$groupID[1]
        pdf("dexseq_plot.pdf")
        plotDEXSeq( dxr1, first_gene, legend=TRUE, cex.axis=1.2, cex=1.3, lwd=2 )
        dev.off()
    }

    writeLines(c(
        '"BIOC_DEXSEQ_R_BASED_BAM_WORKFLOW":',
        paste0('        dexseq: ', as.character(packageVersion("dexseq")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_r_based_bam_workflow.csv versions.yml
    """
}

workflow BIOC_DEXSEQ_R_BASED_BAM_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ annotation.gtf, sample1.bam, sample2.bam ] ]

    main:
    BIOC_DEXSEQ_R_BASED_BAM_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_DEXSEQ_R_BASED_BAM_WORKFLOW.out.tables
    plots    = BIOC_DEXSEQ_R_BASED_BAM_WORKFLOW.out.plots
    objects  = BIOC_DEXSEQ_R_BASED_BAM_WORKFLOW.out.objects
    versions = BIOC_DEXSEQ_R_BASED_BAM_WORKFLOW.out.versions
}
