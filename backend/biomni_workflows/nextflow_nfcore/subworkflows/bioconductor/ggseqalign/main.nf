#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ggseqalign
// Simple visualizations of alignments of DNA or AA sequences as well as arbitrary strings. Compatible 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ggseqalign/inst/doc/ggseqalign.R
// Upstream  : Biostrings, ggplot2
// Downstream: none
//
// Install: BiocManager::install("ggseqalign")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GGSEQALIGN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ggseqalign"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ggseqalign:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ggseqalign:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ggseqalign_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ggseqalign_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ggseqalign_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ggseqalign)
    library(jsonlite)


    # --- Showcase [] ---
    # Key functions: set, readDNAStringSet, extdata, dm3_upstream2000.fa.gz
    ### This chunk dynamically creates fig:showcase but is hidden in the vignette.
    # It is meant to give an initial impression of a real use case without 
    # presenting overwhelming code at the start. This chunk is recreated in 
    # 'ggplot-mod' in its entirety aside from the global figure output setting.

    library(Biostrings)
    library(ggseqalign)
    library(ggplot2)

    knitr::opts_chunk$set(fig.dim = c(6, 4))

    dna <- readDNAStringSet(system.file("extdata", "dm3_upstream2000.fa.gz",
        package = "Biostrings"
    ))


    # --- Noisefig [] ---
    # Key functions: readDNAStringSet, substr, extdata, dm3_upstream2000.fa.gz, reference
    # load
    dna <- Biostrings::readDNAStringSet(system.file("extdata",
        "dm3_upstream2000.fa.gz",
        package = "Biostrings"
    ))
    q <- as(
        c(substr(dna[[1]], 100, 300)),
        "DNAStringSet"
    )
    s <- as(
        c(substr(dna[[2]], 100, 300)),
        "DNAStringSet"
    )
    names(q) <- c("noisy alignment")
    names(s) <- "reference"

    # --- Noisefignolab [] ---
    # Key functions: plot_sequence_alignment, alignment_table, element_text, readDNAStringSet, extdata, dm3_upstream2000.fa.gz
    plot_sequence_alignment(alignment_table(q, s), hide_mismatches = TRUE) +
        theme(text = element_text(size = 15))

    ## ----ggplot-mod, fig.cap="Styling with ggplot2. In this example, text size was increased, axis labels were added, x-axis text rotated and the color scheme changed.", warning=FALSE----
    library(ggseqalign)
    library(ggplot2)
    library(Biostrings)

    dna <- readDNAStringSet(system.file("extdata", "dm3_upstream2000.fa.gz",
        package = "Biostrings"
    ))

    q <- dna[2:4]
    s <- dna[5]


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ggseqalign_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ggseqalign_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ggseqalign_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GGSEQALIGN:", paste0("    ggseqalign: ", packageVersion("ggseqalign"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ggseqalign_results.csv
    touch ${prefix}_ggseqalign_output.rds
    echo "BIOC_GGSEQALIGN:" > versions.yml
    echo "    ggseqalign: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GGSEQALIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GGSEQALIGN(ch_input)

    emit:
    results  = BIOC_GGSEQALIGN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GGSEQALIGN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GGSEQALIGN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GGSEQALIGN.out.versions  // channel: path(versions.yml)
}
