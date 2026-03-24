#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Structstrings
// The Structstrings package implements the widely used dot bracket annotation for storing base pairing
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Structstrings/inst/doc/Structstrings.R
// Upstream  : none
// Downstream: tRNA, tRNAdbImport
//
// Install: BiocManager::install("Structstrings")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_STRUCTSTRINGS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-structstrings"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-structstrings:1.22.1--r44_0' :
        'quay.io/biocontainers/bioconductor-structstrings:1.22.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_structstrings_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_structstrings_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_structstrings_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DotBracketString)
    library(StructuredRNAStringSet)
    library(jsonlite)

    # --- get Base Pairing [] ---
    # Key functions: getBasePairing
    dbdfl <- getBasePairing(dbs)
    # --- get Loop Indices [] ---
    # Key functions: getLoopIndices, all
    loopids <- getLoopIndices(dbs, bracket.type = 1L)
    loopids2 <- getLoopIndices(dbdfl, bracket.type = 1L)
    all(loopids == loopids2)
    # --- get Dot Bracket [] ---
    # Key functions: getDotBracket, unlist, relist
    rec_dbs <- getDotBracket(dbdfl)
    dbdf <- unlist(dbdfl)
    dbdfl2 <- relist(dbdf,dbdfl)
    # --- Dot Bracket String [] ---
    # Key functions: DotBracketString, getDotBracket
    db <- DotBracketString("((((....[[[))))....((((....<<<<...))))]]]....>>>>...")
    getDotBracket(getBasePairing(db), force = TRUE)
    # --- structured rna string [] ---
    # Key functions: StructuredRNAStringSet, dotbracket
    data("dbs", package = "Structstrings")
    data("nseq", package = "Structstrings")
    sdbs <- StructuredRNAStringSet(nseq,dbs)
    # --- structured rna string base pairing [] ---
    # Key functions: getBasePairing
    dbdfl <- getBasePairing(sdbs)
    dbdfl <- getBasePairing(sdbs, return.sequence = TRUE)
    sessionInfo()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_structstrings_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_structstrings_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_structstrings_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_STRUCTSTRINGS:", paste0("    structstrings: ", packageVersion("Structstrings"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_structstrings_results.csv
    touch ${prefix}_structstrings_output.rds
    echo "BIOC_STRUCTSTRINGS:" > versions.yml
    echo "    structstrings: 0.0.0" >> versions.yml
    """
}


workflow BIOC_STRUCTSTRINGS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_STRUCTSTRINGS(ch_input)

    emit:
    results  = BIOC_STRUCTSTRINGS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_STRUCTSTRINGS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_STRUCTSTRINGS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_STRUCTSTRINGS.out.versions  // channel: path(versions.yml)
}
