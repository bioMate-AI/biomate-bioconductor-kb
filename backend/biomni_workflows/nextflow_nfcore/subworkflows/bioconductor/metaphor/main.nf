#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MetaPhOR
// MetaPhOR was developed to enable users to assess metabolic dysregulation using transcriptomic-level 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MetaPhOR/inst/doc/MetaPhOR-vignette.R
// Upstream  : kableExtra
// Downstream: none
//
// Install: BiocManager::install("MetaPhOR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METAPHOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-metaphor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-metaphor:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-metaphor:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_metaphor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_metaphor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_metaphor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MetaPhOR)
    library(jsonlite)

    # --- Csv [] ---
    # Key functions: csv
    ---------------------------------------------------------------------
    exdegs <- read.csv(system.file("extdata/exampledegs.csv",
                                    package = "MetaPhOR"),
                                    header = TRUE)
    # --- Bubbleplot [] ---
    # Key functions: bubblePlot
    ---------------------------------------------------------------------
    pval <- bubblePlot(scorelist = brca,
                        labeltext = "Pval",
                        labelsize = .85)
    plot(pval)
    # --- Csv [] ---
    # Key functions: csv, metaHeatmap
    ---------------------------------------------------------------------
    ##read in two additional sets of scores,
    ##run in the same manner as brca for comparison
    ovca <- read.csv(system.file("extdata/OVCA_Scores.csv", package = "MetaPhOR"),
                    header = TRUE,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_metaphor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_metaphor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_metaphor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METAPHOR:", paste0("    metaphor: ", packageVersion("MetaPhOR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metaphor_results.csv
    touch ${prefix}_metaphor_output.rds
    echo "BIOC_METAPHOR:" > versions.yml
    echo "    metaphor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METAPHOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METAPHOR(ch_input)

    emit:
    results  = BIOC_METAPHOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METAPHOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METAPHOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METAPHOR.out.versions  // channel: path(versions.yml)
}
