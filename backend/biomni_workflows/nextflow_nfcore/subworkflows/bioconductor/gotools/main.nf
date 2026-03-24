#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: goTools
// Wraper functions for description/comparison of oligo ID list using Gene Ontology database
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/goTools/inst/doc/goTools.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("goTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GOTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gotools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gotools:1.80.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gotools:1.80.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gotools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gotools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gotools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CustomEndNodeList)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library("goTools", verbose=FALSE)
    data(probeID)
    # --- Ontoploteg1 [] ---
    # Key functions: ontoCompare
    ## library(GO.db)
    ## subset=c(L1=list(affylist[[1]][1:5]),L2=list(affylist[[2]][1:5]))
    ## res <- ontoCompare(subset, probeType="hgu133a", plot=TRUE)
    # --- Customendnodelist [] ---
    # Key functions: CustomEndNodeList
    ## MFendnode <- CustomEndNodeList("GO:0003674", rank=2)
    # --- Ontocompare [] ---
    # Key functions: ontoCompare
    ## res <- ontoCompare(subset, probeType="hgu133a", endnode=MFendnode, goType="MF")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gotools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gotools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gotools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GOTOOLS:", paste0("    gotools: ", packageVersion("goTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gotools_results.csv
    touch ${prefix}_gotools_output.rds
    echo "BIOC_GOTOOLS:" > versions.yml
    echo "    gotools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GOTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GOTOOLS(ch_input)

    emit:
    results  = BIOC_GOTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GOTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GOTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GOTOOLS.out.versions  // channel: path(versions.yml)
}
