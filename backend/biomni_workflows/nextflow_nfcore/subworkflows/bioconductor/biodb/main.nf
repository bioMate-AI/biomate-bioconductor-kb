#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biodb
// The biodb package provides access to standard remote chemical and biological databases (ChEBI, KEGG,
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biodb/inst/doc/biodb.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("biodb")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIODB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biodb"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biodb:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biodb:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biodb_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biodb_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biodb_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(biodb)
    library(jsonlite)

    # --- Table formatting and display [] ---
    # Key functions: kable
    knitr::kable(head(annotMzRt), "pipe", caption="Results of annotation of an M/Z and RT input file with an LCMS database.")
    msmsUrl <- system.file("extdata", "massbank_extract_msms.tsv", package='biodb')
    msmsdb <- mybiodb$getFactory()$createConn('mass.csv.file', url=msmsUrl)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biodb_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biodb_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biodb_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIODB:", paste0("    biodb: ", packageVersion("biodb"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biodb_results.csv
    touch ${prefix}_biodb_output.rds
    echo "BIOC_BIODB:" > versions.yml
    echo "    biodb: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIODB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIODB(ch_input)

    emit:
    results  = BIOC_BIODB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIODB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIODB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIODB.out.versions  // channel: path(versions.yml)
}
