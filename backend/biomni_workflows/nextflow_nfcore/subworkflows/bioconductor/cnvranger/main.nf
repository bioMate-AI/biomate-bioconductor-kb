#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CNVRanger — cnv_population_summarization_and_overlap
// Summarize individual CNV calls across a population and assess their overlap with functional genomic regions using permutation tests.
// Input: Silva16_PONE_CNV_calls.csv, EnsDb
// Container: quay.io/biocontainers/bioconductor-cnvranger:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Btaurus.UCSC.bosTau6.masked, CNVRanger, GenomeInfoDb, GenomicRanges, S4Vectors, ensembldb, regioneR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read CNV calls and represent them as a GRangesList
//  * 2. [Visualization & Output] Summarize individual calls into population-level CNV
//  * 3. [Visualization & Output] Identify recurrent CNV regions
//  * 4. [Visualization & Output] Find overlaps between CNV regions and functional genomic
//  * 5. [Visualization & Output] Perform an overlap permutation test

nextflow.enable.dsl = 2

process BIOC_CNVRANGER_CNV_POPULATION_SUMMARIZATION_AND_OVERLAP {
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
    .bm_deps <- c("CNVRanger", "GenomicRanges", "S4Vectors", "regioneR", "ensembldb", "BSgenome.Btaurus.UCSC.bosTau6.masked")
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
    library(CNVRanger)
    library(GenomicRanges)
    library(S4Vectors)
    library(regioneR)
    library(ensembldb)
    library(BSgenome.Btaurus.UCSC.bosTau6.masked)
    
    # --- Read CNV calls and represent them as a GRangesList ---
    calls <- read.csv("Silva16_PONE_CNV_calls.csv", as.is=TRUE)
    sample_id_col <- colnames(calls)[4]
    grl <- GenomicRanges::makeGRangesListFromDataFrame(calls, split.field=sample_id_col, keep.extra.columns=TRUE)
    grl <- GenomicRanges::sort(grl)
    
    # --- Summarize individual calls into population-level CNV ---
    cnvrs <- populationRanges(grl, density=0.1)
    ro.cnvrs <- populationRanges(grl, mode="RO", ro.thresh=0.51)
    
    # --- Identify recurrent CNV regions ---
    cnvrs <- populationRanges(grl, density=0.1, est.recur=TRUE)
    recurrent_cnvrs <- subset(cnvrs, pvalue < 0.05)
    
    # Plot recurrent regions and save to PDF
    pdf("recurrent_regions_plot.pdf")
    plotRecurrentRegions(cnvrs, genome="bosTau6", chr="chr1")
    dev.off()
    
    # --- Find overlaps between CNV regions and functional genomic ---
    ensdb <- readRDS("EnsDb")
    bt.genes <- ensembldb::genes(ensdb)
    GenomeInfoDb::seqlevelsStyle(bt.genes) <- "UCSC"
    
    sel.genes <- subset(bt.genes, seqnames %in% paste0("chr", 1:2))
    sel.genes <- subset(sel.genes, gene_biotype == "protein_coding")
    sel.cnvrs <- subset(cnvrs, seqnames %in% paste0("chr", 1:2))
    
    olaps <- GenomicRanges::findOverlaps(sel.genes, sel.cnvrs, ignore.strand=TRUE)
    qh <- S4Vectors::queryHits(olaps)
    sh <- S4Vectors::subjectHits(olaps)
    cgenes <- sel.genes[qh]
    cgenes\$type <- sel.cnvrs\$type[sh]
    
    # Plot OncoPrint and save to PDF
    pdf("oncoprint_plot.pdf")
    cnvOncoPrint(grl, cgenes)
    dev.off()
    
    # --- Perform an overlap permutation test ---
    res <- regioneR::overlapPermTest(A=sel.cnvrs, B=sel.genes, ntimes=100, genome="bosTau6", mask=NA, per.chromosome=TRUE, count.once=TRUE)
    perm_summary <- summary(res[[1]]\$permuted)
    
    # Plot permutation test results and save to PDF
    pdf("permutation_test_plot.pdf")
    plot(res)
    dev.off()
    
    # Write outputs to files
    write.csv(as.data.frame(cnvrs), "cnvrs_summary.csv", row.names=FALSE)
    write.csv(as.data.frame(ro.cnvrs), "ro_cnvrs_summary.csv", row.names=FALSE)
    write.csv(as.data.frame(recurrent_cnvrs), "recurrent_cnvrs.csv", row.names=FALSE)
    write.csv(as.data.frame(cgenes), "overlapping_genes.csv", row.names=FALSE)
    saveRDS(res, "permutation_results.rds")
    
    # Save permutation summary stats
    write.csv(as.data.frame(as.list(perm_summary)), "permutation_summary.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_CNVRANGER_CNV_POPULATION_SUMMARIZATION_AND_OVERLAP":',
        paste0('    CNVRanger: ', as.character(packageVersion('CNVRanger')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnv_population_summarization_and_overlap.csv versions.yml
    """
}

workflow BIOC_CNVRANGER_CNV_POPULATION_SUMMARIZATION_AND_OVERLAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Silva16_PONE_CNV_calls.csv, EnsDb ] ]

    main:
    BIOC_CNVRANGER_CNV_POPULATION_SUMMARIZATION_AND_OVERLAP(ch_input)

    emit:
    tables   = BIOC_CNVRANGER_CNV_POPULATION_SUMMARIZATION_AND_OVERLAP.out.tables
    plots    = BIOC_CNVRANGER_CNV_POPULATION_SUMMARIZATION_AND_OVERLAP.out.plots
    objects  = BIOC_CNVRANGER_CNV_POPULATION_SUMMARIZATION_AND_OVERLAP.out.objects
    versions = BIOC_CNVRANGER_CNV_POPULATION_SUMMARIZATION_AND_OVERLAP.out.versions
}
