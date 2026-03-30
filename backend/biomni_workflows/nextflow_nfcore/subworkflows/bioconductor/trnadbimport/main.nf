#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tRNAdbImport
// tRNAdbImport imports the entries of the tRNAdb and mtRNAdb (http://trna.bioinf.uni-leipzig.de) as GR
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tRNAdbImport/inst/doc/tRNAdbImport.R
// Upstream  : Biostrings, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("tRNAdbImport")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRNADBIMPORT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-trnadbimport"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-trnadbimport:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-trnadbimport:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_trnadbimport_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_trnadbimport_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_trnadbimport_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(tRNAdbImport)
    library(jsonlite)

    # --- Trnadb [] ---
    # Key functions: tRNAdb
    ---------------------------------------------------------------------
    # accessing tRNAdb
    # tRNA from yeast for Alanine and Phenylalanine
    gr <- import.tRNAdb(organism = "Saccharomyces cerevisiae",
                        aminoacids = c("Phe","Ala"))
    # --- Mttrnadb [] ---
    # Key functions: mttRNAdb
    ---------------------------------------------------------------------
    # accessing mtRNAdb
    # get the mitochrondrial tRNA for Alanine in Bos taurus
    gr <- import.mttRNAdb(organism = "Bos taurus",
                          aminoacids = "Ala")
    # --- Istrnadbgranges [] ---
    # Key functions: istRNAdbGRanges
    ---------------------------------------------------------------------
    # check that the result has the appropriate columns
    istRNAdbGRanges(gr)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_trnadbimport_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_trnadbimport_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_trnadbimport_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TRNADBIMPORT:", paste0("    trnadbimport: ", packageVersion("tRNAdbImport"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_trnadbimport_results.csv
    touch ${prefix}_trnadbimport_output.rds
    echo "BIOC_TRNADBIMPORT:" > versions.yml
    echo "    trnadbimport: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TRNADBIMPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TRNADBIMPORT(ch_input)

    emit:
    results  = BIOC_TRNADBIMPORT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TRNADBIMPORT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TRNADBIMPORT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TRNADBIMPORT.out.versions  // channel: path(versions.yml)
}
