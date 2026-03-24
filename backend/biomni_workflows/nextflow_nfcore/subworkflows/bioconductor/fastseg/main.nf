#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: fastseg
// fastseg implements a very fast and efficient segmentation algorithm. It has similar functionality as
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/fastseg/inst/doc/fastseg.R
// Upstream  : DNAcopy, GenomicRanges, oligo
// Downstream: none
//
// Install: BiocManager::install("fastseg")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FASTSEG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fastseg"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fastseg:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-fastseg:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_fastseg_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fastseg_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fastseg_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: na
    ---------------------------------------------------------------------
    data(coriell)
    head(coriell)
    samplenames <- colnames(coriell)[4:5]
    data <- as.matrix(coriell[4:5])
    # --- Granges [] ---
    # Key functions: GRanges, IRanges, mcols, fastseg
    ---------------------------------------------------------------------
    library("GenomicRanges")
    ## with both individuals
    gr <- GRanges(seqnames=chrom,
            ranges=IRanges(maploc, end=maploc))
    # --- Fastseg [] ---
    # Key functions: fastseg
    ---------------------------------------------------------------------
    data2 <- data[, 1]
    res <- fastseg(data2)
    head(res)
    # --- Granges [] ---
    # Key functions: GRanges, IRanges, mcols, fastseg
    ---------------------------------------------------------------------
    ## with both individuals
    gr <- GRanges(seqnames=chrom,
            ranges=IRanges(maploc, end=maploc))
    mcols(gr) <- data
    # --- Segplot [] ---
    # Key functions: segPlot
    ---------------------------------------------------------------------
    segPlot(gr,res, plot.type="w")
    # --- Data [] ---
    # Key functions: time, fastseg
    ---------------------------------------------------------------------
    data(fastsegData)
    system.time(res <- fastseg(fastsegData))
    # --- Segplot [] ---
    # Key functions: segPlot
    ---------------------------------------------------------------------
    segPlot(fastsegData,res, plot.type="w")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fastseg_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fastseg_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fastseg_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FASTSEG:", paste0("    fastseg: ", packageVersion("fastseg"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fastseg_results.csv
    touch ${prefix}_fastseg_output.rds
    echo "BIOC_FASTSEG:" > versions.yml
    echo "    fastseg: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FASTSEG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FASTSEG(ch_input)

    emit:
    results  = BIOC_FASTSEG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FASTSEG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FASTSEG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FASTSEG.out.versions  // channel: path(versions.yml)
}
