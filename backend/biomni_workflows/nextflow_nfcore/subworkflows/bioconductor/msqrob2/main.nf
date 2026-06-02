#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: msqrob2
// msqrob2 provides a robust linear mixed model framework for assessing differential abundance in MS-ba
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/msqrob2/inst/doc/cptac.R
// Upstream  : QFeatures, gridExtra, limma, plotly, tidyverse
// Downstream: none
//
// Install: BiocManager::install("msqrob2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSQROB2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msqrob2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msqrob2:1.14.1--r44_0' :
        'quay.io/biocontainers/bioconductor-msqrob2:1.14.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msqrob2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msqrob2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msqrob2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(msqrob2)
    library(jsonlite)

    # --- Preprocessing ---
    # Key functions: smallestUniqueGroups
    prot_col <- rowData(pe[["peptideRaw"]])$Proteins
    unique_filter <- prot_col %in% smallestUniqueGroups(prot_col)
    pe <- pe[unique_filter, , ]
    pe <- zeroIsNA(pe, "peptideRaw")
    pe <- logTransform(
        pe, 
        base = 2, 
        i = "peptideRaw", 
        name = "peptideLog"
    )

    # --- Feature Filtering ---
    # Key functions: filterFeatures
    pe <- filterFeatures(pe, ~ Reverse != "+")
    pe <- filterFeatures(pe, ~ Potential.contaminant != "+")
    rowData(pe[["peptideLog"]])$nNonZero <- rowSums(
        assay(pe[["peptideLog"]]) > 0, 
        na.rm = TRUE
    )
    pe <- filterFeatures(pe, ~ nNonZero >= 2)

    # --- Normalisation ---
    # Key functions: normalize
    pe <- normalize(
        pe,
        i = "peptideLog",
        name = "peptideNorm",
        method = "center.median"
    )

    # --- Protein Aggregation ---
    # Key functions: aggregateFeatures
    pe <- aggregateFeatures(
        pe,
        i = "peptideNorm",
        fcol = "Proteins",
        na.rm = TRUE,
        name = "protein"
    )

    # --- Differential Abundance Analysis ---
    # Key functions: msqrob, makeContrast, hypothesisTest, getCoef
    pe <- msqrob(object = pe, i = "protein", formula = ~condition)
    L <- makeContrast("conditionB=0", parameterNames = c("conditionB"))
    pe <- hypothesisTest(object = pe, i = "protein", contrast = L)
    models <- rowData(pe[["protein"]])$msqrobModels
    coefs <- getCoef(models[[1]])


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msqrob2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msqrob2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msqrob2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSQROB2:", paste0("    msqrob2: ", packageVersion("msqrob2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msqrob2_results.csv
    touch ${prefix}_msqrob2_output.rds
    echo "BIOC_MSQROB2:" > versions.yml
    echo "    msqrob2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSQROB2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSQROB2(ch_input)

    emit:
    results  = BIOC_MSQROB2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSQROB2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSQROB2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSQROB2.out.versions  // channel: path(versions.yml)
}
