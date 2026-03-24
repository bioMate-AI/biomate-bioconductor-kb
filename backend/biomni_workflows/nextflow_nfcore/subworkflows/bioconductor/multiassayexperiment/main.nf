#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MultiAssayExperiment
// Harmonize data management of multiple experimental assays performed on an overlapping set of specime
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MultiAssayExperiment/inst/doc/MultiAssayExperiment.R
// Upstream  : GenomicRanges, HDF5Array, RaggedExperiment, S4Vectors, SummarizedExperiment
// Downstream: alabaster.mae, CAGEr, cBioPortalData, ClassifyR, evaluomeR
//
// Install: BiocManager::install("MultiAssayExperiment")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MULTIASSAYEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-multiassayexperiment"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-multiassayexperiment:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-multiassayexperiment:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_multiassayexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_multiassayexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_multiassayexperiment_plots.pdf"),    emit: plots, optional: true
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
    library(MultiAssayExperiment)
    library(RaggedExperiment)
    library(jsonlite)

    # --- Data import and loading [] ---
    # Key functions: runif, GRanges, IRanges, sample
    ---------------------------------------------------------------------
    gr <- GRanges(seqnames = c("chr1", "chr1", "chr2"), strand = c("-", "+", "+"),
                  ranges = IRanges(start = c(230602, 443625, 934533),
                                   end = c(330701, 443724, 934632)))
    # --- Quality control and filtering [] ---
    # Key functions: colData, MultiAssayExperiment, metadata, experiments, sampleMap, subsetByRow, assay, getWithColData
    ---------------------------------------------------------------------
    simpleMultiAssay2 <- MultiAssayExperiment(experiments=doubleExp,
                                              colData=patient.data)
    simpleMultiAssay2
    colData(simpleMultiAssay2)
    # --- MultiAssayExperiment analysis [] ---
    # Key functions: MultiAssayExperiment, slotNames, experiments, frame, rnorm, sample, listToMap, objlist
    ---------------------------------------------------------------------
    grlls <- list(chr = rep("chr1", nrows), start = seq(11, 15),
        end = seq(12, 16), strand = c("+", "-", "+", "*", "*"),
        score = seq(1, 5), specimen = c("a", "a", "b", "b", "c"),
        gene_symbols = paste0("GENE", letters[seq_len(nrows)]))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_multiassayexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_multiassayexperiment_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_multiassayexperiment_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MULTIASSAYEXPERIMENT:", paste0("    multiassayexperiment: ", packageVersion("MultiAssayExperiment"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiassayexperiment_results.csv
    touch ${prefix}_multiassayexperiment_output.rds
    echo "BIOC_MULTIASSAYEXPERIMENT:" > versions.yml
    echo "    multiassayexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MULTIASSAYEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MULTIASSAYEXPERIMENT(ch_input)

    emit:
    results  = BIOC_MULTIASSAYEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MULTIASSAYEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MULTIASSAYEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MULTIASSAYEXPERIMENT.out.versions  // channel: path(versions.yml)
}
