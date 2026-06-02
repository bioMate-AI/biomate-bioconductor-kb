#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MSstatsLiP
// Tools for LiP peptide and protein significance analysis. Provides functions for summarization, estim
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MSstatsLiP/inst/doc/MSstatsLiP_Workflow.R
// Upstream  : gghighlight, tidyverse
// Downstream: none
//
// Install: BiocManager::install("MSstatsLiP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSSTATSLIP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msstatslip"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msstatslip:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-msstatslip:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msstatslip_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msstatslip_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msstatslip_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MSstatsLiP)
    library(jsonlite)


    # --- Include=true [] ---
    # Key functions: SpectronauttoMSstatsLiPFormat
    library(MSstatsLiP)
    library(tidyverse)
    library(data.table)

    ## -----------------------------------------------------------------------------
    ## Read in raw data files
    head(LiPRawData)
    head(TrPRawData)

    ## -----------------------------------------------------------------------------
    ## Run converter
    MSstatsLiP_data <- SpectronauttoMSstatsLiPFormat(LiPRawData, 
                                          "../inst/extdata/ExampleFastaFile.fasta", 
                                          TrPRawData, use_log_file = FALSE, 
                                          append = FALSE)

    # --- Calculate Accessibility [] ---
    # Key functions: calculateProteolyticResistance, aSynuclein, ResistanceBarcodePlotLiP
    Accessibility = calculateProteolyticResistance(MSstatsLiP_Summarized, 
                                                   "../inst/extdata/ExampleFastaFile.fasta", 
                                                   differential_analysis = TRUE)

    Accessibility$RunLevelData


    ## ----Barplot of protease resistance of aSynuclein (monomer - M and fibril - F), message=FALSE, warning=FALSE, fig.height=2, fig.width=10,echo=TRUE,include=TRUE----

    ResistanceBarcodePlotLiP(Accessibility,
                             "../inst/extdata/ExampleFastaFile.fasta",
                             which.prot = "P14164",
                             which.condition = "Osmo",
                             address = FALSE)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msstatslip_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msstatslip_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msstatslip_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSSTATSLIP:", paste0("    msstatslip: ", packageVersion("MSstatsLiP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msstatslip_results.csv
    touch ${prefix}_msstatslip_output.rds
    echo "BIOC_MSSTATSLIP:" > versions.yml
    echo "    msstatslip: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSSTATSLIP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSSTATSLIP(ch_input)

    emit:
    results  = BIOC_MSSTATSLIP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSSTATSLIP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSSTATSLIP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSSTATSLIP.out.versions  // channel: path(versions.yml)
}
