#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: QuasR
// This package provides a framework for the quantification and analysis of Short Reads. It covers a co
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/QuasR/inst/doc/QuasR.R
// Upstream  : BSgenome, BiocManager, Biostrings, GenomicFeatures, Gviz
// Downstream: none
//
// Install: BiocManager::install("QuasR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QUASR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-quasr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-quasr:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-quasr:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_quasr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_quasr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_quasr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DataTrack)
    library(GeneRegionTrack)
    library(GenomeAxisTrack)
    library(IRanges)
    library(jsonlite)

    # --- q Align [] ---
    # Key functions: qAlign
    proj <- qAlign(sampleFile, genomeFile)
    # --- q Q C Report [] ---
    # Key functions: qQCReport
    qQCReport(proj, "extdata/qc_report.pdf")
    # --- promoters [] ---
    # Key functions: promoters, qCount
    library(rtracklayer)
    library(GenomicFeatures)
    txStart <- import.gff(annotFile, format = "gtf", feature.type = "start_codon")
    # --- <sampleFileSeqToBam [] ---
    # Key functions: qAlign
    proj1 <- qAlign(sampleFile1, genomeFile)
    write.table(alignments(proj1)$genome, sampleFile2, sep="\t", row.names=FALSE)
    proj2 <- qAlign(sampleFile2, genomeFile)
    # --- tempdir [] ---
    # Key functions: tempdir, preprocessReads, unlink
    td <- tempdir()
    infiles <- system.file(package = "QuasR", "extdata",
    c("rna_1_1.fq.bz2","rna_2_1.fq.bz2"))
    # --- tempdir [] ---
    # Key functions: tempdir, preprocessReads
    td <- tempdir()
    infiles1 <- system.file(package = "QuasR", "extdata", "rna_1_1.fq.bz2")
    infiles2 <- system.file(package = "QuasR", "extdata", "rna_1_2.fq.bz2")
    # --- ChIP qAlign [] ---
    # Key functions: qAlign
    proj1 <- qAlign(sampleFile, genome = genomeFile, auxiliaryFile = auxFile)
    # --- ChIP qcplot1 [] ---
    # Key functions: qQCReport
    qcdat1 <- qQCReport(proj1, pdfFilename = "extdata/qc_report.pdf")
    # --- ChIP qcplots2 [] ---
    # Key functions: qQCReport
    qQCReport(proj1, pdfFilename = "extdata/qc_report.pdf")
    # --- ChIP alignmentStats [] ---
    # Key functions: alignmentStats
    alignmentStats(proj1)
    # --- ChIP qExportWig [] ---
    # Key functions: qExportWig
    qExportWig(proj1, binsize = 100L, scaling = TRUE, collapseBySample = TRUE)
    # --- ChIP GenomicFeatures [] ---
    # Key functions: scanFaIndex, makeTxDbFromGFF, promoters
    library(txdbmaker)
    chrLen <- scanFaIndex(genomeFile)
    chrominfo <- data.frame(chrom = as.character(seqnames(chrLen)),
    # --- ChIP qCount [] ---
    # Key functions: qCount
    cnt <- qCount(proj1, promRegSel)
    # --- ChIP visualize [] ---
    # Key functions: import, GenomeAxisTrack, DataTrack, GeneRegionTrack, plotTracks
    gr1 <- import("Sample1.wig.gz")
    gr2 <- import("Sample2.wig.gz")
    library(Gviz)
    # --- ChIP qProfile [] ---
    # Key functions: qProfile
    prS <- qProfile(proj1, tssRegions, upstream = 3000, downstream = 3000,
    prO <- qProfile(proj1, tssRegions, upstream = 3000, downstream = 3000,
    lapply(prS, "[", , 1:10)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_quasr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_quasr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_quasr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QUASR:", paste0("    quasr: ", packageVersion("QuasR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quasr_results.csv
    touch ${prefix}_quasr_output.rds
    echo "BIOC_QUASR:" > versions.yml
    echo "    quasr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QUASR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_QUASR(ch_input)

    emit:
    results  = BIOC_QUASR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QUASR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QUASR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QUASR.out.versions  // channel: path(versions.yml)
}
