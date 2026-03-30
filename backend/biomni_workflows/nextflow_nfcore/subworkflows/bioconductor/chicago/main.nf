#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Chicago
// A pipeline for analysing Capture Hi-C data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Chicago/inst/doc/Chicago.R
// Upstream  : AnnotationHub, GenomicInteractions, GenomicRanges, PCHiCdata
// Downstream: PCHiCdata
//
// Install: BiocManager::install("Chicago")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHICAGO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chicago"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chicago:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chicago:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chicago_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chicago_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chicago_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Chicago)
    library(jsonlite)

    # --- Anchortwo [] ---
    # Key functions: anchorTwo, renameSeqlevels
    ---------------------------------------------------------------------
    otherEnds <- anchorTwo(gi)
    otherEnds <- renameSeqlevels(otherEnds, c("chr20","chr21"))
    # --- Findoverlaps [] ---
    # Key functions: findOverlaps
    ---------------------------------------------------------------------
    findOverlaps(otherEnds, enhancerTrack)
    # --- Head [] ---
    # Key functions: intData
    ---------------------------------------------------------------------
    head(intData(cd), 2)
    # --- Copycd [] ---
    # Key functions: copyCD
    ---------------------------------------------------------------------
    newCd = copyCD(cd)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chicago_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chicago_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chicago_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHICAGO:", paste0("    chicago: ", packageVersion("Chicago"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chicago_results.csv
    touch ${prefix}_chicago_output.rds
    echo "BIOC_CHICAGO:" > versions.yml
    echo "    chicago: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHICAGO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHICAGO(ch_input)

    emit:
    results  = BIOC_CHICAGO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHICAGO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHICAGO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHICAGO.out.versions  // channel: path(versions.yml)
}
