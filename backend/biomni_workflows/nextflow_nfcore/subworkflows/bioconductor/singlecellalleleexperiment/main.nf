#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SingleCellAlleleExperiment
// Defines a S4 class that is based on SingleCellExperiment. In addition to the usual gene layer the ob
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SingleCellAlleleExperiment/inst/doc/scae_intro.R
// Upstream  : AnnotationDbi, DropletUtils, ggplot2, patchwork, scaeData
// Downstream: none
//
// Install: BiocManager::install("SingleCellAlleleExperiment")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SINGLECELLALLELEEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-singlecellalleleexperiment"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-singlecellalleleexperiment:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-singlecellalleleexperiment:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_singlecellalleleexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_singlecellalleleexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_singlecellalleleexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SingleCellAlleleExperiment)
    library(jsonlite)

    # --- plot Reduced Dim [] ---
    # Key functions: plotReducedDim, ggtitle
    tsne_g_a  <- plotReducedDim(scae, dimred=tsne, colour_by="HLA-DRB1") +
    ggtitle("HLA-DRB1 gene")
    tsne_g_a1 <- plotReducedDim(scae, dimred=tsne, colour_by="DRB1*07:01:01:01") +

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_singlecellalleleexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_singlecellalleleexperiment_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_singlecellalleleexperiment_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SINGLECELLALLELEEXPERIMENT:", paste0("    singlecellalleleexperiment: ", packageVersion("SingleCellAlleleExperiment"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_singlecellalleleexperiment_results.csv
    touch ${prefix}_singlecellalleleexperiment_output.rds
    echo "BIOC_SINGLECELLALLELEEXPERIMENT:" > versions.yml
    echo "    singlecellalleleexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SINGLECELLALLELEEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SINGLECELLALLELEEXPERIMENT(ch_input)

    emit:
    results  = BIOC_SINGLECELLALLELEEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SINGLECELLALLELEEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SINGLECELLALLELEEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SINGLECELLALLELEEXPERIMENT.out.versions  // channel: path(versions.yml)
}
