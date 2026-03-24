#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ShortRead
// This package implements sampling, iteration, and input of FASTQ files. The package includes function
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ShortRead/inst/doc/Overview.R
// Upstream  : none
// Downstream: chipseq, EDASeq, esATAC, girafe, OTUbase
//
// Install: BiocManager::install("ShortRead")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SHORTREAD {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-shortread"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-shortread:1.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-shortread:1.64.0--r44_0'}"

    input:
    tuple val(meta), path(ggplot_object)

    output:
    tuple val(meta), path("${meta.id}_shortread_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_shortread_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_shortread_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FastqSampler)
    library(FastqStreamer)
    library(SolexaPath)
    library(jsonlite)

    # --- FastqSampler analysis [] ---
    # Key functions: FastqSampler, FastqStreamer, yield, countFastq, encoding, dir, open, trimTailw
    sampler <- FastqSampler('E-MTAB-1147/fastq/ERR127302_1.fastq.gz', 20000)
    set.seed(123); ERR127302_1 <- yield(sampler)
    sampler <- FastqSampler('E-MTAB-1147/fastq/ERR127302_2.fastq.gz', 20000)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_shortread_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_shortread_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_shortread_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SHORTREAD:", paste0("    shortread: ", packageVersion("ShortRead"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_shortread_results.csv
    touch ${prefix}_shortread_output.rds
    echo "BIOC_SHORTREAD:" > versions.yml
    echo "    shortread: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SHORTREAD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(ggplot_object) ]

    main:
    BIOC_SHORTREAD(ch_input)

    emit:
    results  = BIOC_SHORTREAD.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SHORTREAD.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SHORTREAD.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SHORTREAD.out.versions  // channel: path(versions.yml)
}
