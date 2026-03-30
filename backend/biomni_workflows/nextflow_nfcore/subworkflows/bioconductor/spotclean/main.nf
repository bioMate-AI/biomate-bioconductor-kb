#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SpotClean
// SpotClean is a computational method to adjust for spot swapping in spatial transcriptomics data. Rec
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SpotClean/inst/doc/SpotClean.R
// Upstream  : SpatialExperiment, knitr
// Downstream: none
//
// Install: BiocManager::install("SpotClean")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPOTCLEAN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spotclean"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spotclean:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spotclean:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spotclean_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spotclean_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spotclean_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SpotClean)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: path, files, read10xSlide
    ---------------------------------------------------------------------
    # load count matrix
    data(mbrain_raw)
    str(mbrain_raw)
    # read spatial metadata
    # --- Createslide [] ---
    # Key functions: createSlide
    ---------------------------------------------------------------------
    slide_obj <- createSlide(mbrain_raw, mbrain_slide_info)
    slide_obj
    # --- Spotclean [] ---
    # Key functions: spotclean
    ---------------------------------------------------------------------
    decont_obj <- spotclean(slide_obj, maxit=10, candidate_radius = 20)
    # --- Summary [] ---
    # Key functions: metadata
    ---------------------------------------------------------------------
    summary(metadata(decont_obj)$contamination_rate)
    # --- Arcscore [] ---
    # Key functions: arcScore
    ---------------------------------------------------------------------
    arcScore(slide_obj)
    # --- Converttoseurat [] ---
    # Key functions: convertToSeurat
    ---------------------------------------------------------------------
    seurat_obj <- convertToSeurat(decont_obj,image_dir = spatial_dir)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spotclean_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spotclean_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spotclean_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPOTCLEAN:", paste0("    spotclean: ", packageVersion("SpotClean"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spotclean_results.csv
    touch ${prefix}_spotclean_output.rds
    echo "BIOC_SPOTCLEAN:" > versions.yml
    echo "    spotclean: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPOTCLEAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPOTCLEAN(ch_input)

    emit:
    results  = BIOC_SPOTCLEAN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPOTCLEAN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPOTCLEAN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPOTCLEAN.out.versions  // channel: path(versions.yml)
}
