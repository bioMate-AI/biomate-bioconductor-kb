#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biotmle
// Tools for differential expression biomarker discovery based on microarray and next-generation sequen
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biotmle/inst/doc/exposureBiomarkers.R
// Upstream  : BiocParallel, SuperLearner, biotmleData, dplyr
// Downstream: none
//
// Install: BiocManager::install("biotmle")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOTMLE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biotmle"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biotmle:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biotmle:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biotmle_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biotmle_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biotmle_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(biotmle)
    library(jsonlite)

    # --- Data Preparation [biotmle] ---
    # Key functions: colData
    colData(illuminaData)$age <- as.numeric(
        colData(illuminaData)$age > median(colData(illuminaData)$age)
    )
    benz_idx <- which(names(colData(illuminaData)) %in% "benzene")

    # --- Biomarker TMLE Estimation [biotmle] ---
    # Key functions: biomarkertmle
    biotmle_out <- biomarkertmle(
        se = illuminaData[1:20, ],
        varInt = benz_idx,
        g_lib = c("SL.mean", "SL.glm"),
        Q_lib = c("SL.bayesglm", "SL.mean"),
        cv_folds = 2
    )

    # --- Moderated Hypothesis Testing [biotmle] ---
    # Key functions: modtest_ic
    modtmle_out <- modtest_ic(
        biotmle = biotmle_out
    )

    # --- Heatmap Visualization [biotmle] ---
    # Key functions: heatmap_ic
    designVar <- as.numeric(
        colData(illuminaData)$benzene == max(colData(illuminaData)$benzene)
    )
    heatmap_ic(
        x = modtmle_out,
        left.label = "none",
        scale = TRUE,
        clustering.method = "hierarchical",
        row.dendrogram = TRUE,
        design = designVar,
        FDRcutoff = 1,
        top = 10
    )

    # --- Volcano Plot Visualization [biotmle] ---
    # Key functions: volcano_ic
    volcano_ic(
        biotmle = modtmle_out
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biotmle_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biotmle_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biotmle_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOTMLE:", paste0("    biotmle: ", packageVersion("biotmle"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biotmle_results.csv
    touch ${prefix}_biotmle_output.rds
    echo "BIOC_BIOTMLE:" > versions.yml
    echo "    biotmle: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOTMLE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOTMLE(ch_input)

    emit:
    results  = BIOC_BIOTMLE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOTMLE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOTMLE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOTMLE.out.versions  // channel: path(versions.yml)
}
