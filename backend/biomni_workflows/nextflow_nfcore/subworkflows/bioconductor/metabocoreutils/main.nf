#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MetaboCoreUtils
// MetaboCoreUtils defines metabolomics-related core functionality provided as low-level functions to a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MetaboCoreUtils/inst/doc/MetaboCoreUtils.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MetaboCoreUtils")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METABOCOREUTILS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-metabocoreutils"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-metabocoreutils:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-metabocoreutils:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_metabocoreutils_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_metabocoreutils_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_metabocoreutils_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MetaboCoreUtils)
    library(jsonlite)

    # --- Chemical Formula Manipulation [] ---
    # Key functions: standardizeFormula, addElements, subtractElements, countElements, calculateMass
    raw_formula <- "Na3C4"
    std_formula <- standardizeFormula(raw_formula)
    added_formula <- addElements(std_formula, "H2O")
    final_formula <- subtractElements(added_formula, "H")
    element_counts <- countElements(final_formula)
    exact_masses <- calculateMass(c(final_formula, "C6H12O6"))


    # --- Kendrick Mass Defect Analysis [] ---
    # Key functions: calculateKmd, calculateRkmd, isRkmd
    lipid_masses <- c(760.5851, 762.6007, 762.5280)
    kmd_values <- calculateKmd(lipid_masses)
    rkmd_values <- calculateRkmd(lipid_masses)
    rkmd_status <- isRkmd(rkmd_values)


    # --- Retention Time Indexing and Correction [] ---
    # Key functions: indexRtime, correctRindex
    rti_data <- data.frame(
        rt = c(100, 200, 300, 400),
        rindex = c(1000, 2000, 3000, 4000)
    )
    rtime_data <- data.frame(
        rtime = c(150, 250, 350)
    )
    indexed_rtime <- indexRtime(rtime_data$rtime, rti_data)
    ref_data <- data.frame(
        rindex = c(1500, 2500),
        refindex = c(1490, 2510)
    )
    corrected_rindex <- correctRindex(indexed_rtime, ref_data)


    # --- Quality Control Signal Drift Modeling [] ---
    # Key functions: fit_lm
    vals_matrix <- matrix(
        runif(100, min = 10, max = 1000),
        nrow = 10,
        ncol = 10
    )
    colnames(vals_matrix) <- c(paste0("POOL_", 1:5), paste0("SAMP_", 1:5))
    sdata <- data.frame(injection_index = seq_len(ncol(vals_matrix)))
    qc_index <- grep("^POOL", colnames(vals_matrix))
    qc_models <- fit_lm(
        y ~ injection_index,
        data = sdata[qc_index, , drop = FALSE],
        y = log2(vals_matrix[, qc_index]),
        minVals = 3
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_metabocoreutils_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_metabocoreutils_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_metabocoreutils_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METABOCOREUTILS:", paste0("    metabocoreutils: ", packageVersion("MetaboCoreUtils"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metabocoreutils_results.csv
    touch ${prefix}_metabocoreutils_output.rds
    echo "BIOC_METABOCOREUTILS:" > versions.yml
    echo "    metabocoreutils: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METABOCOREUTILS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METABOCOREUTILS(ch_input)

    emit:
    results  = BIOC_METABOCOREUTILS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METABOCOREUTILS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METABOCOREUTILS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METABOCOREUTILS.out.versions  // channel: path(versions.yml)
}
