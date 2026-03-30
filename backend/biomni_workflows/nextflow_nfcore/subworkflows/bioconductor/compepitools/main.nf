#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: compEpiTools
// Tools for computational epigenomics developed for the analysis, integration and simultaneous visuali
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/compEpiTools/inst/doc/compEpiTools.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("compEpiTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COMPEPITOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-compepitools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-compepitools:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-compepitools:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_compepitools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_compepitools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_compepitools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(GRannotate)
    library(GRbaseCoverage)
    library(GRcoverage)
    library(GRcoverageInbins)
    library(IRanges)
    library(TSS)
    library(jsonlite)

    # --- Create GenomicRanges object [] ---
    # Key functions: IRanges, GRanges, GRbaseCoverage, GRcoverage, GRcoverageInbins
    bampath <- system.file("extdata", "ex1.bam", package="Rsamtools")
    ir <- IRanges(start=c(1000, 100), end=c(2000, 1000))
    gr <- GRanges(seqnames=Rle(c('seq1','seq2')), ranges=ir)
    # --- T S S [] ---
    # Key functions: TSS, start, end, mcols, GRannotate
    TSSpos <- TSS(txdb)
    start(gr) <- start(gr) - 1000
    end(gr) <- end(gr) - 600
    # --- Create GenomicRanges object [] ---
    # Key functions: start, end, GRanges, heatmapData
    start(gr) <- start(gr) - 1000
    end(gr) <- end(gr) - 600
    extgr <- GRanges(seqnames(gr), ranges=IRanges(start(gr) - 1000, end(gr) + 1000))
    # --- heatmap Plot [] ---
    # Key functions: heatmapPlot
    heatmapPlot(matList=data[[1]], sigMat=pvalues, clusterInds=1:3)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_compepitools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_compepitools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_compepitools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COMPEPITOOLS:", paste0("    compepitools: ", packageVersion("compEpiTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compepitools_results.csv
    touch ${prefix}_compepitools_output.rds
    echo "BIOC_COMPEPITOOLS:" > versions.yml
    echo "    compepitools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COMPEPITOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COMPEPITOOLS(ch_input)

    emit:
    results  = BIOC_COMPEPITOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COMPEPITOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COMPEPITOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COMPEPITOOLS.out.versions  // channel: path(versions.yml)
}
