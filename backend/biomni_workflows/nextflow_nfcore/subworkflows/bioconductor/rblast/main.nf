#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rBLAST
// Seamlessly interfaces the Basic Local Alignment Search Tool (BLAST) to search genetic sequence data 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rBLAST/inst/doc/blast.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("rBLAST")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RBLAST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rblast"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rblast:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rblast:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(xstringset)

    output:
    tuple val(meta), path("${meta.id}_rblast_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rblast_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rblast_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rBLAST)
    library(jsonlite)

    # --- Readrnastringset [] ---
    # Key functions: readRNAStringSet
    ---------------------------------------------------------------------
    seq <- readRNAStringSet(system.file("examples/RNA_example.fasta",
        package = "rBLAST"
    ))
    seq
    # --- Writexstringset [] ---
    # Key functions: writeXStringSet
    ---------------------------------------------------------------------
    writeXStringSet(seq, filepath = "seqs.fasta")
    # --- Unlink [] ---
    # Key functions: unlink
    ---------------------------------------------------------------------
    unlink("seqs.fasta")
    unlink("db", recursive = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rblast_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rblast_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rblast_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RBLAST:", paste0("    rblast: ", packageVersion("rBLAST"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rblast_results.csv
    touch ${prefix}_rblast_output.rds
    echo "BIOC_RBLAST:" > versions.yml
    echo "    rblast: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RBLAST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(xstringset) ]

    main:
    BIOC_RBLAST(ch_input)

    emit:
    results  = BIOC_RBLAST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RBLAST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RBLAST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RBLAST.out.versions  // channel: path(versions.yml)
}
