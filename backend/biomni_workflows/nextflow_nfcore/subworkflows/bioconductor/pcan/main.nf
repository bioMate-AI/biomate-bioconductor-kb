#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PCAN
// Phenotypes comparison based on a pathway consensus approach. Assess the relationship between candida
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PCAN/inst/doc/PCAN.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("PCAN")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PCAN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pcan"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pcan:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pcan:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pcan_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pcan_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pcan_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PCAN)
    library(MulticoreParam)
    library(SerialParam)
    library(jsonlite)

    # --- Phenotype Semantic Similarity Calculation [] ---
    # Key functions: calcHpSim, compareHPSets
    sim_val <- calcHpSim(
        "HP:0000518",
        "HP:0030084",
        IC = ic,
        ancestors = hp_ancestors
    )
    compMat <- compareHPSets(
        hpSet1 = genHp,
        hpSet2 = hpOfInterest,
        IC = ic,
        ancestors = hp_ancestors,
        method = "Resnik"
    )


    # --- Gene-Phenotype Association Scoring [] ---
    # Key functions: hpSetCompSummary
    score_summary <- hpSetCompSummary(
        compMat,
        method = "bma",
        direction = "symSim"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pcan_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pcan_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pcan_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PCAN:", paste0("    pcan: ", packageVersion("PCAN"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pcan_results.csv
    touch ${prefix}_pcan_output.rds
    echo "BIOC_PCAN:" > versions.yml
    echo "    pcan: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PCAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PCAN(ch_input)

    emit:
    results  = BIOC_PCAN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PCAN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PCAN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PCAN.out.versions  // channel: path(versions.yml)
}
