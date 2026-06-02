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

    # --- Adductnames [] ---
    # Key functions: adductNames
    ---------------------------------------------------------------------
    adductNames()
    # --- formula2mz [] ---
    # Key functions: formula2mz
    ---------------------------------------------------------------------
    formula2mz(c("C6H12O6", "C8H10N4O2"), adduct = c("[M+H]+", "[M+Na]+"))
    # --- Standardizeformula [] ---
    # Key functions: standardizeFormula
    ---------------------------------------------------------------------
    frml <- "Na3C4"
    frml <- standardizeFormula(frml)
    frml
    # --- Addelements [] ---
    # Key functions: addElements
    ---------------------------------------------------------------------
    frml <- addElements(frml, "H2O")
    frml
    # --- Subtractelements [] ---
    # Key functions: subtractElements
    ---------------------------------------------------------------------
    frml <- subtractElements(frml, "H")
    frml
    # --- Countelements [] ---
    # Key functions: countElements
    ---------------------------------------------------------------------
    countElements(frml)
    # --- Adductformula [] ---
    # Key functions: adductFormula
    ---------------------------------------------------------------------
    adductFormula(c("C6H12O6", "C8H10N4O2"), adduct = c("[M+H]+", "[M+Na]+"))
    # --- Calculatemass [] ---
    # Key functions: calculateMass
    ---------------------------------------------------------------------
    calculateMass(c("C6H12O6", "[13C3]C3H12O6"))
    # --- Calculaterkmd [] ---
    # Key functions: calculateRkmd, isRkmd
    ---------------------------------------------------------------------
    lipid_rkmd <- calculateRkmd(lipid_masses)
    isRkmd(lipid_rkmd)
    # --- Table [] ---
    # Key functions: file
    ---------------------------------------------------------------------
    # --- Indexrtime [] ---
    # Key functions: indexRtime
    ---------------------------------------------------------------------
    rtime$rindex_r <- indexRtime(rtime$rtime, rti)
    # --- Frame [] ---
    # Key functions: frame, correctRindex
    ---------------------------------------------------------------------
    ref <- data.frame(rindex = c(1709.8765, 553.7975),
                      refindex = c(1700, 550))
    rtime$rindex_cor <- correctRindex(rtime$rindex_r, ref)
    # --- Table [] ---
    # Key functions: file
    ---------------------------------------------------------------------
    vals <- read.table(system.file("txt", "feature_values.txt",
                                   package = "MetaboCoreUtils"), sep = "\t")
    vals <- as.matrix(vals)
    head(vals)
    # --- Frame [] ---
    # Key functions: frame
    ---------------------------------------------------------------------
    #' Define a data frame with the injection index
    sdata <- data.frame(injection_index = seq_len(ncol(vals)))
    #' Identify columns representing QC samples
    qc_index <- grep("^POOL", colnames(vals))
    # --- Fit Lm [] ---
    # Key functions: fit_lm
    ---------------------------------------------------------------------
    #' Fit linear models explaining observed abundances by injection index.
    #' Linear models are fitted row-wise to data of QC samples.

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
