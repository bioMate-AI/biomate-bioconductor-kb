#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GeDi
// The package provides different distances measurements to calculate the difference between genesets. 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GeDi/inst/doc/GeDi_manual.R
// Upstream  : AnnotationDbi, DESeq2, GeneTonic, ReactomePA, biomaRt
// Downstream: none
//
// Install: BiocManager::install("GeDi")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GEDI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gedi"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gedi:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gedi:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gedi_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gedi_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gedi_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DESeq)
    library(DESeqDataSet)
    library(GeDi)
    library(jsonlite)

    # --- Interactive Network Analysis [] ---
    # Key functions: GeDi
    app <- GeDi::GeDi(genesets = macrophage_topGO_example)


    # --- Default Launch [] ---
    # Key functions: GeDi
    app_default <- GeDi::GeDi()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gedi_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gedi_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gedi_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GEDI:", paste0("    gedi: ", packageVersion("GeDi"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gedi_results.csv
    touch ${prefix}_gedi_output.rds
    echo "BIOC_GEDI:" > versions.yml
    echo "    gedi: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GEDI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GEDI(ch_input)

    emit:
    results  = BIOC_GEDI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GEDI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GEDI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GEDI.out.versions  // channel: path(versions.yml)
}
