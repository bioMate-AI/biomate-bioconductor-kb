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
    library(AnnotationTrack)
    library(jsonlite)

    # --- Chromatin State Model Learning [] ---
    # Key functions: learn_model
    inputdir <- system.file('extdata/SAMPLEDATA_HG18', package = 'segmenter')
    coordsdir <- system.file('extdata/COORDS', package = 'chromhmmData')
    anchorsdir <- system.file('extdata/ANCHORFILES', package = 'chromhmmData')
    chromsizefile <- system.file('extdata/CHROMSIZES', 'hg18.txt',
                                 package = 'chromhmmData')
    obj <- learn_model(inputdir = inputdir, coordsdir = coordsdir,
                       anchorsdir = anchorsdir, chromsizefile = chromsizefile,
                       numstates = 3, assembly = 'hg18',
                       cells = c('K562', 'GM12878'), annotation = 'RefSeq',
                       binsize = 200)


    # --- Model Comparison and Selection [] ---
    # Key functions: learn_model, compare_models
    inputdir <- system.file('extdata/SAMPLEDATA_HG18', package = 'segmenter')
    coordsdir <- system.file('extdata/COORDS', package = 'chromhmmData')
    anchorsdir <- system.file('extdata/ANCHORFILES', package = 'chromhmmData')
    chromsizefile <- system.file('extdata/CHROMSIZES', 'hg18.txt',
                                 package = 'chromhmmData')
    objs <- lapply(3:5, function(x) {
      learn_model(inputdir = inputdir, coordsdir = coordsdir,
                  anchorsdir = anchorsdir, chromsizefile = chromsizefile,
                  numstates = x, assembly = 'hg18',
                  cells = c('K562', 'GM12878'), annotation = 'RefSeq',
                  binsize = 200)
    })
    compare_models(objs, type = 'likelihood')


    # --- Parameter Extraction and Heatmap Visualization [] ---
    # Key functions: emission, transition, plot_heatmap
    em <- emission(obj)
    tr <- transition(obj)
    h1 <- plot_heatmap(obj, row_labels = paste('S', 1:3), name = 'Emission')
    h2 <- plot_heatmap(obj, type = 'transition',
                       row_labels = paste('S', 1:3),
                       column_labels = paste('S', 1:3),
                       name = 'Transition')


    # --- Genomic Enrichment Analysis [] ---
    # Key functions: overlap, TSS, TES, plot_heatmap
    ol <- overlap(obj)
    tss_enrich <- TSS(obj)
    tes_enrich <- TES(obj)
    plot_heatmap(obj, type = 'overlap',
                 column_labels = c('Genome', 'CpG', 'Exon', 'Gene',
                                   'TES', 'TSS', 'TSS2kb', 'laminB1lads'),
                 show_heatmap_legend = FALSE)

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
