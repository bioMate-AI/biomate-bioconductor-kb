#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BioQC
// BioQC performs quality control of high-throughput expression data based on tissue gene signatures. I
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BioQC/inst/doc/BioQC.R
// Upstream  : Biobase, RColorBrewer, gplots, gridExtra, lattice
// Downstream: none
//
// Install: BiocManager::install("BioQC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOQC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bioqc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bioqc:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bioqc:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bioqc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bioqc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bioqc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BioQC)
    library(jsonlite)

    # --- Define comparison contrasts [] ---
    # Key functions: with, makeContrasts, exprs, lmFit
    isNeph <- with(pData(eset), Strain=="FVB/NJ" &
    TREATMENTNAME %in% c("Nephrectomy-Losartan", "Sham-Losartan"))
    isContam <- with(pData(eset), INDIVIDUALNAME %in% c("BN7", "FNL8", "FN6"))
    # --- Table formatting and display [] ---
    # Key functions: readGmt, filterPmat, absLog10p, heatmap, matplot, kable
    kable(diffTable, caption="Genes that are identified as strongly changed ony if the contaminated sample is included.")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bioqc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bioqc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bioqc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOQC:", paste0("    bioqc: ", packageVersion("BioQC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bioqc_results.csv
    touch ${prefix}_bioqc_output.rds
    echo "BIOC_BIOQC:" > versions.yml
    echo "    bioqc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOQC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOQC(ch_input)

    emit:
    results  = BIOC_BIOQC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOQC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOQC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOQC.out.versions  // channel: path(versions.yml)
}
