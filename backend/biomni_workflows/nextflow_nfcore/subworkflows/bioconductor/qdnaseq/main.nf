#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: QDNAseq
// Quantitative DNA sequencing for chromosomal aberrations. The genome is divided into non-overlapping 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/QDNAseq/inst/doc/QDNAseq.R
// Upstream  : Biobase
// Downstream: GeneBreak, QDNAseq.hg19, QDNAseq.mm10
//
// Install: BiocManager::install("QDNAseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QDNASEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-qdnaseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-qdnaseq:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-qdnaseq:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(input_file)

    output:
    tuple val(meta), path("${meta.id}_qdnaseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_qdnaseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_qdnaseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnotatedDataFrame)
    library(Genomes)
    library(jsonlite)

    # --- Binreadcounts [] ---
    # Key functions: binReadCounts
    ## readCounts <- binReadCounts(bins)
    ## # all files ending in .bam from the current working directory
    ##
    ## # or
    ##
    # --- Data [] ---
    # Key functions: data
    data(LGG150)
    readCounts <- LGG150
    readCounts
    # --- Rawprofile [] ---
    # Key functions: highlightFilters
    plot(readCounts, logTransform=FALSE, ylim=c(-50, 200))
    highlightFilters(readCounts, logTransform=FALSE,
      residual=TRUE, blacklist=TRUE)
    # --- Applyfilters [] ---
    # Key functions: applyFilters
    readCountsFiltered <- applyFilters(readCounts, residual=TRUE, blacklist=TRUE)
    # --- Isobar [] ---
    # Key functions: isobarPlot
    isobarPlot(readCountsFiltered)
    # --- Estimatecorrection [] ---
    # Key functions: estimateCorrection
    readCountsFiltered <- estimateCorrection(readCountsFiltered)
    # --- Noise [] ---
    # Key functions: noisePlot
    noisePlot(readCountsFiltered)
    # --- Correctbins [] ---
    # Key functions: correctBins, normalizeBins, smoothOutlierBins
    copyNumbers <- correctBins(readCountsFiltered)
    copyNumbers
    copyNumbersNormalized <- normalizeBins(copyNumbers)
    copyNumbersSmooth <- smoothOutlierBins(copyNumbersNormalized)
    # --- Exportbins [] ---
    # Key functions: exportBins
    ## exportBins(copyNumbersSmooth, file="LGG150.txt")
    ## exportBins(copyNumbersSmooth, file="LGG150.igv", format="igv")
    ## exportBins(copyNumbersSmooth, file="LGG150.bed", format="bed")
    # --- Segmentbins [] ---
    # Key functions: segmentBins, normalizeSegmentedBins
    copyNumbersSegmented <- segmentBins(copyNumbersSmooth, transformFun="sqrt")
    copyNumbersSegmented <- normalizeSegmentedBins(copyNumbersSegmented)
    # --- Callbins [] ---
    # Key functions: callBins
    copyNumbersCalled <- callBins(copyNumbersSegmented)
    # --- Exportbins [] ---
    # Key functions: exportBins
    ## exportBins(copyNumbersCalled, format="vcf")
    ## exportBins(copyNumbersCalled, format="seg")
    # --- Makecgh [] ---
    # Key functions: makeCgh
    cgh <- makeCgh(copyNumbersCalled)
    cgh
    # --- Callbins [] ---
    # Key functions: callBins
    ## copyNumbers <- callBins(..., ncpus=4)
    # --- Plan [] ---
    # Key functions: plan
    ## future::plan("sequential")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_qdnaseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_qdnaseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_qdnaseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QDNASEQ:", paste0("    qdnaseq: ", packageVersion("QDNAseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qdnaseq_results.csv
    touch ${prefix}_qdnaseq_output.rds
    echo "BIOC_QDNASEQ:" > versions.yml
    echo "    qdnaseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QDNASEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input_file) ]

    main:
    BIOC_QDNASEQ(ch_input)

    emit:
    results  = BIOC_QDNASEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QDNASEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QDNASEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QDNASEQ.out.versions  // channel: path(versions.yml)
}
