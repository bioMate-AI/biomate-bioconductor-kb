#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Streamer
// Large data files can be difficult to work with in R, where data generally resides in memory. This pa
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Streamer/inst/doc/Streamer.R
// Upstream  : GenomicAlignments
// Downstream: none
//
// Install: BiocManager::install("Streamer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_STREAMER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-streamer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-streamer:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-streamer:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_streamer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_streamer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_streamer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Streamer)
    library(GRanges)
    library(IRanges)
    library(Rle)
    library(Stream)
    library(jsonlite)

    # --- Producer Initialization ---
    # Key functions: Producer, setRefClass
    .MyProducer <- setRefClass("MyProducer",
        contains = "Producer",
        fields = list(data = "list")
    )
    .MyProducer$methods(
        yield = function() {
            if (length(.self$data) == 0) return(list())
            val <- .self$data[[1]]
            .self$data <- .self$data[-1]
            list(val)
        }
    )
    prod <- .MyProducer$new(data = list(1:10, 11:20, 21:30))

    # --- Consumer Configuration ---
    # Key functions: Consumer, setRefClass
    .MyConsumer <- setRefClass("MyConsumer",
        contains = "Consumer"
    )
    .MyConsumer$methods(
        yield = function() {
            input <- callSuper()[[1]]
            if (length(input) == 0) return(NULL)
            sum(input)
        }
    )
    cons <- .MyConsumer$new()

    # --- Stream Assembly ---
    # Key functions: Stream, status
    stream <- Stream(prod, cons)
    stream_status <- status(stream)

    # --- Data Streaming and Processing ---
    # Key functions: yield, reset
    results <- list()
    results[[1]] <- yield(stream)
    results[[2]] <- yield(stream)
    results[[3]] <- yield(stream)
    reset(stream)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_streamer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_streamer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_streamer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_STREAMER:", paste0("    streamer: ", packageVersion("Streamer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_streamer_results.csv
    touch ${prefix}_streamer_output.rds
    echo "BIOC_STREAMER:" > versions.yml
    echo "    streamer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_STREAMER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_STREAMER(ch_input)

    emit:
    results  = BIOC_STREAMER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_STREAMER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_STREAMER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_STREAMER.out.versions  // channel: path(versions.yml)
}
