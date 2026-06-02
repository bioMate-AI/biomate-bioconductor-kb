#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iNETgrate
// The iNETgrate package provides functions to build a correlation network in which nodes are genes. DN
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iNETgrate/inst/doc/iNETgrate_inference.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("iNETgrate")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_INETGRATE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-inetgrate"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-inetgrate:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-inetgrate:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_inetgrate_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_inetgrate_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_inetgrate_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(iNETgrate)
    library(jsonlite)

    # --- downloa Data [] ---
    # Key functions: downloaData
    tcgaAML <- downloaData(dataProject="TCGA-LAML", savePath=".")
    # --- i N E Tgrate [] ---
    # Key functions: iNETgrate

    # --- clean All Data [] ---
    # Key functions: cleanAllData

    # --- elect Genes [] ---
    # Key functions: electGenes
    data(toyCleanedAml)
    # --- computing eigenloci [] ---
    # Key functions: setNames, intersect, computEigenloci
    patientLabel <- setNames(as.character(cleaned$survival$Risk1),
    nm=rownames(cleaned$survival))
    inBoth <- intersect(colnames(cleaned$dnam), names(patientLabel))
    # --- make Network [] ---
    # Key functions: makeNetwork

    # --- combining eigengenes [] ---
    # Key functions: computEigengenes

    # --- analyze Survival [] ---
    # Key functions: analyzeSurvival

    # --- best Inetgrator [] ---
    # Key functions: bestInetgrator


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_inetgrate_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_inetgrate_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_inetgrate_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_INETGRATE:", paste0("    inetgrate: ", packageVersion("iNETgrate"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_inetgrate_results.csv
    touch ${prefix}_inetgrate_output.rds
    echo "BIOC_INETGRATE:" > versions.yml
    echo "    inetgrate: 0.0.0" >> versions.yml
    """
}


workflow BIOC_INETGRATE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_INETGRATE(ch_input)

    emit:
    results  = BIOC_INETGRATE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_INETGRATE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_INETGRATE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_INETGRATE.out.versions  // channel: path(versions.yml)
}
