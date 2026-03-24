#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: FastqCleaner
// An interactive web application for quality control, filtering and trimming of FASTQ files. This user
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/FastqCleaner/inst/doc/Overview.R
// Upstream  : Biostrings, ShortRead
// Downstream: none
//
// Install: BiocManager::install("FastqCleaner")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FASTQCLEANER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fastqcleaner"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fastqcleaner:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-fastqcleaner:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_fastqcleaner_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fastqcleaner_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fastqcleaner_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ShortReadQ)
    library(jsonlite)

    # --- Qmean Filter [] ---
    # Key functions: qmean_filter, qual_plot
    ---------------------------------------------------------------------
    # Apply the filter
    filtered <- qmean_filter(my_read, minq = 30)
    # Average qualities after
    qual_plot(filtered, cutoff = 30)
    # --- Random Seq [] ---
    # Key functions: random_seq, sample, random_qual, seq_names, ShortReadQ, isUnique, sread
    ---------------------------------------------------------------------
    # Create duplicated sequences
    s <- random_seq(10, 10)
    s <- sample(s, 30, replace = TRUE)
    # Create a ShortReadQ object

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fastqcleaner_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fastqcleaner_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fastqcleaner_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FASTQCLEANER:", paste0("    fastqcleaner: ", packageVersion("FastqCleaner"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fastqcleaner_results.csv
    touch ${prefix}_fastqcleaner_output.rds
    echo "BIOC_FASTQCLEANER:" > versions.yml
    echo "    fastqcleaner: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FASTQCLEANER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FASTQCLEANER(ch_input)

    emit:
    results  = BIOC_FASTQCLEANER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FASTQCLEANER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FASTQCLEANER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FASTQCLEANER.out.versions  // channel: path(versions.yml)
}
