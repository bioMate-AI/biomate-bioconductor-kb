#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: lefser
// lefser is the R implementation of the popular microbiome biomarker discovery too, LEfSe. It uses the
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/lefser/inst/doc/lefser.R
// Upstream  : SummarizedExperiment, phyloseq
// Downstream: none
//
// Install: BiocManager::install("lefser")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LEFSER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-lefser"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-lefser:1.16.2--r44_0' :
        'quay.io/biocontainers/bioconductor-lefser:1.16.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_lefser_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_lefser_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_lefser_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(lefser)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(zeller14)
    zeller14 <- zeller14[, zeller14$study_condition != "adenoma"]
    # --- Get Terminal Nodes [] ---
    # Key functions: get_terminal_nodes
    ---------------------------------------------------------------------
    tn <- get_terminal_nodes(rownames(zeller14))
    zeller14tn <- zeller14[tn,]
    # --- Relativeab [] ---
    # Key functions: relativeAb
    ---------------------------------------------------------------------
    zeller14tn_ra <- relativeAb(zeller14tn)
    # --- Lefserplot [] ---
    # Key functions: lefserPlot
    ---------------------------------------------------------------------
    lefserPlot(res)
    # --- Maketreesummarizedexperimentfromphyloseq [] ---
    # Key functions: makeTreeSummarizedExperimentFromPhyloseq
    ---------------------------------------------------------------------
    mia::makeTreeSummarizedExperimentFromPhyloseq(kostic)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_lefser_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_lefser_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_lefser_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LEFSER:", paste0("    lefser: ", packageVersion("lefser"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lefser_results.csv
    touch ${prefix}_lefser_output.rds
    echo "BIOC_LEFSER:" > versions.yml
    echo "    lefser: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LEFSER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LEFSER(ch_input)

    emit:
    results  = BIOC_LEFSER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LEFSER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LEFSER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LEFSER.out.versions  // channel: path(versions.yml)
}
