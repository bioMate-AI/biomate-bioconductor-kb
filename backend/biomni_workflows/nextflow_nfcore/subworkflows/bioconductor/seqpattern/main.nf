#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: seqPattern
// Visualising oligonucleotide patterns and sequence motifs occurrences across a large set of sequences
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/seqPattern/inst/doc/seqPattern.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("seqPattern")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQPATTERN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-seqpattern"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-seqpattern:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-seqpattern:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_seqpattern_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_seqpattern_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_seqpattern_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(seqPattern)
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- Pattern Occurrence List Generation [] ---
    # Key functions: getPatternOccurrenceList
    occurrence_list <- getPatternOccurrenceList(
        regionsSeq = sequences,
        patterns = c("CG", "TA", "GC"),
        seqpos = seq(-15, 14)
    )


    # --- Density Map Visualisation [] ---
    # Key functions: plotPatternDensityMap
    plotPatternDensityMap(
        regionsSeq = sequences,
        patterns = c("CG", "GC"),
        seqpos = seq(-15, 14),
        colormap = "Blues",
        enableCentering = TRUE,
        useMulticore = FALSE
    )


    # --- Average Occurrence Profiling [] ---
    # Key functions: plotPatternOccurrenceAverage
    plotPatternOccurrenceAverage(
        regionsSeq = sequences,
        patterns = c("TA", "CG"),
        seqpos = seq(-15, 14),
        flank = 2,
        smoothingWindow = 3,
        color = c("red", "blue")
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_seqpattern_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_seqpattern_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_seqpattern_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEQPATTERN:", paste0("    seqpattern: ", packageVersion("seqPattern"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seqpattern_results.csv
    touch ${prefix}_seqpattern_output.rds
    echo "BIOC_SEQPATTERN:" > versions.yml
    echo "    seqpattern: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEQPATTERN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEQPATTERN(ch_input)

    emit:
    results  = BIOC_SEQPATTERN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEQPATTERN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEQPATTERN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEQPATTERN.out.versions  // channel: path(versions.yml)
}
