#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CNVRanger
// The CNVRanger package implements a comprehensive tool suite for CNV analysis. This includes function
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CNVRanger/inst/doc/CNVRanger.R
// Upstream  : AnnotationHub, SummarizedExperiment, TCGAutils, curatedTCGAData, regioneR
// Downstream: none
//
// Install: BiocManager::install("CNVRanger")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CNVRANGER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cnvranger"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cnvranger:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cnvranger:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cnvranger_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cnvranger_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cnvranger_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnotationHub)
    library(RaggedExperiment)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Access AnnotationHub resources [] ---
    # Key functions: AnnotationHub, query, granges, SummarizedExperiment
    library(SummarizedExperiment)
    rranges <- GenomicRanges::granges(sel.genes)[rownames(rcounts)]
    rse <- SummarizedExperiment(assays=list(rcounts=rcounts), rowRanges=rranges)
    # --- Find overlapping genomic intervals [] ---
    # Key functions: findOverlaps, queryHits, subjectHits
    olaps <- GenomicRanges::findOverlaps(sel.genes, sel.cnvrs, ignore.strand=TRUE)
    qh <- S4Vectors::queryHits(olaps)
    sh <- S4Vectors::subjectHits(olaps)
    # --- Assay data access [] ---
    # Key functions: include_graphics, makeGRangesListFromDataFrame, RaggedExperiment, assay, rnorm, colData, populationRanges, plotRecurrentRegions
    order.chrs <- c(1:24, "25LG1", "25LG2", 27:28, "LGE22", "1A", "4A")
    chr.size.file <- file.path(data.dir, "Parus_major_chr_sizes.txt")
    chr.sizes <- scan(chr.size.file)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cnvranger_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cnvranger_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cnvranger_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CNVRANGER:", paste0("    cnvranger: ", packageVersion("CNVRanger"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnvranger_results.csv
    touch ${prefix}_cnvranger_output.rds
    echo "BIOC_CNVRANGER:" > versions.yml
    echo "    cnvranger: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CNVRANGER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CNVRANGER(ch_input)

    emit:
    results  = BIOC_CNVRANGER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CNVRANGER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CNVRANGER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CNVRANGER.out.versions  // channel: path(versions.yml)
}
