#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: aggregateBioVar
// For single cell RNA-seq data collected from more than one subject (e.g. biological sample or technic
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/aggregateBioVar/inst/doc/multi-subject-scRNA-seq.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("aggregateBioVar")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AGGREGATEBIOVAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-aggregatebiovar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-aggregatebiovar:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-aggregatebiovar:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(deseqdataset)

    output:
    tuple val(meta), path("${meta.id}_aggregatebiovar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_aggregatebiovar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_aggregatebiovar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(aggregateBioVar)
    library(DESeq)
    library(DESeqDataSetFromMatrix)
    library(jsonlite)

    # --- Pseudobulk Aggregation [] ---
    # Key functions: aggregateBioVar
    aggregate_data <- aggregateBioVar(
        scExp = small_airway,
        subjectVar = "orig.ident",
        cellVar = "celltype"
    )
    agg_assays <- names(aggregate_data)


    # --- Summarized Counts Generation [] ---
    # Key functions: summarizedCounts
    summarized_results <- summarizedCounts(
        scExp = small_airway,
        subjectVar = "orig.ident"
    )
    sum_dims <- dim(summarized_results)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_aggregatebiovar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_aggregatebiovar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_aggregatebiovar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AGGREGATEBIOVAR:", paste0("    aggregatebiovar: ", packageVersion("aggregateBioVar"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_aggregatebiovar_results.csv
    touch ${prefix}_aggregatebiovar_output.rds
    echo "BIOC_AGGREGATEBIOVAR:" > versions.yml
    echo "    aggregatebiovar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AGGREGATEBIOVAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(deseqdataset) ]

    main:
    BIOC_AGGREGATEBIOVAR(ch_input)

    emit:
    results  = BIOC_AGGREGATEBIOVAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AGGREGATEBIOVAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AGGREGATEBIOVAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AGGREGATEBIOVAR.out.versions  // channel: path(versions.yml)
}
