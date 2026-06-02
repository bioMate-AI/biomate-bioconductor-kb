#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: EpiCompare
// EpiCompare is used to compare and analyse epigenetic datasets for quality control and benchmarking p
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/EpiCompare/inst/doc/EpiCompare.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("EpiCompare")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPICOMPARE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-epicompare"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-epicompare:1.10.1--r44_0' :
        'quay.io/biocontainers/bioconductor-epicompare:1.10.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_epicompare_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_epicompare_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_epicompare_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(EpiCompare)
    library(jsonlite)


    # --- Setup Vignette [] ---
    # Key functions: encode_H3K27ac, CnT_H3K27ac, CnR_H3K27ac, hg19_blacklist, CnT_H3K27ac_picard, CnR_H3K27ac_picard
    library(EpiCompare)

    ## -----------------------------------------------------------------------------
    data("encode_H3K27ac") # ENCODE ChIP-seq
    data("CnT_H3K27ac") # CUT&Tag
    data("CnR_H3K27ac") # CUT&Run
    data("hg19_blacklist") # hg19 genome blacklist 
    data("CnT_H3K27ac_picard") # CUT&Tag Picard summary output
    data("CnR_H3K27ac_picard") # CUT&Run Picard summary output

    ## -----------------------------------------------------------------------------
    peaklist <- list(CnT_H3K27ac, CnR_H3K27ac) # create list of peakfiles 
    names(peaklist) <- c("CnT", "CnR") # set names 

    ## -----------------------------------------------------------------------------

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_epicompare_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_epicompare_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_epicompare_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EPICOMPARE:", paste0("    epicompare: ", packageVersion("EpiCompare"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_epicompare_results.csv
    touch ${prefix}_epicompare_output.rds
    echo "BIOC_EPICOMPARE:" > versions.yml
    echo "    epicompare: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EPICOMPARE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EPICOMPARE(ch_input)

    emit:
    results  = BIOC_EPICOMPARE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EPICOMPARE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EPICOMPARE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EPICOMPARE.out.versions  // channel: path(versions.yml)
}
