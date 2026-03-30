#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ipdDb
// All alleles from the IPD IMGT/HLA <https://www.ebi.ac.uk/ipd/imgt/hla/> and IPD KIR <https://www.ebi
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/ipdDb/inst/doc/Readme.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ipdDb")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IPDDB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ipddb"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ipddb:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ipddb:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_ipddb_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ipddb_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ipddb_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ipdDb)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: loadHlaData, getLoci, getAlleles, getReference
    library(ipdDb)
    hla <- loadHlaData()
    ## get all loci stored in the db
    available_loci <- hla$getLoci()
    ## get all alleles of a locus

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ipddb_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ipddb_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ipddb_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IPDDB:", paste0("    ipddb: ", packageVersion("ipdDb"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ipddb_results.csv
    touch ${prefix}_ipddb_output.rds
    echo "BIOC_IPDDB:" > versions.yml
    echo "    ipddb: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IPDDB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_IPDDB(ch_input)

    emit:
    results  = BIOC_IPDDB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IPDDB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IPDDB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IPDDB.out.versions  // channel: path(versions.yml)
}
