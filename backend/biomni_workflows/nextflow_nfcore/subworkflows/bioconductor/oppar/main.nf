#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: oppar
// The R implementation of mCOPA package published by Wang et al. (2012). Oppar provides methods for Ca
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/oppar/inst/doc/oppar.R
// Upstream  : Biobase, knitr, limma
// Downstream: none
//
// Install: BiocManager::install("oppar")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OPPAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-oppar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-oppar:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-oppar:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_oppar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_oppar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_oppar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(oppar)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: cases, factor, exprs, opa
    ---------------------------------------------------------------------
    data(Tomlins) # loads processed Tomlins data
    # the first 21 samples are Normal samples, and the rest of
    # the samples are our cases (metastatic). We, thus, generate a group
    # variable for the samples based on this knowledge.
    # --- Getsampleoutlier [] ---
    # Key functions: getSampleOutlier
    ---------------------------------------------------------------------
    getSampleOutlier(tomlins.opa, c(1,5))
    # --- Getsubtypeprobes [] ---
    # Key functions: getSubtypeProbes
    ---------------------------------------------------------------------
    outlier.list <- getSubtypeProbes(tomlins.opa, 1:ncol(tomlins.opa$profileMatrix))
    # --- Rownames [] ---
    # Key functions: columns, keytypes, select
    ---------------------------------------------------------------------
    go.terms <- rownames(up.mroast[1:10,])
    #BiocManager::install(GO.db)
    library(GO.db)
    columns(GO.db)
    # --- List [] ---
    # Key functions: exprs, fData
    ---------------------------------------------------------------------
    library(org.Hs.eg.db)
    library(limma)
    org.Hs.egGO2EG
    go2eg <- as.list(org.Hs.egGO2EG)
    # --- Rownames [] ---
    # Key functions: select
    ---------------------------------------------------------------------
    go_terms_down <- rownames(down_mroast[1:10,])
    dr2tab <- select(GO.db, keys=go_terms_down,
                    columns=c("GOID","TERM"),
                    keytype="GOID")
    # --- Data [] ---
    # Key functions: gsva
    ---------------------------------------------------------------------
    data("Maupin")
    names(maupin)
    head(maupin$data)
    head(maupin$sig)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_oppar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_oppar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_oppar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OPPAR:", paste0("    oppar: ", packageVersion("oppar"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_oppar_results.csv
    touch ${prefix}_oppar_output.rds
    echo "BIOC_OPPAR:" > versions.yml
    echo "    oppar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OPPAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OPPAR(ch_input)

    emit:
    results  = BIOC_OPPAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OPPAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OPPAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OPPAR.out.versions  // channel: path(versions.yml)
}
