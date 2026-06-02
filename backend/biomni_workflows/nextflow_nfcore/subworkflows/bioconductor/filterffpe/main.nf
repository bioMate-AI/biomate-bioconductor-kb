#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: FilterFFPE
// This package finds and filters artificial chimeric reads specifically generated in next-generation s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/FilterFFPE/inst/doc/FilterFFPE.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("FilterFFPE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FILTERFFPE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-filterffpe"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-filterffpe:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-filterffpe:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_filterffpe_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_filterffpe_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_filterffpe_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FilterFFPE)
    library(FFPEReadFilter)
    library(jsonlite)

    # --- Filter BAM by Read Names [] ---
    # Key functions: filterBamByReadNames
    file <- system.file("extdata", "example.bam", package = "FilterFFPE")
    outFolder <- tempdir()
    destination <- paste0(outFolder, "/example.FilterFFPE.bam")
    filterBamByReadNames(
        file = file, 
        readsToFilter = c("read1", "read2"),
        destination = destination, 
        overwrite = TRUE
    )


    # --- One-step FFPE Read Filtering [] ---
    # Key functions: FFPEReadFilter
    file <- system.file("extdata", "example.bam", package = "FilterFFPE")
    outFolder <- tempdir()
    destination <- paste0(outFolder, "/example.FilterFFPE.bam")
    FFPEReadFilter(
        file = file, 
        threads = 2, 
        destination = destination,
        overwrite = TRUE, 
        FFPEReadsFile = paste0(outFolder, "/example.FFPEReads.txt"),
        dupChimFile = paste0(outFolder, "/example.dupChim.txt")
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_filterffpe_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_filterffpe_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_filterffpe_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FILTERFFPE:", paste0("    filterffpe: ", packageVersion("FilterFFPE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_filterffpe_results.csv
    touch ${prefix}_filterffpe_output.rds
    echo "BIOC_FILTERFFPE:" > versions.yml
    echo "    filterffpe: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FILTERFFPE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FILTERFFPE(ch_input)

    emit:
    results  = BIOC_FILTERFFPE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FILTERFFPE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FILTERFFPE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FILTERFFPE.out.versions  // channel: path(versions.yml)
}
