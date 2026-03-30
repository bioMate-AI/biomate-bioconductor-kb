#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ribosomeProfilingQC
// Ribo-Seq (also named ribosome profiling or footprinting) measures translatome (unlike RNA-Seq, which
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ribosomeProfilingQC/inst/doc/ribosomeProfilingQC.R
// Upstream  : AnnotationDbi, AnnotationHub, BiocManager, ChIPpeakAnno, GenomicFeatures
// Downstream: none
//
// Install: BiocManager::install("ribosomeProfilingQC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RIBOSOMEPROFILINGQC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ribosomeprofilingqc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ribosomeprofilingqc:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ribosomeprofilingqc:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(dgelist)

    output:
    tuple val(meta), path("${meta.id}_ribosomeprofilingqc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ribosomeprofilingqc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ribosomeprofilingqc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BamFile)
    library(DGEList)
    library(jsonlite)

    # --- Import genomic data file [] ---
    # Key functions: scanBamHeader, import, mcols, with, seqlevelsStyle, DGEList, calcNormFactors, estimateDisp
    bamfilename <- system.file("extdata", "RPF.WT.1.bam",
    bamHeader <- Rsamtools::scanBamHeader(bamfilename)
    (chromsomeNameStyle <- GenomeInfoDb::seqlevelsStyle(names(bamHeader[[1]]$targets)))
    # --- Linear model fit (limma) [] ---
    # Key functions: lmFit, eBayes, topTable
    library(limma)
    gp <- c("KD", "KD", "CTL", "CTL") ## sample groups: KD:knockdown; CTL:Control
    TE.log2 <- log2(TE$TE + 1)
    # --- BAM file connection [] ---
    # Key functions: makeTxDbFromGFF, prepareCDS, BamFile, estimatePsite, readsEndPlot, getPsiteCoordinates, summaryReadsLength, strandPlot
    cvgs.utr5 <- coverageDepth(RPFs = bamfilename, gtf = txdb, region="utr5")
    cvgs.CDS <- coverageDepth(RPFs = bamfilename, gtf = txdb, region="cds")
    cvgs.utr3 <- coverageDepth(RPFs = bamfilename, gtf = txdb, region="utr3")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ribosomeprofilingqc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ribosomeprofilingqc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ribosomeprofilingqc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RIBOSOMEPROFILINGQC:", paste0("    ribosomeprofilingqc: ", packageVersion("ribosomeProfilingQC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ribosomeprofilingqc_results.csv
    touch ${prefix}_ribosomeprofilingqc_output.rds
    echo "BIOC_RIBOSOMEPROFILINGQC:" > versions.yml
    echo "    ribosomeprofilingqc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RIBOSOMEPROFILINGQC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(dgelist) ]

    main:
    BIOC_RIBOSOMEPROFILINGQC(ch_input)

    emit:
    results  = BIOC_RIBOSOMEPROFILINGQC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RIBOSOMEPROFILINGQC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RIBOSOMEPROFILINGQC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RIBOSOMEPROFILINGQC.out.versions  // channel: path(versions.yml)
}
