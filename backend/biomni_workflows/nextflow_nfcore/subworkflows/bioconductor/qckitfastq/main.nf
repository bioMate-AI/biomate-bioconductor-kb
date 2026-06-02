#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: qckitfastq
// Assessment of FASTQ file format with multiple metrics including quality score, sequence content, ove
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/qckitfastq/inst/doc/vignette-qckitfastq.R
// Upstream  : seqTools, ShortRead, rbenchmark
// Downstream: none
//
// Install: BiocManager::install("qckitfastq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QCKITFASTQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-qckitfastq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-qckitfastq:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-qckitfastq:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_qckitfastq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_qckitfastq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_qckitfastq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(qckitfastq)
    library(jsonlite)


    # --- Loading File [] ---
    # Key functions: fastqq, extdata, qckitfastq
    library(qckitfastq)
    infile <- system.file("extdata", "10^5_reads_test.fq.gz", package = "qckitfastq")
    fseq <- seqTools::fastqq(infile)

    # --- Read Length [] ---
    # Key functions: read_length, kable_styling, plot_read_length
    read_len <- read_length(fseq)
    kable(head(read_len)) %>% kable_styling()
    plot_read_length(read_len)

    # --- Per Base Sequence Quality [] ---
    # Key functions: per_base_quality, kable_styling, plot_per_base_quality
    bs <- per_base_quality(infile)
    kable(head(bs)) %>% kable_styling()
    plot_per_base_quality(bs)

    # --- Per Read Quality [] ---
    # Key functions: per_read_quality, kable_styling, plot_per_read_quality
    prq <- per_read_quality(infile)
    kable(head(prq)) %>% kable_styling()
    plot_per_read_quality(prq)

    # --- Gc Content [] ---
    # Key functions: GC_content, kable_styling, plot_GC_content
    gc_df <- GC_content(infile)
    kable(head(gc_df)) %>% kable_styling()
    plot_GC_content(gc_df)

    # --- Nucleotide Read Content [] ---
    # Key functions: read_base_content, kable_styling, read_content, plot_read_content
    scA <- read_base_content(fseq, content = "A")
    kable(head(scA)) %>% kable_styling()
    rc <- read_content(fseq)
    kable(head(rc)) %>% kable_styling()
    plot_read_content(rc)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_qckitfastq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_qckitfastq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_qckitfastq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QCKITFASTQ:", paste0("    qckitfastq: ", packageVersion("qckitfastq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qckitfastq_results.csv
    touch ${prefix}_qckitfastq_output.rds
    echo "BIOC_QCKITFASTQ:" > versions.yml
    echo "    qckitfastq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QCKITFASTQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_QCKITFASTQ(ch_input)

    emit:
    results  = BIOC_QCKITFASTQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QCKITFASTQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QCKITFASTQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QCKITFASTQ.out.versions  // channel: path(versions.yml)
}
