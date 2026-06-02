#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: bugsigdbr
// The bugsigdbr package implements convenient access to bugsigdb.org from within R/Bioconductor. The g
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/bugsigdbr/inst/doc/bugsigdbr.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("bugsigdbr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BUGSIGDBR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bugsigdbr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bugsigdbr:1.12.3--r44_0' :
        'quay.io/biocontainers/bioconductor-bugsigdbr:1.12.3--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bugsigdbr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bugsigdbr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bugsigdbr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(bugsigdbr)
    library(jsonlite)

    # --- import Bug Sig D B [] ---
    # Key functions: importBugSigDB
    bsdb <- importBugSigDB()
    dim(bsdb)
    colnames(bsdb)
    # --- get Signatures [] ---
    # Key functions: getSignatures
    sigs <- getSignatures(bsdb)
    length(sigs)
    # --- write G M T [] ---
    # Key functions: writeGMT
    writeGMT(sigs, gmt.file = "bugsigdb_signatures.gmt")
    # --- browse Signature [] ---
    # Key functions: browseSignature
    browseSignature(names(sigs)[1])
    # --- browse Taxon [] ---
    # Key functions: browseTaxon
    browseTaxon(sigs[[1]][1])
    # --- get Ontology [] ---
    # Key functions: getOntology
    efo <- getOntology("efo")
    # --- subset By Ontology [] ---
    # Key functions: subsetByOntology


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bugsigdbr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bugsigdbr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bugsigdbr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BUGSIGDBR:", paste0("    bugsigdbr: ", packageVersion("bugsigdbr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bugsigdbr_results.csv
    touch ${prefix}_bugsigdbr_output.rds
    echo "BIOC_BUGSIGDBR:" > versions.yml
    echo "    bugsigdbr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BUGSIGDBR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BUGSIGDBR(ch_input)

    emit:
    results  = BIOC_BUGSIGDBR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BUGSIGDBR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BUGSIGDBR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BUGSIGDBR.out.versions  // channel: path(versions.yml)
}
