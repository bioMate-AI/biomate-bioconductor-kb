#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tLOH
// tLOH, or transcriptomicsLOH, assesses evidence for loss of heterozygosity (LOH) in pre-processed spa
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tLOH/inst/doc/tLOH_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("tLOH")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TLOH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tloh"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tloh:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tloh:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tloh_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tloh_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tloh_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tLOH)
    library(jsonlite)

    # --- t L O H Data Import [] ---
    # Key functions: tLOHDataImport
    exampleData <- tLOHDataImport('../inst/extdata/Example.vcf')
    # --- t L O H Calc [] ---
    # Key functions: tLOHCalc
    load("../data/humanGBMsampleAC.rda")
    df <- tLOHCalc(humanGBMsampleAC)
    head(df)
    # --- allele Frequency Plot [] ---
    # Key functions: alleleFrequencyPlot, aggregateCHRPlot
    alleleFrequencyPlot(df, "Example")
    aggregateCHRPlot(df, "Example")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tloh_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tloh_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tloh_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TLOH:", paste0("    tloh: ", packageVersion("tLOH"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tloh_results.csv
    touch ${prefix}_tloh_output.rds
    echo "BIOC_TLOH:" > versions.yml
    echo "    tloh: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TLOH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TLOH(ch_input)

    emit:
    results  = BIOC_TLOH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TLOH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TLOH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TLOH.out.versions  // channel: path(versions.yml)
}
