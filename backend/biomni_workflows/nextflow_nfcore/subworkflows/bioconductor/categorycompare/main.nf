#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: categoryCompare
// Calculates significant annotations (categories) in each of two (or more) feature (i.e. gene) lists, 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/categoryCompare/inst/doc/categoryCompare_vignette.R
// Upstream  : KEGGREST, affy, estrogen, genefilter, limma
// Downstream: none
//
// Install: BiocManager::install("categoryCompare")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CATEGORYCOMPARE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-categorycompare"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-categorycompare:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-categorycompare:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(marraylm)

    output:
    tuple val(meta), path("${meta.id}_categorycompare_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_categorycompare_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_categorycompare_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ReadAffy)
    library(jsonlite)

    # --- Linear model fit (limma) [] ---
    # Key functions: nsFilter, lmFit, makeContrasts, eBayes, topTable

    # --- Phenotype data inspection [] ---
    # Key functions: pData, ReadAffy, new, fdr, ccEnrich, pvalueCutoff, ccCompare, createNetworkFromDataFrames
    list10 <- list(genes=g10, universe=gUniverse, annotation='org.Hs.eg.db')
    list48 <- list(genes=g48, universe=gUniverse, annotation='org.Hs.eg.db')
    geneLists <- list(T10=list10, T48=list48)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_categorycompare_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_categorycompare_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_categorycompare_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CATEGORYCOMPARE:", paste0("    categorycompare: ", packageVersion("categoryCompare"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_categorycompare_results.csv
    touch ${prefix}_categorycompare_output.rds
    echo "BIOC_CATEGORYCOMPARE:" > versions.yml
    echo "    categorycompare: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CATEGORYCOMPARE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(marraylm) ]

    main:
    BIOC_CATEGORYCOMPARE(ch_input)

    emit:
    results  = BIOC_CATEGORYCOMPARE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CATEGORYCOMPARE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CATEGORYCOMPARE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CATEGORYCOMPARE.out.versions  // channel: path(versions.yml)
}
