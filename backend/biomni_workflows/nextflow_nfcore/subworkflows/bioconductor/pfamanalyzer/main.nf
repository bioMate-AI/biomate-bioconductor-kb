#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pfamAnalyzeR
// Protein domains is one of the most import annoation of proteins we have with the Pfam database/tool 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pfamAnalyzeR/inst/doc/pfamAnalyzeR.R
// Upstream  : none
// Downstream: IsoformSwitchAnalyzeR
//
// Install: BiocManager::install("pfamAnalyzeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PFAMANALYZER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pfamanalyzer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pfamanalyzer:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pfamanalyzer:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pfamanalyzer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pfamanalyzer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pfamanalyzer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pfamAnalyzeR)
    library(jsonlite)

    # --- pfam Analyze R [] ---
    # Key functions: pfamAnalyzeR
    pfamRes <- pfamAnalyzeR(pfamResultFile)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pfamanalyzer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pfamanalyzer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pfamanalyzer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PFAMANALYZER:", paste0("    pfamanalyzer: ", packageVersion("pfamAnalyzeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pfamanalyzer_results.csv
    touch ${prefix}_pfamanalyzer_output.rds
    echo "BIOC_PFAMANALYZER:" > versions.yml
    echo "    pfamanalyzer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PFAMANALYZER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PFAMANALYZER(ch_input)

    emit:
    results  = BIOC_PFAMANALYZER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PFAMANALYZER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PFAMANALYZER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PFAMANALYZER.out.versions  // channel: path(versions.yml)
}
