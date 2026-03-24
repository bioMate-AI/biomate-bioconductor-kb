#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cBioPortalData
// The cBioPortalData R package accesses study datasets from the cBio Cancer Genomics Portal. It access
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cBioPortalData/inst/doc/cBioPortalData.R
// Upstream  : AnVIL, survival, survminer
// Downstream: bioCancer, canceR
//
// Install: BiocManager::install("cBioPortalData")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CBIOPORTALDATA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cbioportaldata"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cbioportaldata:2.18.2--r44_0' :
        'quay.io/biocontainers/bioconductor-cbioportaldata:2.18.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cbioportaldata_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cbioportaldata_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cbioportaldata_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Surv)
    library(jsonlite)

    # --- Cbioportal [] ---
    # Key functions: cBioPortal, getStudies
    ---------------------------------------------------------------------
    cbio <- cBioPortal()
    studies <- getStudies(cbio, buildReport = TRUE)
    head(studies)
    # --- Metadata [] ---
    # Key functions: metadata
    ---------------------------------------------------------------------
    metadata(acc)
    # --- Table [] ---
    # Key functions: colData
    ---------------------------------------------------------------------
    table(colData(laml)$OS_STATUS)
    class(colData(laml)$OS_MONTHS)
    # --- Coldata [] ---
    # Key functions: colData
    ---------------------------------------------------------------------
    collaml <- colData(laml)
    collaml[collaml$OS_MONTHS == "[Not Available]", "OS_MONTHS"] <- NA
    collaml$OS_MONTHS <- as.numeric(collaml$OS_MONTHS)
    colData(laml) <- collaml
    # --- Survfit [] ---
    # Key functions: survfit, Surv, colData, ggsurvplot
    ---------------------------------------------------------------------
    fit <- survfit(
        Surv(OS_MONTHS, as.numeric(substr(OS_STATUS, 1, 1))) ~ SEX,
        data = colData(laml)
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cbioportaldata_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cbioportaldata_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cbioportaldata_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CBIOPORTALDATA:", paste0("    cbioportaldata: ", packageVersion("cBioPortalData"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cbioportaldata_results.csv
    touch ${prefix}_cbioportaldata_output.rds
    echo "BIOC_CBIOPORTALDATA:" > versions.yml
    echo "    cbioportaldata: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CBIOPORTALDATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CBIOPORTALDATA(ch_input)

    emit:
    results  = BIOC_CBIOPORTALDATA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CBIOPORTALDATA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CBIOPORTALDATA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CBIOPORTALDATA.out.versions  // channel: path(versions.yml)
}
