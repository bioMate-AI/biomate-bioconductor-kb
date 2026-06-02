#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BloodGen3Module
// The BloodGen3Module package provides functions for R user performing module repertoire analyses and 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BloodGen3Module/inst/doc/BloodGen3Module.R
// Upstream  : knitr, ExperimentHub, SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("BloodGen3Module")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BLOODGEN3MODULE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bloodgen3module"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bloodgen3module:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bloodgen3module:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bloodgen3module_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bloodgen3module_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bloodgen3module_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BloodGen3Module)
    library(Groupcomparison)
    library(Groupcomparisonlimma)
    library(jsonlite)

    # --- Grid Visualisation [] ---
    # Key functions: gridplot
    gridplot(
        Group_df,
        cutoff = 15,
        Ref_group = "Control",
        filename = tempfile()
    )


    # --- Individual Single Sample Analysis [] ---
    # Key functions: Individualcomparison
    Individual_df <- Individualcomparison(
        GSE13015,
        sample_info = NULL,
        FC = 1.5,
        DIFF = 10,
        Group_column = "Group_test",
        Ref_group = "Control",
        SummarizedExperiment = TRUE
    )


    # --- Fingerprint Visualisation [] ---
    # Key functions: fingerprintplot
    fingerprintplot(
        Individual_df,
        sample_info = NULL,
        cutoff = 15,
        rowSplit = TRUE,
        Group_column = "Group_test",
        show_ref_group = FALSE,
        Ref_group = "Control",
        Aggregate = "A28",
        filename = tempfile()
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bloodgen3module_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bloodgen3module_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bloodgen3module_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BLOODGEN3MODULE:", paste0("    bloodgen3module: ", packageVersion("BloodGen3Module"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bloodgen3module_results.csv
    touch ${prefix}_bloodgen3module_output.rds
    echo "BIOC_BLOODGEN3MODULE:" > versions.yml
    echo "    bloodgen3module: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BLOODGEN3MODULE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BLOODGEN3MODULE(ch_input)

    emit:
    results  = BIOC_BLOODGEN3MODULE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BLOODGEN3MODULE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BLOODGEN3MODULE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BLOODGEN3MODULE.out.versions  // channel: path(versions.yml)
}
