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
    library(DGEList)
    library(jsonlite)

    # --- multimir switchDBVersion [] ---
    # Key functions: multimir_dbInfoVersions, multimir_switchDBVersion
    vers_table <- multimir_dbInfoVersions()
    multimir_switchDBVersion(db_version = "2.0.0")
    multimir_switchDBVersion(db_version = curr_vers)
    # --- predicted_tables [] ---
    # Key functions: predicted_tables, validated_tables, diseasedrug_tables, reverse_table_lookup
    predicted_tables()
    validated_tables()
    diseasedrug_tables()
    # --- Load saved R data object [] ---
    # Key functions: DGEList, calcNormFactors, estimateGLMCommonDisp, estimateGLMTrendedDisp
    library(edgeR)
    library(multiMiR)
    counts_file  <- system.file("extdata", "counts_table.Rds", package = "multiMiR")
    # --- Example1 [] ---
    # Key functions: get_multimir
    example1 <- get_multimir(mirna = 'hsa-miR-18a-3p', summary = TRUE)
    names(example1)
    table(example1@data$type)
    # --- Example2 [] ---
    # Key functions: get_multimir
    example2 <- get_multimir(disease.drug = 'cisplatin', table = 'disease.drug')
    names(example2)
    nrow(example2@data)
    # --- Example3 part1 [] ---
    # Key functions: get_multimir

    # --- Example4 part1 [] ---
    # Key functions: get_multimir

    # --- Example5 part2 [] ---
    # Key functions: get_multimir

    # --- Example5 part4 [] ---
    # Key functions: keys
    mykeys <- keys(example5, keytype = mykeytype)
    mykeys <- mykeys[grep("bladder", mykeys, ignore.case = TRUE)]
    # --- columns [] ---
    # Key functions: columns, keytypes, keys
    columns(example4)
    head(keys(example4))
    keytypes(example4)
    # --- Direct query1 [] ---
    # Key functions: search_multimir
    direct2 <- search_multimir(query = "describe diana_microt")
    # --- Direct query2 [] ---
    # Key functions: search_multimir


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
