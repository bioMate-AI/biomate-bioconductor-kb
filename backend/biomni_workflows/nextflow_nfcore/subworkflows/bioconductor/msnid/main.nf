#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MSnID
// Extracts MS/MS ID data from mzIdentML (leveraging mzID package) or text files. After collating the s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MSnID/inst/doc/handling_mods.R
// Upstream  : Biostrings, MSnbase, dplyr, ggplot2, xtable
// Downstream: none
//
// Install: BiocManager::install("MSnID")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSNID {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msnid"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msnid:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-msnid:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msnid_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msnid_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msnid_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MSnID)
    library(jsonlite)

    # --- Data Loading and Parsing [Data Loading and Parsing] ---
    # Key functions: MSnID, read_mzIDs, id_files, peptides
    msnid <- MSnID()
    mzid_files <- c("sample1.mzid", "sample2.mzid")
    msnid <- read_mzIDs(msnid, mzid_files)
    loaded_files <- id_files(msnid)
    peptide_sequences <- peptides(msnid)

    # --- Peptide-Spectrum Match Filtering [Peptide-Spectrum Match Filtering] ---
    # Key functions: MSnIDFilter, apply_filter
    filtObj <- MSnIDFilter(msnid)
    filtObj$msmsScore <- list(comparison = ">", value = 20)
    filtObj$absParentMassErrorPPM <- list(comparison = "<", value = 10)
    msnid <- apply_filter(msnid, filtObj)

    # --- FDR Assessment and Optimization [FDR Assessment and Optimization] ---
    # Key functions: MSnIDFilter, optimize_filter, apply_filter, assess_fdr
    filtObj <- MSnIDFilter(msnid)
    filtObj$msmsScore <- list(comparison = ">", value = 10)
    filtObj$absParentMassErrorPPM <- list(comparison = "<", value = 20)
    filtObj_opt <- optimize_filter(
        filtObj, msnid, fdr.max = 0.01,
        method = "Grid", level = "peptide"
    )
    msnid <- apply_filter(msnid, filtObj_opt)
    fdr_summary <- assess_fdr(msnid, level = "peptide")

    # --- Data Conversion and Export [Data Conversion and Export] ---
    # Key functions: psms, as
    psm_table <- psms(msnid)
    msnset_data <- as(msnid, "MSnSet")
    flat_dataframe <- as(msnid, "data.frame")


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msnid_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msnid_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msnid_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSNID:", paste0("    msnid: ", packageVersion("MSnID"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msnid_results.csv
    touch ${prefix}_msnid_output.rds
    echo "BIOC_MSNID:" > versions.yml
    echo "    msnid: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSNID_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSNID(ch_input)

    emit:
    results  = BIOC_MSNID.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSNID.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSNID.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSNID.out.versions  // channel: path(versions.yml)
}
