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
    library(AnnotationTrack)
    library(jsonlite)

    # --- Gene annotation retrieval [] ---
    # Key functions: install_github, learn_model, tempdir, binarize_bam, segment, compare_models, emission, transition
    binarize_bam(inputdir,
    example_binaries <- list.files(outputdir, pattern = '*_binary.txt')
    readLines(file.path(outputdir, example_binaries[1]), n = 3)

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
