#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CBNplot
// This package provides the visualization of bayesian network inferred from gene expression data. The 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CBNplot/inst/doc/CBNplot_basic_usage.R
// Upstream  : bnlearn
// Downstream: none
//
// Install: BiocManager::install("CBNplot")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CBNPLOT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cbnplot"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cbnplot:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cbnplot:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(character)

    output:
    tuple val(meta), path("${meta.id}_cbnplot_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cbnplot_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cbnplot_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CBNplot)
    library(jsonlite)

    # --- KEGG pathway enrichment [] ---
    # Key functions: mappedkeys, enrichKEGG, setReadable
    library(CBNplot)
    library(bnlearn)
    library(org.Hs.eg.db)
    # --- Bngeneplot analysis [] ---
    # Key functions: bngeneplot, evcent, bnpathplot, bnpathplotCustom, bngeneplotCustom
    bnpathplotCustom(results = pway, exp = counts, expRow="ENTREZID",
    bngeneplotCustom(results = pway, exp = counts, expRow="ENTREZID",
    sessionInfo()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cbnplot_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cbnplot_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cbnplot_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CBNPLOT:", paste0("    cbnplot: ", packageVersion("CBNplot"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cbnplot_results.csv
    touch ${prefix}_cbnplot_output.rds
    echo "BIOC_CBNPLOT:" > versions.yml
    echo "    cbnplot: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CBNPLOT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(character) ]

    main:
    BIOC_CBNPLOT(ch_input)

    emit:
    results  = BIOC_CBNPLOT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CBNPLOT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CBNPLOT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CBNPLOT.out.versions  // channel: path(versions.yml)
}
