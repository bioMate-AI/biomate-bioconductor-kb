#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: msa
// The 'msa' package provides a unified R/Bioconductor interface to the multiple sequence alignment alg
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/msa/inst/doc/msa.R
// Upstream  : seqinr, pwalign, ape
// Downstream: none
//
// Install: BiocManager::install("msa")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msa:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-msa:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DNAMultipleAlignment)
    library(IRanges)
    library(jsonlite)

    # --- Integer ranges construction [] ---
    # Key functions: packageDescription, readAAStringSet, msa, msaPrettyPrint, IRanges, colmask, unmasked, consensusMatrix
    msaPrettyPrint(myFirstAlignment, output="asis", y=c(164, 213),
    subset=c(1:6), showNames="none", showLogo="none",
    furtherCode=c("\\defconsensus{.}{lower}{upper}",

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSA:", paste0("    msa: ", packageVersion("msa"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msa_results.csv
    touch ${prefix}_msa_output.rds
    echo "BIOC_MSA:" > versions.yml
    echo "    msa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSA(ch_input)

    emit:
    results  = BIOC_MSA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSA.out.versions  // channel: path(versions.yml)
}
