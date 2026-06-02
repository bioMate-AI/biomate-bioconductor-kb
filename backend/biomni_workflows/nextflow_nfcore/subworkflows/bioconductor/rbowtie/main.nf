#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Rbowtie
// This package provides an R wrapper around the popular bowtie short read aligner and around SpliceMap
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Rbowtie/inst/doc/Rbowtie-Overview.R
// Upstream  : BiocManager
// Downstream: QuasR
//
// Install: BiocManager::install("Rbowtie")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RBOWTIE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rbowtie"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rbowtie:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rbowtie:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rbowtie_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rbowtie_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rbowtie_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SpliceMap)
    library(jsonlite)

    # --- bowtie_build_usage [] ---
    # Key functions: bowtie_build_usage
    bowtie_build_usage()
    # --- bowtie_build [] ---
    # Key functions: bowtie_build
    refFiles <- dir(system.file(package="Rbowtie", "samples", "refs"), full=TRUE)
    indexDir <- file.path(tempdir(), "refsIndex")
    tmp <- bowtie_build(references=refFiles, outdir=indexDir, prefix="index", force=TRUE)
    # --- bowtie [] ---
    # Key functions: bowtie, strtrim
    readsFiles <- system.file(package="Rbowtie", "samples", "reads", "reads.fastq")
    samFiles <- file.path(tempdir(), "alignments.sam")
    # --- Splice Map [] ---
    # Key functions: SpliceMap, strtrim
    readsFiles <- system.file(package="Rbowtie", "samples", "reads", "reads.fastq")
    refDir <- system.file(package="Rbowtie", "samples", "refs", "chr1.fa")
    indexDir <- file.path(tempdir(), "refsIndex")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rbowtie_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rbowtie_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rbowtie_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RBOWTIE:", paste0("    rbowtie: ", packageVersion("Rbowtie"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rbowtie_results.csv
    touch ${prefix}_rbowtie_output.rds
    echo "BIOC_RBOWTIE:" > versions.yml
    echo "    rbowtie: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RBOWTIE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RBOWTIE(ch_input)

    emit:
    results  = BIOC_RBOWTIE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RBOWTIE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RBOWTIE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RBOWTIE.out.versions  // channel: path(versions.yml)
}
