#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biodbNci
// The biodbNci library is an extension of the biodb framework package. It provides access to biodbNci,
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biodbNci/inst/doc/biodbNci.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("biodbNci")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIODBNCI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biodbnci"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biodbnci:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biodbnci:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biodbnci_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biodbnci_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biodbnci_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(biodbNci)
    library(jsonlite)

    # --- Getfactory [] ---
    # Key functions: getFactory, createConn
    ---------------------------------------------------------------------
    conn <- mybiodb$getFactory()$createConn('nci.cactus')
    # --- Getentryids [] ---
    # Key functions: getEntryIds
    ---------------------------------------------------------------------
    ids <- conn$getEntryIds(2)
    ids
    # --- Getentry [] ---
    # Key functions: getEntry
    ---------------------------------------------------------------------
    entries <- conn$getEntry(ids)
    entries
    # --- Entriestodataframe [] ---
    # Key functions: entriesToDataframe
    ---------------------------------------------------------------------
    x <- mybiodb$entriesToDataframe(entries)
    x
    # --- Wschemicalidentifierresolver [] ---
    # Key functions: wsChemicalIdentifierResolver
    ---------------------------------------------------------------------
    conn$wsChemicalIdentifierResolver(structid='C=O', repr='InChI')
    # --- Convcastoinchi [] ---
    # Key functions: convCasToInchi, convCasToInchikey
    ---------------------------------------------------------------------
    conn$convCasToInchi('87605-72-9')
    conn$convCasToInchikey('87605-72-9')
    # --- Terminate [] ---
    # Key functions: terminate
    ---------------------------------------------------------------------
    mybiodb$terminate()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biodbnci_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biodbnci_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biodbnci_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIODBNCI:", paste0("    biodbnci: ", packageVersion("biodbNci"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biodbnci_results.csv
    touch ${prefix}_biodbnci_output.rds
    echo "BIOC_BIODBNCI:" > versions.yml
    echo "    biodbnci: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIODBNCI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIODBNCI(ch_input)

    emit:
    results  = BIOC_BIODBNCI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIODBNCI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIODBNCI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIODBNCI.out.versions  // channel: path(versions.yml)
}
