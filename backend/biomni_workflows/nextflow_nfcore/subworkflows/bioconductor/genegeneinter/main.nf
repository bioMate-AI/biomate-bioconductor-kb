#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GeneGeneInteR
// The aim of this package is to propose several methods for testing gene-gene interaction in case-cont
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GeneGeneInteR/inst/doc/GenePair.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GeneGeneInteR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENEGENEINTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genegeneinter"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genegeneinter:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genegeneinter:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genegeneinter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genegeneinter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genegeneinter_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GeneGeneInteR)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ## library("GeneGeneInteR")
    ## data("gene.pair")
    ## head(gene.pair$Y)
    # --- Test [] ---
    # Key functions: test
    ## PCA.test(Y=gene.pair$Y, G1=gene.pair$G1, G2=gene.pair$G2,threshold=0.7,
    ## method="GenFreq")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genegeneinter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genegeneinter_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genegeneinter_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENEGENEINTER:", paste0("    genegeneinter: ", packageVersion("GeneGeneInteR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genegeneinter_results.csv
    touch ${prefix}_genegeneinter_output.rds
    echo "BIOC_GENEGENEINTER:" > versions.yml
    echo "    genegeneinter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENEGENEINTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENEGENEINTER(ch_input)

    emit:
    results  = BIOC_GENEGENEINTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENEGENEINTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENEGENEINTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENEGENEINTER.out.versions  // channel: path(versions.yml)
}
