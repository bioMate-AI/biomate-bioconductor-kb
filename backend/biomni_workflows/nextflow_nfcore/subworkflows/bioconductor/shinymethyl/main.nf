#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: shinyMethyl
// Interactive tool for visualizing Illumina methylation array data. Both the 450k and EPIC array are s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/shinyMethyl/inst/doc/shinyMethyl.R
// Upstream  : minfi, minfiData, shinyMethylData
// Downstream: none
//
// Install: BiocManager::install("shinyMethyl")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SHINYMETHYL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-shinymethyl"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-shinymethyl:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-shinymethyl:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_shinymethyl_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_shinymethyl_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_shinymethyl_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(shinyMethyl)
    library(jsonlite)

    # --- run Shiny Methyl [] ---
    # Key functions: runShinyMethyl
    library(shinyMethyl)
    library(shinyMethylData)
    runShinyMethyl(summary.tcga.raw, summary.tcga.norm)
    # --- p Data [] ---
    # Key functions: pData
    pd <- pData(RGSet)
    head(pd)
    # --- shiny Summarize [] ---
    # Key functions: shinySummarize
    myShinyMethylSet <- shinySummarize(RGSet)
    # --- run Shiny Methyl [] ---
    # Key functions: runShinyMethyl
    runShinyMethyl(myShinyMethylSet)
    # --- shiny Summarize [] ---
    # Key functions: shinySummarize
    summary   <- shinySummarize(RGSset)
    summary.norm <- shinySummarize(GRSet.norm)
    # --- run Shiny Methyl [] ---
    # Key functions: runShinyMethyl
    runShinyMethyl(summary, summary.norm)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_shinymethyl_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_shinymethyl_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_shinymethyl_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SHINYMETHYL:", paste0("    shinymethyl: ", packageVersion("shinyMethyl"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_shinymethyl_results.csv
    touch ${prefix}_shinymethyl_output.rds
    echo "BIOC_SHINYMETHYL:" > versions.yml
    echo "    shinymethyl: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SHINYMETHYL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SHINYMETHYL(ch_input)

    emit:
    results  = BIOC_SHINYMETHYL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SHINYMETHYL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SHINYMETHYL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SHINYMETHYL.out.versions  // channel: path(versions.yml)
}
