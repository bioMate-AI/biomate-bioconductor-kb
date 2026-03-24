#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: methylSig
// MethylSig is a package for testing for differentially methylated cytosines (DMCs) or regions (DMRs) 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/methylSig/inst/doc/updating-methylSig-code.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("methylSig")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHYLSIG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-methylsig"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-methylsig:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-methylsig:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_methylsig_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_methylsig_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_methylsig_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(methylSig)
    library(jsonlite)

    # --- filter by group coverage [] ---
    # Key functions: pData
    bsseq::pData(bs)
    bs = filter_loci_by_group_coverage(
    c('cancer' = 2, 'normal' = 2))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_methylsig_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_methylsig_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_methylsig_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METHYLSIG:", paste0("    methylsig: ", packageVersion("methylSig"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylsig_results.csv
    touch ${prefix}_methylsig_output.rds
    echo "BIOC_METHYLSIG:" > versions.yml
    echo "    methylsig: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METHYLSIG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METHYLSIG(ch_input)

    emit:
    results  = BIOC_METHYLSIG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METHYLSIG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METHYLSIG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METHYLSIG.out.versions  // channel: path(versions.yml)
}
