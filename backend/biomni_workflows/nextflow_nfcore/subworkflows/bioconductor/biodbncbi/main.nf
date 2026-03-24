#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biodbNcbi
// The biodbNcbi library provides access to the NCBI databases CCDS, Gene, Pubchem Comp and Pubchem Sub
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biodbNcbi/inst/doc/biodbNcbi.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("biodbNcbi")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIODBNCBI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biodbncbi"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biodbncbi:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biodbncbi:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biodbncbi_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biodbncbi_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biodbncbi_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(biodbNcbi)
    library(jsonlite)

    # --- Getfactory [] ---
    # Key functions: getFactory, createConn
    ---------------------------------------------------------------------
    gene <- mybiodb$getFactory()$createConn('ncbi.gene')
    # --- Getnbentries [] ---
    # Key functions: getNbEntries
    ---------------------------------------------------------------------
    gene$getNbEntries()
    # --- Getentryids [] ---
    # Key functions: getEntryIds
    ---------------------------------------------------------------------
    ids <- gene$getEntryIds(2)
    ids
    # --- Getentry [] ---
    # Key functions: getEntry
    ---------------------------------------------------------------------
    entries <- gene$getEntry(ids)
    entries
    # --- Entriestodataframe [] ---
    # Key functions: entriesToDataframe
    ---------------------------------------------------------------------
    x <- mybiodb$entriesToDataframe(entries)
    x
    # --- Wsefetch [] ---
    # Key functions: wsEfetch, getNodeSet
    ---------------------------------------------------------------------
    entryxml <- gene$wsEfetch('2833', retmode='xml', retfmt='parsed')
    XML::getNodeSet(entryxml, "//Entrezgene_prot")
    # --- Wsesearch [] ---
    # Key functions: wsEsearch
    ---------------------------------------------------------------------
    gene$wsEsearch(term='"chemokine"[Gene Name]', retmax=10, retfmt='ids')
    # --- Searchforentries [] ---
    # Key functions: searchForEntries
    ---------------------------------------------------------------------
    gene$searchForEntries(fields=list(name='chemokine'), max.results=10)
    # --- Wseinfo [] ---
    # Key functions: wsEinfo, getNodeSet
    ---------------------------------------------------------------------
    infoxml <- pubchem.comp$wsEinfo(retfmt='parsed')
    XML::getNodeSet(infoxml, "//Field[1]")
    # --- Terminate [] ---
    # Key functions: terminate
    ---------------------------------------------------------------------
    mybiodb$terminate()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biodbncbi_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biodbncbi_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biodbncbi_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIODBNCBI:", paste0("    biodbncbi: ", packageVersion("biodbNcbi"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biodbncbi_results.csv
    touch ${prefix}_biodbncbi_output.rds
    echo "BIOC_BIODBNCBI:" > versions.yml
    echo "    biodbncbi: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIODBNCBI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIODBNCBI(ch_input)

    emit:
    results  = BIOC_BIODBNCBI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIODBNCBI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIODBNCBI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIODBNCBI.out.versions  // channel: path(versions.yml)
}
