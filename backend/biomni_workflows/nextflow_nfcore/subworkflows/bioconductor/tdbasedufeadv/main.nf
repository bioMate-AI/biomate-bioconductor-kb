#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TDbasedUFEadv
// This is an advanced version of TDbasedUFE, which is a comprehensive package to perform Tensor decomp
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TDbasedUFEadv/inst/doc/Enrichment.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("TDbasedUFEadv")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TDBASEDUFEADV {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tdbasedufeadv"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tdbasedufeadv:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tdbasedufeadv:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tdbasedufeadv_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tdbasedufeadv_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tdbasedufeadv_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PrepareSummarizedExperimentTensor)
    library(jsonlite)

    # --- List [] ---
    # Key functions: prepareTensorfromList, aperm, PrepareSummarizedExperimentTensor, array
    ---------------------------------------------------------------------
    Multi <- list(
      BLCA.rnaseq[seq_len(100), 1 + seq_len(1000)],
      BRCA.rnaseq[seq_len(100), 1 + seq_len(1000)],
      CESC.rnaseq[seq_len(100), 1 + seq_len(1000)],
    # --- Setenrichrsite [] ---
    # Key functions: setEnrichrSite, enrichr, plotEnrich
    ---------------------------------------------------------------------
    setEnrichrSite("Enrichr")
    websiteLive <- TRUE
    dbs <- c(
      "GO_Molecular_Function_2015", "GO_Cellular_Component_2015",
    # --- Enrichdgn [] ---
    # Key functions: enrichDGN, dotplot, ggtitle
    ---------------------------------------------------------------------
    edo <- enrichDGN(entrez)
    dotplot(edo, showCategory=30) + ggtitle("dotplot for ORA")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tdbasedufeadv_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tdbasedufeadv_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tdbasedufeadv_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TDBASEDUFEADV:", paste0("    tdbasedufeadv: ", packageVersion("TDbasedUFEadv"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tdbasedufeadv_results.csv
    touch ${prefix}_tdbasedufeadv_output.rds
    echo "BIOC_TDBASEDUFEADV:" > versions.yml
    echo "    tdbasedufeadv: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TDBASEDUFEADV_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TDBASEDUFEADV(ch_input)

    emit:
    results  = BIOC_TDBASEDUFEADV.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TDBASEDUFEADV.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TDBASEDUFEADV.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TDBASEDUFEADV.out.versions  // channel: path(versions.yml)
}
