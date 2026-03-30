#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cbaf
// This package contains functions that allow analysing and comparing omic data across various cancers/
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cbaf/inst/doc/cbaf.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("cbaf")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CBAF {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cbaf"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cbaf:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cbaf:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cbaf_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cbaf_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cbaf_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Carcinoma)
    library(Glioma)
    library(Leukemia)
    library(jsonlite)

    # --- List [] ---
    # Key functions: processOneStudy, Carcinoma
    ---------------------------------------------------------------------
    genes <- list(K.demethylases = c("KDM1A", "KDM1B", "KDM2A", "KDM2B", "KDM3A", "KDM3B", "JMJD1C", "KDM4A"), K.methyltransferases = c("SUV39H1", "SUV39H2", "EHMT1", "EHMT2", "SETDB1", "SETDB2", "KMT2A", "KMT2A"))
    processOneStudy(genes, "test", "Breast Invasive Carcinoma (TCGA, Cell 2015)", "RNA-Seq", desiredCaseList = c(2,3,4,5), calculate = c("frequencyPercentage",  "frequencyRatio"), heatmapFileFormat = "TIFF")
    # --- List [] ---
    # Key functions: Leukemia, Carcinoma, Glioma, processMultipleStudies
    ---------------------------------------------------------------------
    genes <- list(K.demethylases = c("KDM1A", "KDM1B", "KDM2A", "KDM2B", "KDM3A", "KDM3B", "JMJD1C", "KDM4A"), K.methyltransferases = c("SUV39H1", "SUV39H2", "EHMT1", "EHMT2", "SETDB1", "SETDB2", "KMT2A", "KMT2A"))
    studies <- c("Acute Myeloid Leukemia (TCGA, Provisional)", "Adrenocortical Carcinoma (TCGA, Provisional)", "Bladder Urothelial Carcinoma (TCGA, Provisional)", "Brain Lower Grade Glioma (TCGA, Provisional)", "Breast Invasive Carcinoma (TCGA, Provisional)")
    processMultipleStudies(genes, "test2", studies, "RNA-Seq", calculate = c("frequencyPercentage", "frequencyRatio"), heatmapFileFormat = "TIFF")
    # --- List [] ---
    # Key functions: obtainOneStudy, Carcinoma
    ---------------------------------------------------------------------
    genes <- list(K.demethylases = c("KDM1A", "KDM1B", "KDM2A"), K.acetyltransferases = c("CLOCK", "CREBBP", "ELP3", "EP300"))
    obtainOneStudy(genes, "test", "Breast Invasive Carcinoma (TCGA, Cell 2015)", "RNA-Seq", desiredCaseList = c(2,3,4,5))
    # --- List [] ---
    # Key functions: Leukemia, Carcinoma, Glioma, obtainMultipleStudies
    ---------------------------------------------------------------------
    genes <- list(K.demethylases = c("KDM1A", "KDM1B", "KDM2A"), K.acetyltransferases = c("CLOCK", "CREBBP", "ELP3", "EP300"))
    # Specifying names of cancer studies by standard study names
    cancernames <- c("Acute Myeloid Leukemia (TCGA, Provisional)", "Adrenocortical Carcinoma (TCGA, Provisional)", "Bladder Urothelial Carcinoma (TCGA, Provisional)", "Brain Lower Grade Glioma (TCGA, Provisional)", "Breast Invasive Carcinoma (TCGA, Provisional)")
    # Specifying names of cancer studies by creating a matrix that includes standard and desired study names
    # --- Automatedstatistics [] ---
    # Key functions: automatedStatistics
    ---------------------------------------------------------------------
    automatedStatistics("test", obtainedDataType = "single study", calculate = c("frequencyPercentage", "frequencyRatio"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cbaf_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cbaf_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cbaf_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CBAF:", paste0("    cbaf: ", packageVersion("cbaf"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cbaf_results.csv
    touch ${prefix}_cbaf_output.rds
    echo "BIOC_CBAF:" > versions.yml
    echo "    cbaf: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CBAF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CBAF(ch_input)

    emit:
    results  = BIOC_CBAF.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CBAF.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CBAF.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CBAF.out.versions  // channel: path(versions.yml)
}
