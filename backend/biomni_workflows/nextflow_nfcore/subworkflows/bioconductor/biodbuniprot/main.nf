#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biodbUniprot
// The biodbUniprot library is an extension of the biodb framework package. It provides access to the U
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biodbUniprot/inst/doc/biodbUniprot.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("biodbUniprot")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIODBUNIPROT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biodbuniprot"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biodbuniprot:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biodbuniprot:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biodbuniprot_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biodbuniprot_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biodbuniprot_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(biodbUniprot)
    library(jsonlite)

    # --- Getfactory [] ---
    # Key functions: getFactory, createConn
    ---------------------------------------------------------------------
    conn <- mybiodb$getFactory()$createConn('uniprot')
    # --- Getentry [] ---
    # Key functions: getEntry
    ---------------------------------------------------------------------
    entries <- conn$getEntry(c('P01011', 'P09237'))
    # --- Entriestodataframe [] ---
    # Key functions: entriesToDataframe
    ---------------------------------------------------------------------
    mybiodb$entriesToDataframe(entries)
    # --- Wssearch [] ---
    # Key functions: wsSearch
    ---------------------------------------------------------------------
    conn$wsSearch('reviewed:true AND organism_id:9606', fields=c('accession', 'id'),
        size=2, retfmt='plain')
    # --- Genesymboltouniprotids [] ---
    # Key functions: geneSymbolToUniprotIds, entryIdsToDataframe
    ---------------------------------------------------------------------
    ids <- conn$geneSymbolToUniprotIds('G-CSF')
    mybiodb$entryIdsToDataframe(ids[['G-CSF']], 'uniprot', fields=c('accession',
        'gene.symbol'))
    # --- Terminate [] ---
    # Key functions: terminate
    ---------------------------------------------------------------------
    mybiodb$terminate()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biodbuniprot_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biodbuniprot_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biodbuniprot_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIODBUNIPROT:", paste0("    biodbuniprot: ", packageVersion("biodbUniprot"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biodbuniprot_results.csv
    touch ${prefix}_biodbuniprot_output.rds
    echo "BIOC_BIODBUNIPROT:" > versions.yml
    echo "    biodbuniprot: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIODBUNIPROT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIODBUNIPROT(ch_input)

    emit:
    results  = BIOC_BIODBUNIPROT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIODBUNIPROT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIODBUNIPROT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIODBUNIPROT.out.versions  // channel: path(versions.yml)
}
