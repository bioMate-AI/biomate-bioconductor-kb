#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MEAT
// This package estimates epigenetic age in skeletal muscle, using DNA methylation data generated with 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MEAT/inst/doc/MEAT.R
// Upstream  : SummarizedExperiment, minfi
// Downstream: none
//
// Install: BiocManager::install("MEAT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MEAT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-meat"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-meat:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-meat:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_meat_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_meat_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_meat_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BMIQcalibration)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Methylation matrix presentation table [] ---
    # Key functions: kable
    kable(head(GSE121961),
    # --- Phenotype table presentation table [] ---
    # Key functions: kable
    kable(GSE121961_pheno,
    # --- Data formatting [] ---
    # Key functions: SummarizedExperiment
    library(SummarizedExperiment)
    GSE121961_SE <- SummarizedExperiment(assays=list(beta=GSE121961),
    # --- Data cleaning [] ---
    # Key functions: clean_beta
    GSE121961_SE_clean <- clean_beta(SE = GSE121961_SE,
    # --- Data cleaning table [] ---
    # Key functions: kable
    kable(head(assays(GSE121961_SE_clean)$beta),
    # --- Data calibration [] ---
    # Key functions: BMIQcalibration
    GSE121961_SE_calibrated <- BMIQcalibration(SE = GSE121961_SE_clean,
    # --- Data calibration table [] ---
    # Key functions: kable
    kable(head(assays(GSE121961_SE_calibrated)$beta),
    # --- DNA methylation profile distribution before and after calibration [] ---
    # Key functions: densityPlot
    data("gold.mean.MEAT2.0", envir = environment())
    GSE121961_SE_clean_with_gold_mean <- cbind(assays(GSE121961_SE_clean)$beta,
    GSE121961_SE_calibrated_with_gold_mean <- cbind(assays(GSE121961_SE_calibrated)$beta,
    # --- Epigenetic age estimation with phenotypes [] ---
    # Key functions: epiage_estimation
    GSE121961_SE_epiage <- epiage_estimation(SE = GSE121961_SE_calibrated,
    # --- Epigenetic age estimation with phenotypes table [] ---
    # Key functions: kable
    kable(colData(GSE121961_SE_epiage),

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_meat_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_meat_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_meat_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MEAT:", paste0("    meat: ", packageVersion("MEAT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_meat_results.csv
    touch ${prefix}_meat_output.rds
    echo "BIOC_MEAT:" > versions.yml
    echo "    meat: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MEAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MEAT(ch_input)

    emit:
    results  = BIOC_MEAT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MEAT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MEAT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MEAT.out.versions  // channel: path(versions.yml)
}
