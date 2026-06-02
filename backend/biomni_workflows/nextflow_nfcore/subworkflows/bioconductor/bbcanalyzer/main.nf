#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BBCAnalyzer
// BBCAnalyzer is a package for visualizing the relative or absolute number of bases, deletions and ins
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BBCAnalyzer/inst/doc/BBCAnalyzer.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("BBCAnalyzer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BBCANALYZER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bbcanalyzer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bbcanalyzer:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bbcanalyzer:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bbcanalyzer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bbcanalyzer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bbcanalyzer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BBCAnalyzer)
    library(jsonlite)

    # --- Example2 [] ---
    # Key functions: analyzeBasesPlotOnly

    # --- Example3 [] ---
    # Key functions: analyzeBases


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bbcanalyzer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bbcanalyzer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bbcanalyzer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BBCANALYZER:", paste0("    bbcanalyzer: ", packageVersion("BBCAnalyzer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bbcanalyzer_results.csv
    touch ${prefix}_bbcanalyzer_output.rds
    echo "BIOC_BBCANALYZER:" > versions.yml
    echo "    bbcanalyzer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BBCANALYZER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BBCANALYZER(ch_input)

    emit:
    results  = BIOC_BBCANALYZER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BBCANALYZER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BBCANALYZER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BBCANALYZER.out.versions  // channel: path(versions.yml)
}
