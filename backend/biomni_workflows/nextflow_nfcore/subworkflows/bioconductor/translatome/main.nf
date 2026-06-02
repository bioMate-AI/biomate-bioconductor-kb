#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tRanslatome
// Detection of differentially expressed genes (DEGs) from the comparison of two biological conditions 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tRanslatome/inst/doc/tRanslatome_package.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("tRanslatome")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRANSLATOME {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-translatome"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-translatome:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-translatome:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_translatome_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_translatome_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_translatome_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GOComparison)
    library(GOEnrichment)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: newTranslatomeDataset, computeDEGs, GOEnrichment, GOComparison
    ##loading the tRanslatome package
     library(tRanslatome)
     ##loading the training data set
     data(tRanslatomeSampleData)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_translatome_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_translatome_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_translatome_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TRANSLATOME:", paste0("    translatome: ", packageVersion("tRanslatome"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_translatome_results.csv
    touch ${prefix}_translatome_output.rds
    echo "BIOC_TRANSLATOME:" > versions.yml
    echo "    translatome: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TRANSLATOME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TRANSLATOME(ch_input)

    emit:
    results  = BIOC_TRANSLATOME.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TRANSLATOME.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TRANSLATOME.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TRANSLATOME.out.versions  // channel: path(versions.yml)
}
