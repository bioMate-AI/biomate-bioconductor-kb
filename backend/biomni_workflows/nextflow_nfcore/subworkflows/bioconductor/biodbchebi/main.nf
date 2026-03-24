#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biodbChebi
// The biodbChebi library provides access to the ChEBI Database, using biodb package framework. It allo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biodbChebi/inst/doc/biodbChebi.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("biodbChebi")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIODBCHEBI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biodbchebi"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biodbchebi:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biodbchebi:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biodbchebi_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biodbchebi_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biodbchebi_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(biodbChebi)
    library(jsonlite)

    # --- Getfactory [] ---
    # Key functions: getFactory, createConn
    ---------------------------------------------------------------------
    chebi <- mybiodb$getFactory()$createConn('chebi')
    # --- Getentry [] ---
    # Key functions: getEntry
    ---------------------------------------------------------------------
    entries <- chebi$getEntry(c('2528', '17053', '15440'))
    # --- Getfieldvalue [] ---
    # Key functions: getFieldValue
    ---------------------------------------------------------------------
    entries[[1]]$getFieldValue('smiles')
    # --- Getfieldsasdataframe [] ---
    # Key functions: getFieldsAsDataframe
    ---------------------------------------------------------------------
    entries[[1]]$getFieldsAsDataframe()
    # --- Entriestodataframe [] ---
    # Key functions: entriesToDataframe
    ---------------------------------------------------------------------
    mybiodb$entriesToDataframe(entries, fields=c('accession', 'formula',
        'molecular.mass', 'inchikey', 'kegg.compound.id'))
    # --- Searchcompound [] ---
    # Key functions: searchCompound
    ---------------------------------------------------------------------
    chebi$searchCompound(name='aspartic', max.results=3)
    # --- Entriestodataframe [] ---
    # Key functions: entriesToDataframe, getEntry
    ---------------------------------------------------------------------
    mybiodb$entriesToDataframe(chebi$getEntry(ids), fields=c('accession',
        'molecular.mass', 'name'))
    # --- Convcastochebi [] ---
    # Key functions: convCasToChebi
    ---------------------------------------------------------------------
    chebi$convCasToChebi(c('87605-72-9', '51-41-2'))
    # --- Convinchitochebi [] ---
    # Key functions: convInchiToChebi, 8, 6, 7
    ---------------------------------------------------------------------
    chebi$convInchiToChebi('InChI=1S/C8H11NO3/c9-4-8(12)5-1-2-6(10)7(11)3-5/h1-3,8,10-12H,4,9H2/t8-/m0/s1')
    # --- Convinchitochebi [] ---
    # Key functions: convInchiToChebi
    ---------------------------------------------------------------------
    chebi$convInchiToChebi('MBDOYVRWFFCFHM-SNAWJCMRSA-N')
    # --- Terminate [] ---
    # Key functions: terminate
    ---------------------------------------------------------------------
    mybiodb$terminate()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biodbchebi_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biodbchebi_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biodbchebi_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIODBCHEBI:", paste0("    biodbchebi: ", packageVersion("biodbChebi"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biodbchebi_results.csv
    touch ${prefix}_biodbchebi_output.rds
    echo "BIOC_BIODBCHEBI:" > versions.yml
    echo "    biodbchebi: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIODBCHEBI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIODBCHEBI(ch_input)

    emit:
    results  = BIOC_BIODBCHEBI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIODBCHEBI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIODBCHEBI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIODBCHEBI.out.versions  // channel: path(versions.yml)
}
