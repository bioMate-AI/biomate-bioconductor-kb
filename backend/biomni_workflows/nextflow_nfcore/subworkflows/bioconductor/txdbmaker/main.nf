#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: txdbmaker
// A set of tools for making TxDb objects from genomic annotations from various sources (e.g. UCSC, Ens
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/txdbmaker/inst/doc/txdbmaker.R
// Upstream  : none
// Downstream: mygene
//
// Install: BiocManager::install("txdbmaker")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TXDBMAKER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-txdbmaker"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-txdbmaker:1.2.1--r44_0' :
        'quay.io/biocontainers/bioconductor-txdbmaker:1.2.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_txdbmaker_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_txdbmaker_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_txdbmaker_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(txdbmaker)
    library(jsonlite)

    # --- supported U C S Ctables [] ---
    # Key functions: supportedUCSCtables, makeTxDbFromUCSC
    supportedUCSCtables(genome="mm9")
    mm9KG_txdb <- makeTxDbFromUCSC(genome="mm9", tablename="knownGene")
    # --- make Tx Db From Biomart [] ---
    # Key functions: makeTxDbFromBiomart
    mmusculusEnsembl <- makeTxDbFromBiomart(dataset="mmusculus_gene_ensembl")
    # --- save Db [] ---
    # Key functions: saveDb
    saveDb(mm9KG_txdb, file="mm9KG_txdb.sqlite")
    # --- load Db [] ---
    # Key functions: loadDb
    mm9KG_txdb <- loadDb("mm9KG_txdb.sqlite")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_txdbmaker_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_txdbmaker_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_txdbmaker_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TXDBMAKER:", paste0("    txdbmaker: ", packageVersion("txdbmaker"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_txdbmaker_results.csv
    touch ${prefix}_txdbmaker_output.rds
    echo "BIOC_TXDBMAKER:" > versions.yml
    echo "    txdbmaker: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TXDBMAKER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TXDBMAKER(ch_input)

    emit:
    results  = BIOC_TXDBMAKER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TXDBMAKER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TXDBMAKER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TXDBMAKER.out.versions  // channel: path(versions.yml)
}
