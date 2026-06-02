#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: multiMiR
// A collection of microRNAs/targets from external resources, including validated microRNA-target datab
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/multiMiR/inst/doc/multiMiR.R
// Upstream  : edgeR, knitr
// Downstream: none
//
// Install: BiocManager::install("multiMiR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MULTIMIR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-multimir"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-multimir:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-multimir:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_multimir_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_multimir_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_multimir_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(multiMiR)
    library(DGEList)
    library(jsonlite)

    # --- Entity Exploration and Table Lookup [] ---
    # Key functions: list_multimir, predicted_tables, validated_tables, reverse_table_lookup
    sample_mirnas <- list_multimir("mirna", limit = 10)
    sample_genes <- list_multimir("gene", limit = 10)
    pred_tables <- predicted_tables()
    val_tables <- validated_tables()
    targetscan_source <- reverse_table_lookup("targetscan")


    # --- MicroRNA Target Querying [] ---
    # Key functions: get_multimir
    multimir_results <- get_multimir(
        org = "hsa",
        mirna = "hsa-miR-18a-3p",
        table = "validated",
        summary = TRUE
    )
    result_data <- multimir_results@data
    result_summary <- multimir_results@summary
    luciferase_validated <- result_data[
        grep("Luciferase", result_data[, "experiment"]), 
    ]


    # --- Disease and Drug Association Querying [] ---
    # Key functions: get_multimir
    drug_results <- get_multimir(
        disease.drug = "cisplatin",
        table = "disease.drug"
    )
    drug_data <- drug_results@data
    association_types <- table(drug_data$type)


    # --- Result Filtering and Selection [] ---
    # Key functions: select, keys, columns
    all_columns <- columns(multimir_results)
    validated_subset <- select(
        multimir_results,
        keytype = "type",
        keys = "validated",
        columns = all_columns
    )
    unique_pairs <- validated_subset[
        !duplicated(validated_subset[, c("mature_mirna_id", "target_entrez")]), 
    ]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_multimir_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_multimir_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_multimir_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MULTIMIR:", paste0("    multimir: ", packageVersion("multiMiR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multimir_results.csv
    touch ${prefix}_multimir_output.rds
    echo "BIOC_MULTIMIR:" > versions.yml
    echo "    multimir: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MULTIMIR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MULTIMIR(ch_input)

    emit:
    results  = BIOC_MULTIMIR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MULTIMIR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MULTIMIR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MULTIMIR.out.versions  // channel: path(versions.yml)
}
