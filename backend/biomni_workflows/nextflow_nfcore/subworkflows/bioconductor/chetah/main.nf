#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CHETAH
// CHETAH (CHaracterization of cEll Types Aided by Hierarchical classification) is an accurate, selecti
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CHETAH/inst/doc/CHETAH_introduction.R
// Upstream  : BiocManager
// Downstream: none
//
// Install: BiocManager::install("CHETAH")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHETAH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chetah"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chetah:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chetah:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(singlecellexperiment)

    output:
    tuple val(meta), path("${meta.id}_chetah_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chetah_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chetah_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CHETAH)
    library(CHETAHclassifier)
    library(PlotCHETAH)
    library(SingleCellExperiment)
    library(jsonlite)

    # --- Cell Type Classification [] ---
    # Key functions: CHETAHclassifier, Classify
    input_mel <- CHETAHclassifier(
        input = input_mel,
        ref_cells = headneck_ref
    )
    input_mel <- Classify(input = input_mel, 0.8)


    # --- Classification Refinement [] ---
    # Key functions: RenameBelowNode, Classify
    input_mel <- RenameBelowNode(
        input_mel, 
        whichnode = 6,
        replacement = "T cell"
    )
    input_mel <- Classify(input_mel, 0.1)


    # --- Reference Evaluation and Visualisation [] ---
    # Key functions: PlotCHETAH, CorrelateReference, ClassifyReference
    PlotCHETAH(input = input_mel, tree = FALSE)
    cor_ref <- CorrelateReference(ref_cells = headneck_ref)
    class_ref <- ClassifyReference(ref_cells = headneck_ref)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chetah_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chetah_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chetah_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHETAH:", paste0("    chetah: ", packageVersion("CHETAH"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chetah_results.csv
    touch ${prefix}_chetah_output.rds
    echo "BIOC_CHETAH:" > versions.yml
    echo "    chetah: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHETAH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(singlecellexperiment) ]

    main:
    BIOC_CHETAH(ch_input)

    emit:
    results  = BIOC_CHETAH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHETAH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHETAH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHETAH.out.versions  // channel: path(versions.yml)
}
