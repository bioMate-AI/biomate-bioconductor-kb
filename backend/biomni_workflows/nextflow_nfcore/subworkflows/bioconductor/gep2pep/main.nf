#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gep2pep
// Pathway Expression Profiles (PEPs) are based on the expression of pathways (defined as sets of genes
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gep2pep/inst/doc/vignette.R
// Upstream  : GSEABase, knitr
// Downstream: none
//
// Install: BiocManager::install("gep2pep")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GEP2PEP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gep2pep"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gep2pep:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gep2pep:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gep2pep_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gep2pep_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gep2pep_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CategorizedCollection)
    library(jsonlite)

    # --- Xml [] ---
    # Key functions: xml, CategorizedCollection
    ---------------------------------------------------------------------
    ## db <- importMSigDB.xml("msigdb_v6.1.xml")
    ## db <- as.CategorizedCollection(db)
    # --- Loadsamplepws [] ---
    # Key functions: loadSamplePWS
    ---------------------------------------------------------------------
    db <- loadSamplePWS()
    # --- Sapply [] ---
    # Key functions: makeCollectionIDs
    ---------------------------------------------------------------------
    colltypes <- sapply(db, collectionType)
    cats <- sapply(colltypes, attr, "category")
    subcats <- sapply(colltypes, attr, "subCategory")
    print(cats)
    # --- Loadcollection [] ---
    # Key functions: loadCollection, description
    ---------------------------------------------------------------------
    rp
    TFTsets <- loadCollection(rp, "c3_TFT")
    TFTsets
    description(TFTsets[["E47_01"]])
    # --- Loadsamplegep [] ---
    # Key functions: loadSampleGEP
    ---------------------------------------------------------------------
    geps <- loadSampleGEP()
    dim(geps)
    geps[1:5, 1:3]
    # --- Loadesmatrix [] ---
    # Key functions: loadESmatrix, loadPVmatrix
    ---------------------------------------------------------------------
    loadESmatrix(rp, "c3_TFT")[1:3, 1:3]
    loadPVmatrix(rp, "c3_TFT")[1:3, 1:3]
    # --- Getresults [] ---
    # Key functions: getResults
    ---------------------------------------------------------------------
    getResults(psea, "c3_TFT")
    # --- Loadcollection [] ---
    # Key functions: loadCollection, description
    ---------------------------------------------------------------------
    sets <- loadCollection(rp, "c3_MIR")
    wM5012 <- which(sapply(sets, setIdentifier)=="M5012")
    wM18759 <- which(sapply(sets, setIdentifier)=="M18759")
    description(sets[[wM5012]])
    # --- Getresults [] ---
    # Key functions: getResults
    ---------------------------------------------------------------------
    getResults(psea, "c3_TFT")
    # --- gene2pathways [] ---
    # Key functions: gene2pathways
    ---------------------------------------------------------------------
    pathways <- gene2pathways(rp, "FAM126A")
    pathways
    # --- Info [] ---
    # Key functions: info
    ---------------------------------------------------------------------
    rp$info("gep2pep repository")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gep2pep_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gep2pep_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gep2pep_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GEP2PEP:", paste0("    gep2pep: ", packageVersion("gep2pep"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gep2pep_results.csv
    touch ${prefix}_gep2pep_output.rds
    echo "BIOC_GEP2PEP:" > versions.yml
    echo "    gep2pep: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GEP2PEP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GEP2PEP(ch_input)

    emit:
    results  = BIOC_GEP2PEP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GEP2PEP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GEP2PEP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GEP2PEP.out.versions  // channel: path(versions.yml)
}
