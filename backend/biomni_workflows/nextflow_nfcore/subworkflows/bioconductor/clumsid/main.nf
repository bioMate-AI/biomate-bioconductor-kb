#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CluMSID
// CluMSID is a tool that aids the identification of features in untargeted LC-MS/MS analysis by the us
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CluMSID/inst/doc/CluMSID_DI-MSMS.R
// Upstream  : CluMSIDdata, magrittr, metaMS, metaMSdata
// Downstream: none
//
// Install: BiocManager::install("CluMSID")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLUMSID {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-clumsid"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-clumsid:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-clumsid:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_clumsid_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_clumsid_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_clumsid_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HCplot)
    library(jsonlite)

    # --- extract M S2spectra [] ---
    # Key functions: extractMS2spectra
    ms2list <- extractMS2spectra(DIfile)
    length(ms2list)
    # --- merge M S2spectra [] ---
    # Key functions: mergeMS2spectra
    featlist <- mergeMS2spectra(ms2list, rt_tolerance = 1)
    length(featlist)
    # --- distance Matrix [] ---
    # Key functions: distanceMatrix
    distmat <- distanceMatrix(featlist)
    # --- H Cplot [] ---
    # Key functions: HCplot
    HCplot(distmat, cex = 0.5)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_clumsid_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_clumsid_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_clumsid_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLUMSID:", paste0("    clumsid: ", packageVersion("CluMSID"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clumsid_results.csv
    touch ${prefix}_clumsid_output.rds
    echo "BIOC_CLUMSID:" > versions.yml
    echo "    clumsid: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLUMSID_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLUMSID(ch_input)

    emit:
    results  = BIOC_CLUMSID.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLUMSID.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLUMSID.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLUMSID.out.versions  // channel: path(versions.yml)
}
