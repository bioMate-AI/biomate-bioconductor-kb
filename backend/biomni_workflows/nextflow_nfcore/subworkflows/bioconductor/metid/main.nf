#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MetID
// This package uses an innovative network-based approach that will enhance our ability to determine th
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/MetID/inst/doc/Introduction_to_MetID.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MetID")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METID {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-metid"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-metid:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-metid:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_metid_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_metid_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_metid_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Bis)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: bis, Bis
    data("demo1")
    dim(demo1)
    #> [1] 20  6
    head(demo1)
    #>   Query.Mass                                                   Name     Formula
    # --- Code Block 2 [] ---
    # Key functions: get_scores_for_LC_MS, bis, Bis
    colnames(demo1) <- c('query_m.z','name','formula','exact_m.z','pubchem_cid','kegg_id')
    out <- get_scores_for_LC_MS(demo1, type = 'data.frame', na='-', mode='POS')
    #> Start building network: it may take several minutes......
    #> Start getting random samples: it may take several minutes......
    #> Start writing scores......

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_metid_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_metid_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_metid_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METID:", paste0("    metid: ", packageVersion("MetID"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metid_results.csv
    touch ${prefix}_metid_output.rds
    echo "BIOC_METID:" > versions.yml
    echo "    metid: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METID_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METID(ch_input)

    emit:
    results  = BIOC_METID.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METID.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METID.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METID.out.versions  // channel: path(versions.yml)
}
