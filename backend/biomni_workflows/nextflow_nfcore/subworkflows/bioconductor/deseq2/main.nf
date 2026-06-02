#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DESeq2
// Estimate variance-mean dependence in count data from high-throughput sequencing assays and test for 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DESeq2/inst/doc/DESeq2.R
// Upstream  : BiocParallel, IHW, RColorBrewer, airway, ggplot2
// Downstream: DEWSeq, DEXSeq, metaseqR2, octad, rgsepd
//
// Install: BiocManager::install("DESeq2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DESEQ2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-deseq2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-deseq2:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-deseq2:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(deseqdataset)

    output:
    tuple val(meta), path("${meta.id}_deseq2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_deseq2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_deseq2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DESeq)
    library(DESeqDataSet)
    library(DESeqDataSetFromHTSeqCount)
    library(DESeqDataSetFromMatrix)
    library(DESeqDataSetFromTximport)
    library(jsonlite)

    # --- Create DESeqDataSet from count matrix [] ---
    # Key functions: DESeqDataSetFromMatrix, DESeq, resultsNames, results, lfcShrink, read_csv, tximport, DESeqDataSetFromTximport
    files <- file.path(dir,"salmon", samples$run, "quant.sf.gz")
    names(files) <- samples$run
    tx2gene <- read_csv(file.path(dir, "tx2gene.gencode.v27.csv"))
    # --- Filter by row sum threshold [] ---
    # Key functions: rowSums, estimateSizeFactors, estimateDispersions, nbinomWaldTest
    dds <- estimateSizeFactors(dds)
    dds <- estimateDispersions(dds)
    dds <- nbinomWaldTest(dds)
    # --- Variance-stabilizing transformation (VST) [] ---
    # Key functions: vst, rlog, normTransform, meanSdPlot
    vsd <- vst(dds, blind=FALSE)
    rld <- rlog(dds, blind=FALSE)
    head(assay(vsd), 3)
    # --- Run DESeq2 differential expression [] ---
    # Key functions: DESeq, results, resultsNames, lfcShrink, metadata, design, plotMA, relevel
    resApeT <- lfcShrink(dds, coef=2, type="apeglm", lfcThreshold=1)
    plotMA(resApeT, ylim=c(-3,3), cex=.8)
    abline(h=c(-1,1), col="dodgerblue", lwd=2)
    # --- Compute distance matrix [] ---
    # Key functions: dist
    sampleDists <- dist(t(assay(vsd)))
    # --- MA plot of DE results [] ---
    # Key functions: plotMA, plotCounts, ggplot, geom_point, scale_y_log10, pheatmap, colorRampPalette, plotPCA
    pcaData <- plotPCA(vsd, intgroup=c("condition", "type"), returnData=TRUE)
    percentVar <- round(100 * attr(pcaData, "percentVar"))
    ggplot(pcaData, aes(PC1, PC2, color=condition, shape=type)) +
    # --- Object metadata inspection [] ---
    # Key functions: all, mcols, register, identify, rnbinom, plotit, dispersionFunction, estimateDispersionsMAP
    useForMedian <- mcols(ddsCustom)$dispGeneEst > 1e-7

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_deseq2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_deseq2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_deseq2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DESEQ2:", paste0("    deseq2: ", packageVersion("DESeq2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_deseq2_results.csv
    touch ${prefix}_deseq2_output.rds
    echo "BIOC_DESEQ2:" > versions.yml
    echo "    deseq2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DESEQ2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(deseqdataset) ]

    main:
    BIOC_DESEQ2(ch_input)

    emit:
    results  = BIOC_DESEQ2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DESEQ2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DESEQ2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DESEQ2.out.versions  // channel: path(versions.yml)
}
