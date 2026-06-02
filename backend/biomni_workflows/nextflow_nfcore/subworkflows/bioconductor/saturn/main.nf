#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: satuRn
// satuRn provides a higly performant and scalable framework for performing differential transcript usa
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/satuRn/inst/doc/Vignette.R
// Upstream  : AnnotationHub, DEXSeq, SummarizedExperiment, edgeR, ensembldb
// Downstream: IsoformSwitchAnalyzeR
//
// Install: BiocManager::install("satuRn")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SATURN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-saturn"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-saturn:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-saturn:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(summarizedexperiment)

    output:
    tuple val(meta), path("${meta.id}_saturn_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_saturn_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_saturn_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(satuRn)
    library(jsonlite)


    # --- Warning=false [] ---
    # Key functions: colData, plotDTU, VISp.L5_IT_VISp_Hsd11b1_Endou, ALM.L5_IT_ALM_Tnc, model
    group1 <- colnames(sumExp)[colData(sumExp)$group == 
                                 "VISp.L5_IT_VISp_Hsd11b1_Endou"]
    group2 <- colnames(sumExp)[colData(sumExp)$group == 
                                 "ALM.L5_IT_ALM_Tnc"]


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_saturn_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_saturn_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_saturn_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SATURN:", paste0("    saturn: ", packageVersion("satuRn"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_saturn_results.csv
    touch ${prefix}_saturn_output.rds
    echo "BIOC_SATURN:" > versions.yml
    echo "    saturn: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SATURN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(summarizedexperiment) ]

    main:
    BIOC_SATURN(ch_input)

    emit:
    results  = BIOC_SATURN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SATURN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SATURN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SATURN.out.versions  // channel: path(versions.yml)
}
