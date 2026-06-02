#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: segmenter
// Chromatin segmentation analysis transforms ChIP-seq data into signals over the genome. The latter re
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/segmenter/inst/doc/segmenter.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("segmenter")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEGMENTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-segmenter"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-segmenter:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-segmenter:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_segmenter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_segmenter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_segmenter_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(segmenter)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set, learn_model, show
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>",
      message = FALSE
    )
    # locate input and annotation files
    inputdir <- system.file('extdata/SAMPLEDATA_HG18',
                            package = 'segmenter')
    coordsdir <- system.file('extdata/COORDS',
                             package = 'chromhmmData')
    anchorsdir <- system.file('extdata/ANCHORFILES',
                              package = 'chromhmmData')
    chromsizefile <- system.file('extdata/CHROMSIZES',
                                 'hg18.txt',
                                 package = 'chromhmmData')
    # run command
    # --- Genomic Annotations [] ---
    # Key functions: list.files, readLines, tempdir, extdata, bamsignals, binarize_bam
    # coordinates
    coordsdir <- system.file('extdata/COORDS',
                             package = 'chromhmmData')

    list.files(file.path(coordsdir, 'hg18'))

    # anchors
    anchorsdir <- system.file('extdata/ANCHORFILES',
                              package = 'chromhmmData')

    # a table to assign marker and cell names to the bam files
    cellmarkfiletable <- system.file('extdata',
                                     'cell_mark_table.tsv',
                                     package = 'segmenter')

    readLines(cellmarkfiletable, n = 3)
    # locate input and output
    inputdir <- system.file("extdata", package = "bamsignals")
    outputdir <- tempdir()
    # run command

    # --- Input Bins [] ---
    # Key functions: list.files, learn_model, show, emission
    # locate input and output files
    inputdir <- system.file('extdata/SAMPLEDATA_HG18',
                            package = 'segmenter')

    list.files(inputdir)
    # run command
    # --- Subset [] ---
    # Key functions: segment, function, learn_model, compare_models
    # subset the segment slot
    segment(obj, cell = 'K562')
    # relearn the models with 3 to 8 states
    # --- Plot Comparison [] ---
    # Key functions: par, compare_models, emission, transition, plot_heatmap, overlap
    # compare models plots
    par(mfrow = c(1, 2))
    compare_models(objs,
                   plot = TRUE,
                   xlab = 'Model', ylab = 'State Correlation')
    compare_models(objs, type = 'likelihood',
                   plot = TRUE,
                   xlab = 'Model', ylab = 'Likelihood')
    # access object slots
    emission(obj)
    transition(obj)
    # emission and transition plots
    h1 <- plot_heatmap(obj,
                       row_labels = paste('S', 1:3),
                       name = 'Emission')

    # --- Visulaizing Overlap [] ---
    # Key functions: plot_heatmap, TSS, TES, segment
    # overlap enrichment plots
    plot_heatmap(obj,
                 type = 'overlap',
                 column_labels = c('Genome', 'CpG', 'Exon', 'Gene',
                                   'TES', 'TSS', 'TSS2kb', 'laminB1lads'),
                 show_heatmap_legend = FALSE)
    # genomic locations enrichment
    TSS(obj)
    TES(obj)
    # genomic locations enrichment plots
    h1 <- plot_heatmap(obj,
                       type = 'TSS',
                       show_heatmap_legend = FALSE)
    h2 <- plot_heatmap(obj,
                       type = 'TES',
                       show_heatmap_legend = FALSE)

    h1 + h2
    # get segments
    segment(obj)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_segmenter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_segmenter_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_segmenter_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEGMENTER:", paste0("    segmenter: ", packageVersion("segmenter"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_segmenter_results.csv
    touch ${prefix}_segmenter_output.rds
    echo "BIOC_SEGMENTER:" > versions.yml
    echo "    segmenter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEGMENTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEGMENTER(ch_input)

    emit:
    results  = BIOC_SEGMENTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEGMENTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEGMENTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEGMENTER.out.versions  // channel: path(versions.yml)
}
